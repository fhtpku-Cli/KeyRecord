import Foundation
import CoreGraphics
import IOKit
import Darwin
import KeyRecordCore
import KeyRecordCapture

struct ObservedLockPlatform {
    let version: OperatingSystemVersion
    let build: String
    let architecture: String

    var isObservedCandidate: Bool {
        version.majorVersion == 27 && version.minorVersion == 0 && version.patchVersion == 0
            && build == "26A428" && architecture == "arm64"
    }

    static var current: Self {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unsupported"
        #endif
        var count = 0
        guard sysctlbyname("kern.osversion", nil, &count, nil, 0) == 0,
              count > 1, count <= 256 else {
            return .init(version: ProcessInfo.processInfo.operatingSystemVersion,
                         build: "", architecture: architecture)
        }
        var bytes = [CChar](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            sysctlbyname("kern.osversion", buffer.baseAddress, &count, nil, 0)
        }
        let build = status == 0 ? String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                                         as: UTF8.self) : ""
        return .init(version: ProcessInfo.processInfo.operatingSystemVersion,
                     build: build, architecture: architecture)
    }

}

struct ObservedPlatformCaptureQualification: CaptureQualification {
    private let supported: Bool
    init(platform: ObservedLockPlatform) { supported = platform.isObservedCandidate }
    func liveCaptureQualified() async -> Bool { supported }
}

final class ObservedSessionLockProvider: SessionLockProvider, @unchecked Sendable {
    typealias SessionDictionaryQuery = () -> NSDictionary?
    typealias ConsoleLockQuery = () -> CFTypeRef?
    typealias NotificationRegistrar = (@escaping (SessionLockState) -> Void) -> Void

    private let mutex = NSLock()
    private let sessionDictionaryQuery: SessionDictionaryQuery
    private let consoleLockQuery: ConsoleLockQuery
    private let currentUserID: uid_t
    private var notificationState: SessionLockState?
    private var observers: [any NSObjectProtocol]

    convenience init(platform: ObservedLockPlatform = .current) {
        if platform.isObservedCandidate {
            self.init(sessionDictionaryQuery: Self.liveSessionDictionary,
                      consoleLockQuery: Self.liveConsoleLock)
        } else {
            self.init(sessionDictionaryQuery: { nil }, consoleLockQuery: { nil },
                      notificationRegistrar: { _ in })
        }
    }

    init(sessionDictionaryQuery: @escaping SessionDictionaryQuery,
         consoleLockQuery: @escaping ConsoleLockQuery = { nil },
         currentUserID: uid_t = getuid(),
         notificationRegistrar: NotificationRegistrar? = nil) {
        self.sessionDictionaryQuery = sessionDictionaryQuery
        self.consoleLockQuery = consoleLockQuery
        self.currentUserID = currentUserID
        notificationState = nil
        observers = []
        if let notificationRegistrar {
            notificationRegistrar { [weak self] state in self?.record(state) }
        } else {
            registerDistributedNotifications()
        }
    }

    private func registerDistributedNotifications() {
        let center = DistributedNotificationCenter.default()
        for entry in [("com.apple.screenIsLocked", SessionLockState.locked),
                      ("com.apple.screenIsUnlocked", SessionLockState.unlocked)] {
            let state = entry.1
            observers.append(center.addObserver(forName: Notification.Name(entry.0), object: nil,
                                                 queue: nil) { [weak self] _ in
                self?.record(state)
            })
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        for observer in observers { center.removeObserver(observer) }
    }

    func sessionLockState() async -> SessionLockState {
        // Bracket the global console read with caller eligibility checks; these reads are not atomic.
        let before = sessionDictionaryQuery()
        let console = Self.booleanState(consoleLockQuery())
        let after = sessionDictionaryQuery()
        let first = Self.state(from: before)
        let last = Self.state(from: after)
        let live: SessionLockState
        if case .locked = first {
            live = .locked
        } else if case .locked = last {
            live = .locked
        } else if case .locked = console {
            live = .locked
        } else if eligible(before), eligible(after),
                  validLockField(before), validLockField(after) {
            if case .unlocked = console {
                live = .unlocked
            } else if case .unlocked = first, case .unlocked = last {
                live = .unlocked
            } else {
                live = .unknown
            }
        } else {
            live = .unknown
        }
        return mutex.withLock {
            if case .some(.locked) = notificationState { return .locked }
            return live
        }
    }

    private func record(_ state: SessionLockState) {
        mutex.withLock { notificationState = state }
    }

    private static func liveSessionDictionary() -> NSDictionary? {
        CGSessionCopyCurrentDictionary() as NSDictionary?
    }

    #if DEBUG
    /// Coarse inputs behind `sessionLockState()`, for the explicitly enabled witness only.
    /// This is a separate read; it never feeds a capture or display decision.
    func diagnosticLockComponents() async -> String {
        let dictionary = sessionDictionaryQuery()
        let session = Self.state(from: dictionary)
        let console = Self.booleanState(consoleLockQuery())
        let notification = mutex.withLock { notificationState }.map { String(describing: $0) } ?? "none"
        return "session=\(session),console=\(console),eligible=\(eligible(dictionary)),notification=\(notification)"
    }

    #endif

    private static func liveConsoleLock() -> CFTypeRef? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "IOConsoleLocked" as CFString,
                                               kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func eligible(_ dictionary: NSDictionary?) -> Bool {
        guard let onConsole = dictionary?[kCGSessionOnConsoleKey] as? NSNumber,
              CFGetTypeID(onConsole) == CFBooleanGetTypeID(), onConsole.boolValue,
              let user = dictionary?[kCGSessionUserIDKey] as? NSNumber,
              CFGetTypeID(user) == CFNumberGetTypeID() else { return false }
        return user.doubleValue == Double(currentUserID)
    }

    private func validLockField(_ dictionary: NSDictionary?) -> Bool {
        guard dictionary?["CGSSessionScreenIsLocked"] != nil else { return true }
        if case .unknown = Self.state(from: dictionary) { return false }
        return true
    }

    private static func booleanState(_ value: CFTypeRef?) -> SessionLockState {
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID(),
              let number = value as? NSNumber else { return .unknown }
        return number.boolValue ? .locked : .unlocked
    }

    private static func state(from dictionary: NSDictionary?) -> SessionLockState {
        guard let value = dictionary?["CGSSessionScreenIsLocked"] as? NSNumber else { return .unknown }
        switch value.doubleValue {
        case 1: return .locked
        case 0: return .unlocked
        default: return .unknown
        }
    }
}

#if DEBUG
extension ObservedSessionLockProvider: SessionLockDiagnosing {}
#endif

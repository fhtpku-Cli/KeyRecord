#if DEBUG
import Foundation
import AppKit
import CoreGraphics
import IOKit
import KeyRecordCore
import KeyRecordCapture

// DEBUG-only local developer capture support. This file compiles to nothing in Release
// builds; the arming token exists nowhere outside DEBUG compilation units.

enum LocalDevelopmentCaptureArmament {
    static let environmentKey = "KEYRECORD_LOCAL_CAPTURE"
    static let defaultsKey = "debug.localCaptureEnabled"

    static func isArmed(in environment: [String: String]) -> Bool {
        environment[environmentKey] == "1"
    }

    static var environmentArmed: Bool {
        isArmed(in: ProcessInfo.processInfo.environment)
    }

    static var defaultsArmed: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    static func setDefaultsArmed(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
    }

    static var isArmed: Bool { environmentArmed || defaultsArmed }
}

final class LocalDevelopmentCapture: CaptureQualification, @unchecked Sendable {
    private let mutex = NSLock()
    private var armed: Bool

    init(armed: Bool = LocalDevelopmentCaptureArmament.isArmed) {
        self.armed = armed
    }

    func liveCaptureQualified() async -> Bool { mutex.withLock { armed } }

    var isArmed: Bool { mutex.withLock { armed } }

    func setArmed(_ armed: Bool) { mutex.withLock { self.armed = armed } }
}

final class SystemSessionLockProvider: SessionLockProvider, @unchecked Sendable {
    typealias SessionDictionaryQuery = () -> NSDictionary?
    typealias ConsoleLockQuery = () -> CFTypeRef?
    typealias NotificationRegistrar = (@escaping (SessionLockState) -> Void) -> Void

    private let mutex = NSLock()
    private let sessionDictionaryQuery: SessionDictionaryQuery
    private let consoleLockQuery: ConsoleLockQuery
    private let currentUserID: uid_t
    private var notificationState: SessionLockState?
    private var observers: [any NSObjectProtocol]

    convenience init() {
        self.init(sessionDictionaryQuery: Self.liveSessionDictionary,
                  consoleLockQuery: Self.liveConsoleLock)
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
        // Bracket the global console read with caller eligibility checks; this DEBUG witness is not atomic.
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

@MainActor
final class LocalDevelopmentCaptureMenu: NSObject {
    static let toggleIdentifier = "menu.developer.localCapture"
    static let sectionIdentifier = "menu.developer.section"

    private let qualification: LocalDevelopmentCapture?
    private var item: NSMenuItem?
    /// Performs the real stop/start transaction. KR-05: the menu may not simply flip a
    /// flag; turning capture Off has to revoke delivery and stop the event source, and the
    /// title may only read "Off" once that has actually completed.
    private let transaction: (any LocalCaptureTransacting)?
    private(set) var isApplying = false

    init(qualification: LocalDevelopmentCapture?,
         transaction: (any LocalCaptureTransacting)? = nil) {
        self.qualification = qualification
        self.transaction = transaction
    }

    static let diagnosisIdentifier = "menu.developer.diagnosis"

    /// Supplies the current layered diagnosis line (batch 6). DEBUG-only.
    var diagnosisProvider: (@MainActor () -> String)?
    private var diagnosisItem: NSMenuItem?

    func addItems(to menu: NSMenu) {
        menu.addItem(.separator())
        let section = NSMenuItem(title: "Developer", action: nil, keyEquivalent: "")
        section.setAccessibilityIdentifier(Self.sectionIdentifier)
        menu.addItem(section)
        // Names the layer that stopped, so the menu never leaves the user with an
        // unexplained BLOCKED. Counts only — no captured text ever reaches this line.
        let diagnosis = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        diagnosis.isEnabled = false
        diagnosis.setAccessibilityIdentifier(Self.diagnosisIdentifier)
        menu.addItem(diagnosis)
        diagnosisItem = diagnosis
        let item = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
        item.target = self
        item.setAccessibilityIdentifier(Self.toggleIdentifier)
        menu.addItem(item)
        self.item = item
        refresh()
    }

    @objc func toggle() {
        Task { @MainActor in await applyToggle() }
    }

    /// KR-05: Off is a real stop transaction, not a flag flip.
    ///
    /// Off  -> revoke queue delivery and stop the source FIRST, then clear the
    ///         qualification flag, then repaint the menu. Until the stop completes the
    ///         item stays disabled and keeps showing the previous state, so the UI can
    ///         never claim "Off" while a tap is still delivering.
    /// On   -> only re-arms the qualification. It does NOT start capture and therefore
    ///         cannot bypass consent, permission, lock, Secure Input or foreground checks:
    ///         collection still has to go through the normal verified-readiness start.
    func applyToggle() async {
        guard let qualification, !isApplying else { return }
        isApplying = true
        refresh()
        defer { isApplying = false; refresh() }

        let next = !qualification.isArmed
        if next == false {
            // Stop before the flag and before the UI changes.
            await transaction?.stopLocalCapture()
        }
        qualification.setArmed(next)
        LocalDevelopmentCaptureArmament.setDefaultsArmed(next)
        if next {
            // Re-arming only restores eligibility; every gate is re-evaluated by the
            // normal start path.
            await transaction?.rearmLocalCapture()
        }
    }

    @discardableResult
    func refresh() -> NSMenuItem? {
        guard let item else { return nil }
        let armed = qualification?.isArmed ?? false
        item.state = armed ? .on : .off
        // Disabled while a stop transaction is in flight: the displayed state must match
        // the real runtime state, never an optimistic one.
        item.isEnabled = qualification != nil && !isApplying
        item.title = isApplying
            ? "Developer: Local Capture…"
            : (armed ? "Developer: Local Capture On" : "Developer: Local Capture Off")
        diagnosisItem?.title = diagnosisProvider?() ?? "Diagnosis: unavailable"
        return item
    }
}

/// The stop/re-arm side of the developer toggle, injected so it can be verified without
/// a live event tap.
@MainActor
protocol LocalCaptureTransacting {
    /// Must revoke queued delivery and stop the real event source before returning.
    func stopLocalCapture() async
    /// Re-arms eligibility only; must not bypass consent/permission/lock/Secure Input.
    func rearmLocalCapture() async
}
#endif

#if DEBUG
import Foundation
import AppKit
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
    private let mutex = NSLock()
    private var observed: SessionLockState
    private var observers: [any NSObjectProtocol]

    init() {
        observed = SystemSessionLockProvider.liveQuery() ?? .unlocked
        observers = []
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
        SystemSessionLockProvider.liveQuery() ?? mutex.withLock { observed }
    }

    private func record(_ state: SessionLockState) {
        mutex.withLock { observed = state }
    }

    // CGSessionCopyCurrentDictionary (SkyLight SPI, served from the dyld shared cache):
    // CGSSessionScreenIsLocked == 1 while the session is locked; absent means unlocked.
    private static func liveQuery() -> SessionLockState? {
        guard let function = sessionQuery else { return nil }
        guard let cf = function()?.takeRetainedValue() else { return nil }
        let locked = (cf as NSDictionary)["CGSSessionScreenIsLocked"]
            .flatMap { $0 as? NSNumber }?.intValue == 1
        return locked ? .locked : .unlocked
    }

    private static let sessionQuery: (@convention(c) () -> Unmanaged<CFDictionary>?)? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let symbol = dlsym(handle, "CGSessionCopyCurrentDictionary") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Unmanaged<CFDictionary>?).self)
    }()
}

@MainActor
final class LocalDevelopmentCaptureMenu: NSObject {
    static let toggleIdentifier = "menu.developer.localCapture"
    static let sectionIdentifier = "menu.developer.section"

    private let qualification: LocalDevelopmentCapture?
    private var item: NSMenuItem?

    init(qualification: LocalDevelopmentCapture?) {
        self.qualification = qualification
    }

    func addItems(to menu: NSMenu) {
        menu.addItem(.separator())
        let section = NSMenuItem(title: "Developer", action: nil, keyEquivalent: "")
        section.setAccessibilityIdentifier(Self.sectionIdentifier)
        menu.addItem(section)
        let item = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
        item.target = self
        item.setAccessibilityIdentifier(Self.toggleIdentifier)
        menu.addItem(item)
        self.item = item
        refresh()
    }

    @objc func toggle() {
        guard let qualification else { return }
        let next = !qualification.isArmed
        qualification.setArmed(next)
        LocalDevelopmentCaptureArmament.setDefaultsArmed(next)
        refresh()
    }

    @discardableResult
    func refresh() -> NSMenuItem? {
        guard let item else { return nil }
        let armed = qualification?.isArmed ?? false
        item.state = armed ? .on : .off
        item.isEnabled = qualification != nil
        item.title = armed
            ? "Developer: Local Capture On"
            : "Developer: Local Capture Off"
        return item
    }
}
#endif

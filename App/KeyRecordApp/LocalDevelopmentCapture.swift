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

/// Providers that can explain their lock verdict to the diagnostic witness.
protocol SessionLockDiagnosing: Sendable {
    func diagnosticLockComponents() async -> String
}

typealias SystemSessionLockProvider = ObservedSessionLockProvider

@MainActor
final class LocalDevelopmentCaptureMenu: NSObject {
    static let toggleIdentifier = "menu.developer.localCapture"
    static let sectionIdentifier = "menu.developer.section"

    private let qualification: LocalDevelopmentCapture?
    private let language: () -> String
    private var text: NativeText { NativeText(locale: language()) }
    private var sectionItem: NSMenuItem?
    private var item: NSMenuItem?
    /// Performs the real stop/start transaction. KR-05: the menu may not simply flip a
    /// flag; turning capture Off has to revoke delivery and stop the event source, and the
    /// title may only read "Off" once that has actually completed.
    private let transaction: (any LocalCaptureTransacting)?
    private(set) var isApplying = false

    init(qualification: LocalDevelopmentCapture?,
         transaction: (any LocalCaptureTransacting)? = nil,
         language: @escaping () -> String = { "en" }) {
        self.language = language
        self.qualification = qualification
        self.transaction = transaction
    }

    static let diagnosisIdentifier = "menu.developer.diagnosis"

    /// Supplies the current layered diagnosis line (batch 6). DEBUG-only.
    var diagnosisProvider: (@MainActor () -> String?)?
    private var diagnosisItem: NSMenuItem?

    func addItems(to menu: NSMenu) {
        menu.addItem(.separator())
        let section = NSMenuItem(title: text("capture.developer"), action: nil, keyEquivalent: "")
        section.setAccessibilityIdentifier(Self.sectionIdentifier)
        menu.addItem(section)
        sectionItem = section
        // Names the layer that stopped, so the menu never leaves the user with an
        // unexplained BLOCKED. Counts only — no captured text ever reaches this line.
        let diagnosis = NSMenuItem(title: "", action: #selector(showDiagnosis), keyEquivalent: "")
        diagnosis.target = self
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

    @objc private func showDiagnosis() {
        guard let details = diagnosisProvider?() else { return }
        let alert = NSAlert()
        alert.messageText = text("capture.diagnostics")
        alert.informativeText = details
        alert.addButton(withTitle: text("capture.close"))
        alert.runModal()
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
            ? text("capture.changing")
            : text(armed ? "capture.on" : "capture.off")
        sectionItem?.title = text("capture.developer")
        diagnosisItem?.title = text("capture.diagnostics")
        diagnosisItem?.isEnabled = diagnosisProvider != nil
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

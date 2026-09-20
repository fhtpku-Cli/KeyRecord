import KeyRecordCore
@testable import KeyRecordCapture

struct AllowedCapture: CaptureQualification {
    func liveCaptureQualified() async -> Bool { true }
}

/// Input Monitoring already granted. Existing capture tests exercise provider/generation
/// behaviour, not the permission gate, so they inject this explicitly; the production
/// default stays fail-closed (`DeniedInputMonitoringPermission`).
struct GrantedPermission: InputMonitoringPermission {
    func preflight() -> InputMonitoringStatus { .granted }
    @discardableResult
    func request() -> InputMonitoringStatus { .granted }
}

final class CaptureTestBackend: CaptureTapBackend, FrontmostAppProvider, SecureInputProvider, SessionLockProvider {
    private struct State: Sendable {
        var foreground: ForegroundState = .attributable(bundleID: "test.app")
        var secure: SecureInputState = .disabled
        var lock: SessionLockState = .unlocked
        var invalidate: (@Sendable (CaptureInvalidation) -> Void)?
        var duringRead: CaptureInvalidation?
        var duringStart: CaptureInvalidation?
        var starts = 0
        var reads = 0
        var unsubscribedReads = 0
        var handoffResult: EventHandoffResult?
        var providers: CaptureProviderSnapshot {
            CaptureProviderSnapshot(GateInputs(sessionLock: lock, secureInput: secure, foreground: foreground))
        }
    }
    private let state = CaptureLock(State())
    private let queue: CaptureQueue

    init(queue: CaptureQueue) { self.queue = queue }
    func foregroundState() async -> ForegroundState { state.withLock { $0.foreground } }
    func secureInputState() async -> SecureInputState { state.withLock { $0.secure } }
    func sessionLockState() async -> SessionLockState { state.withLock { $0.lock } }

    func subscribe(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) async throws {
        state.withLock { $0.invalidate = invalidate }
    }

    func readProviders() async -> CaptureProviderSnapshot {
        let (sample, change) = state.withLock { state in
            state.reads += 1
            if state.invalidate == nil { state.unsubscribedReads += 1 }
            let change = state.duringRead
            state.duringRead = nil
            return (state.providers, change)
        }
        if let change { report(change) }
        return sample
    }

    func cachedProviders() -> CaptureProviderSnapshot { state.withLock { $0.providers } }
    func changeDuringRead(_ reason: CaptureInvalidation) { state.withLock { $0.duringRead = reason } }
    func driftDuringStart(_ reason: CaptureInvalidation) { state.withLock { $0.duringStart = reason } }

    func report(_ reason: CaptureInvalidation, notify: Bool = true) {
        let handler = state.withLock { state in
            switch reason {
            case .foregroundChanged: state.foreground = .attributable(bundleID: "other.app")
            case .secureInputChanged: state.secure = .enabled
            case .sessionChanged: state.lock = .locked
            case .permissionRevoked, .sleep, .tapDisabled:
                state.foreground = .unknown
                state.secure = .unknown
                state.lock = .unknown
            }
            return state.invalidate
        }
        if notify { handler?(reason) }
    }

    func changeLock(_ lock: SessionLockState) {
        let handler = state.withLock { state in
            state.lock = lock
            return state.invalidate
        }
        handler?(.sessionChanged)
    }

    func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws {
        let change = state.withLock { state in
            state.starts += 1
            return state.duringStart
        }
        if let change { report(change, notify: false) }
        let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown, isAutoRepeat: false,
            modifiers: ModifierSet(), source: .ordinaryObserved, generation: queue.generation)
        let result = handoff(event)
        state.withLock { $0.handoffResult = result }
    }

    func stop() async { state.withLock { $0.invalidate = nil } }
    var starts: Int { state.withLock { $0.starts } }
    var reads: Int { state.withLock { $0.reads } }
    var unsubscribedReads: Int { state.withLock { $0.unsubscribedReads } }
    var handoffResult: EventHandoffResult? { state.withLock { $0.handoffResult } }
}

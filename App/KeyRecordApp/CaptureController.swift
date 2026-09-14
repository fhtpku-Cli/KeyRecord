import SwiftUI
import KeyRecordCore
import KeyRecordCapture

/// Bridges the task 13 listen-only `EventSource` protocol to the lifecycle port.
/// The bounded queue/deliver closure is composed in task 19; callback work stays O(1) handoff.
public final class EventSourceCaptureAdapter: LifecycleCaptureControlling {
    private let source: any EventSource
    private let deliver: @Sendable (ObservedKeyEvent) -> EventHandoffResult

    public init(source: any EventSource,
                deliver: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) {
        self.source = source
        self.deliver = deliver
    }

    public func start() async throws {
        try await source.start(deliver: deliver)
    }

    public func stop() async {
        await source.stop()
    }
}

/// Minimal observable wiring over `LifecycleOrchestrator`. Screens arrive in task 18; this type only
/// mirrors reducer state for SwiftUI and forwards intents. All external dependencies stay injectable.
@MainActor
@Observable
public final class CaptureController {
    public private(set) var phase: LifecyclePhase = .unstarted
    public private(set) var failure: LifecycleFailure?
    public private(set) var notice: LifecycleNotice?
    public private(set) var blockedReason: BlockedReason?
    public private(set) var gateOpen = false
    public let loginItem: LoginItemController

    private let orchestrator: LifecycleOrchestrator

    public init(orchestrator: LifecycleOrchestrator) {
        self.orchestrator = orchestrator
        self.loginItem = LoginItemController(request: { [weak orchestrator] enabled in
            await orchestrator?.setLoginItem(enabled: enabled)
        })
        sync()
    }

    public func presentConsent() {
        orchestrator.requestConsent()
        sync()
    }

    public func accept() async {
        await orchestrator.acceptConsent()
        sync()
    }

    public func deny() {
        orchestrator.denyConsent()
        sync()
    }

    public func pause() async {
        await orchestrator.pause()
        sync()
    }

    public func resume() async {
        await orchestrator.resume()
        sync()
    }

    public func quit() async {
        await orchestrator.quit()
        sync()
    }

    public func reload() async {
        await orchestrator.reload()
        sync()
    }

    public func retryAfterFailure() async {
        await orchestrator.retry()
        sync()
    }

    public func setExclusions(_ excludedBundleIDs: Set<String>) async {
        await orchestrator.setExclusions(excludedBundleIDs)
        sync()
    }

    public func updateConditions(_ conditions: RuntimeConditions) {
        orchestrator.observe(conditions)
        sync()
    }

    public func dismissNotice() {
        orchestrator.dismissNotice()
        sync()
    }

    private func sync() {
        let state = orchestrator.state
        phase = state.phase
        failure = state.failure
        notice = state.notice
        blockedReason = state.blockedReason
        gateOpen = state.gate.isOpen
        loginItem.update(phase: state.phase, state: state.loginItem, notice: state.notice)
    }
}

#if DEBUG
import Foundation
import KeyRecordCore

public final class FixedReplayController: @unchecked Sendable {
    struct State: Sendable {
        var handoff: (@Sendable (ObservedKeyEvent) -> EventHandoffResult)?
        var generation: CaptureGeneration?
        var acceptedEvents: Int64 = 0
    }

    static let pattern = [[0, 1, 2, 3, 0, 1, 2, 3], [0], [1], [2], [3], [0], [1], [2], [3], [0]]
    public static let fixtureJSON = Data("[[0,1,2,3,0,1,2,3],[0],[1],[2],[3],[0],[1],[2],[3],[0]]".utf8)
    public static let windowTicks = 6_620
    public static func expectedEvents(tick: Int) -> Int {
        guard tick >= 0 else { return 0 }
        return pattern[tick % pattern.count].count * 2
    }

    private let state = CaptureLock(State())

    public init() {}

    public var acceptedEvents: Int64 { state.withLock { $0.acceptedEvents } }

    public func emit(tick: Int) -> Int {
        guard tick >= 0 else { return 0 }
        let active = state.withLock { ($0.handoff, $0.generation) }
        guard let handoff = active.0, let generation = active.1 else { return 0 }
        let modifiers = ModifierSet(command: tick.isMultiple(of: 3) ? .left : .none,
                                    option: .none, control: .none, shift: .none, fn: .none)
        var accepted = 0
        for rawCode in Self.pattern[tick % Self.pattern.count] {
            guard let keyCode = try? KeyCode(rawCode) else { return accepted }
            for kind in [KeyEventKind.keyDown, .keyUp] {
                let event = ObservedKeyEvent(keyCode: keyCode, kind: kind, isAutoRepeat: false,
                                             modifiers: modifiers, source: .ordinaryObserved,
                                             generation: generation)
                guard handoff(event) == .accepted else {
                    state.withLock { $0.acceptedEvents += Int64(accepted) }
                    return accepted
                }
                accepted += 1
            }
        }
        state.withLock { $0.acceptedEvents += Int64(accepted) }
        return accepted
    }

    fileprivate var isActive: Bool { state.withLock { $0.handoff != nil } }

    fileprivate func start(generation: CaptureGeneration,
                           handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) throws {
        let inserted = state.withLock { state in
            guard state.handoff == nil else { return false }
            state.generation = generation
            state.handoff = handoff
            return true
        }
        guard inserted else { throw CaptureStartError.alreadyStarted }
    }

    fileprivate func stop() {
        state.withLock { $0.handoff = nil; $0.generation = nil }
    }
}

private struct FixedReplayPermission: InputMonitoringPermission {
    func preflight() -> InputMonitoringStatus { .granted }
    func request() -> InputMonitoringStatus { .granted }
}

private final class FixedReplayBackend: CaptureTapBackend, @unchecked Sendable {
    private let queue: CaptureQueue
    private let providers: CaptureProviderSet
    private let controller: FixedReplayController
    private let cached = CaptureLock(CaptureProviderSnapshot.unknown)

    init(queue: CaptureQueue, providers: CaptureProviderSet, controller: FixedReplayController) {
        self.queue = queue
        self.providers = providers
        self.controller = controller
    }

    func subscribe(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) async throws {}

    func readProviders() async -> CaptureProviderSnapshot {
        let foreground = await providers.foreground.foregroundState()
        let secureInput = await providers.secureInput.secureInputState()
        let sessionLock = await providers.sessionLock.sessionLockState()
        let current = CaptureProviderSnapshot(GateInputs(sessionLock: sessionLock,
            secureInput: secureInput, foreground: foreground))
        cached.withLock { $0 = current }
        return current
    }

    func cachedProviders() -> CaptureProviderSnapshot { cached.withLock { $0 } }

    func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws {
        try controller.start(generation: queue.generation, handoff: handoff)
    }

    func isEnabled() -> Bool { controller.isActive }

    func stop() {
        controller.stop()
        cached.withLock { $0 = .unknown }
    }
}

extension ListenOnlyEventSource {
    public static func fixedReplay(queue: CaptureQueue, qualification: any CaptureQualification,
                                   providers: CaptureProviderSet, controller: FixedReplayController)
        -> ListenOnlyEventSource {
        ListenOnlyEventSource(queue: queue, qualification: qualification,
            backend: FixedReplayBackend(queue: queue, providers: providers, controller: controller),
            permission: FixedReplayPermission())
    }
}
#endif

import Foundation
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

final class ProductReduction: @unchecked Sendable {
    private let mutex = NSLock()
    private var aggregate: AggregationReducer?
    private var normalizer = ChordNormalizer()
    private var changed = false
    let gate: KeyAvailabilityGate
    init(gate: KeyAvailabilityGate) { self.gate = gate }

    func open(_ aggregate: AggregationReducer, inputs: GateInputs) {
        mutex.withLock {
            self.aggregate = aggregate
            normalizer = ChordNormalizer()
            normalizer.update(inputs)
            self.aggregate?.update(normalizer.gate)
        }
    }
    func clear() {
        mutex.withLock {
            aggregate = nil; normalizer.reset(); changed = false
        }
    }
    func deliver(_ event: ObservedKeyEvent) -> EventHandoffResult {
        mutex.withLock {
            guard normalizer.gate.isOpen,
                  let generation = try? gate.begin() else { return .closed }
            do {
                return try gate.use(generation) {
                    let observed = ObservedKeyEvent(keyCode: event.keyCode, kind: event.kind,
                        isAutoRepeat: event.isAutoRepeat, modifiers: event.modifiers,
                        source: event.source, generation: normalizer.gate.generation)
                    let output = normalizer.process(observed)
                    try aggregate?.process(output, generation: observed.generation, clock: ProductClock())
                    changed = true
                    return .accepted
                }
            } catch { return .closed }
        }
    }
    func take() throws -> AggregationReducer? {
        try mutex.withLock {
            let generation = try gate.begin()
            return try gate.use(generation) {
                guard changed else { return nil }
                changed = false
                return aggregate
            }
        }
    }

    func snapshot() throws -> AggregateSnapshot? {
        try mutex.withLock {
            let generation = try gate.begin()
            return try gate.use(generation) {
                guard let aggregate else { return nil }
                return try AggregateSnapshot(shortcuts: aggregate.shortcuts, bareKeys: aggregate.bareKeys)
            }
        }
    }
}

actor ProductFlush: LifecycleFlushing {
    let reduction: ProductReduction
    let scheduler: FlushScheduler
    init(reduction: ProductReduction, scheduler: FlushScheduler) {
        self.reduction = reduction; self.scheduler = scheduler
    }
    func stage() async throws {
        if let aggregate = try reduction.take() {
            try await scheduler.stage(AggregatePersistence.objects(aggregate))
        }
    }
    func pulse() async throws { try await stage(); await scheduler.tick() }
    func flushWhileUnlocked() async throws { try await stage(); try await scheduler.flushWhileUnlocked() }
}

actor ProductCapture: LifecycleCaptureControlling, RestartReadinessChecking {
    let source: ListenOnlyEventSource
    let queue: CaptureQueue
    let control: CaptureControl
    let reduction: ProductReduction
    let persistence: ProductPersistence
    let scheduler: FlushScheduler
    let foreground: SystemForegroundProvider
    let secure: SystemSecureInputProvider
    let qualification = UnqualifiedCapture()
    init(source: ListenOnlyEventSource, queue: CaptureQueue, reduction: ProductReduction,
         persistence: ProductPersistence, scheduler: FlushScheduler, foreground: SystemForegroundProvider) {
        self.source = source; self.queue = queue; self.reduction = reduction
        self.persistence = persistence; self.scheduler = scheduler; self.foreground = foreground
        secure = SystemSecureInputProvider()
        control = CaptureControl(queue: queue, providers: CaptureProviderSet(
            foreground: foreground, secureInput: secure, sessionLock: UnqualifiedSessionLockProvider()))
    }
    func verifyRestartReadiness() async throws -> RuntimeConditions {
        guard await qualification.liveCaptureQualified() else { throw LifecycleReadinessError.sessionLocked }
        _ = try reduction.gate.begin()
        return RuntimeConditions(keyAvailability: .available,
            sessionLock: await UnqualifiedSessionLockProvider().sessionLockState(),
            secureInput: await secure.secureInputState(), foreground: await foreground.foregroundState())
    }
    func start() async throws {
        _ = try await verifyRestartReadiness()
        guard let preferences = try await persistence.load() else { throw LifecycleCaptureError.runtimeFailed }
        let excluded: ExclusionState
        switch await foreground.foregroundState() {
        case .attributable(let bundleID):
            excluded = preferences.excludedBundleIDs.contains(bundleID) ? .excluded : .included
        case .reliablyUnattributable: excluded = .included
        case .unknown: excluded = .unknown
        }
        await control.refresh(policy: CapturePolicy(collecting: preferences.expectedCollecting,
            keyAvailability: .available, exclusion: excluded))
        guard queue.isOpen else { throw LifecycleCaptureError.runtimeFailed }
        try await scheduler.reopen()
        let restored = try await AggregatePersistence.restore(cycleID: preferences.currentCycleID,
            store: persistence.store, gate: reduction.gate)
        let snapshot = queue.snapshot
        reduction.open(restored, inputs: snapshot.inputs)
        try await source.start { [reduction] in reduction.deliver($0) }
    }
    func stop() async { await source.stop() }
}

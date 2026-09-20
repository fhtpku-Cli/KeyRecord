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
    let qualification: any CaptureQualification
    private let sessionLock: any SessionLockProvider
    init(source: ListenOnlyEventSource, queue: CaptureQueue, reduction: ProductReduction,
         persistence: ProductPersistence, scheduler: FlushScheduler, foreground: SystemForegroundProvider,
         qualification: any CaptureQualification = UnqualifiedCapture(),
         sessionLock: any SessionLockProvider = UnqualifiedSessionLockProvider()) {
        self.source = source; self.queue = queue; self.reduction = reduction
        self.persistence = persistence; self.scheduler = scheduler; self.foreground = foreground
        self.qualification = qualification; self.sessionLock = sessionLock
        secure = SystemSecureInputProvider()
        control = CaptureControl(queue: queue, providers: CaptureProviderSet(
            foreground: foreground, secureInput: secure, sessionLock: sessionLock))
    }
    func verifyRestartReadiness() async throws -> RuntimeConditions {
        guard await qualification.liveCaptureQualified() else { throw LifecycleReadinessError.sessionLocked }
        _ = try reduction.gate.begin()
        return RuntimeConditions(keyAvailability: .available,
            sessionLock: await sessionLock.sessionLockState(),
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

    /// Recompute the capture policy from the supplied preferences and a FRESH foreground
    /// read, without touching the in-memory aggregate.
    ///
    /// KR-04: exclusion changes must reach the real CaptureQueue policy, not just Core/UI.
    /// Deliberately NOT `start()`: that reloads the aggregate from disk and would discard
    /// counted-but-unflushed deltas. The persistence boundary is unchanged here — only the
    /// gate inputs are recomputed, so excluding the current app stops attribution
    /// immediately and un-excluding reopens it under fresh provider checks.
    /// Returns the exclusion state actually applied.
    @discardableResult
    func reapplyPolicy(preferences: Preferences) async -> ExclusionState {
        let excluded: ExclusionState
        switch await foreground.foregroundState() {
        case .attributable(let bundleID):
            excluded = preferences.excludedBundleIDs.contains(bundleID) ? .excluded : .included
        case .reliablyUnattributable: excluded = .included
        case .unknown: excluded = .unknown
        }
        await control.refresh(policy: CapturePolicy(collecting: preferences.expectedCollecting,
            keyAvailability: .available, exclusion: excluded))
        return excluded
    }

    /// Rebuilds the event-source session WITHOUT reloading the aggregate from disk.
    ///
    /// `start()` cannot be reused for recovery: it calls `AggregatePersistence.restore`,
    /// which replaces in-memory counts with the last durable commit and so discards every
    /// increment since the last flush. A foreground switch or tap re-arm must not cost the
    /// user data, so recovery refreshes policy, reopens the flush scheduler and starts a
    /// fresh source session against the EXISTING reduction, leaving the aggregate alone.
    func resumeSession(preferences: Preferences) async -> Bool {
        guard (try? await verifyRestartReadiness()) != nil else { return false }
        guard queue.isOpen else { return false }
        guard (try? await scheduler.reopen()) != nil else { return false }
        do {
            try await source.start { [reduction] in reduction.deliver($0) }
            return true
        } catch {
            return false
        }
    }

    /// KR-08: the authoritative answer to "is capture actually running right now".
    /// Delegates to the event source rather than to any cached flag or lifecycle phase.
    func hasLiveSession() async -> Bool {
        await source.hasLiveSession
    }

    /// Bundle id of the current foreground app, if reliably attributable.
    func foregroundBundleID() async -> String? {
        if case .attributable(let bundleID) = await foreground.foregroundState() { return bundleID }
        return nil
    }

    /// Whether the persisted user intent is still "collecting". Read from storage rather
    /// than from a cached flag, so a recovery cannot resurrect capture the user turned off.
    func persistedExpectsCollecting() async -> Bool {
        (try? await persistence.load())??.expectedCollecting ?? false
    }
}

/// Supplies the coordinator with genuinely fresh runtime state (KR-02 step 3).
/// Every call re-reads qualification, key gate and all three providers; nothing here is
/// cached, so a recovery can never reopen on stale inputs.
struct ProductRuntimeChecks: CaptureRuntimeChecking {
    let capture: ProductCapture

    func freshRuntimeConditions() async -> RuntimeConditions? {
        // verifyRestartReadiness re-checks qualification + key availability and samples the
        // providers; a throw means fail closed.
        try? await capture.verifyRestartReadiness()
    }

    func expectsCollecting() async -> Bool {
        await capture.persistedExpectsCollecting()
    }
}

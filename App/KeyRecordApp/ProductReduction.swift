import Foundation
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

private struct ProductReductionClock: LocalClock {
    var calendar: Calendar { Calendar.current }
    var timeZone: TimeZone { TimeZone.current }
    func now() -> Date { Date() }
}

final class ProductReduction: @unchecked Sendable {
    private let mutex = NSLock()
    private var aggregate: AggregationReducer?
    private var normalizer = ChordNormalizer()
    private var sourceGeneration: CaptureGeneration?
    private var changed = false
    #if DEBUG
    private var diagnostics: CaptureDiagnosticsRecorder?
    #endif
    let gate: KeyAvailabilityGate

    init(gate: KeyAvailabilityGate) { self.gate = gate }

    #if DEBUG
    func configureDiagnostics(_ recorder: CaptureDiagnosticsRecorder?) {
        mutex.withLock { diagnostics = recorder }
    }
    #endif

    func open(_ aggregate: AggregationReducer, inputs: GateInputs,
              generation: CaptureGeneration) {
        mutex.withLock {
            self.aggregate = aggregate
            changed = false
            _ = installSession(inputs: inputs, generation: generation, markChanged: false)
        }
    }

    @discardableResult
    func resume(inputs: GateInputs, generation: CaptureGeneration) -> Bool {
        mutex.withLock {
            guard aggregate != nil else { return false }
            return installSession(inputs: inputs, generation: generation, markChanged: true)
        }
    }

    func clear() {
        mutex.withLock {
            aggregate = nil
            normalizer.reset()
            sourceGeneration = nil
            changed = false
        }
    }

    func deliver(_ event: ObservedKeyEvent) -> EventHandoffResult {
        mutex.withLock {
            guard event.generation == sourceGeneration,
                  normalizer.gate.isOpen,
                  aggregate != nil,
                  let keyGeneration = try? gate.begin() else { return .closed }
            do {
                return try gate.use(keyGeneration) {
                    let observed = ObservedKeyEvent(keyCode: event.keyCode, kind: event.kind,
                        isAutoRepeat: event.isAutoRepeat, modifiers: event.modifiers,
                        source: event.source, generation: normalizer.gate.generation)
                    let output = normalizer.process(observed)
                    #if DEBUG
                    if output != .none { diagnostics?.increment(.normalizationOutput) }
                    #endif
                    let previousTotal = aggregate?.totalCount
                    try aggregate?.process(output, generation: observed.generation,
                                           clock: ProductReductionClock())
                    if aggregate?.totalCount != previousTotal {
                        changed = true
                        #if DEBUG
                        diagnostics?.increment(.aggregateDelta)
                        #endif
                    }
                    return .accepted
                }
            } catch {
                return .closed
            }
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
                return try AggregateSnapshot(shortcuts: aggregate.shortcuts,
                                             bareKeys: aggregate.bareKeys)
            }
        }
    }

    func hasSession(generation: CaptureGeneration) -> Bool {
        mutex.withLock { sourceGeneration == generation && normalizer.gate.isOpen }
    }

    func hasUnflushedChanges() -> Bool {
        mutex.withLock { changed }
    }

    @discardableResult
    func prepareForSchedulerReopen() -> Bool {
        mutex.withLock {
            guard aggregate != nil else { return false }
            changed = true
            return true
        }
    }

    func reopenScheduler(_ reopen: @Sendable () async throws -> Void) async -> Bool {
        guard prepareForSchedulerReopen() else { return false }
        defer { _ = prepareForSchedulerReopen() }
        do {
            try await reopen()
            return true
        } catch {
            return false
        }
    }

    func revokeProtectedState(queue: CaptureQueue, recoveryFence: ManualRecoveryFence) {
        recoveryFence.invalidate()
        gate.update(.unknown)
        queue.revoke()
        clear()
    }

    private func installSession(inputs: GateInputs, generation: CaptureGeneration,
                                markChanged: Bool) -> Bool {
        normalizer.reset()
        aggregate?.update(normalizer.gate)
        normalizer = ChordNormalizer()
        normalizer.update(inputs)
        aggregate?.update(normalizer.gate)
        sourceGeneration = normalizer.gate.isOpen ? generation : nil
        if markChanged { changed = true }
        return sourceGeneration != nil
    }
}

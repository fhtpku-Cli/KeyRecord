import Foundation
import KeyRecordCore

public struct FlushObject: Sendable {
    public let identity: CanonicalLogicalIdentity
    public let payload: Data
    public init(identity: CanonicalLogicalIdentity, payload: Data) {
        self.identity = identity; self.payload = payload
    }
}

public protocol FlushWriting: Sendable {
    func write(_ objects: [FlushObject], generation: CaptureGeneration) async throws
}

public protocol FlushClock: Sendable {
    func now() -> Duration
    func sleep(until deadline: Duration) async throws
}

public struct SystemFlushClock: FlushClock {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now
    public init() {}
    public func now() -> Duration { origin.duration(to: clock.now) }
    public func sleep(until deadline: Duration) async throws {
        try await clock.sleep(until: origin.advanced(by: deadline))
    }
}

/// One physical writer at a time, including after timeout/close. Noncooperative fsync
/// may finish ciphertext work, but never acknowledges a revoked generation as saved.
public actor FlushScheduler: LifecycleFlushing {
    private let gate: KeyAvailabilityGate
    private let writer: any FlushWriting
    private let clock: any FlushClock
    private var schedule = FlushSchedule()
    private var pending: [FlushObject] = []
    private var writing: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var waiters: [CheckedContinuation<FlushCompletion, Never>] = []
    var waiterCount: Int { waiters.count }
    private var physicalID: UUID?
    private var lastResult: FlushCompletion?
#if DEBUG
    private var diagnostics: CaptureDiagnosticsRecorder?
    private var diagnosticOutcomeRecorded = false
#endif

    public init(gate: KeyAvailabilityGate, writer: any FlushWriting, clock: any FlushClock) {
        self.gate = gate; self.writer = writer; self.clock = clock
    }

#if DEBUG
    public func setDiagnostics(_ recorder: CaptureDiagnosticsRecorder?) {
        diagnostics = recorder
    }
#endif

    public func reopen() throws {
        discard()
        schedule.reopen(generation: try gate.renewOpenGeneration(), now: clock.now())
    }

    public nonisolated func close(_ state: SessionLockState = .locked) async {
        gate.update(state)
        await discard()
    }

    private func discard() {
#if DEBUG
        if physicalID != nil { recordOutcome(.flushInvalidated) }
#endif
        writing?.cancel()
        timeout?.cancel()
        timeout = nil
        pending.removeAll()
        schedule.close()
        finishWaiters(.locked)
        lastResult = nil
    }

    public func stage(_ objects: [FlushObject]) throws {
        guard let generation = schedule.generation else { throw LifecycleFlushError.locked }
        try gate.use(generation) {
            pending = objects
            schedule.markDirty()
        }
    }

    public func tick() { start(force: false) }

    public func waitForIssuedWrite() async { await writing?.value }

    public func suspend() { discard() }

    public func completion() async -> FlushCompletion {
        guard let generation = schedule.generation,
              (try? gate.check(generation)) != nil else { return .locked }
        if schedule.revision == schedule.durableRevision { return .saved }
        if physicalID != nil && schedule.active == nil { return .timedOut }
        guard waiters.count < 32 else { return .failed }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            start(force: true)
        }
    }

    public func flushWhileUnlocked() async throws {
        switch await completion() {
        case .saved: return
        case .failed: throw LifecycleFlushError.failed
        case .timedOut: throw LifecycleFlushError.timedOut
        case .locked: throw LifecycleFlushError.locked
        }
    }

    public func result() -> FlushCompletion? {
        guard let generation = schedule.generation,
              (try? gate.check(generation)) != nil else { return nil }
        return lastResult
    }

    public func hasPendingChanges() -> Bool {
        schedule.revision != schedule.durableRevision
    }

    private func start(force: Bool) {
        guard physicalID == nil,
              let generation = schedule.generation,
              (try? gate.check(generation)) != nil,
              let ticket = schedule.start(now: clock.now(), force: force) else { return }
        let objects = pending, writer = writer, gate = gate, id = UUID()
        physicalID = id
#if DEBUG
        diagnosticOutcomeRecorded = false
        diagnostics?.increment(.flushIssued)
#endif
        let deadline = clock.now() + .seconds(5)
        writing = Task {
            let result: FlushCompletion
            do {
                try gate.check(ticket.generation)
                try Task.checkCancellation()
                try await writer.write(objects, generation: ticket.generation)
#if DEBUG
                diagnostics?.increment(.flushWriteSucceeded)
#endif
                try gate.check(ticket.generation)
                result = .saved
            } catch {
                result = (try? gate.check(ticket.generation)) == nil ? .locked : .failed
            }
            self.finished(ticket, id: id, result: result)
        }
        timeout = Task {
            do { try await clock.sleep(until: deadline) } catch { return }
            self.expire(ticket)
        }
    }

    private func expire(_ ticket: FlushTicket) {
        guard schedule.active == ticket else { return }
        writing?.cancel()
        // Keep the physical writer slot occupied until it really returns.
        guard schedule.complete(ticket, result: .timedOut) else { return }
        lastResult = .timedOut
#if DEBUG
        recordOutcome(.flushTimedOut)
#endif
        finishWaiters(.timedOut)
    }

    private func finished(_ ticket: FlushTicket, id: UUID, result: FlushCompletion) {
        guard physicalID == id else { return }
#if DEBUG
        diagnostics?.increment(.flushWriteReturned)
#endif
        physicalID = nil
        writing = nil
        timeout?.cancel()
        timeout = nil
        guard (try? gate.check(ticket.generation)) != nil else {
#if DEBUG
            recordOutcome(.flushInvalidated)
#endif
            if schedule.generation == ticket.generation { discard() }
            return
        }
        guard schedule.complete(ticket, result: result) else {
#if DEBUG
            recordOutcome(.flushInvalidated)
#endif
            return
        }
        lastResult = result
#if DEBUG
        switch result {
        case .saved:
            recordOutcome(.flushDurable)
        case .failed:
            recordOutcome(.flushFailed)
        case .timedOut:
            recordOutcome(.flushTimedOut)
        case .locked:
            recordOutcome(.flushInvalidated)
        }
#endif
        if result == .saved && schedule.durableRevision < schedule.revision {
            if !waiters.isEmpty { start(force: true) }
        } else {
            finishWaiters(result)
        }
    }

#if DEBUG
    /// Exactly one logical outcome per issued task, even when a physical return
    /// arrives after timeout, suspend, or generation revocation.
    private func recordOutcome(_ counter: CaptureDiagnosticCounter) {
        guard !diagnosticOutcomeRecorded else { return }
        diagnosticOutcomeRecorded = true
        diagnostics?.increment(counter)
    }
#endif

    private func finishWaiters(_ result: FlushCompletion) {
        let current = waiters
        waiters.removeAll()
        for continuation in current { continuation.resume(returning: result) }
    }
}

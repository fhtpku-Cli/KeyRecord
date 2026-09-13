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
    private var physicalID: UUID?
    private var lastResult: FlushCompletion?

    public init(gate: KeyAvailabilityGate, writer: any FlushWriting, clock: any FlushClock) {
        self.gate = gate; self.writer = writer; self.clock = clock
    }

    public func reopen() throws {
        discard()
        schedule.reopen(generation: try gate.renewOpenGeneration(), now: clock.now())
    }

    public nonisolated func close(_ state: SessionLockState = .locked) async {
        gate.update(state)
        await discard()
    }

    private func discard() {
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

    public func completion() async -> FlushCompletion {
        guard let generation = schedule.generation,
              (try? gate.check(generation)) != nil else { return .locked }
        if schedule.revision == schedule.durableRevision { return .saved }
        if physicalID != nil && schedule.active == nil { return .timedOut }
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

    private func start(force: Bool) {
        guard physicalID == nil,
              let generation = schedule.generation,
              (try? gate.check(generation)) != nil,
              let ticket = schedule.start(now: clock.now(), force: force) else { return }
        let objects = pending, writer = writer, gate = gate, id = UUID()
        physicalID = id
        let deadline = clock.now() + .seconds(5)
        writing = Task {
            let result: FlushCompletion
            do {
                try gate.check(ticket.generation)
                try Task.checkCancellation()
                try await writer.write(objects, generation: ticket.generation)
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
        _ = schedule.complete(ticket, result: .timedOut)
        lastResult = .timedOut
        finishWaiters(.timedOut)
    }

    private func finished(_ ticket: FlushTicket, id: UUID, result: FlushCompletion) {
        guard physicalID == id else { return }
        physicalID = nil
        writing = nil
        timeout?.cancel()
        timeout = nil
        guard (try? gate.check(ticket.generation)) != nil,
              schedule.complete(ticket, result: result) else { return }
        lastResult = result
        if result == .saved && schedule.durableRevision < schedule.revision {
            if !waiters.isEmpty { start(force: true) }
        } else {
            finishWaiters(result)
        }
    }

    private func finishWaiters(_ result: FlushCompletion) {
        let current = waiters
        waiters.removeAll()
        for continuation in current { continuation.resume(returning: result) }
    }
}

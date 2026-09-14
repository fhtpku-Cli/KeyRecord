import KeyRecordCore

public enum FlushCompletion: Equatable, Sendable {
    case saved, failed, timedOut, locked
}

public struct FlushTicket: Equatable, Sendable {
    public let generation: CaptureGeneration
    public let revision: UInt64
}

/// Pure monotonic-time reducer. A timer is only a wakeup, never evidence of durability.
/// Revisions describe this open session, not a promise about a one-second loss window.
public struct FlushSchedule: Sendable {
    public private(set) var generation: CaptureGeneration?
    public private(set) var revision: UInt64 = 0
    public private(set) var durableRevision: UInt64 = 0
    public private(set) var active: FlushTicket?
    private var nextTarget: Duration = .zero

    public init() {}

    public mutating func reopen(generation: CaptureGeneration, now: Duration) {
        self = Self()
        self.generation = generation
        nextTarget = now + .seconds(1)
    }

    /// Pending deltas are discarded on close. This does not guarantee zeroized copies;
    /// everything since the last durable commit may be lost, regardless of elapsed time.
    public mutating func close() { self = Self() }

    public mutating func markDirty() {
        guard generation != nil else { return }
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { close(); return }
        revision = next
    }

    public mutating func start(now: Duration, force: Bool = false) -> FlushTicket? {
        guard let generation, active == nil, revision > durableRevision,
              force || now >= nextTarget else { return nil }
        let ticket = FlushTicket(generation: generation, revision: revision)
        active = ticket
        nextTarget = now + .seconds(1)
        return ticket
    }

    @discardableResult
    public mutating func complete(_ ticket: FlushTicket, result: FlushCompletion) -> Bool {
        guard generation == ticket.generation, active == ticket else { return false }
        active = nil
        switch result {
        case .saved: durableRevision = ticket.revision
        case .failed, .timedOut, .locked: break
        }
        return true
    }
}

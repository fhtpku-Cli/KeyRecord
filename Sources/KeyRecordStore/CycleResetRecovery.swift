import Foundation
import KeyRecordCore

/// Typed rejections for the ordered cycle-reset transaction. Every case names a state the
/// idempotent recovery cannot repair; callers surface a generic failure and never guess.
public enum CycleResetError: Error, Equatable, Sendable {
    /// The fixed current-cycle record is absent or undecodable; there is nothing to close.
    case missingCurrentCycle
    /// Preferences must exist before reset so expectedCollecting can be preserved.
    case missingPreferences
    /// A pending journal coordinates a DIFFERENT operation; one reset finishes first.
    case conflictingOperation
    /// A pending journal envelope cannot be authenticated or decoded (fail closed).
    case journalUnreadable
    /// A retained object's payload hash drifted from the journal's committed set.
    case retainedObjectsChanged
    /// A daily shard claims a different cycle than the one being reset.
    case shardCycleMismatch
    /// A shard uses an aggregate type this build cannot reduce.
    case unrecognizedShard
}

/// Fault injection for the ordered reset transaction. File-phase injections reuse the
/// durable boundary machinery; kill points fire strictly BETWEEN durable stages.
public struct CycleResetInjection: Sendable {
    public var journalWrite: DurabilityInjection
    public var summaryWrite: DurabilityInjection
    public var detailDelete: DurabilityInjection
    public var cycleWrite: DurabilityInjection
    public var journalClear: DurabilityInjection
    public var killAfter: ResetKillPoint?

    public init(
        journalWrite: DurabilityInjection = .none,
        summaryWrite: DurabilityInjection = .none,
        detailDelete: DurabilityInjection = .none,
        cycleWrite: DurabilityInjection = .none,
        journalClear: DurabilityInjection = .none,
        killAfter: ResetKillPoint? = nil
    ) {
        self.journalWrite = journalWrite
        self.summaryWrite = summaryWrite
        self.detailDelete = detailDelete
        self.cycleWrite = cycleWrite
        self.journalClear = journalClear
        self.killAfter = killAfter
    }

    public static let none = CycleResetInjection()
}

/// Inter-stage SIGKILL points. Each name names the durable state that must already exist
/// when the process dies: recovery resumes from the following stage.
public enum ResetKillPoint: String, Sendable {
    case journalPrepared
    case summaryWritten
    case detailsRemoved
    case cycleCommitted
}

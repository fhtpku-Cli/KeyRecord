import Foundation
import KeyRecordCore

/// Fixed canonical identities for the cycle-reset transaction (contract 9, architecture §5.1).
/// The journal identity is stable across processes and key rotations: its locator
/// `HMAC(material(version), identity)` is therefore deterministic per key version, which
/// lets bootstrap and retirement scans discover a pending journal without any pointer.
public enum CycleResetObjects: Sendable {
    public static let schemaVersion: UInt32 = 1

    public static let preferences = CanonicalLogicalIdentity(
        validatedObjectType: "com.keyrecord.preferences", schemaVersion: schemaVersion,
        logicalID: Data("current".utf8))

    public static let currentCycle = CanonicalLogicalIdentity(
        validatedObjectType: "com.keyrecord.cycle", schemaVersion: schemaVersion,
        logicalID: Data("current".utf8))

    public static let journal = CanonicalLogicalIdentity(
        validatedObjectType: "com.keyrecord.resetJournal", schemaVersion: schemaVersion,
        logicalID: Data("cycle-reset".utf8))

    public static func summary(_ cycleID: CycleID) -> CanonicalLogicalIdentity {
        CanonicalLogicalIdentity(validatedObjectType: "com.keyrecord.cycleSummary",
                                 schemaVersion: schemaVersion,
                                 logicalID: Data(cycleID.rawValue.utf8))
    }
}

public enum CycleResetIdentifiers: Sendable {
    /// The new cycle ID is a pure function of the stable operation ID, so a duplicated
    /// request after kill/reopen converges on the exact same cycle instead of minting one.
    public static func newCycleID(operationID: UUID) -> CycleID {
        CycleID(rawValue: "cycle-\(operationID.uuidString)")
    }
}

public enum ResetShardAggregate: String, Sendable {
    case shortcut
    case bareKey
}

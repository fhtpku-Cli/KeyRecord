import Foundation

public enum Phase0Registry {
    public static let spikeIDs: Set<String> = ["SP-1", "SP-2", "SP-3", "SP-4A", "SP-4B", "SP-5A", "SP-5B", "SP-6A", "SP-6B"]

    public static let legIDs: Set<String> = [
        "sp1.tap.session.matrix", "sp1.tap.annotated.matrix", "sp1.systemShortcut", "sp1.autoRepeat", "sp1.productStampedDrop", "sp1.tapReset", "sp1.o7Boundary",
        "sp2.frontmostKnown", "sp2.frontmostUnattributable", "sp2.frontmostIndeterminate", "sp2.secureInput", "sp2.excludedApp", "sp2.tapReset", "sp2.sleepWake", "sp2.sidedModifiers", "sp2.sidedRecovery", "sp2.fnRecoveryModel", "sp2.fnRecoveryLive",
        "sp3.schemaLint", "sp3.managedBlock", "sp3.atomicity", "sp3.crashRecovery", "sp3.versionSample", "sp3.reload", "sp3.disableLatency",
        "sp4a.v2Schema", "sp4a.v3Schema", "sp4a.opaqueRoundTrip", "sp4a.bounds",
        "sp4b.layoutRoundTrip", "sp4b.deviceProtocol", "sp4b.keycodeDialect", "sp4b.importer", "sp4b.bounds",
        "sp5a.vilRoundTrip", "sp5a.uidBinding", "sp5a.importer", "sp5a.bounds",
        "sp5b.whitelistSource", "sp5b.replay", "sp5b.denyMutation", "sp5b.liveCapture",
        "sp6a.envelope", "sp6a.keychainAfterFirstUnlock", "sp6a.keychainWhenUnlocked", "sp6a.keychainSelection", "sp6a.hkdfLocator", "sp6a.pathCanary", "sp6a.atomicity", "sp6a.securityAudit",
        "sp6b.phcAudit", "sp6b.swiftAudit", "sp6b.vectors", "sp6b.universalBuild", "sp6b.armTiming", "sp6b.intelTiming", "sp6b.securityAudit",
    ]

    public static let o4IDs: Set<String> = [
        "karabiner.configSchema", "karabiner.managedBlock", "karabiner.atomicReplace", "karabiner.reload", "karabiner.disableLatency",
        "via.definitionSchema", "via.deviceProtocol", "via.layoutBackupFormat", "via.keycodeDialect", "via.officialImporterCompatibility",
        "vial.definitionSchema", "vial.deviceProtocol", "vial.layoutBackupFormat", "vial.keycodeDialect", "vial.officialImporterCompatibility",
    ]
}

public struct TreeMembershipRules: Codable, Equatable, Sendable {
    public let boundRoots: [String]
    public let allowedUntrackedPrefixes: [String]
    public let allowedUntrackedExactPaths: [String]
    public let rejectSymlinks: Bool
    public let requireCommitBlobIdentity: Bool

    public static let phase0 = TreeMembershipRules(
        boundRoots: ["Spikes", "evidence/phase0"],
        allowedUntrackedPrefixes: [".omo/"],
        allowedUntrackedExactPaths: [".DS_Store"],
        rejectSymlinks: true,
        requireCommitBlobIdentity: true
    )
}

public struct ReceiptContract: Codable, Equatable, Sendable {
    public let reviewerIDs: [String]
    public let requiredStatus: String
    public let requiredCandidateFields: [String]

    public static let finalReview = ReceiptContract(
        reviewerIDs: ["F1", "F2", "F3", "F4"],
        requiredStatus: "APPROVE",
        requiredCandidateFields: ["commitSha", "treeSha", "auditBaseSha", "planSha256", "environmentSha256", "evidenceDigest", "boundInputPathsSha256", "createdAt"]
    )
}

public enum LiveProvenanceSemantics {
    public static let eventLevelAllowedEvidenceKinds: Set<EvidenceKind> = [.synthetic]
    public static let livePersistenceRule = "aggregate-counts-only"
    public static let requiredFields = ["environmentSha256", "runnerCommitSha", "runnerTreeSha", "command", "exitStatus", "artifacts"]
}

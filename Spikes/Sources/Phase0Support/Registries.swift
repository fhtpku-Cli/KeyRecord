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

    public struct LegRule: Equatable, Sendable {
        public let evidenceKind: EvidenceKind
        public let detectorID: String
        public let allowsInconclusive: Bool

        public init(_ evidenceKind: EvidenceKind, _ detectorID: String, inconclusive: Bool = false) {
            self.evidenceKind = evidenceKind
            self.detectorID = detectorID
            self.allowsInconclusive = inconclusive
        }
    }

    public static let legRules: [String: LegRule] = [
        "sp1.tap.session.matrix": .init(.live, "D2", inconclusive: true),
        "sp1.tap.annotated.matrix": .init(.live, "D2", inconclusive: true),
        "sp1.systemShortcut": .init(.live, "D1", inconclusive: true),
        "sp1.autoRepeat": .init(.synthetic, "D1"),
        "sp1.productStampedDrop": .init(.synthetic, "D1"),
        "sp1.tapReset": .init(.synthetic, "D1", inconclusive: true),
        "sp1.o7Boundary": .init(.synthetic, "D1"),
        "sp2.frontmostKnown": .init(.live, "D1", inconclusive: true),
        "sp2.frontmostUnattributable": .init(.live, "D1", inconclusive: true),
        "sp2.frontmostIndeterminate": .init(.fixture, "D0"),
        "sp2.secureInput": .init(.live, "D3", inconclusive: true),
        "sp2.excludedApp": .init(.synthetic, "D1"),
        "sp2.tapReset": .init(.synthetic, "D1"),
        "sp2.sleepWake": .init(.live, "D4", inconclusive: true),
        "sp2.sidedModifiers": .init(.fixture, "D0"),
        "sp2.sidedRecovery": .init(.synthetic, "D1"),
        "sp2.fnRecoveryModel": .init(.fixture, "D0"),
        "sp2.fnRecoveryLive": .init(.live, "D1", inconclusive: true),
        "sp3.schemaLint": .init(.fixture, "D5"),
        "sp3.managedBlock": .init(.fixture, "D0"),
        "sp3.atomicity": .init(.fixture, "D0"),
        "sp3.crashRecovery": .init(.fixture, "D0"),
        "sp3.versionSample": .init(.live, "D5", inconclusive: true),
        "sp3.reload": .init(.live, "D2", inconclusive: true),
        "sp3.disableLatency": .init(.live, "D2", inconclusive: true),
        "sp4a.v2Schema": .init(.fixture, "D0"), "sp4a.v3Schema": .init(.fixture, "D0"),
        "sp4a.opaqueRoundTrip": .init(.fixture, "D0"), "sp4a.bounds": .init(.fixture, "D0"),
        "sp4b.layoutRoundTrip": .init(.synthetic, "D0"),
        "sp4b.deviceProtocol": .init(.source, "D0", inconclusive: true),
        "sp4b.keycodeDialect": .init(.source, "D0", inconclusive: true),
        "sp4b.importer": .init(.live, "D6", inconclusive: true), "sp4b.bounds": .init(.fixture, "D0"),
        "sp5a.vilRoundTrip": .init(.synthetic, "D0"), "sp5a.uidBinding": .init(.synthetic, "D0"),
        "sp5a.importer": .init(.live, "D7", inconclusive: true), "sp5a.bounds": .init(.fixture, "D0"),
        "sp5b.whitelistSource": .init(.source, "D0"), "sp5b.replay": .init(.fixture, "D0"),
        "sp5b.denyMutation": .init(.fixture, "D0"), "sp5b.liveCapture": .init(.live, "D8", inconclusive: true),
        "sp6a.envelope": .init(.fixture, "D0"),
        "sp6a.keychainAfterFirstUnlock": .init(.live, "D9", inconclusive: true),
        "sp6a.keychainWhenUnlocked": .init(.live, "D9", inconclusive: true),
        "sp6a.keychainSelection": .init(.live, "D9", inconclusive: true),
        "sp6a.hkdfLocator": .init(.fixture, "D0"), "sp6a.pathCanary": .init(.fixture, "D0"),
        "sp6a.atomicity": .init(.fixture, "D0"), "sp6a.securityAudit": .init(.source, "D0"),
        "sp6b.phcAudit": .init(.source, "D12"), "sp6b.swiftAudit": .init(.source, "D12"),
        "sp6b.vectors": .init(.fixture, "D0"), "sp6b.universalBuild": .init(.source, "D10"),
        "sp6b.armTiming": .init(.live, "D0", inconclusive: true),
        "sp6b.intelTiming": .init(.live, "D11", inconclusive: true),
        "sp6b.securityAudit": .init(.source, "D12"),
    ]

    public static let selectedTapLegIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]
    public static let identityBoundSP1LegIDs: Set<String> = ["sp1.systemShortcut", "sp1.autoRepeat", "sp1.productStampedDrop", "sp1.tapReset", "sp1.o7Boundary"]
    public static let oDispositionIDs: Set<String> = Set((1...7).map { "O\($0)" })
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

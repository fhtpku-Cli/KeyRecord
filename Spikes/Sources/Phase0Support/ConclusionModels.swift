import Foundation

public enum ConclusionContract {
    public static let spikeIDs = ["SP-1", "SP-2", "SP-3", "SP-4A", "SP-4B", "SP-5A", "SP-5B", "SP-6A", "SP-6B"]
    public static let oItemIDs = (1...7).map { "O\($0)" }
    public static let o4IDs = [
        "karabiner.configSchema", "karabiner.managedBlock", "karabiner.atomicReplace", "karabiner.reload", "karabiner.disableLatency",
        "via.definitionSchema", "via.deviceProtocol", "via.layoutBackupFormat", "via.keycodeDialect", "via.officialImporterCompatibility",
        "vial.definitionSchema", "vial.deviceProtocol", "vial.layoutBackupFormat", "vial.keycodeDialect", "vial.officialImporterCompatibility",
    ]
    public static let downstreamBlockIDs = ["G1", "KARABINER_STABLE", "VIA_GENERATION", "VIAL_BETA", "FULL_BACKUP_FINAL_RELEASE"]
}

public struct ConclusionEvidenceBinding: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
    public let manifestPath: String
    public let manifestSha256: String
    public init(path: String, sha256: String, manifestPath: String, manifestSha256: String) { self.path = path; self.sha256 = sha256; self.manifestPath = manifestPath; self.manifestSha256 = manifestSha256 }
}

public struct ValidatedSpikeConclusion: Codable, Equatable, Sendable {
    public let id: String
    public let verdict: Verdict
    public let evidence: ConclusionEvidenceBinding
    public let runnerCommitSha: String
    public let runnerTreeSha: String
    public let passCount: Int
    public let blockedCount: Int
    public let inconclusiveCount: Int
    public let failCount: Int
    public let limitations: [String]
    public let rerunArgv: [String]
    public let dependencyFrozen: Bool
    public init(id: String, verdict: Verdict, evidence: ConclusionEvidenceBinding, runnerCommitSha: String, runnerTreeSha: String, passCount: Int, blockedCount: Int, inconclusiveCount: Int, failCount: Int, limitations: [String], rerunArgv: [String], dependencyFrozen: Bool) { self.id = id; self.verdict = verdict; self.evidence = evidence; self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha; self.passCount = passCount; self.blockedCount = blockedCount; self.inconclusiveCount = inconclusiveCount; self.failCount = failCount; self.limitations = limitations; self.rerunArgv = rerunArgv; self.dependencyFrozen = dependencyFrozen }
}

public struct ValidatedOItemDisposition: Codable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let evidencePaths: [String]
    public let blockerRefs: [String]
    public let semantics: String
    public init(id: String, status: String, evidencePaths: [String], blockerRefs: [String], semantics: String) { self.id = id; self.status = status; self.evidencePaths = evidencePaths; self.blockerRefs = blockerRefs; self.semantics = semantics }
}

public struct ValidatedO4Row: Codable, Equatable, Sendable {
    public let id: String
    public let evidencePath: String?
    public let evidenceSha256: String?
    public let blockedRef: String?
    public init(id: String, evidencePath: String?, evidenceSha256: String?, blockedRef: String?) { self.id = id; self.evidencePath = evidencePath; self.evidenceSha256 = evidenceSha256; self.blockedRef = blockedRef }
}

public struct ValidatedDownstreamBlock: Codable, Equatable, Sendable {
    public let id: String
    public let blockedCapability: String
    public let causedBy: [String]
    public let artifactRefs: [String]
    public let rerunArgv: [[String]]
    public init(id: String, blockedCapability: String, causedBy: [String], artifactRefs: [String], rerunArgv: [[String]]) { self.id = id; self.blockedCapability = blockedCapability; self.causedBy = causedBy; self.artifactRefs = artifactRefs; self.rerunArgv = rerunArgv }
}

public struct ValidatedG0: Codable, Equatable, Sendable {
    public let status: G0Status
    public let reasons: [String]
    public let blockingLegIDs: [String]
    public let candidateSelection: String?
    public init(status: G0Status, reasons: [String], blockingLegIDs: [String], candidateSelection: String?) { self.status = status; self.reasons = reasons; self.blockingLegIDs = blockingLegIDs; self.candidateSelection = candidateSelection }
}

public struct Phase0Conclusions: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceEvidenceCommitSha: String
    public let sourceEvidenceTreeSha: String
    public let sourceRootManifestSha256: String
    public let generatorCommitSha: String
    public let generatorTreeSha: String
    public let generatorSourceSha256: [String: String]
    public let spikes: [ValidatedSpikeConclusion]
    public let oItems: [ValidatedOItemDisposition]
    public let o4Matrix: [ValidatedO4Row]
    public let downstreamBlocks: [ValidatedDownstreamBlock]
    public let g0: ValidatedG0
    public init(schemaVersion: Int, sourceEvidenceCommitSha: String, sourceEvidenceTreeSha: String, sourceRootManifestSha256: String, generatorCommitSha: String, generatorTreeSha: String, generatorSourceSha256: [String: String], spikes: [ValidatedSpikeConclusion], oItems: [ValidatedOItemDisposition], o4Matrix: [ValidatedO4Row], downstreamBlocks: [ValidatedDownstreamBlock], g0: ValidatedG0) { self.schemaVersion = schemaVersion; self.sourceEvidenceCommitSha = sourceEvidenceCommitSha; self.sourceEvidenceTreeSha = sourceEvidenceTreeSha; self.sourceRootManifestSha256 = sourceRootManifestSha256; self.generatorCommitSha = generatorCommitSha; self.generatorTreeSha = generatorTreeSha; self.generatorSourceSha256 = generatorSourceSha256; self.spikes = spikes; self.oItems = oItems; self.o4Matrix = o4Matrix; self.downstreamBlocks = downstreamBlocks; self.g0 = g0 }
}

public enum ConclusionDeriver {
    public static func aggregate(_ verdicts: [Verdict]) -> Verdict {
        verdicts.max { precedence($0) < precedence($1) } ?? .blocked
    }

    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict {
        case .pass: 0
        case .inconclusive: 1
        case .blocked: 2
        case .fail: 3
        }
    }
}

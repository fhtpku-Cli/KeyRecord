import Foundation

public struct EnvironmentEvidence: Codable, Equatable, Sendable {
    public let macOS: String
    public let architecture: String
    public let swift: String
    public let xcode: String
    public let generatedAt: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case macOS, architecture, swift, xcode, generatedAt }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "EnvironmentEvidence")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        macOS = try values.decode(String.self, forKey: .macOS)
        architecture = try values.decode(String.self, forKey: .architecture)
        swift = try values.decode(String.self, forKey: .swift)
        xcode = try values.decode(String.self, forKey: .xcode)
        generatedAt = try values.decode(String.self, forKey: .generatedAt)
    }
}

public struct SourceProvenance: Codable, Equatable, Sendable {
    public let url: String
    public let retrievedAt: String
    public let sha256: String
    public let upstreamRef: String
    public let license: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case url, retrievedAt, sha256, upstreamRef, license }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SourceProvenance")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(String.self, forKey: .url)
        retrievedAt = try values.decode(String.self, forKey: .retrievedAt)
        sha256 = try values.decode(String.self, forKey: .sha256)
        upstreamRef = try values.decode(String.self, forKey: .upstreamRef)
        license = try values.decode(String.self, forKey: .license)
        guard sha256.isLowercaseSHA256 else { throw EvidenceModelError.invalidSHA256(field: "sha256") }
    }
}

public struct SpikeConclusion: Codable, Equatable, Sendable {
    public let spikeID: String
    public let verdict: Verdict
    public let legIDs: [String]
    public let artifactHashes: [ArtifactHash]
    public let downstreamBlockIDs: [String]

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case spikeID, verdict, legIDs, artifactHashes, downstreamBlockIDs }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SpikeConclusion")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spikeID = try values.decode(String.self, forKey: .spikeID)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        legIDs = try values.decode([String].self, forKey: .legIDs)
        artifactHashes = try values.decode([ArtifactHash].self, forKey: .artifactHashes)
        downstreamBlockIDs = try values.decode([String].self, forKey: .downstreamBlockIDs)
    }
}

public struct OItemDisposition: Codable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let evidencePaths: [String]
    public let blockerIDs: [String]

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case id, status, evidencePaths, blockerIDs }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "OItemDisposition")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        status = try values.decode(String.self, forKey: .status)
        evidencePaths = try values.decode([String].self, forKey: .evidencePaths)
        blockerIDs = try values.decode([String].self, forKey: .blockerIDs)
    }
}

public struct DownstreamBlock: Codable, Equatable, Sendable {
    public let id: String
    public let blockedCapability: String
    public let causedBy: [String]
    public let unblockAction: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case id, blockedCapability, causedBy, unblockAction }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "DownstreamBlock")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        blockedCapability = try values.decode(String.self, forKey: .blockedCapability)
        causedBy = try values.decode([String].self, forKey: .causedBy)
        unblockAction = try values.decode(String.self, forKey: .unblockAction)
    }
}

public enum G0Status: String, Codable, Sendable { case open = "OPEN", passed = "PASSED" }

public struct AggregateG0Result: Codable, Equatable, Sendable {
    public let status: G0Status
    public let sp1Verdict: Verdict
    public let sp2Verdict: Verdict
    public let blockingLegIDs: [String]

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case status, sp1Verdict, sp2Verdict, blockingLegIDs }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "AggregateG0Result")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decode(G0Status.self, forKey: .status)
        sp1Verdict = try values.decode(Verdict.self, forKey: .sp1Verdict)
        sp2Verdict = try values.decode(Verdict.self, forKey: .sp2Verdict)
        blockingLegIDs = try values.decode([String].self, forKey: .blockingLegIDs)
    }
}

public struct FinalCandidate: Codable, Equatable, Sendable {
    public let commitSha: String
    public let treeSha: String
    public let auditBaseSha: String
    public let planSha256: String
    public let environmentSha256: String
    public let evidenceDigest: String
    public let boundInputPathsSha256: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case commitSha, treeSha, auditBaseSha, planSha256, environmentSha256, evidenceDigest, boundInputPathsSha256, createdAt
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "FinalCandidate")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        commitSha = try values.decode(String.self, forKey: .commitSha)
        treeSha = try values.decode(String.self, forKey: .treeSha)
        auditBaseSha = try values.decode(String.self, forKey: .auditBaseSha)
        planSha256 = try values.decode(String.self, forKey: .planSha256)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        evidenceDigest = try values.decode(String.self, forKey: .evidenceDigest)
        boundInputPathsSha256 = try values.decode(String.self, forKey: .boundInputPathsSha256)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        for (field, hash) in [("commitSha", commitSha), ("treeSha", treeSha), ("auditBaseSha", auditBaseSha)] {
            guard hash.isLowercaseGitSHA1 else { throw EvidenceModelError.invalidSHA256(field: field) }
        }
        for (field, hash) in [("planSha256", planSha256), ("environmentSha256", environmentSha256), ("evidenceDigest", evidenceDigest), ("boundInputPathsSha256", boundInputPathsSha256)] {
            guard hash.isLowercaseSHA256 else { throw EvidenceModelError.invalidSHA256(field: field) }
        }
    }
}

public struct CommandResult: Codable, Equatable, Sendable {
    public let commandID: String
    public let argv: [String]
    public let exitStatus: Int32
    public let stdoutSha256: String
    public let stderrSha256: String
    public let startedAt: String
    public let endedAt: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case commandID, argv, exitStatus, stdoutSha256, stderrSha256, startedAt, endedAt }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "CommandResult")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        commandID = try values.decode(String.self, forKey: .commandID)
        argv = try values.decode([String].self, forKey: .argv)
        exitStatus = try values.decode(Int32.self, forKey: .exitStatus)
        stdoutSha256 = try values.decode(String.self, forKey: .stdoutSha256)
        stderrSha256 = try values.decode(String.self, forKey: .stderrSha256)
        startedAt = try values.decode(String.self, forKey: .startedAt)
        endedAt = try values.decode(String.self, forKey: .endedAt)
        for (field, hash) in [("stdoutSha256", stdoutSha256), ("stderrSha256", stderrSha256)] {
            guard hash.isLowercaseSHA256 else { throw EvidenceModelError.invalidSHA256(field: field) }
        }
    }
}

public struct FinalReviewReceipt: Codable, Equatable, Sendable {
    public let reviewerID: String
    public let status: String
    public let candidateSha256: String
    public let commitSha: String
    public let treeSha: String
    public let auditBaseSha: String
    public let planSha256: String
    public let environmentSha256: String
    public let evidenceDigest: String
    public let boundInputPathsSha256: String
    public let createdAt: String
    public let commandResults: [CommandResult]

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case reviewerID, status, candidateSha256, commitSha, treeSha, auditBaseSha, planSha256, environmentSha256, evidenceDigest, boundInputPathsSha256, createdAt, commandResults
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "FinalReviewReceipt")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reviewerID = try values.decode(String.self, forKey: .reviewerID)
        status = try values.decode(String.self, forKey: .status)
        candidateSha256 = try values.decode(String.self, forKey: .candidateSha256)
        commitSha = try values.decode(String.self, forKey: .commitSha)
        treeSha = try values.decode(String.self, forKey: .treeSha)
        auditBaseSha = try values.decode(String.self, forKey: .auditBaseSha)
        planSha256 = try values.decode(String.self, forKey: .planSha256)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        evidenceDigest = try values.decode(String.self, forKey: .evidenceDigest)
        boundInputPathsSha256 = try values.decode(String.self, forKey: .boundInputPathsSha256)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        commandResults = try values.decode([CommandResult].self, forKey: .commandResults)
        for (field, hash) in [("commitSha", commitSha), ("treeSha", treeSha), ("auditBaseSha", auditBaseSha)] {
            guard hash.isLowercaseGitSHA1 else { throw EvidenceModelError.invalidSHA256(field: field) }
        }
        for (field, hash) in [("candidateSha256", candidateSha256), ("planSha256", planSha256), ("environmentSha256", environmentSha256), ("evidenceDigest", evidenceDigest), ("boundInputPathsSha256", boundInputPathsSha256)] {
            guard hash.isLowercaseSHA256 else { throw EvidenceModelError.invalidSHA256(field: field) }
        }
    }
}

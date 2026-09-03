import Foundation

public enum Verdict: String, Codable, CaseIterable, Sendable {
    case pass = "PASS"
    case fail = "FAIL"
    case inconclusive = "INCONCLUSIVE"
    case blocked = "BLOCKED"
}

public enum EvidenceKind: String, Codable, CaseIterable, Sendable {
    case fixture
    case synthetic
    case source
    case live
}

public struct ArtifactHash: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case path, sha256 }

    public init(path: String, sha256: String) throws {
        guard sha256.isLowercaseSHA256 else { throw EvidenceModelError.invalidSHA256(field: path) }
        self.path = path
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "ArtifactHash")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(path: values.decode(String.self, forKey: .path), sha256: values.decode(String.self, forKey: .sha256))
    }
}

public struct Blocker: Codable, Equatable, Sendable {
    public let blockedBy: String
    public let detectCommand: [String]
    public let prerequisite: String
    public let unblockAction: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case blockedBy = "blocked_by"
        case detectCommand = "detect_command"
        case prerequisite
        case unblockAction = "unblock_action"
    }

    public init(blockedBy: String, detectCommand: [String], prerequisite: String, unblockAction: String) throws {
        for (field, value) in [("blocked_by", blockedBy), ("prerequisite", prerequisite), ("unblock_action", unblockAction)] {
            guard !value.isEmpty else { throw EvidenceModelError.invalidBlocker(field: field) }
        }
        guard !detectCommand.isEmpty, detectCommand.allSatisfy({ !$0.isEmpty }) else {
            throw EvidenceModelError.invalidBlocker(field: "detect_command")
        }
        self.blockedBy = blockedBy
        self.detectCommand = detectCommand
        self.prerequisite = prerequisite
        self.unblockAction = unblockAction
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "Blocker")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            blockedBy: values.decode(String.self, forKey: .blockedBy),
            detectCommand: values.decode([String].self, forKey: .detectCommand),
            prerequisite: values.decode(String.self, forKey: .prerequisite),
            unblockAction: values.decode(String.self, forKey: .unblockAction)
        )
    }
}

public struct ExperimentLeg: Codable, Equatable, Sendable {
    public let legID: String
    public let verdict: Verdict
    public let evidenceKind: EvidenceKind
    public let environmentSha256: String
    public let runnerCommitSha: String
    public let runnerTreeSha: String
    public let command: [String]
    public let exitStatus: Int32?
    public let artifacts: [ArtifactHash]
    public let blocker: Blocker?

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case legID = "leg_id"
        case verdict
        case evidenceKind
        case environmentSha256
        case runnerCommitSha
        case runnerTreeSha
        case command
        case exitStatus
        case artifacts
        case blocker
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "ExperimentLeg")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        legID = try values.decode(String.self, forKey: .legID)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        evidenceKind = try values.decode(EvidenceKind.self, forKey: .evidenceKind)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        runnerCommitSha = try values.decode(String.self, forKey: .runnerCommitSha)
        runnerTreeSha = try values.decode(String.self, forKey: .runnerTreeSha)
        command = try values.decode([String].self, forKey: .command)
        exitStatus = try values.decodeIfPresent(Int32.self, forKey: .exitStatus)
        artifacts = try values.decode([ArtifactHash].self, forKey: .artifacts)
        blocker = try values.decodeIfPresent(Blocker.self, forKey: .blocker)
        guard Phase0Registry.legIDs.contains(legID) else { throw EvidenceModelError.unknownLegID(legID) }
        guard environmentSha256.isLowercaseSHA256 else { throw EvidenceModelError.invalidSHA256(field: "environmentSha256") }
        guard runnerCommitSha.isLowercaseGitSHA1 else { throw EvidenceModelError.invalidSHA256(field: "runnerCommitSha") }
        guard runnerTreeSha.isLowercaseGitSHA1 else { throw EvidenceModelError.invalidSHA256(field: "runnerTreeSha") }
        if verdict == .pass && artifacts.isEmpty {
            throw EvidenceModelError.unsupportedPassWithoutArtifactHash(legID: legID)
        }
        let isValidExecutionState = verdict == .blocked
            ? blocker != nil && exitStatus == nil
            : blocker == nil && exitStatus != nil
        guard isValidExecutionState else { throw EvidenceModelError.invalidVerdictSemantics(legID: legID) }
    }
}

public struct EvidenceFixture: Codable, Equatable, Sendable {
    public let legs: [ExperimentLeg]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case legs }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "EvidenceFixture")
        legs = try decoder.container(keyedBy: CodingKeys.self).decode([ExperimentLeg].self, forKey: .legs)
    }
}

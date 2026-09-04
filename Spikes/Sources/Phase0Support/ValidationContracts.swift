import Foundation

public struct TapIdentity: Codable, Equatable, Sendable {
    public let tapType: String
    public let attemptID: String
    public let runnerCommitSha: String
    public let runnerTreeSha: String
    public let environmentSha256: String
    public let tapConfigSha256: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case tapType, attemptID, runnerCommitSha, runnerTreeSha, environmentSha256, tapConfigSha256
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "TapIdentity")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tapType = try values.decode(String.self, forKey: .tapType)
        attemptID = try values.decode(String.self, forKey: .attemptID)
        runnerCommitSha = try values.decode(String.self, forKey: .runnerCommitSha)
        runnerTreeSha = try values.decode(String.self, forKey: .runnerTreeSha)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        tapConfigSha256 = try values.decode(String.self, forKey: .tapConfigSha256)
    }
}

public struct GateLeg: Codable, Equatable, Sendable {
    public let legID: String
    public let verdict: Verdict
    public let evidenceKind: EvidenceKind
    public let detectorID: String
    public let detectorAvailable: Bool
    public let environmentSha256: String
    public let runnerCommitSha: String
    public let runnerTreeSha: String
    public let command: [String]
    public let exitStatus: Int32?
    public let artifacts: [ArtifactHash]
    public let blocker: Blocker?
    public let tapIdentity: TapIdentity?
    public let containsEventLevelData: Bool
    public let productStampedSynthetic: Bool

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case legID, verdict, evidenceKind, detectorID, detectorAvailable, environmentSha256
        case runnerCommitSha, runnerTreeSha, command, exitStatus, artifacts, blocker, tapIdentity
        case containsEventLevelData, productStampedSynthetic
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "GateLeg")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        legID = try values.decode(String.self, forKey: .legID)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        evidenceKind = try values.decode(EvidenceKind.self, forKey: .evidenceKind)
        detectorID = try values.decode(String.self, forKey: .detectorID)
        detectorAvailable = try values.decode(Bool.self, forKey: .detectorAvailable)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        runnerCommitSha = try values.decode(String.self, forKey: .runnerCommitSha)
        runnerTreeSha = try values.decode(String.self, forKey: .runnerTreeSha)
        command = try values.decode([String].self, forKey: .command)
        exitStatus = try values.decodeIfPresent(Int32.self, forKey: .exitStatus)
        artifacts = try values.decode([ArtifactHash].self, forKey: .artifacts)
        blocker = try values.decodeIfPresent(Blocker.self, forKey: .blocker)
        tapIdentity = try values.decodeIfPresent(TapIdentity.self, forKey: .tapIdentity)
        containsEventLevelData = try values.decode(Bool.self, forKey: .containsEventLevelData)
        productStampedSynthetic = try values.decode(Bool.self, forKey: .productStampedSynthetic)
    }
}

public struct O4ValidationRow: Codable, Equatable, Sendable {
    public let id: String
    public let evidencePaths: [String]
    public let blocker: Blocker?
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case id, evidencePaths, blocker }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "O4ValidationRow")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        evidencePaths = try values.decode([String].self, forKey: .evidencePaths)
        blocker = try values.decodeIfPresent(Blocker.self, forKey: .blocker)
    }
}

public struct SpikeResult: Codable, Equatable, Sendable {
    public let spikeID: String
    public let verdict: Verdict
    public let downstreamBlockIDs: [String]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case spikeID, verdict, downstreamBlockIDs }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SpikeResult")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spikeID = try values.decode(String.self, forKey: .spikeID)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        downstreamBlockIDs = try values.decode([String].self, forKey: .downstreamBlockIDs)
    }
}

public struct GateEvidenceDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let fixturePurpose: String?
    public let selectedTapIdentity: TapIdentity
    public let legs: [GateLeg]
    public let o4Rows: [O4ValidationRow]
    public let spikeResults: [SpikeResult]
    public let dispositions: [OItemDisposition]
    public let downstreamBlocks: [DownstreamBlock]
    public let g0: AggregateG0Result
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case schemaVersion, fixturePurpose, selectedTapIdentity, legs, o4Rows, spikeResults, dispositions, downstreamBlocks, g0
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "GateEvidenceDocument")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        fixturePurpose = try values.decodeIfPresent(String.self, forKey: .fixturePurpose)
        selectedTapIdentity = try values.decode(TapIdentity.self, forKey: .selectedTapIdentity)
        legs = try values.decode([GateLeg].self, forKey: .legs)
        o4Rows = try values.decode([O4ValidationRow].self, forKey: .o4Rows)
        spikeResults = try values.decode([SpikeResult].self, forKey: .spikeResults)
        dispositions = try values.decode([OItemDisposition].self, forKey: .dispositions)
        downstreamBlocks = try values.decode([DownstreamBlock].self, forKey: .downstreamBlocks)
        g0 = try values.decode(AggregateG0Result.self, forKey: .g0)
    }
}

public struct DetectorResult: Codable, Equatable, Sendable {
    public let id: String
    public let available: Bool
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case id, available }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "DetectorResult")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        available = try values.decode(Bool.self, forKey: .available)
    }
}

public struct DetectorManifest: Codable, Equatable, Sendable {
    public let fixturePurpose: String?
    public let detectors: [DetectorResult]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case fixturePurpose, detectors }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "DetectorManifest")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fixturePurpose = try values.decodeIfPresent(String.self, forKey: .fixturePurpose)
        detectors = try values.decode([DetectorResult].self, forKey: .detectors)
    }
}

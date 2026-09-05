import Foundation

public struct SP5BLeg: Codable, Equatable, Sendable {
    public var legID: String
    public var evidenceKind: EvidenceKind
    public var detectorID: String
    public var detectorAvailable: Bool
    public var verdict: Verdict
    public var blocker: SP1Blocker?
    public var runnerCommitSha: String
    public var runnerTreeSha: String
    public var environmentSha256: String
    public var command: [String]
    public var exitStatus: Int32?
    public var artifactPath: String?
    public var artifactSha256: String?
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case legID, evidenceKind, detectorID, detectorAvailable, verdict, blocker
        case runnerCommitSha, runnerTreeSha, environmentSha256, command, exitStatus, artifactPath, artifactSha256
    }

    public init(
        legID: String, evidenceKind: EvidenceKind, detectorID: String, detectorAvailable: Bool,
        verdict: Verdict, blocker: SP1Blocker?, runnerCommitSha: String, runnerTreeSha: String,
        environmentSha256: String, command: [String], exitStatus: Int32?, artifactPath: String?, artifactSha256: String?
    ) {
        self.legID = legID; self.evidenceKind = evidenceKind; self.detectorID = detectorID
        self.detectorAvailable = detectorAvailable; self.verdict = verdict; self.blocker = blocker
        self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha
        self.environmentSha256 = environmentSha256; self.command = command; self.exitStatus = exitStatus
        self.artifactPath = artifactPath; self.artifactSha256 = artifactSha256
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP5BLeg")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        legID = try values.decode(String.self, forKey: .legID)
        evidenceKind = try values.decode(EvidenceKind.self, forKey: .evidenceKind)
        detectorID = try values.decode(String.self, forKey: .detectorID)
        detectorAvailable = try values.decode(Bool.self, forKey: .detectorAvailable)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        blocker = try values.decodeIfPresent(SP1Blocker.self, forKey: .blocker)
        runnerCommitSha = try values.decode(String.self, forKey: .runnerCommitSha)
        runnerTreeSha = try values.decode(String.self, forKey: .runnerTreeSha)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        command = try values.decode([String].self, forKey: .command)
        exitStatus = try values.decodeIfPresent(Int32.self, forKey: .exitStatus)
        artifactPath = try values.decodeIfPresent(String.self, forKey: .artifactPath)
        artifactSha256 = try values.decodeIfPresent(String.self, forKey: .artifactSha256)
    }
}

public enum SP5BValidationError: String, Error, Equatable {
    case duplicateLeg, missingLeg, invalidRule, invalidExecution, invalidBlocker
    case invalidProvenance, invalidAggregate, invalidRunnerSourceSet
}

public struct SP5BEvidence: Codable, Equatable, Sendable {
    public static let requiredLegIDs = Set(Phase0Registry.legRules.keys.filter { $0.hasPrefix("sp5b.") })
    public var schemaVersion: Int
    public var spikeID: String
    public var legs: [SP5BLeg]
    public var verdict: Verdict
    public var runnerSourceSha256: [String: String]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case schemaVersion, spikeID, legs, verdict, runnerSourceSha256
    }

    public init(schemaVersion: Int = 1, legs: [SP5BLeg], verdict: Verdict, runnerSourceSha256: [String: String]) {
        self.schemaVersion = schemaVersion; spikeID = "SP-5B"; self.legs = legs
        self.verdict = verdict; self.runnerSourceSha256 = runnerSourceSha256
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP5BEvidence")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        spikeID = try values.decode(String.self, forKey: .spikeID)
        legs = try values.decode([SP5BLeg].self, forKey: .legs)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        runnerSourceSha256 = try values.decode([String: String].self, forKey: .runnerSourceSha256)
    }

    public func validate() throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        if grouped.values.contains(where: { $0.count != 1 }) { throw SP5BValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP5BValidationError.missingLeg }
        guard schemaVersion == 1, spikeID == "SP-5B" else { throw SP5BValidationError.invalidProvenance }
        guard Set(runnerSourceSha256.keys) == SP5BRunnerBinding.sourcePaths,
              runnerSourceSha256.values.allSatisfy({ $0.isLowercaseSHA256 && $0 != String(repeating: "0", count: 64) }) else {
            throw SP5BValidationError.invalidRunnerSourceSet
        }
        guard let first = legs.first else { throw SP5BValidationError.missingLeg }
        for leg in legs {
            guard let rule = Phase0Registry.legRules[leg.legID], rule.evidenceKind == leg.evidenceKind,
                  rule.detectorID == leg.detectorID else { throw SP5BValidationError.invalidRule }
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1,
                  leg.runnerCommitSha == first.runnerCommitSha, leg.runnerTreeSha == first.runnerTreeSha,
                  leg.environmentSha256.isLowercaseSHA256,
                  leg.environmentSha256 != String(repeating: "0", count: 64) else { throw SP5BValidationError.invalidProvenance }
            if let artifact = SP5BDirectoryLayout.legArtifacts[leg.legID] {
                guard leg.detectorAvailable, leg.verdict == .pass, leg.blocker == nil,
                      !leg.command.isEmpty, leg.exitStatus == 0, leg.artifactPath == artifact,
                      leg.artifactSha256?.isLowercaseSHA256 == true,
                      leg.artifactSha256 != String(repeating: "0", count: 64) else { throw SP5BValidationError.invalidExecution }
            } else {
                guard leg.legID == "sp5b.liveCapture", !leg.detectorAvailable, leg.verdict == .blocked,
                      leg.blocker?.complete == true, leg.command.isEmpty, leg.exitStatus == nil,
                      leg.artifactPath == nil, leg.artifactSha256 == nil else { throw SP5BValidationError.invalidBlocker }
            }
        }
        let aggregate = legs.map(\.verdict).max { precedence($0) < precedence($1) } ?? .blocked
        guard verdict == aggregate else { throw SP5BValidationError.invalidAggregate }
    }

    private func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

public enum SP5BRunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/run-task-qa.sh", "Spikes/Scripts/task-13-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift", "Spikes/Sources/Phase0Probe/SP5BProbe.swift",
        "Spikes/Sources/Phase0Probe/main.swift", "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP5BArtifacts.swift", "Spikes/Sources/Phase0Support/SP5BEvidence.swift",
        "Spikes/Sources/Phase0Support/SP5BScenarios.swift", "Spikes/Sources/Phase0Support/VialQuery.swift",
        "Spikes/Sources/Phase0Support/VialRecordedFixtures.swift", "Spikes/Sources/Phase0Support/VialReplay.swift",
        "Spikes/Sources/Phase0Support/VialSourceContract.swift", "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift", "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP5BDirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
    ]
}

public enum SP5BDirectoryLayout {
    public static let artifactNames: Set<String> = [
        "SP-5B-CONCLUSION.md", "deny-mutation.json", "evidence.json", "replay.json", "source-facts.json",
    ]
    public static let allNames = artifactNames.union(["manifest.sha256"])
    public static let legArtifacts = [
        "sp5b.whitelistSource": "source-facts.json", "sp5b.replay": "replay.json",
        "sp5b.denyMutation": "deny-mutation.json",
    ]
}

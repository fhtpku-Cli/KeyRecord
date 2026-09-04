import Foundation

public struct SP5ALeg: Codable, Equatable, Sendable {
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

    public init(
        legID: String, evidenceKind: EvidenceKind, detectorID: String, detectorAvailable: Bool, verdict: Verdict,
        blocker: SP1Blocker?, runnerCommitSha: String, runnerTreeSha: String, environmentSha256: String,
        command: [String], exitStatus: Int32?, artifactPath: String?, artifactSha256: String?
    ) {
        self.legID = legID; self.evidenceKind = evidenceKind; self.detectorID = detectorID
        self.detectorAvailable = detectorAvailable; self.verdict = verdict; self.blocker = blocker
        self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha; self.environmentSha256 = environmentSha256
        self.command = command; self.exitStatus = exitStatus; self.artifactPath = artifactPath; self.artifactSha256 = artifactSha256
    }
}

public enum SP5AValidationError: String, Error, Equatable {
    case duplicateLeg, missingLeg, invalidRule, invalidExecution, invalidBlocker, invalidProvenance, invalidAggregate, invalidRunnerSourceSet
}

public struct SP5AEvidence: Codable, Equatable, Sendable {
    public static let requiredLegIDs = Set(Phase0Registry.legRules.keys.filter { $0.hasPrefix("sp5a.") })
    public var schemaVersion: Int
    public var spikeID: String
    public var legs: [SP5ALeg]
    public var verdict: Verdict
    public var runnerSourceSha256: [String: String]

    public init(schemaVersion: Int = 1, legs: [SP5ALeg], verdict: Verdict, runnerSourceSha256: [String: String]) {
        self.schemaVersion = schemaVersion; spikeID = "SP-5A"; self.legs = legs; self.verdict = verdict
        self.runnerSourceSha256 = runnerSourceSha256
    }

    public func validate() throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        if grouped.values.contains(where: { $0.count != 1 }) { throw SP5AValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP5AValidationError.missingLeg }
        guard schemaVersion == 1, spikeID == "SP-5A" else { throw SP5AValidationError.invalidProvenance }
        guard Set(runnerSourceSha256.keys) == SP5ARunnerBinding.sourcePaths,
              runnerSourceSha256.values.allSatisfy({ $0.isLowercaseSHA256 && $0 != String(repeating: "0", count: 64) }) else {
            throw SP5AValidationError.invalidRunnerSourceSet
        }
        guard let first = legs.first else { throw SP5AValidationError.missingLeg }
        for leg in legs {
            guard let rule = Phase0Registry.legRules[leg.legID], rule.evidenceKind == leg.evidenceKind,
                  rule.detectorID == leg.detectorID else { throw SP5AValidationError.invalidRule }
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1,
                  leg.runnerCommitSha == first.runnerCommitSha, leg.runnerTreeSha == first.runnerTreeSha,
                  leg.environmentSha256.isLowercaseSHA256, leg.environmentSha256 != String(repeating: "0", count: 64) else {
                throw SP5AValidationError.invalidProvenance
            }
            if leg.legID == "sp5a.importer" {
                guard leg.evidenceKind == .live, leg.detectorID == "D7", !leg.detectorAvailable, leg.verdict == .blocked,
                      leg.blocker?.complete == true, leg.command.isEmpty, leg.exitStatus == nil,
                      leg.artifactPath == nil, leg.artifactSha256 == nil else { throw SP5AValidationError.invalidBlocker }
            } else {
                guard leg.detectorAvailable, leg.verdict == .pass, leg.blocker == nil, !leg.command.isEmpty, leg.exitStatus == 0,
                      let path = leg.artifactPath, SP5ADirectoryLayout.boundArtifactNames.contains(path),
                      !path.contains("/"), !path.contains(".."), leg.artifactSha256?.isLowercaseSHA256 == true,
                      leg.artifactSha256 != String(repeating: "0", count: 64) else { throw SP5AValidationError.invalidExecution }
            }
        }
        let aggregate = legs.map(\.verdict).max { Self.precedence($0) < Self.precedence($1) } ?? .blocked
        guard verdict == aggregate else { throw SP5AValidationError.invalidAggregate }
    }

    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

public enum SP5ARunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
        "Spikes/Sources/Phase0Probe/SP5AProbe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP5AArtifacts.swift",
        "Spikes/Sources/Phase0Support/SP5AEvidence.swift",
        "Spikes/Sources/Phase0Support/VialDocumentParser.swift",
        "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP5ADirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
    ]
}

public enum SP5ADirectoryLayout {
    public static let artifactNames: Set<String> = [
        "SP-5A-CONCLUSION.md", "bounds.json", "evidence.json", "format-facts.json", "round-trip.json", "uid-binding.json",
    ]
    public static let allNames = artifactNames.union(["manifest.sha256"])
    public static let boundArtifactNames = artifactNames.subtracting(["SP-5A-CONCLUSION.md", "evidence.json", "format-facts.json"])
    public static let legArtifacts = [
        "sp5a.vilRoundTrip": "round-trip.json",
        "sp5a.uidBinding": "uid-binding.json",
        "sp5a.bounds": "bounds.json",
    ]
}

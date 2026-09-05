import Foundation

public struct SP4BLeg: Codable, Equatable, Sendable {
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
}

public enum SP4BValidationError: String, Error, Equatable {
    case duplicateLeg, missingLeg, invalidRule, invalidExecution, invalidBlocker
    case invalidProvenance, invalidAggregate, invalidRunnerSourceSet
}

public struct SP4BEvidence: Codable, Equatable, Sendable {
    public static let requiredLegIDs = Set(Phase0Registry.legRules.keys.filter { $0.hasPrefix("sp4b.") })
    public var schemaVersion: Int
    public var spikeID: String
    public var legs: [SP4BLeg]
    public var verdict: Verdict
    public var runnerSourceSha256: [String: String]

    public init(schemaVersion: Int = 1, legs: [SP4BLeg], verdict: Verdict, runnerSourceSha256: [String: String]) {
        self.schemaVersion = schemaVersion; spikeID = "SP-4B"; self.legs = legs
        self.verdict = verdict; self.runnerSourceSha256 = runnerSourceSha256
    }

    public func validate() throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        if grouped.values.contains(where: { $0.count != 1 }) { throw SP4BValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP4BValidationError.missingLeg }
        guard schemaVersion == 1, spikeID == "SP-4B" else { throw SP4BValidationError.invalidProvenance }
        guard Set(runnerSourceSha256.keys) == SP4BRunnerBinding.sourcePaths,
              runnerSourceSha256.values.allSatisfy({ $0.isLowercaseSHA256 && $0 != String(repeating: "0", count: 64) }) else {
            throw SP4BValidationError.invalidRunnerSourceSet
        }
        guard let first = legs.first else { throw SP4BValidationError.missingLeg }
        for leg in legs {
            guard let rule = Phase0Registry.legRules[leg.legID], rule.evidenceKind == leg.evidenceKind,
                  rule.detectorID == leg.detectorID else { throw SP4BValidationError.invalidRule }
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1,
                  leg.runnerCommitSha == first.runnerCommitSha, leg.runnerTreeSha == first.runnerTreeSha,
                  leg.environmentSha256.isLowercaseSHA256,
                  leg.environmentSha256 != String(repeating: "0", count: 64) else { throw SP4BValidationError.invalidProvenance }
            if SP4BDirectoryLayout.legArtifacts[leg.legID] != nil {
                guard leg.detectorAvailable, leg.verdict == .pass, leg.blocker == nil,
                      !leg.command.isEmpty, leg.exitStatus == 0,
                      let path = leg.artifactPath, path == SP4BDirectoryLayout.legArtifacts[leg.legID],
                      leg.artifactSha256?.isLowercaseSHA256 == true,
                      leg.artifactSha256 != String(repeating: "0", count: 64) else { throw SP4BValidationError.invalidExecution }
            } else {
                guard !leg.detectorAvailable, leg.verdict == .blocked, leg.blocker?.complete == true,
                      leg.command.isEmpty, leg.exitStatus == nil, leg.artifactPath == nil,
                      leg.artifactSha256 == nil else { throw SP4BValidationError.invalidBlocker }
            }
        }
        let aggregate = legs.map(\.verdict).max { precedence($0) < precedence($1) } ?? .blocked
        guard verdict == aggregate else { throw SP4BValidationError.invalidAggregate }
    }

    private func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

public enum SP4BRunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/run-task-qa.sh", "Spikes/Scripts/task-12-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift", "Spikes/Sources/Phase0Probe/SP4BProbe.swift",
        "Spikes/Sources/Phase0Probe/main.swift", "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP4BArtifacts.swift", "Spikes/Sources/Phase0Support/SP4BEvidence.swift",
        "Spikes/Sources/Phase0Support/ViaDefinitionParser.swift", "Spikes/Sources/Phase0Support/ViaLayoutJSONScanner.swift",
        "Spikes/Sources/Phase0Support/ViaLayoutParser.swift", "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift", "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP4BDirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
    ]
}

public enum SP4BDirectoryLayout {
    public static let artifactNames: Set<String> = [
        "SP-4B-CONCLUSION.md", "axes.json", "bounds.json", "evidence.json", "round-trip.json", "source-facts.json",
    ]
    public static let allNames = artifactNames.union(["manifest.sha256"])
    public static let boundArtifactNames = Set(["bounds.json", "round-trip.json"])
    public static let legArtifacts = ["sp4b.layoutRoundTrip": "round-trip.json", "sp4b.bounds": "bounds.json"]
}

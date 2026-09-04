import Foundation

public struct SP3Leg: Codable, Equatable, Sendable {
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

    public init(legID: String, evidenceKind: EvidenceKind, detectorID: String, detectorAvailable: Bool, verdict: Verdict,
                blocker: SP1Blocker?, runnerCommitSha: String, runnerTreeSha: String, environmentSha256: String,
                command: [String], exitStatus: Int32?, artifactPath: String? = nil, artifactSha256: String? = nil) {
        self.legID = legID; self.evidenceKind = evidenceKind; self.detectorID = detectorID; self.detectorAvailable = detectorAvailable
        self.verdict = verdict; self.blocker = blocker; self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha
        self.environmentSha256 = environmentSha256; self.command = command; self.exitStatus = exitStatus
        self.artifactPath = artifactPath; self.artifactSha256 = artifactSha256
    }
}

public enum SP3ValidationError: String, Error, Equatable {
    case duplicateLeg, missingLeg, invalidRule, invalidVerdict, invalidBlocker, invalidProvenance, invalidAggregate, invalidRunnerSourceSet
}

public struct SP3Evidence: Codable, Equatable, Sendable {
    public static let requiredLegIDs = Set(Phase0Registry.legRules.keys.filter { $0.hasPrefix("sp3.") })
    public var schemaVersion: Int
    public var spikeID: String
    public var legs: [SP3Leg]
    public var verdict: Verdict
    public var runnerSourceSha256: [String: String]

    public init(schemaVersion: Int = 1, legs: [SP3Leg], verdict: Verdict, runnerSourceSha256: [String: String]) {
        self.schemaVersion = schemaVersion; spikeID = "SP-3"; self.legs = legs; self.verdict = verdict
        self.runnerSourceSha256 = runnerSourceSha256
    }

    public func validate() throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        if grouped.values.contains(where: { $0.count != 1 }) { throw SP3ValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP3ValidationError.missingLeg }
        guard schemaVersion == 1, spikeID == "SP-3" else { throw SP3ValidationError.invalidProvenance }
        guard Set(runnerSourceSha256.keys) == SP3RunnerBinding.sourcePaths,
              runnerSourceSha256.values.allSatisfy({ $0.isLowercaseSHA256 && $0 != String(repeating: "0", count: 64) }) else {
            throw SP3ValidationError.invalidRunnerSourceSet
        }
        guard let first = legs.first else { throw SP3ValidationError.missingLeg }
        for leg in legs {
            guard let rule = Phase0Registry.legRules[leg.legID], rule.evidenceKind == leg.evidenceKind,
                  rule.detectorID == leg.detectorID else { throw SP3ValidationError.invalidRule }
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1,
                  leg.runnerCommitSha == first.runnerCommitSha, leg.runnerTreeSha == first.runnerTreeSha,
                  leg.environmentSha256.isLowercaseSHA256, leg.environmentSha256 != String(repeating: "0", count: 64) else {
                throw SP3ValidationError.invalidProvenance
            }
            if leg.verdict == .blocked {
                guard !leg.detectorAvailable, leg.blocker?.complete == true, leg.command.isEmpty,
                      leg.exitStatus == nil, leg.artifactPath == nil, leg.artifactSha256 == nil else { throw SP3ValidationError.invalidBlocker }
            } else {
                guard leg.detectorAvailable, leg.blocker == nil, !leg.command.isEmpty, leg.exitStatus != nil,
                      let path = leg.artifactPath, !path.isEmpty, !path.contains("/"), !path.contains(".."),
                      leg.artifactSha256?.isLowercaseSHA256 == true,
                      leg.artifactSha256 != String(repeating: "0", count: 64) else { throw SP3ValidationError.invalidVerdict }
                if leg.verdict == .inconclusive, !rule.allowsInconclusive { throw SP3ValidationError.invalidVerdict }
            }
        }
        let aggregate = legs.map(\.verdict).max { Self.precedence($0) < Self.precedence($1) } ?? .blocked
        guard verdict == aggregate else { throw SP3ValidationError.invalidAggregate }
    }
    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

public enum SP3RunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
        "Spikes/Sources/Phase0Probe/SP3Probe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/AtomicityEvidence.swift",
        "Spikes/Sources/Phase0Support/KarabinerManagedBlock.swift",
        "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP3Evidence.swift",
        "Spikes/Sources/Phase0Support/SP3FixtureScenarios.swift",
        "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP3DirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
    ]
}

public enum SP3DirectoryLayout {
    public static let artifactNames: Set<String> = [
        "SP-3-CONCLUSION.md", "atomicity-citation.json", "evidence.json", "format-facts.json", "lint-results.json", "managed-block.json", "recovery.json",
    ]
    public static let allNames = artifactNames.union(["manifest.sha256"])
    public static let boundArtifactNames = artifactNames.subtracting(["SP-3-CONCLUSION.md", "evidence.json"])
}

public struct SP3ManagedBlockArtifact: Codable, Equatable, Sendable {
    public let upstreamFixturePath: String
    public let upstreamFixtureSha256: String
    public let insertPreservedOutsideBytes: Bool
    public let updatePreservedOutsideBytes: Bool
    public let clearPreservedOutsideBytes: Bool
    public let restorePreservedOutsideBytes: Bool
    public let threeRuleBatchCount: Int
    public let malformedRejected: Bool
    public let duplicateRejected: Bool
    public let baselineMismatchRejected: Bool
    public let externalEditRefused: Bool
    public let maximumBytes: Int
    public let maximumDepth: Int
}

public struct SP3RecoveryArtifact: Codable, Equatable, Sendable {
    public let hExpect: String
    public let hBase: String
    public let external: String
    public let crashBoundaries: [String: String]
    public let automaticExternalWrite: Bool
}

public struct SP3AtomicityCitation: Codable, Equatable, Sendable {
    public let artifactPath: String
    public let artifactSha256: String
    public let manifestPath: String
    public let citedBy: [String]
    public init(artifactPath: String, artifactSha256: String, manifestPath: String, citedBy: [String]) {
        self.artifactPath = artifactPath; self.artifactSha256 = artifactSha256; self.manifestPath = manifestPath; self.citedBy = citedBy
    }
}

public struct SP3FormatFacts: Codable, Equatable, Sendable {
    public let upstreamRepository: String
    public let upstreamCommit: String
    public let upstreamTree: String
    public let lintSourcePath: String
    public let fixtureSourcePath: String
    public let currentFormat: String
    public let descriptionNotesMinimumVersion: String
    public let descriptionNotesSourceURL: String
    public let supportMatrixStatus: Verdict
    public let limitation: String
}

public struct SP3LintArtifact: Codable, Equatable, Sendable {
    public let executed: Bool
    public let cliPath: String?
    public let version: String?
    public let validAccepted: [String]
    public let invalidRejected: [String]
    public let blockedBy: String?
    public init(executed: Bool, cliPath: String?, version: String?, validAccepted: [String], invalidRejected: [String], blockedBy: String?) {
        self.executed = executed; self.cliPath = cliPath; self.version = version; self.validAccepted = validAccepted
        self.invalidRejected = invalidRejected; self.blockedBy = blockedBy
    }
}

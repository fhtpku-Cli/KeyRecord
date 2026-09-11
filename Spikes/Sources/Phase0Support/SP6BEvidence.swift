import Foundation

public struct SP6BLeg: Codable, Equatable, Sendable {
    public let legID: String
    public let evidenceKind: EvidenceKind
    public let detectorID: String
    public let detectorAvailable: Bool
    public let verdict: Verdict
    public let blocker: SP1Blocker?
    public let runnerCommitSha: String
    public let runnerTreeSha: String
    public let environmentSha256: String
    public let command: [String]
    public let exitStatus: Int32?
    public let artifactPath: String?
    public let artifactSha256: String?
}

public enum SP6BBlockers {
    public static let intelHost = SP1Blocker(
        blockedBy: "physical_intel_macos14_host_unavailable",
        detectCommand: ["uname", "-m"], prerequisite: "physical x86_64 Mac running macOS 14 or later",
        unblockAction: "Run the bound benchmark with frozen recommended parameters on a physical Intel macOS 14+ host"
    )
}

public enum SP6BValidationError: String, Error {
    case aggregate, blocker, duplicateLeg, execution, legSet, provenance, rule, runnerSourceSet
}

public struct SP6BEvidence: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let spikeID: String
    public let dependencyFrozen: Bool
    public let recommendedCandidate: String
    public let legs: [SP6BLeg]
    public let verdict: Verdict
    public let runnerSourceSha256: [String: String]

    public func validate() throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { throw SP6BValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP6BValidationError.legSet }
        guard schemaVersion == 2, ISO8601DateFormatter().date(from: generatedAt) != nil,
              spikeID == "SP-6B", !dependencyFrozen, recommendedCandidate == "phc",
              let first = legs.first else { throw SP6BValidationError.provenance }
        guard Set(runnerSourceSha256.keys) == SP6BRunnerBinding.sourcePaths,
              runnerSourceSha256.values.allSatisfy(\.isLowercaseSHA256) else { throw SP6BValidationError.runnerSourceSet }
        for leg in legs {
            guard let rule = Phase0Registry.legRules[leg.legID], rule.evidenceKind == leg.evidenceKind,
                  rule.detectorID == leg.detectorID else { throw SP6BValidationError.rule }
            guard leg.runnerCommitSha == first.runnerCommitSha, leg.runnerTreeSha == first.runnerTreeSha,
                  leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1,
                  leg.environmentSha256.isLowercaseSHA256 else { throw SP6BValidationError.provenance }
            if leg.legID == "sp6b.intelTiming" {
                guard !leg.detectorAvailable, leg.verdict == .blocked, leg.blocker == SP6BBlockers.intelHost,
                      leg.command.isEmpty, leg.exitStatus == nil, leg.artifactPath == nil,
                      leg.artifactSha256 == nil else { throw SP6BValidationError.blocker }
            } else {
                guard leg.detectorAvailable, leg.verdict == .pass, leg.blocker == nil, !leg.command.isEmpty,
                      leg.exitStatus == 0, let path = leg.artifactPath, !path.contains(".."),
                      leg.artifactSha256?.isLowercaseSHA256 == true else { throw SP6BValidationError.execution }
            }
        }
        guard verdict == .blocked else { throw SP6BValidationError.aggregate }
    }

    public static let requiredLegIDs = Set(Phase0Registry.legRules.keys.filter { $0.hasPrefix("sp6b.") })
}

public struct SP6BCandidateEvaluation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let candidates: [Argon2Candidate]
    public let scores: [String: Argon2Score]
    public let eligibleCandidateIDs: [String]
    public let recommendation: String
    public let dependencyFrozen: Bool

    public func validate() throws {
        guard schemaVersion == 1, !dependencyFrozen, let date = ISO8601DateFormatter().date(from: generatedAt),
              Set(candidates.map(\.id)) == ["phc", "swift"], candidates.count == 2 else { throw SP6BValidationError.provenance }
        let eligible = candidates.filter(\.isEligible)
        guard eligibleCandidateIDs == eligible.map(\.id).sorted(), Set(scores.keys) == Set(candidates.map(\.id)) else { throw SP6BValidationError.execution }
        for candidate in candidates { guard try scores[candidate.id] == candidate.score(at: date) else { throw SP6BValidationError.execution } }
        guard try Argon2Ranking.recommend(candidates, at: date).id == recommendation else { throw SP6BValidationError.execution }
    }
}

public enum SP6BRunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/argon-bench.c", "Spikes/Scripts/argon-swift-vector.swift", "Spikes/Scripts/argon-vector.c",
        "Spikes/Scripts/audit-argon-sources.sh", "Spikes/Scripts/audit-security.sh",
        "Spikes/Scripts/benchmark-argon-arm.sh", "Spikes/Scripts/build-argon-universal.sh",
        "Spikes/Scripts/capture-argon-advisories.sh", "Spikes/Scripts/run-sp6b.sh", "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Scripts/sp6b-nvd-review.json", "Spikes/Scripts/sp6b-source-contract.json", "Spikes/Scripts/task-11-qa.sh",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift", "Spikes/Sources/EvidenceValidator/SP6BBenchmarkValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BBuildValidator.swift", "Spikes/Sources/EvidenceValidator/SP6BDirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BNVDValidator.swift", "Spikes/Sources/EvidenceValidator/SP6BSourceValidator.swift",
        "Spikes/Sources/Phase0Probe/SP6BProbe.swift", "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/Argon2Candidate.swift", "Spikes/Sources/Phase0Support/D12Fixture.swift", "Spikes/Sources/Phase0Support/D12Snapshot.swift",
        "Spikes/Sources/Phase0Support/SP6BEvidence.swift", "Spikes/Tests/EvidenceValidatorTests/SP6BValidatorTests.swift",
        "Spikes/Tests/Phase0SupportTests/Argon2AuditTests.swift",
    ]
}

public enum SP6BHistoricalSealContract {
    public static let sealCommitSha = "7a394243bb498de43478d436ffe3839795c749ad"
    public static let runnerCommitSha = "b19a3436606a2cbafadf38140d96824dac39f2ec"
    public static let runnerTreeSha = "97b003dda9d6519b74f7402585b765b84d051093"
    public static let executionEnvironmentSha256 = "6b3288f5983cbce231295762d3f8381b8467d6dbe2e74fff0e17a1aebf7215f4"
    public static let sealPath = "evidence/phase0/sp6b"
}

public enum SP6BDirectoryLayout {
    public static let fixedArtifactNames: Set<String> = [
        "SP-6B-CONCLUSION.md", "arm-benchmark.json", "build/argon2-universal.a", "build/build.json",
        "build/phc-vector.txt", "build/swift-vector.txt", "candidate-evaluation.json", "d12/snapshot.json",
        "dependency-audit.md", "evidence.json", "intel-blocker.json", "source-audit.json",
    ]
    public static let legArtifacts = [
        "sp6b.phcAudit": "dependency-audit.md", "sp6b.swiftAudit": "dependency-audit.md",
        "sp6b.vectors": "build/build.json", "sp6b.universalBuild": "build/argon2-universal.a",
        "sp6b.armTiming": "arm-benchmark.json", "sp6b.securityAudit": "dependency-audit.md",
    ]
}

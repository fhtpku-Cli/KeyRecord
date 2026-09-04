import Foundation

public struct SP6ALeg: Codable, Equatable, Sendable {
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
        blocker: SP1Blocker? = nil, runnerCommitSha: String, runnerTreeSha: String, environmentSha256: String,
        command: [String], exitStatus: Int32?, artifactPath: String?, artifactSha256: String?
    ) {
        self.legID = legID; self.evidenceKind = evidenceKind; self.detectorID = detectorID
        self.detectorAvailable = detectorAvailable; self.verdict = verdict; self.blocker = blocker
        self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha; self.environmentSha256 = environmentSha256
        self.command = command; self.exitStatus = exitStatus; self.artifactPath = artifactPath; self.artifactSha256 = artifactSha256
    }
}

public enum SP6AValidationError: String, Error, Equatable {
    case duplicateLeg, invalidAggregate, invalidBlocker, invalidExecution, invalidProvenance, invalidRule
    case invalidRunnerSourceSet, misleadingSelection, missingLeg
}

public enum SP6AD9Blocker {
    public static let expected = SP1Blocker(
        blockedBy: "data_protection_keychain_entitlement_unavailable",
        detectCommand: ["SecItemDelete", "isolated-random-service", "kSecUseDataProtectionKeychain=true"],
        prerequisite: "signed probe runner with an application identifier entitlement and isolated data-protection Keychain access",
        unblockAction: "Run the same bound probe from a separately approved signed helper without locking, logging out, or restarting the host"
    )
}

public struct SP6AEvidence: Codable, Equatable, Sendable {
    public static let requiredLegIDs = Set(Phase0Registry.legRules.keys.filter { $0.hasPrefix("sp6a.") })
    public var schemaVersion: Int
    public var spikeID: String
    public var legs: [SP6ALeg]
    public var verdict: Verdict
    public var runnerSourceSha256: [String: String]

    public init(schemaVersion: Int = 1, legs: [SP6ALeg], verdict: Verdict, runnerSourceSha256: [String: String]) {
        self.schemaVersion = schemaVersion; spikeID = "SP-6A"; self.legs = legs; self.verdict = verdict
        self.runnerSourceSha256 = runnerSourceSha256
    }

    public func validate() throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        if grouped.values.contains(where: { $0.count != 1 }) { throw SP6AValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP6AValidationError.missingLeg }
        guard schemaVersion == 1, spikeID == "SP-6A", let first = legs.first else { throw SP6AValidationError.invalidProvenance }
        guard Set(runnerSourceSha256.keys) == SP6ARunnerBinding.sourcePaths,
              runnerSourceSha256.values.allSatisfy({ $0.isLowercaseSHA256 && $0 != String(repeating: "0", count: 64) }) else {
            throw SP6AValidationError.invalidRunnerSourceSet
        }
        for leg in legs {
            guard let rule = Phase0Registry.legRules[leg.legID], rule.evidenceKind == leg.evidenceKind,
                  rule.detectorID == leg.detectorID else { throw SP6AValidationError.invalidRule }
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1,
                  leg.runnerCommitSha == first.runnerCommitSha, leg.runnerTreeSha == first.runnerTreeSha,
                  leg.environmentSha256.isLowercaseSHA256 else { throw SP6AValidationError.invalidProvenance }
            if leg.detectorID == "D9", !leg.detectorAvailable {
                guard leg.verdict == .blocked, leg.blocker == SP6AD9Blocker.expected, leg.command.isEmpty, leg.exitStatus == nil,
                      leg.artifactPath == nil, leg.artifactSha256 == nil else { throw SP6AValidationError.invalidBlocker }
            } else {
                guard leg.detectorAvailable, leg.blocker == nil, !leg.command.isEmpty, leg.exitStatus == 0,
                      let path = leg.artifactPath, SP6ADirectoryLayout.boundArtifactNames.contains(path),
                      !path.contains("/"), !path.contains(".."), leg.artifactSha256?.isLowercaseSHA256 == true else {
                    throw SP6AValidationError.invalidExecution
                }
                if leg.legID == "sp6a.keychainSelection" {
                    guard leg.verdict == .inconclusive else { throw SP6AValidationError.misleadingSelection }
                } else if leg.verdict != .pass {
                    throw SP6AValidationError.invalidExecution
                }
            }
        }
        let aggregate = legs.map(\.verdict).max { Self.precedence($0) < Self.precedence($1) } ?? .blocked
        guard verdict == aggregate else { throw SP6AValidationError.invalidAggregate }
    }

    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

public enum SP6ARunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/audit-security.sh", "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift", "Spikes/Sources/Phase0Probe/SP6AKeychainProbe.swift",
        "Spikes/Sources/Phase0Probe/SP6AProbe.swift", "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/AuthenticatedStorage.swift", "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP6AArtifacts.swift", "Spikes/Sources/Phase0Support/SP6AEvidence.swift",
        "Spikes/Sources/Phase0Support/SP6ANamespaceEvidence.swift",
        "Spikes/Sources/EvidenceValidator/AtomicityHistoricalValidator.swift", "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift", "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP6ADirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/SP6ANamespaceValidator.swift",
        "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
        "Spikes/Tests/EvidenceValidatorTests/SP6ANamespaceValidatorTests.swift",
        "Spikes/Tests/EvidenceValidatorTests/SP6AValidatorTests.swift",
        "Spikes/Tests/Phase0ProbeTests/Phase0ProbeTests.swift",
        "Spikes/Tests/Phase0SupportTests/StorageSecurityTests.swift",
    ]
}

public enum SP6ADirectoryLayout {
    public static let artifactNames: Set<String> = [
        "SP-6A-CONCLUSION.md", "atomicity-citation.json", "crypto.json", "evidence.json", "keychain.json",
        "locator.json", "path-canary.json", "security-audit.md",
    ]
    public static let allNames = artifactNames.union(["manifest.sha256"])
    public static let boundArtifactNames = artifactNames.subtracting(["SP-6A-CONCLUSION.md", "evidence.json"])
    public static let legArtifacts = [
        "sp6a.envelope": "crypto.json", "sp6a.keychainAfterFirstUnlock": "keychain.json",
        "sp6a.keychainWhenUnlocked": "keychain.json", "sp6a.keychainSelection": "keychain.json",
        "sp6a.hkdfLocator": "locator.json", "sp6a.pathCanary": "path-canary.json",
        "sp6a.atomicity": "atomicity-citation.json", "sp6a.securityAudit": "security-audit.md",
    ]
}

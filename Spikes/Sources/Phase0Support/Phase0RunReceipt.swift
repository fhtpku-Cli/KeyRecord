import Foundation

public struct Phase0RunStage: Codable, Equatable, Sendable {
    public let id: String
    public let command: [String]
    public let exitStatus: Int32
    public let stdout: String
    public let stderr: String
    public let verdict: String?
    public let policy: String
    public let artifactSha256: String?

    public init(id: String, command: [String], exitStatus: Int32, stdout: String, stderr: String,
                verdict: String?, policy: String, artifactSha256: String?) {
        self.id = id
        self.command = command
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
        self.verdict = verdict
        self.policy = policy
        self.artifactSha256 = artifactSha256
    }
}

public struct Phase0ToolVersion: Codable, Equatable, Sendable {
    public let tool: String
    public let command: [String]
    public let exitStatus: Int32
    public let stdout: String
    public let stderr: String

    public init(tool: String, command: [String], exitStatus: Int32, stdout: String, stderr: String) {
        self.tool = tool
        self.command = command
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct Phase0RunReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runnerCommitSha: String
    public let runnerTreeSha: String
    public let runnerSourceSha256: [String: String]
    public let environmentSha256: String
    public let directories: [String]
    public let rootArtifacts: [String]
    public let stages: [Phase0RunStage]
    public let toolVersions: [Phase0ToolVersion]
    public let conclusionGenerated: Bool

    public init(runnerCommitSha: String, runnerTreeSha: String, runnerSourceSha256: [String: String],
                environmentSha256: String, directories: [String], rootArtifacts: [String],
                stages: [Phase0RunStage], toolVersions: [Phase0ToolVersion]) {
        schemaVersion = 1
        self.runnerCommitSha = runnerCommitSha
        self.runnerTreeSha = runnerTreeSha
        self.runnerSourceSha256 = runnerSourceSha256
        self.environmentSha256 = environmentSha256
        self.directories = directories
        self.rootArtifacts = rootArtifacts
        self.stages = stages
        self.toolVersions = toolVersions
        conclusionGenerated = false
    }
}

public enum Phase0RunLayout {
    public static let spikeDirectories = ["sp1", "sp2", "sp3", "sp4a", "sp4b", "sp5a", "sp5b", "sp6a", "sp6b"]
    public static let directories = ["fixtures", "shared-atomicity", "sources"] + spikeDirectories
    public static let rootArtifacts = ["README.md", "environment.json", "privacy-audit.json", "run-all.json"]
    public static let rootFiles = Set(rootArtifacts + ["manifest.sha256"])
}

public enum Phase0RunBinding {
    public static let sourcePaths: Set<String> = AtomicityRunnerBinding.sourcePaths
        .union(SP1RunnerBinding.sourcePaths).union(SP2RunnerBinding.sourcePaths)
        .union(SP3RunnerBinding.sourcePaths).union(SP4ARunnerBinding.sourcePaths)
        .union(SP4BRunnerBinding.sourcePaths).union(SP5ARunnerBinding.sourcePaths)
        .union(SP5BRunnerBinding.sourcePaths).union(SP6ARunnerBinding.sourcePaths)
        .union(SP6BRunnerBinding.sourcePaths).union([
        "Spikes/Scripts/run-task-qa.sh", "Spikes/Scripts/task-14-qa.sh", "Spikes/Scripts/verify-manifests.sh",
        "Spikes/Sources/EvidenceValidator/AtomicityHistoricalValidator.swift",
        "Spikes/Sources/EvidenceValidator/CandidateBinder.swift", "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/GateValidator.swift", "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/EvidenceValidator/Phase0RootValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP1DirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/SP2DirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP3DirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/SP4ADirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP4BDirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/SP5ADirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP5BDirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/SP6ADirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6AHistoryAnchorValidator.swift", "Spikes/Sources/EvidenceValidator/SP6ANamespaceValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BDirectoryValidator.swift", "Spikes/Sources/EvidenceValidator/SP6BBenchmarkValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BBuildValidator.swift", "Spikes/Sources/EvidenceValidator/SP6BNVDValidator.swift",
        "Spikes/Sources/EvidenceValidator/ReceiptValidator.swift", "Spikes/Sources/EvidenceValidator/SP6BSourceValidator.swift",
        "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift", "Spikes/Sources/Phase0Probe/RunAllProbe.swift",
        "Spikes/Sources/Phase0Probe/RunAllPublication.swift", "Spikes/Sources/Phase0Probe/RunAllSignalCleanup.swift",
        "Spikes/Sources/Phase0Probe/RunAllTestDelay.swift", "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/FinalReviewCommands.swift", "Spikes/Sources/Phase0Support/Phase0Privacy.swift",
        "Spikes/Sources/Phase0Support/Phase0RunReceipt.swift", "Spikes/Sources/Phase0Support/SourceLedger.swift",
        "Spikes/Sources/Phase0Support/StrictCoding.swift", "Spikes/Sources/Phase0Support/ValidationContracts.swift",
        "Spikes/Tests/EvidenceValidatorTests/Phase0RootValidatorTests.swift",
        "Spikes/Tests/Phase0ProbeTests/RunAllProbeTests.swift"
    ])
}

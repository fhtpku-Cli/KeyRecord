import CryptoKit
import Foundation

public enum AtomicityTerminalState: String, Codable, Sendable { case old, new }

public struct AtomicityHost: Codable, Equatable, Sendable {
    public let filesystem: String
    public let macOSVersion: String
    public let macOSBuild: String
    public let architecture: String
    public let hostHash: String

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case filesystem, macOSVersion, macOSBuild, architecture, hostHash
    }

    public init(filesystem: String, macOSVersion: String, macOSBuild: String, architecture: String) {
        self.filesystem = filesystem
        self.macOSVersion = macOSVersion
        self.macOSBuild = macOSBuild
        self.architecture = architecture
        hostHash = AtomicityDigest.sha256(Data("\(filesystem)\n\(macOSVersion)\n\(macOSBuild)\n\(architecture)\n".utf8))
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "AtomicityHost")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        filesystem = try values.decode(String.self, forKey: .filesystem)
        macOSVersion = try values.decode(String.self, forKey: .macOSVersion)
        macOSBuild = try values.decode(String.self, forKey: .macOSBuild)
        architecture = try values.decode(String.self, forKey: .architecture)
        hostHash = try values.decode(String.self, forKey: .hostHash)
    }
}

public struct AtomicityExecution: Codable, Equatable, Sendable {
    public let iteration: Int
    public let observedHash: String
    public let terminalState: AtomicityTerminalState

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case iteration, observedHash, terminalState }
    public init(iteration: Int, observedHash: String, terminalState: AtomicityTerminalState) {
        self.iteration = iteration; self.observedHash = observedHash; self.terminalState = terminalState
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "AtomicityExecution")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        iteration = try values.decode(Int.self, forKey: .iteration)
        observedHash = try values.decode(String.self, forKey: .observedHash)
        terminalState = try values.decode(AtomicityTerminalState.self, forKey: .terminalState)
    }
}

public struct AtomicityBoundaryResult: Codable, Equatable, Sendable {
    public let boundary: AtomicReplacementCrashBoundary
    public let observedHash: String
    public let terminalState: AtomicityTerminalState
    public let injectedStatus: String
    public let staleTemporaryFilesBeforeCleanup: Int
    public let staleTemporaryFilesAfterCleanup: Int

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case boundary, observedHash, terminalState, injectedStatus, staleTemporaryFilesBeforeCleanup, staleTemporaryFilesAfterCleanup
    }
    public init(boundary: AtomicReplacementCrashBoundary, observedHash: String, terminalState: AtomicityTerminalState, injectedStatus: String, staleTemporaryFilesBeforeCleanup: Int, staleTemporaryFilesAfterCleanup: Int) {
        self.boundary = boundary; self.observedHash = observedHash; self.terminalState = terminalState
        self.injectedStatus = injectedStatus; self.staleTemporaryFilesBeforeCleanup = staleTemporaryFilesBeforeCleanup
        self.staleTemporaryFilesAfterCleanup = staleTemporaryFilesAfterCleanup
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "AtomicityBoundaryResult")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        boundary = try values.decode(AtomicReplacementCrashBoundary.self, forKey: .boundary)
        observedHash = try values.decode(String.self, forKey: .observedHash)
        terminalState = try values.decode(AtomicityTerminalState.self, forKey: .terminalState)
        injectedStatus = try values.decode(String.self, forKey: .injectedStatus)
        staleTemporaryFilesBeforeCleanup = try values.decode(Int.self, forKey: .staleTemporaryFilesBeforeCleanup)
        staleTemporaryFilesAfterCleanup = try values.decode(Int.self, forKey: .staleTemporaryFilesAfterCleanup)
    }
}

public struct AtomicityFailureResult: Codable, Equatable, Sendable {
    public let step: AtomicReplacementFailureStep
    public let observedHash: String
    public let terminalState: AtomicityTerminalState
    public let injectedStatus: String
    public let temporaryFilesAfterCleanup: Int

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case step, observedHash, terminalState, injectedStatus, temporaryFilesAfterCleanup
    }
    public init(step: AtomicReplacementFailureStep, observedHash: String, terminalState: AtomicityTerminalState, injectedStatus: String, temporaryFilesAfterCleanup: Int) {
        self.step = step; self.observedHash = observedHash; self.terminalState = terminalState
        self.injectedStatus = injectedStatus; self.temporaryFilesAfterCleanup = temporaryFilesAfterCleanup
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "AtomicityFailureResult")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        step = try values.decode(AtomicReplacementFailureStep.self, forKey: .step)
        observedHash = try values.decode(String.self, forKey: .observedHash)
        terminalState = try values.decode(AtomicityTerminalState.self, forKey: .terminalState)
        injectedStatus = try values.decode(String.self, forKey: .injectedStatus)
        temporaryFilesAfterCleanup = try values.decode(Int.self, forKey: .temporaryFilesAfterCleanup)
    }
}

public struct AtomicityEvidence: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let verdict: Verdict
    public let scope: String
    public let limitation: String
    public let ordinaryRenameObservedAtomic: Bool
    public let exchangeRenameNeeded: Bool
    public let environmentSha256: String
    public let runnerCommitSha: String
    public let runnerTreeSha: String
    public let command: [String]
    public let host: AtomicityHost
    public let oldHash: String
    public let newHash: String
    public let successfulExecutions: [AtomicityExecution]
    public let boundaries: [AtomicityBoundaryResult]
    public let failures: [AtomicityFailureResult]
    public let citedBy: [String]

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case schemaVersion, verdict, scope, limitation, ordinaryRenameObservedAtomic, exchangeRenameNeeded
        case environmentSha256, runnerCommitSha, runnerTreeSha, command, host, oldHash, newHash
        case successfulExecutions, boundaries, failures, citedBy
    }

    public init(verdict: Verdict, scope: String, limitation: String, ordinaryRenameObservedAtomic: Bool, exchangeRenameNeeded: Bool, environmentSha256: String, runnerCommitSha: String, runnerTreeSha: String, command: [String], host: AtomicityHost, oldHash: String, newHash: String, successfulExecutions: [AtomicityExecution], boundaries: [AtomicityBoundaryResult], failures: [AtomicityFailureResult], citedBy: [String]) {
        schemaVersion = 1; self.verdict = verdict; self.scope = scope; self.limitation = limitation
        self.ordinaryRenameObservedAtomic = ordinaryRenameObservedAtomic; self.exchangeRenameNeeded = exchangeRenameNeeded
        self.environmentSha256 = environmentSha256; self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha
        self.command = command; self.host = host; self.oldHash = oldHash; self.newHash = newHash
        self.successfulExecutions = successfulExecutions; self.boundaries = boundaries; self.failures = failures; self.citedBy = citedBy
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "AtomicityEvidence")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion); verdict = try values.decode(Verdict.self, forKey: .verdict)
        scope = try values.decode(String.self, forKey: .scope); limitation = try values.decode(String.self, forKey: .limitation)
        ordinaryRenameObservedAtomic = try values.decode(Bool.self, forKey: .ordinaryRenameObservedAtomic)
        exchangeRenameNeeded = try values.decode(Bool.self, forKey: .exchangeRenameNeeded)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        runnerCommitSha = try values.decode(String.self, forKey: .runnerCommitSha); runnerTreeSha = try values.decode(String.self, forKey: .runnerTreeSha)
        command = try values.decode([String].self, forKey: .command); host = try values.decode(AtomicityHost.self, forKey: .host)
        oldHash = try values.decode(String.self, forKey: .oldHash); newHash = try values.decode(String.self, forKey: .newHash)
        successfulExecutions = try values.decode([AtomicityExecution].self, forKey: .successfulExecutions)
        boundaries = try values.decode([AtomicityBoundaryResult].self, forKey: .boundaries)
        failures = try values.decode([AtomicityFailureResult].self, forKey: .failures); citedBy = try values.decode([String].self, forKey: .citedBy)
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == 1, verdict == .pass, host.filesystem == "apfs",
              !host.macOSVersion.isEmpty, host.macOSVersion != "unknown", !host.macOSBuild.isEmpty, host.macOSBuild != "unknown",
              !host.architecture.isEmpty, host.architecture != "unknown", ordinaryRenameObservedAtomic, !exchangeRenameNeeded,
              environmentSha256.isLowercaseSHA256, runnerCommitSha.isLowercaseGitSHA1, runnerTreeSha.isLowercaseGitSHA1,
              oldHash.isLowercaseSHA256, newHash.isLowercaseSHA256, oldHash != newHash, !command.isEmpty,
              successfulExecutions.count == 100, Set(successfulExecutions.map(\.iteration)) == Set(1...100),
              successfulExecutions.allSatisfy({ $0.terminalState == .new && $0.observedHash == newHash }),
              Set(boundaries.map(\.boundary)) == Set(AtomicReplacementCrashBoundary.allCases), boundaries.count == AtomicReplacementCrashBoundary.allCases.count,
              boundaries.allSatisfy({ $0.observedHash == ($0.boundary.isAfterRename ? newHash : oldHash) && $0.terminalState == ($0.boundary.isAfterRename ? .new : .old) && $0.staleTemporaryFilesAfterCleanup == 0 }),
              Set(failures.map(\.step)) == Set(AtomicReplacementFailureStep.allCases), failures.count == AtomicReplacementFailureStep.allCases.count,
              failures.allSatisfy({ $0.observedHash == ($0.step == .directoryFsync ? newHash : oldHash) && $0.terminalState == ($0.step == .directoryFsync ? .new : .old) && $0.temporaryFilesAfterCleanup == 0 }),
              citedBy == ["SP-3", "SP-6A"] else { throw EvidenceModelError.invalidBlocker(field: "atomicity_evidence") }
        let expectedHostHash = AtomicityHost(filesystem: host.filesystem, macOSVersion: host.macOSVersion, macOSBuild: host.macOSBuild, architecture: host.architecture).hostHash
        guard host.hostHash == expectedHostHash else { throw EvidenceModelError.invalidSHA256(field: "hostHash") }
    }
}

public enum AtomicityDigest {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

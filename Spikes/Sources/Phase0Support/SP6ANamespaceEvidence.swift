import CryptoKit
import Foundation

public struct SP6ANamespaceTransformation: Codable, Equatable, Sendable {
    public let versionByteIndex: Int
    public let versionClearMask: UInt8
    public let versionSetBits: UInt8
    public let variantByteIndex: Int
    public let variantClearMask: UInt8
    public let variantSetBits: UInt8

    public static let rfc4122UUIDv4 = SP6ANamespaceTransformation(
        versionByteIndex: 6, versionClearMask: 0x0f, versionSetBits: 0x40,
        variantByteIndex: 8, variantClearMask: 0x3f, variantSetBits: 0x80
    )
}

public struct SP6ANamespaceRunnerIdentity: Codable, Equatable, Sendable {
    public let commitSha: String
    public let treeSha: String
    public let environmentSha256: String

    public init(commitSha: String, treeSha: String, environmentSha256: String) {
        self.commitSha = commitSha
        self.treeSha = treeSha
        self.environmentSha256 = environmentSha256
    }
}

public struct SP6ANamespaceGenerationReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let attemptID: String
    public let inputBytes: [UInt8]
    public let randomStatus: Int32
    public let transformation: SP6ANamespaceTransformation
    public let uuid: String
    public let service: String
    public let runner: SP6ANamespaceRunnerIdentity
    public let generatedAtUTC: String
    public let cleanupService: String

    public init(
        attemptID: String, inputBytes: [UInt8], randomStatus: Int32,
        uuid: String, service: String, runner: SP6ANamespaceRunnerIdentity,
        generatedAtUTC: String, cleanupService: String
    ) {
        self.schemaVersion = 1
        self.attemptID = attemptID
        self.inputBytes = inputBytes
        self.randomStatus = randomStatus
        self.transformation = .rfc4122UUIDv4
        self.uuid = uuid
        self.service = service
        self.runner = runner
        self.generatedAtUTC = generatedAtUTC
        self.cleanupService = cleanupService
    }
}

public struct SP6ANamespaceAttemptHistory: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let scope: String
    public var attempts: [SP6ANamespaceGenerationReceipt]

    public static let capturedScope = "All SP-6A task-10 QA, signal, deterministic-model, and canonical evidence attempts retained by this bound run. Uniqueness claims apply only to this captured history and the explicit regression denylist."

    public init(attempts: [SP6ANamespaceGenerationReceipt]) {
        self.schemaVersion = 1
        self.scope = Self.capturedScope
        self.attempts = attempts
    }
}

public struct SP6ANamespaceHistoryAnchor: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceCommitSha: String
    public let anchorCommitSha: String
    public let anchorTreeSha: String
    public let anchorPath: String
    public let anchorBlobSha1: String
    public let anchorFileSha256: String

    public init(
        sourceCommitSha: String, anchorCommitSha: String, anchorTreeSha: String,
        anchorPath: String, anchorBlobSha1: String, anchorFileSha256: String
    ) {
        self.schemaVersion = 1
        self.sourceCommitSha = sourceCommitSha
        self.anchorCommitSha = anchorCommitSha
        self.anchorTreeSha = anchorTreeSha
        self.anchorPath = anchorPath
        self.anchorBlobSha1 = anchorBlobSha1
        self.anchorFileSha256 = anchorFileSha256
    }
}

public enum SP6ANamespaceHistoryContract {
    public static let expectedAttemptCount = 11
    public static let anchorPath = "evidence/phase0/sp6a/namespace-attempt-history-v3.json"
    public static let anchorArtifactName = "namespace-attempt-history-v3.json"
    public static let metadataArtifactName = "history-anchor.json"
    /// Immutable prior anchor artifact; retained in git history only — never mutated after its anchor commit.
    public static let legacyAnchorArtifactName = "namespace-attempt-history-v2.json"
    public static let legacyAnchorPath = "evidence/phase0/sp6a/namespace-attempt-history-v2.json"
    public static let legacyAnchorCommitSha = "090e2eb55e44763dbf4a31c30ee3a9e59cb59212"
    public static let legacyAnchorTreeSha = "9a6400040668a0d59bf485c2a6884807e6b19d56"
    public static let legacyAnchorBlobSha1 = "ad8d2c3d40d8215518cfac7a141e5601da1e84c3"
    public static let legacyAnchorFileSha256 = "c944feb30eeede44d807f7e9d617e144eb50d6b7b59ff1b067b020296eab8833"
}

public enum SP6ANamespaceDerivation {
    public static let rejectedServices: Set<String> = [
        SP6AKeychainNamespace.prefix + "00000000-0000-4000-8000-000000000000",
        SP6AKeychainNamespace.prefix + "86660268-fe78-4919-9eea-7f2eeebb848e",
        SP6AKeychainNamespace.prefix + "ffb62654-5437-46e5-925e-f15e2e98985b",
    ]

    public static func uuid(inputBytes: [UInt8]) -> String? {
        guard inputBytes.count == 16 else { return nil }
        var bytes = inputBytes
        let rule = SP6ANamespaceTransformation.rfc4122UUIDv4
        bytes[rule.versionByteIndex] = (bytes[rule.versionByteIndex] & rule.versionClearMask) | rule.versionSetBits
        bytes[rule.variantByteIndex] = (bytes[rule.variantByteIndex] & rule.variantClearMask) | rule.variantSetBits
        let value = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: value).uuidString.lowercased()
    }

    public static func attemptID(
        inputBytes: [UInt8], runner: SP6ANamespaceRunnerIdentity, generatedAtUTC: String
    ) -> String {
        var input = Data("sp6a-namespace-attempt-v1\0".utf8)
        input.append(contentsOf: inputBytes)
        input.append(Data("\0\(runner.commitSha)\0\(runner.treeSha)\0\(runner.environmentSha256)\0\(generatedAtUTC)".utf8))
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}

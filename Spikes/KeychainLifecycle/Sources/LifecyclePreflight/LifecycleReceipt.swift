import Foundation

public enum LifecycleReceiptID: String, Codable, CaseIterable, Sendable {
    case keychainPolicy, sessionLock, restart, sleepWake
    public var assertions: [String] {
        switch self {
        case .keychainPolicy: ["t7.keychain.whenUnlockedThisDeviceOnly", "t7.keychain.nonSynchronizable"]
        case .sessionLock: ["t7.lock.authoritativeInitialState", "t7.lock.generationFence"]
        case .restart: ["t7.restart.unlocked", "t7.restart.startupLocked"]
        case .sleepWake: ["t7.sleep.captureClosed", "t7.wake.authoritativeUnlock"]
        }
    }
}

public struct LifecycleFileBinding: Codable, Sendable {
    public let path: String
    public let sha256: String
}
public struct LifecycleAssertion: Codable, Sendable {
    public let id: String
    public let status: LifecycleStatus
    public let artifactSHA256: String
}
public struct LifecycleIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let receipts: [LifecycleFileBinding]
}
public struct LifecycleReceipt: Codable, Sendable {
    public let schemaVersion: Int
    public let id: LifecycleReceiptID
    public let commitSha: String
    public let treeSha: String
    public let sourceFiles: [LifecycleFileBinding]
    public let argv: [String]
    public let status: LifecycleStatus
    public let executed: Int
    public let failed: Int
    public let skipped: Int
    public let assertions: [LifecycleAssertion]
    public let producerControllerSHA256: String
    public let hostManifestPath: String
}

public enum LifecycleReceiptCodec {
    public enum Invalid: Error { case nonCanonical, contract }
    public static func encode(_ receipt: LifecycleReceipt) throws -> Data {
        try validate(receipt)
        return try canonical(receipt)
    }
    // Probe exchange is canonical-only. Round-trip equality rejects unknown/duplicate keys,
    // coercions and ambiguous encodings; the independent consumer also checks file hashes.
    public static func decode(_ bytes: Data) throws -> LifecycleReceipt {
        guard bytes.count <= 1_048_576 else { throw Invalid.contract }
        let receipt = try JSONDecoder().decode(LifecycleReceipt.self, from: bytes)
        guard try encode(receipt) == bytes else { throw Invalid.nonCanonical }
        return receipt
    }
    public static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private static func validate(_ r: LifecycleReceipt) throws {
        let statuses = r.assertions.map(\.status)
        let aggregate: LifecycleStatus = statuses.contains(.fail) ? .fail : statuses.contains(.blocked) ? .blocked : .pass
        guard r.schemaVersion == 1, r.assertions.map(\.id) == r.id.assertions,
              r.status == aggregate, r.executed == statuses.filter({ $0 != .blocked }).count,
              r.failed == statuses.filter({ $0 == .fail }).count, r.skipped == 0,
              matches(r.commitSha, 40), matches(r.treeSha, 40), matches(r.producerControllerSHA256, 64),
              !r.sourceFiles.isEmpty, Set(r.sourceFiles.map(\.path)).count == r.sourceFiles.count,
              r.sourceFiles.allSatisfy({ safePath($0.path) && matches($0.sha256, 64) }),
              r.assertions.allSatisfy({ matches($0.artifactSHA256, 64) }), safePath(r.hostManifestPath),
              r.executed == 0 ? r.argv.isEmpty : !r.argv.isEmpty && r.argv.allSatisfy({ !$0.isEmpty }) else {
            throw Invalid.contract
        }
    }
    private static func matches(_ value: String, _ length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func safePath(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("\0") && !value.contains("\n") && !value.contains("\r") &&
        value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

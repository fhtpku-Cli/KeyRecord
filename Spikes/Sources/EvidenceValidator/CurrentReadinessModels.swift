import Foundation
import Phase0Support

enum ReadinessStatus: String, Codable, Equatable, Sendable {
    case pass = "PASS", fail = "FAIL", blocked = "BLOCKED"
    var exitStatus: Int32 {
        switch self { case .pass: 0; case .fail: 1; case .blocked: 2 }
    }
}

enum ReadinessGateID: String, Codable, Sendable {
    case g0 = "G0", lifecycle = "SP6A_LOCAL_LIFECYCLE", implementation = "G1_IMPLEMENTATION"
}

// These are independent assertion receipts, not policy-selection claims. A future
// host runner must emit the lifecycle receipts; implementation needs its own runs.
enum ReadinessReceiptID: String, Codable, CaseIterable, Sendable {
    case keychainPolicy, sessionLock, restart, sleepWake, capture, privacy, encryptedPersistence
    static let lifecycle: [Self] = [.keychainPolicy, .sessionLock, .restart, .sleepWake]
    static let implementation: [Self] = [.capture, .privacy, .encryptedPersistence]
    // Task 7 qualifies policy/lock lifecycle; tasks 20 and 23 require independent
    // privacy and signed-product assertions. Counts alone never satisfy these IDs.
    var requiredAssertions: [String] {
        switch self {
        case .keychainPolicy: ["t7.keychain.whenUnlockedThisDeviceOnly", "t7.keychain.nonSynchronizable"]
        case .sessionLock: ["t7.lock.authoritativeInitialState", "t7.lock.generationFence"]
        case .restart: ["t7.restart.unlocked", "t7.restart.startupLocked"]
        case .sleepWake: ["t7.sleep.captureClosed", "t7.wake.authoritativeUnlock"]
        case .capture: ["t7.capture.lockGating", "t23.signed.captureIntegration"]
        case .privacy: ["t20.network.zeroOutbound", "t20.persistence.noEventLevelData"]
        case .encryptedPersistence: ["t23.signed.encryptedStore", "t23.signed.lifecycleRecovery"]
        }
    }
    // Only the synthetic readiness producer is modeled today. Task 7 must extend
    // this per-ID allowlist for its signed probe, not reuse the phase0 closure.
    var requiredSourcePaths: Set<String> {
        switch self {
        case .keychainPolicy, .sessionLock, .restart, .sleepWake, .capture, .privacy, .encryptedPersistence:
            ["Spikes/Sources/EvidenceValidator/CurrentReadinessModels.swift",
             "Spikes/Sources/EvidenceValidator/CurrentReadinessDeriver.swift",
             "Spikes/Sources/EvidenceValidator/CurrentReadinessValidator.swift"]
        }
    }
}

struct ReadinessAssertion: Codable, Equatable, Sendable {
    let id: String
    let status: ReadinessStatus
    let artifactSHA256: String
    // Content-addressed assertion reports live beside their receipt. Even a
    // FAIL/BLOCKED assertion needs a report explaining the observed outcome.
    var artifactPath: String { "readiness-assertions/\(artifactSHA256).json" }
}

struct ReadinessFileBinding: Codable, Equatable, Sendable {
    let path: String
    let sha256: String
}

struct ReadinessSourceBindings: Codable, Equatable, Sendable {
    let commitSha: String
    let treeSha: String
    let files: [ReadinessFileBinding]
    let missingPaths: [String]
}

struct ReadinessGate: Codable, Equatable, Sendable {
    let id: ReadinessGateID
    let title: String
    let status: ReadinessStatus
    let unresolvedCauses: [String]
}

struct ReadinessLifecycle: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let receipts: [ReadinessFileBinding]
}

struct ReadinessReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: ReadinessReceiptID
    let commitSha: String
    let treeSha: String
    let sourceFiles: [ReadinessFileBinding]
    let argv: [String]
    let status: ReadinessStatus
    let executed: Int
    let failed: Int
    let skipped: Int
    let assertions: [ReadinessAssertion]
    let producerControllerSHA256: String
    let hostManifestPath: String
}

struct CurrentReadiness: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let historicalRoot: String
    let lifecyclePath: String
    let bindings: ReadinessSourceBindings
    // Attribution is carried by the sealed document's own generator/source IDs;
    // its unchanged value is distinct from the recomputed current gates below.
    let historicalAssessment: Phase0Conclusions?
    let localLifecycleAssessment: ReadinessStatus
    let gates: [ReadinessGate]
    let retainedReleaseBlockers: [ValidatedDownstreamBlock]
    var status: ReadinessStatus {
        CurrentReadinessDeriver.aggregate(gates.map(\.status) + (retainedReleaseBlockers.isEmpty ? [] : [.blocked]))
    }
}

struct ReadinessInputs {
    let historical: Phase0Conclusions?
    let historicalRoot: String
    let lifecyclePath: String
    let bindings: ReadinessSourceBindings
    let receipts: [ReadinessReceipt]
    let sp1: SP1Evidence?
    let sp2: SP2Evidence?
    // Trusted process context, never decoded from evidence. Plan contract 3:
    // only task 7's authorized host runner may supply a real controller SHA.
    var approvedProducerSHA256s: Set<String> = []
}

enum ReadinessDecoding {
    static func decode<T: Decodable>(_ type: T.Type, from bytes: Data) throws -> T {
        try BoundedJSONPreflight.rejectDuplicateKeys(bytes)
        return try JSONDecoder().decode(type, from: bytes)
    }
}

private struct ReadinessDynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension Decoder {
    func readinessContainer<K: CodingKey & CaseIterable>(_ type: K.Type) throws -> KeyedDecodingContainer<K> {
        let known = Set(K.allCases.map(\.stringValue))
        let keys = try container(keyedBy: ReadinessDynamicKey.self).allKeys.map(\.stringValue)
        guard Set(keys).isSubset(of: known) else { throw ValidatorError("readiness_unknown_fields") }
        return try container(keyedBy: type)
    }
}

extension ReadinessFileBinding {
    enum CodingKeys: String, CodingKey, CaseIterable { case path, sha256 }
    init(from decoder: Decoder) throws {
        let c = try decoder.readinessContainer(CodingKeys.self)
        self.init(path: try c.decode(String.self, forKey: .path), sha256: try c.decode(String.self, forKey: .sha256))
    }
}

extension ReadinessSourceBindings {
    enum CodingKeys: String, CodingKey, CaseIterable { case commitSha, treeSha, files, missingPaths }
    init(from decoder: Decoder) throws {
        let c = try decoder.readinessContainer(CodingKeys.self)
        self.init(commitSha: try c.decode(String.self, forKey: .commitSha), treeSha: try c.decode(String.self, forKey: .treeSha), files: try c.decode([ReadinessFileBinding].self, forKey: .files), missingPaths: try c.decode([String].self, forKey: .missingPaths))
    }
}

extension ReadinessGate {
    enum CodingKeys: String, CodingKey, CaseIterable { case id, title, status, unresolvedCauses }
    init(from decoder: Decoder) throws {
        let c = try decoder.readinessContainer(CodingKeys.self)
        self.init(id: try c.decode(ReadinessGateID.self, forKey: .id), title: try c.decode(String.self, forKey: .title), status: try c.decode(ReadinessStatus.self, forKey: .status), unresolvedCauses: try c.decode([String].self, forKey: .unresolvedCauses))
    }
}

extension ReadinessLifecycle {
    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, receipts }
    init(from decoder: Decoder) throws {
        let c = try decoder.readinessContainer(CodingKeys.self)
        self.init(schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), receipts: try c.decode([ReadinessFileBinding].self, forKey: .receipts))
        guard schemaVersion == 1 else { throw ValidatorError("readiness_unknown_schema") }
    }
}

extension ReadinessReceipt {
    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, id, commitSha, treeSha, sourceFiles, argv, status, executed, failed, skipped, assertions, producerControllerSHA256, hostManifestPath }
    init(from decoder: Decoder) throws {
        let c = try decoder.readinessContainer(CodingKeys.self)
        self.init(schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), id: try c.decode(ReadinessReceiptID.self, forKey: .id), commitSha: try c.decode(String.self, forKey: .commitSha), treeSha: try c.decode(String.self, forKey: .treeSha), sourceFiles: try c.decode([ReadinessFileBinding].self, forKey: .sourceFiles), argv: try c.decode([String].self, forKey: .argv), status: try c.decode(ReadinessStatus.self, forKey: .status), executed: try c.decode(Int.self, forKey: .executed), failed: try c.decode(Int.self, forKey: .failed), skipped: try c.decode(Int.self, forKey: .skipped), assertions: try c.decode([ReadinessAssertion].self, forKey: .assertions), producerControllerSHA256: try c.decode(String.self, forKey: .producerControllerSHA256), hostManifestPath: try c.decode(String.self, forKey: .hostManifestPath))
        guard schemaVersion == 1 else { throw ValidatorError("readiness_unknown_schema") }
    }
}

extension ReadinessAssertion {
    enum CodingKeys: String, CodingKey, CaseIterable { case id, status, artifactSHA256 }
    init(from decoder: Decoder) throws {
        let c = try decoder.readinessContainer(CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), status: try c.decode(ReadinessStatus.self, forKey: .status), artifactSHA256: try c.decode(String.self, forKey: .artifactSHA256))
    }
}

extension CurrentReadiness {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, historicalRoot, lifecyclePath, bindings, historicalAssessment, localLifecycleAssessment, gates, retainedReleaseBlockers
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.readinessContainer(CodingKeys.self)
        self.init(schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), historicalRoot: try c.decode(String.self, forKey: .historicalRoot), lifecyclePath: try c.decode(String.self, forKey: .lifecyclePath), bindings: try c.decode(ReadinessSourceBindings.self, forKey: .bindings), historicalAssessment: try c.decodeIfPresent(Phase0Conclusions.self, forKey: .historicalAssessment), localLifecycleAssessment: try c.decode(ReadinessStatus.self, forKey: .localLifecycleAssessment), gates: try c.decode([ReadinessGate].self, forKey: .gates), retainedReleaseBlockers: try c.decode([ValidatedDownstreamBlock].self, forKey: .retainedReleaseBlockers))
        guard schemaVersion == 1 else { throw ValidatorError("readiness_unknown_schema") }
    }
}

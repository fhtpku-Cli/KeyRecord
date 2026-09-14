import Foundation
import Phase0Support

struct SP6AAppDigestPayload: Codable {
    let treeSha: String
    let sourceFiles: [ReadinessFileBinding]
}

enum SP6AAssertionArtifactValidator {
    static func expectedAppDigest(for receipt: ReadinessReceipt) throws -> String {
        let payload = SP6AAppDigestPayload(treeSha: receipt.treeSha, sourceFiles: receipt.sourceFiles.sorted { $0.path < $1.path })
        return Canonical.sha256(try Canonical.encode(payload))
    }
    static func validate(_ entries: [(assertion: ReadinessAssertion, bytes: Data)], receipt: ReadinessReceipt,
                         hostManifestBytes: Data) throws {
        try BoundedJSONPreflight.rejectDuplicateKeys(hostManifestBytes)
        let hostID = try JSONDecoder().decode(SP6AHostManifest.self, from: hostManifestBytes).hostID
        let decoded = try Dictionary(uniqueKeysWithValues: entries.map { entry in
            try BoundedJSONPreflight.rejectDuplicateKeys(entry.bytes)
            let artifact = try JSONDecoder().decode(SP6AAssertionArtifact.self, from: entry.bytes)
            return (entry.assertion.id, artifact)
        })
        for entry in entries {
            guard let artifact = decoded[entry.assertion.id] else { throw ValidatorError("sp6a_missing_assertion_artifact") }
            try validate(entry.assertion, artifact: artifact, receipt: receipt, hostID: hostID, artifacts: decoded)
        }
    }

    private static func validate(_ assertion: ReadinessAssertion, artifact: SP6AAssertionArtifact,
                                 receipt: ReadinessReceipt, hostID: String,
                                 artifacts: [String: SP6AAssertionArtifact]) throws {
        guard artifact.assertionID == assertion.id else { throw ValidatorError("sp6a_assertion_id_mismatch") }
        try validateCommon(assertion, artifact: artifact, receipt: receipt, hostID: hostID)
        switch assertion.status {
        case .blocked: try validateBlocked(artifact)
        case .fail: break
        case .pass: try validatePass(assertion.id, artifact: artifact, artifacts: artifacts)
        }
    }

    private static func validateCommon(_ assertion: ReadinessAssertion, artifact: SP6AAssertionArtifact,
                                       receipt: ReadinessReceipt, hostID: String) throws {
        let appDigest = try expectedAppDigest(for: receipt)
        guard artifact.hostID == hostID, !hostID.isEmpty,
              !artifact.runID.isEmpty, artifact.runID.count <= 128,
              artifact.appDigest == appDigest, artifact.appDigest.range(of: hex64, options: .regularExpression) != nil,
              artifact.generation.range(of: uuid, options: .regularExpression) != nil,
              artifact.observedAt.range(of: timestamp, options: .regularExpression) != nil,
              artifact.sequence >= 0,
              artifact.protectedReadDelta == 0, artifact.publishDelta == 0, artifact.aggregateDelta == 0,
              ["locked", "unlocked", "unknown"].contains(artifact.state) else {
            throw ValidatorError("sp6a_assertion_binding_invalid", assertion.id)
        }
    }

    private static func validateBlocked(_ artifact: SP6AAssertionArtifact) throws {
        guard artifact.state == "unknown", !artifact.authoritative, artifact.captureClosed == nil,
              artifact.accessibility == nil, artifact.synchronizable == nil,
              artifact.initialWitness == nil, artifact.priorGeneration == nil else {
            throw ValidatorError("sp6a_blocked_artifact_claims_observation")
        }
    }

    private static func validatePass(_ id: String, artifact: SP6AAssertionArtifact,
                                     artifacts: [String: SP6AAssertionArtifact]) throws {
        guard artifact.authoritative, artifact.state != "unknown" else { throw ValidatorError("sp6a_forged_witness", id) }
        switch id {
        case "t7.keychain.whenUnlockedThisDeviceOnly":
            try expectBase(artifact, state: "unlocked", sequence: 0, capture: nil)
            guard artifact.accessibility == "aku", artifact.synchronizable == nil else { throw failure(id) }
        case "t7.keychain.nonSynchronizable":
            try expectBase(artifact, state: "unlocked", sequence: 0, capture: nil)
            guard artifact.accessibility == nil, artifact.synchronizable == false else { throw failure(id) }
        case "t7.lock.authoritativeInitialState":
            try expect(artifact, state: artifact.state, sequence: 0, capture: nil)
        case "t7.lock.generationFence":
            try expectTransition(artifact, state: "locked", sequence: 1, capture: true)
            try expect(initial: artifacts["t7.lock.authoritativeInitialState"], for: artifact, prior: true)
        case "t7.restart.startupLocked":
            try expectTransition(artifact, state: "locked", sequence: 0, capture: true)
            try expect(artifact.initialWitness, matches: artifact.witnessProjection())
            guard artifact.priorGeneration == nil else { throw failure(id) }
        case "t7.restart.unlocked":
            try expectTransition(artifact, state: "unlocked", sequence: 1, capture: false)
            try expect(initial: artifacts["t7.restart.startupLocked"], for: artifact, prior: true)
        case "t7.sleep.captureClosed":
            try expectTransition(artifact, state: "locked", sequence: 1, capture: true)
            try expectStandaloneInitial(artifact, state: "unlocked")
        case "t7.wake.authoritativeUnlock":
            try expectTransition(artifact, state: "unlocked", sequence: 2, capture: false)
            try expectStandaloneInitial(artifact, state: "unlocked")
        default: throw ValidatorError("sp6a_unknown_assertion", id)
        }
    }

    private static func expectTransition(_ artifact: SP6AAssertionArtifact, state: String, sequence: Int, capture: Bool?) throws {
        try expectBase(artifact, state: state, sequence: sequence, capture: capture)
        guard artifact.accessibility == nil, artifact.synchronizable == nil else { throw failure(artifact.assertionID) }
    }

    private static func expectBase(_ artifact: SP6AAssertionArtifact, state: String, sequence: Int, capture: Bool?) throws {
        guard artifact.state == state, artifact.sequence == sequence, artifact.captureClosed == capture else {
            throw failure(artifact.assertionID)
        }
    }

    private static func expect(_ artifact: SP6AAssertionArtifact, state: String, sequence: Int, capture: Bool?) throws {
        try expectBase(artifact, state: state, sequence: sequence, capture: capture)
        guard artifact.initialWitness == nil, artifact.priorGeneration == nil,
              artifact.accessibility == nil, artifact.synchronizable == nil else { throw failure(artifact.assertionID) }
    }

    private static func expect(initial: SP6AAssertionArtifact?, for artifact: SP6AAssertionArtifact, prior: Bool) throws {
        guard let initial, let witness = artifact.initialWitness, let priorGeneration = artifact.priorGeneration,
              witness == initial.witnessProjection(), initial.sequence == 0,
              witness.hostID == artifact.hostID, witness.runID == artifact.runID, witness.appDigest == artifact.appDigest,
              priorGeneration == initial.generation, artifact.generation != priorGeneration,
              artifact.sequence == initial.sequence + 1 || artifact.sequence == 2 else {
            throw failure(artifact.assertionID)
        }
    }

    private static func expectStandaloneInitial(_ artifact: SP6AAssertionArtifact, state: String) throws {
        guard let witness = artifact.initialWitness, let priorGeneration = artifact.priorGeneration,
              witness.hostID == artifact.hostID, witness.runID == artifact.runID, witness.appDigest == artifact.appDigest,
              witness.sequence == 0, witness.state == state,
              (artifact.sequence == 1 && priorGeneration == witness.generation) ||
              (artifact.sequence == 2 && priorGeneration != witness.generation),
              artifact.generation != priorGeneration else { throw failure(artifact.assertionID) }
    }

    private static func expect(_ witness: SP6AWitnessArtifact?, matches expected: SP6AWitnessArtifact) throws {
        guard witness == expected else { throw failure(expected.state) }
    }

    private static func failure(_ id: String) -> ValidatorError { .init("sp6a_assertion_semantics_invalid", id) }
    private static let hex64 = "^[0-9a-f]{64}$"
    private static let uuid = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
    private static let timestamp = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
}

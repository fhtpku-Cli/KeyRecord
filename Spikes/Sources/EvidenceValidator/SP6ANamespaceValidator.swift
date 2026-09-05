import Foundation
import Phase0Support

enum SP6ANamespaceValidator {
    static func validate(_ artifact: SP6AKeychainArtifact) throws {
        guard !SP6ANamespaceDerivation.rejectedServices.contains(artifact.service) else {
            throw ValidatorError("sp6a_keychain_namespace_reused")
        }
        guard artifact.attemptHistory.schemaVersion == 1,
              artifact.attemptHistory.scope == SP6ANamespaceAttemptHistory.capturedScope,
              !artifact.attemptHistory.attempts.isEmpty else {
            throw ValidatorError("sp6a_keychain_attempt_history_invalid")
        }
        var attemptIDs = Set<String>(), services = Set<String>(), entropy = Set<[UInt8]>()
        for receipt in artifact.attemptHistory.attempts {
            try validate(receipt)
            guard !SP6ANamespaceDerivation.rejectedServices.contains(receipt.service) else {
                throw ValidatorError("sp6a_keychain_namespace_reused")
            }
            guard attemptIDs.insert(receipt.attemptID).inserted else {
                throw ValidatorError("sp6a_keychain_attempt_id_reused")
            }
            guard entropy.insert(receipt.inputBytes).inserted else {
                throw ValidatorError("sp6a_keychain_entropy_reused")
            }
            guard services.insert(receipt.service).inserted else {
                throw ValidatorError("sp6a_keychain_namespace_reused")
            }
        }
        guard artifact.attemptHistory.attempts.filter({ $0 == artifact.generationReceipt }).count == 1,
              artifact.generationReceipt.service == artifact.service else {
            throw ValidatorError("sp6a_keychain_generation_history_mismatch")
        }
        guard artifact.generationReceipt.cleanupService == artifact.cleanupReceipt.service else {
            throw ValidatorError("sp6a_keychain_cleanup_namespace_mismatch")
        }
    }

    static func validateIdentity(
        _ artifact: SP6AKeychainArtifact, commitSha: String, treeSha: String, environmentSha256: String
    ) throws {
        let expected = SP6ANamespaceRunnerIdentity(
            commitSha: commitSha, treeSha: treeSha, environmentSha256: environmentSha256
        )
        guard artifact.attemptHistory.attempts.allSatisfy({ $0.runner == expected }) else {
            throw ValidatorError("sp6a_keychain_generation_identity_mismatch")
        }
    }

    static func validateHistoryContract(_ artifact: SP6AKeychainArtifact) throws {
        let timestamps = artifact.attemptHistory.attempts.map(\.generatedAtUTC)
        guard artifact.attemptHistory.attempts.count == SP6ANamespaceHistoryContract.expectedAttemptCount,
              timestamps == timestamps.sorted(),
              artifact.attemptHistory.attempts.last == artifact.generationReceipt else {
            throw ValidatorError("sp6a_keychain_attempt_history_anchor_mismatch")
        }
    }

    private static func validate(_ receipt: SP6ANamespaceGenerationReceipt) throws {
        guard receipt.schemaVersion == 1,
              receipt.transformation == .rfc4122UUIDv4,
              receipt.cleanupService == receipt.service else {
            throw ValidatorError("sp6a_keychain_generation_receipt_invalid")
        }
        guard receipt.randomStatus == 0 else { throw ValidatorError("sp6a_keychain_rng_failed") }
        guard receipt.inputBytes.count == 16, receipt.inputBytes.contains(where: { $0 != 0 }) else {
            throw ValidatorError("sp6a_keychain_entropy_invalid")
        }
        guard let uuid = SP6ANamespaceDerivation.uuid(inputBytes: receipt.inputBytes),
              receipt.uuid == uuid,
              receipt.service == SP6AKeychainNamespace.prefix + uuid,
              SP6AKeychainNamespace.isValid(receipt.service) else {
            throw ValidatorError("sp6a_keychain_generation_uuid_mismatch")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard receipt.generatedAtUTC.hasSuffix("Z"),
              let date = formatter.date(from: receipt.generatedAtUTC),
              formatter.string(from: date) == receipt.generatedAtUTC else {
            throw ValidatorError("sp6a_keychain_generation_utc_invalid")
        }
        guard receipt.attemptID == SP6ANamespaceDerivation.attemptID(
            inputBytes: receipt.inputBytes, runner: receipt.runner, generatedAtUTC: receipt.generatedAtUTC
        ) else {
            throw ValidatorError("sp6a_keychain_attempt_id_invalid")
        }
    }
}

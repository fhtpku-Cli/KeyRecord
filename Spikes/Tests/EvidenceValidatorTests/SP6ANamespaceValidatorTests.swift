import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP6ANamespaceValidatorTests: XCTestCase {
    func testGenerationReceiptAndHistoryOmissionRejectWithTypedErrors() throws {
        for field in ["generationReceipt", "attemptHistory"] {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.removeKeychainField(field)
            try fixture.rebindArtifact("keychain.json")

            XCTAssertEqual(
                errorCode(fixture),
                field == "generationReceipt" ? "sp6a_keychain_generation_receipt_missing" : "sp6a_keychain_attempt_history_missing"
            )
        }
    }

    func testEntropyUUIDAttemptAndRNGForgeriesReject() throws {
        let cases: [(String, (SP6ANamespaceGenerationReceipt) -> SP6ANamespaceGenerationReceipt)] = [
            ("sp6a_keychain_entropy_invalid", { receipt in
                receiptCopy(receipt, inputBytes: Array(repeating: 0, count: 16))
            }),
            ("sp6a_keychain_generation_uuid_mismatch", { receipt in
                var bytes = receipt.inputBytes
                bytes[0] ^= 1
                return receiptCopy(receipt, inputBytes: bytes)
            }),
            ("sp6a_keychain_rng_failed", { receipt in receiptCopy(receipt, randomStatus: -1) }),
            ("sp6a_keychain_attempt_id_invalid", { receipt in
                receiptCopy(receipt, attemptID: String(repeating: "f", count: 64))
            }),
        ]
        for item in cases {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            let artifact = try fixture.keychain()
            let changed = item.1(artifact.generationReceipt)
            try fixture.writeKeychain(artifact, receipt: changed, history: .init(attempts: [changed]))
            try fixture.rebindArtifact("keychain.json")

            XCTAssertEqual(errorCode(fixture), item.0)
        }
    }

    func testDuplicateAttemptServiceAndEntropyRejectIndependently() throws {
        let expected = [
            "sp6a_keychain_attempt_id_reused",
            "sp6a_keychain_entropy_reused",
            "sp6a_keychain_namespace_reused",
        ]
        for index in expected.indices {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            let artifact = try fixture.keychain()
            let first = artifact.generationReceipt
            let second: SP6ANamespaceGenerationReceipt
            if index == 0 {
                second = first
            } else {
                var bytes = first.inputBytes
                if index == 2 { bytes[6] ^= 0x10 }
                let utc = "2026-09-05T00:00:0\(index).000Z"
                second = receiptCopy(first, inputBytes: bytes, generatedAtUTC: utc, recomputeAttemptID: true)
            }
            try fixture.writeKeychain(artifact, receipt: first, history: .init(attempts: [first, second]))
            try fixture.rebindArtifact("keychain.json")

            XCTAssertEqual(errorCode(fixture), expected[index])
        }
    }

    func testCurrentReceiptMustAppearOnceAndMatchBoundIdentity() throws {
        let historyFixture = try SP6ATestDirectory.make()
        defer { historyFixture.remove() }
        let artifact = try historyFixture.keychain()
        let current = artifact.generationReceipt
        var bytes = current.inputBytes
        bytes[0] ^= 1
        let other = receiptCopy(
            current, inputBytes: bytes, generatedAtUTC: "2026-09-05T00:00:03.000Z",
            recomputeUUID: true, recomputeAttemptID: true
        )
        try historyFixture.writeKeychain(artifact, receipt: current, history: .init(attempts: [other]))
        try historyFixture.rebindArtifact("keychain.json")
        XCTAssertEqual(errorCode(historyFixture), "sp6a_keychain_generation_history_mismatch")

        let identityFixture = try SP6ATestDirectory.make()
        defer { identityFixture.remove() }
        let identityArtifact = try identityFixture.keychain()
        let forgedRunner = SP6ANamespaceRunnerIdentity(
            commitSha: String(repeating: "9", count: 40),
            treeSha: identityArtifact.generationReceipt.runner.treeSha,
            environmentSha256: identityArtifact.generationReceipt.runner.environmentSha256
        )
        let forged = receiptCopy(identityArtifact.generationReceipt, runner: forgedRunner, recomputeAttemptID: true)
        try identityFixture.writeKeychain(identityArtifact, receipt: forged, history: .init(attempts: [forged]))
        try identityFixture.rebindArtifact("keychain.json")
        XCTAssertEqual(errorCode(identityFixture), "sp6a_keychain_generation_identity_mismatch")
    }

    func testFlagsCaseMissingExtraAndOutcomeDriftReject() throws {
        for mutation in 0..<3 {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.editCrypto { artifact in
                guard let index = artifact.tamperCases.firstIndex(of: "flags") else { return }
                if mutation == 0 {
                    artifact.tamperCases.remove(at: index)
                    artifact.tamperResults.remove(at: index)
                } else if mutation == 1 {
                    artifact.tamperCases.insert("flags", at: index)
                    artifact.tamperResults.insert(.init(caseID: "flags", rejected: true), at: index)
                } else {
                    artifact.tamperResults[index] = .init(caseID: "flags", rejected: false)
                }
            }
            try fixture.rebindArtifact("crypto.json")

            XCTAssertEqual(
                errorCode(fixture),
                mutation < 2 ? "sp6a_crypto_case_set_mismatch" : "sp6a_crypto_canonical_mismatch"
            )
        }
    }

    private func errorCode(_ fixture: SP6ATestDirectory) -> String? {
        do {
            _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository)
            return nil
        } catch let error as ValidatorError {
            return error.code
        } catch {
            return "unexpected"
        }
    }
}

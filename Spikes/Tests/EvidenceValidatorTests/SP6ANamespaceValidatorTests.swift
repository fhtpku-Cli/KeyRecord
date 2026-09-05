import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP6ANamespaceValidatorTests: XCTestCase {
    func testHistoryAnchorRejectsEveryDescendantPathTouch() throws {
        for scenario in SP6AAnchorAttackScenario.allCases where scenario != .deleteAndReadd {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.commitAnchorAttack(scenario)

            XCTAssertEqual(
                errorCode(fixture), "sp6a_history_anchor_descendant_touch",
                "descendant anchor attack unexpectedly validated: \(scenario.rawValue)"
            )
        }
    }

    func testHistoryAnchorRejectsAdditionalCreationCandidate() throws {
        let fixture = try SP6ATestDirectory.make()
        defer { fixture.remove() }
        try fixture.commitAnchorAttack(.deleteAndReadd)

        XCTAssertEqual(errorCode(fixture), "sp6a_history_anchor_descendant_touch")
    }

    func testHistoryAnchorRejectsForgedLatestRecordedSHAAndShallowHistory() throws {
        let forgedFixture = try SP6ATestDirectory.make()
        defer { forgedFixture.remove() }
        try forgedFixture.commitAnchorAttack(.changedBytes)
        let artifact = try forgedFixture.keychain()
        let forged = try forgedFixture.latestCommitAnchor(basedOn: artifact.historyAnchor)
        try forgedFixture.writeKeychain(
            artifact, receipt: artifact.generationReceipt, history: artifact.attemptHistory,
            historyAnchor: forged
        )
        try forgedFixture.writeHistoryAnchor(forged)
        try forgedFixture.rebindArtifact("keychain.json")
        XCTAssertEqual(errorCode(forgedFixture), "sp6a_history_anchor_commit_selection_mismatch")

        let shallowFixture = try SP6ATestDirectory.make()
        defer { shallowFixture.remove() }
        try shallowFixture.markRepositoryShallow()
        let evidence = try JSONDecoder().decode(
            SP6AEvidence.self,
            from: Data(contentsOf: shallowFixture.output.appendingPathComponent("evidence.json"))
        )
        XCTAssertEqual(errorCode {
            try SP6ADirectoryValidator.validateHistoryAnchor(
                evidence, directory: shallowFixture.output, repository: shallowFixture.repository
            )
        }, "sp6a_history_anchor_history_incomplete")
    }

    func testHistoryAnchorMetadataAndBlobForgeriesReject() throws {
        let cases: [(String, (SP6ANamespaceHistoryAnchor) -> SP6ANamespaceHistoryAnchor)] = [
            ("sp6a_history_anchor_contract_invalid", { copyAnchor($0, anchorPath: "evidence/phase0/sp6a/wrong.json") }),
            ("sp6a_history_anchor_commit_missing", { copyAnchor($0, anchorCommitSha: String(repeating: "f", count: 40)) }),
            ("sp6a_history_anchor_tree_mismatch", { copyAnchor($0, anchorTreeSha: String(repeating: "e", count: 40)) }),
            ("sp6a_history_anchor_source_parent_mismatch", { copyAnchor($0, sourceCommitSha: String(repeating: "d", count: 40)) }),
            ("sp6a_history_anchor_blob_mismatch", { copyAnchor($0, anchorBlobSha1: String(repeating: "c", count: 40)) }),
            ("sp6a_history_anchor_hash_mismatch", { copyAnchor($0, anchorFileSha256: String(repeating: "b", count: 64)) }),
        ]
        for (expected, mutate) in cases {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            let artifact = try fixture.keychain()
            let anchor = mutate(artifact.historyAnchor)
            try fixture.writeKeychain(
                artifact, receipt: artifact.generationReceipt, history: artifact.attemptHistory,
                historyAnchor: anchor
            )
            try fixture.writeHistoryAnchor(anchor)
            try fixture.rebindArtifact("keychain.json")

            XCTAssertEqual(errorCode(fixture), expected)
        }
    }

    func testHistoryAnchorWorkingBytesAndAttemptOrderReject() throws {
        let bytesFixture = try SP6ATestDirectory.make()
        defer { bytesFixture.remove() }
        try bytesFixture.rewrite(
            SP6ANamespaceHistoryContract.anchorArtifactName,
            replacing: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2", remanifest: true
        )
        XCTAssertEqual(errorCode(bytesFixture), "sp6a_keychain_attempt_history_anchor_mismatch")

        let orderFixture = try SP6ATestDirectory.make()
        defer { orderFixture.remove() }
        let artifact = try orderFixture.keychain()
        var attempts = artifact.attemptHistory.attempts
        attempts.swapAt(0, 1)
        try orderFixture.writeKeychain(artifact, receipt: artifact.generationReceipt, history: .init(attempts: attempts))
        try orderFixture.rebindArtifact("keychain.json")
        XCTAssertEqual(errorCode(orderFixture), "sp6a_keychain_attempt_history_anchor_mismatch")
    }

    func testRemovingNonCurrentHistoryReceiptRejectsAfterCanonicalRebinding() throws {
        let fixture = try SP6ATestDirectory.make()
        defer { fixture.remove() }
        let artifact = try fixture.keychain()
        var attempts = (0..<10).map { index in
            var bytes = artifact.generationReceipt.inputBytes
            bytes[0] = UInt8(index + 1)
            return receiptCopy(
                artifact.generationReceipt, inputBytes: bytes,
                generatedAtUTC: String(format: "2026-09-05T00:00:%02d.000Z", index + 1),
                recomputeUUID: true, recomputeAttemptID: true
            )
        }
        attempts.append(artifact.generationReceipt)
        attempts.removeFirst()
        try fixture.writeKeychain(artifact, receipt: artifact.generationReceipt, history: .init(attempts: attempts))
        try fixture.rebindArtifact("keychain.json")

        XCTAssertEqual(errorCode(fixture), "sp6a_keychain_attempt_history_anchor_mismatch")
    }

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

    private func errorCode(_ body: () throws -> Void) -> String? {
        do {
            try body()
            return nil
        } catch let error as ValidatorError {
            return error.code
        } catch {
            return "unexpected"
        }
    }
}

enum SP6AAnchorAttackScenario: String, CaseIterable {
    case changedBytes
    case restoredBytes
    case deleteAndReadd
    case renameCycle
}

private func copyAnchor(
    _ value: SP6ANamespaceHistoryAnchor,
    sourceCommitSha: String? = nil, anchorCommitSha: String? = nil,
    anchorTreeSha: String? = nil, anchorPath: String? = nil,
    anchorBlobSha1: String? = nil, anchorFileSha256: String? = nil
) -> SP6ANamespaceHistoryAnchor {
    SP6ANamespaceHistoryAnchor(
        sourceCommitSha: sourceCommitSha ?? value.sourceCommitSha,
        anchorCommitSha: anchorCommitSha ?? value.anchorCommitSha,
        anchorTreeSha: anchorTreeSha ?? value.anchorTreeSha,
        anchorPath: anchorPath ?? value.anchorPath,
        anchorBlobSha1: anchorBlobSha1 ?? value.anchorBlobSha1,
        anchorFileSha256: anchorFileSha256 ?? value.anchorFileSha256
    )
}

import Foundation
import XCTest
@testable import EvidenceValidator

final class ReceiptValidatorTests: XCTestCase {
    func testHappyPathAssemblyAndVerificationIsDeterministic() throws {
        let fixture = try ReceiptFixture.make()
        defer { fixture.remove() }
        let first = try ReceiptValidator.assemble(sourceDirectory: fixture.receipts, candidate: fixture.candidate, commands: fixture.commands, requiredReviewers: ["F1", "F2", "F3", "F4"])
        let second = try ReceiptValidator.assemble(sourceDirectory: fixture.receipts, candidate: fixture.candidate, commands: fixture.commands, requiredReviewers: ["F1", "F2", "F3", "F4"])
        XCTAssertEqual(first, second)
        try first.write(to: fixture.aggregate)
        XCTAssertNoThrow(try ReceiptValidator.verify(aggregate: fixture.aggregate, sourceDirectory: fixture.receipts, candidate: fixture.candidate, commands: fixture.commands, requiredReviewers: ["F1", "F2", "F3", "F4"], expectations: .none))
    }

    func testReceiptAdversarialMatrixReturnsExactCodes() throws {
        let cases: [(ReceiptFixture.Mutation, String)] = [
            (.forgedAggregate, "receipt_aggregate_forged"), (.missingSource, "receipt_source_set_mismatch"),
            (.substitutedSource, "candidate_field_mismatch"), (.symlinkSource, "receipt_source_not_regular"),
            (.extraSource, "receipt_source_set_mismatch"), (.duplicateReviewer, "duplicate_reviewer"),
            (.unknownReviewer, "unknown_reviewer"), (.nonApprove, "review_not_approved"),
            (.missingCommand, "command_results_mismatch"), (.extraCommand, "command_results_mismatch"),
            (.truncatedCommand, "malformed_receipt"), (.argvDrift, "command_results_mismatch"),
            (.exitDrift, "command_results_mismatch"), (.hashDrift, "malformed_receipt"),
            (.timeDrift, "command_results_mismatch"), (.staleReceiptExpectation, "expected_receipt_set_mismatch"),
            (.staleCandidateExpectation, "expected_candidate_mismatch"), (.staleCommitExpectation, "expected_commit_mismatch"),
        ]
        for (mutation, expected) in cases {
            let fixture = try ReceiptFixture.make(mutation: mutation)
            defer { fixture.remove() }
            XCTAssertEqual(fixture.captureValidationCode(), expected, String(describing: mutation))
        }
    }

    func testEveryCandidateFieldOmissionAndMismatchRejects() throws {
        let fields = ["candidateSha256", "commitSha", "treeSha", "auditBaseSha", "planSha256", "environmentSha256", "evidenceDigest", "boundInputPathsSha256", "createdAt"]
        for field in fields {
            for omitted in [false, true] {
                let fixture = try ReceiptFixture.make(mutation: .candidateField(field: field, omitted: omitted))
                defer { fixture.remove() }
                XCTAssertEqual(fixture.captureValidationCode(), omitted ? "malformed_receipt" : "candidate_field_mismatch", "\(field) omitted=\(omitted)")
            }
        }
    }
}

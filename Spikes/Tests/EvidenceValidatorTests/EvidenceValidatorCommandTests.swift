import XCTest
@testable import EvidenceValidator

final class EvidenceValidatorCommandTests: XCTestCase {
    func testBindArgumentsAcceptPositionalEvidenceWhenFollowedByOptions() throws {
        // Given
        let arguments = ["evidence/phase0", "--plan", "plan.md", "--output", "candidate.json"]

        // When
        let parsed = try EvidenceValidatorCommand.parseBindArguments(arguments)

        // Then
        XCTAssertEqual(parsed.evidence, "evidence/phase0")
        XCTAssertEqual(parsed.plan, "plan.md")
        XCTAssertEqual(parsed.output, "candidate.json")
        XCTAssertEqual(parsed.environment, "evidence/phase0/environment.json")
    }

    func testBindArgumentsAcceptEvidenceFlagForCompatibility() throws {
        // Given
        let arguments = [
            "--plan", "plan.md",
            "--evidence", "evidence/phase0",
            "--environment", "environment.json",
            "--output", "candidate.json",
        ]

        // When
        let parsed = try EvidenceValidatorCommand.parseBindArguments(arguments)

        // Then
        XCTAssertEqual(parsed.evidence, "evidence/phase0")
        XCTAssertEqual(parsed.plan, "plan.md")
        XCTAssertEqual(parsed.output, "candidate.json")
        XCTAssertEqual(parsed.environment, "environment.json")
    }

    func testBindArgumentsRejectMalformedOrAmbiguousEvidenceWithUsage() {
        // Given
        let cases: [([String], String)] = [
            (["--plan", "plan.md", "--output", "candidate.json"], "evidence"),
            (["evidence/phase0", "--evidence", "other", "--plan", "plan.md", "--output", "candidate.json"], "evidence"),
            (["--evidence", "evidence/phase0", "--evidence", "other", "--plan", "plan.md", "--output", "candidate.json"], "--evidence"),
            (["evidence/phase0", "extra", "--plan", "plan.md", "--output", "candidate.json"], ""),
            (["evidence/phase0", "--plan"], ""),
            (["evidence/phase0", "--plan", "plan.md", "--output", "candidate.json", "--unknown", "value"], "--unknown"),
        ]

        for (arguments, expectedDetail) in cases {
            // When
            var error: Error?
            XCTAssertThrowsError(try EvidenceValidatorCommand.parseBindArguments(arguments)) { error = $0 }

            // Then
            guard let validatorError = error as? ValidatorError else {
                return XCTFail("unexpected error type for \(arguments)")
            }
            XCTAssertEqual(validatorError.code, "usage", "arguments: \(arguments)")
            XCTAssertEqual(validatorError.detail, expectedDetail, "arguments: \(arguments)")
        }
    }
}

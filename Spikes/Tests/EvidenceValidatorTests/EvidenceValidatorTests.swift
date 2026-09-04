import Foundation
import XCTest
@testable import EvidenceValidator

final class EvidenceValidatorTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../Fixtures/Evidence")
        .standardizedFileURL

    func testCompliantEvidencePasses() throws {
        let report = try GateValidator.validate(directory: fixtures.appendingPathComponent("compliant"))
        XCTAssertEqual(report.legCount, 57)
        XCTAssertEqual(report.o4RowCount, 15)
        XCTAssertEqual(report.g0Status, .passed)
    }

    func testValidBlockedAndG0OpenTreesUsePrecedenceWithoutClaimingPass() throws {
        let blocked = try GateValidator.validate(directory: fixtures.appendingPathComponent("valid/blocked"))
        XCTAssertEqual(blocked.g0Status, .passed)
        let open = try GateValidator.validate(directory: fixtures.appendingPathComponent("valid/g0-open"))
        XCTAssertEqual(open.g0Status, .open)
    }

    func testRepresentativeInvalidEvidenceReturnsExactTypedCodes() {
        let expected = [
            "unknown-leg": "unknown_leg_id",
            "missing-leg": "missing_leg_id",
            "duplicate-leg": "duplicate_leg_id",
            "unsupported-pass": "unsupported_pass",
            "incomplete-blocker": "incomplete_blocker",
            "evidence-kind-substitution": "wrong_evidence_kind",
            "mixed-sp1-identity": "mixed_sp1_identity",
            "event-level-live": "live_event_data_forbidden",
        ]
        for (fixture, code) in expected {
            XCTAssertEqual(capturedCode(for: fixture), code, fixture)
        }
    }

    func testAllAdversarialFixtureDirectoriesHaveExpectedTypedCode() throws {
        let root = fixtures.appendingPathComponent("invalid")
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        XCTAssertGreaterThan(directories.count, 20)
        for directory in directories {
            let expected = try String(
                contentsOf: directory.appendingPathComponent("expected-error.txt"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(capturedCode(at: directory), expected, directory.lastPathComponent)
        }
    }

    private func capturedCode(for fixture: String) -> String? {
        capturedCode(at: fixtures.appendingPathComponent("invalid/\(fixture)"))
    }

    private func capturedCode(at url: URL) -> String? {
        do {
            _ = try GateValidator.validate(directory: url)
            return nil
        } catch let error as ValidatorError {
            return error.code
        } catch {
            return "unexpected_error_type"
        }
    }
}

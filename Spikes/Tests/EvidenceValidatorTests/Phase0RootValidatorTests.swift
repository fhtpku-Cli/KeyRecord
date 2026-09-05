import Foundation
import XCTest
@testable import EvidenceValidator

final class Phase0RootValidatorTests: XCTestCase {
    func testRootValidatorRejectsUnexpectedDirectoryBeforeConclusionGeneration() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-root-validator-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(
            at: sandbox.appendingPathComponent("unexpected", isDirectory: true),
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(try Phase0RootValidator.validateMembership(sandbox)) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, "phase0_root_directory_set_mismatch")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("conclusions.json").path))
    }
}

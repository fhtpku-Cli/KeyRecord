import Foundation
import XCTest

final class CurrentMilestonePhysicalTests: XCTestCase {
    func testFailureTraversalDespiteValidRelocation() throws {
        // Given valid objects but an escaping declaration, when checking, then reject the path.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        var evidence = try XCTUnwrap(fixture.document["evidence"] as? [String: [String: String]])
        evidence["q19"]?["path"] = "../outside/receipt.json"
        fixture.document["evidence"] = evidence
        let result = try fixture.check()
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("unsafe_path:"), result.output)
    }

    func testFailureReceiptCannotBecomeReference() throws {
        // Given receipt evidence relabeled as a reference, when checking, then reject the bypass.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        var evidence = try XCTUnwrap(fixture.document["evidence"] as? [String: [String: String]])
        evidence["q19"]?["status"] = "REFERENCE"
        evidence["q19"]?["path"] = "reference.txt"
        fixture.document["evidence"] = evidence
        let result = try fixture.check()
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("evidence_status:q19"), result.output)
    }

    func testFailureMalformedJSON() throws {
        // Given invalid JSON, when invoked through the CLI, then report failure, not approval.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        try Data("{".utf8).write(to: fixture.input)
        let result = try MilestoneFixture.run(
            [fixture.checker.path, fixture.input.path], repository: fixture.repository
        )
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("CURRENT_MILESTONE=FAIL"))
    }

    func testHappyContentAddressedRelocation() throws {
        // Given isolated pinned fixture bytes, when relocated by digest, then verification succeeds.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        let result = try fixture.check()
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("scope=physical-evidence"))
        XCTAssertTrue(result.output.contains("BLOCKED_GATE=FULL_BACKUP_FINAL_RELEASE"))
    }

    func testFailureProductionRejectsFixtureTrustRoot() throws {
        // Given synthetic identities, when submitted to production, then they are unapproved.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        let result = try fixture.check(production: true)
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("unapproved_evidence_identity:"))
    }

    func testFailureTamperedDigest() throws {
        // Given modified physical bytes, when checked, then the pinned digest fails.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        try Data("tampered".utf8).write(to: XCTUnwrap(fixture.artifacts["q19"]))
        let result = try fixture.check()
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("evidence_digest:q19"), result.output)
    }

    func testFailureMalformedReceiptWithMatchingDigest() throws {
        // Given a hash-correct receipt with failed assertions, when checked, then semantics reject it.
        let fixture = try MilestoneFixture(malformedReceipt: true)
        defer { try? fixture.cleanUp() }
        let result = try fixture.check()
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("receipt_assertions:"), result.output)
    }

    func testFailureSymlinkArtifact() throws {
        // Given a symlink to otherwise valid bytes, when relocated, then reject the link.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        let path = try XCTUnwrap(fixture.artifacts["q19"])
        let target = fixture.root.appendingPathComponent("real-receipt.json")
        try FileManager.default.moveItem(at: path, to: target)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        let result = try fixture.check()
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("unsafe_path:"), result.output)
    }

    func testFailureSymlinkBundleAncestor() throws {
        // Given a linked bundle directory, when resolving digest objects, then reject the ancestor.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        let target = fixture.root.appendingPathComponent("real-objects")
        try FileManager.default.moveItem(at: fixture.bundle, to: target)
        try FileManager.default.createSymbolicLink(at: fixture.bundle, withDestinationURL: target)
        let result = try fixture.check()
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("unsafe_path:"), result.output)
    }

    func testFailureSymlinkAllocation() throws {
        // Given a linked input document, when checking structure, then reject the input itself.
        let fixture = try MilestoneFixture()
        defer { try? fixture.cleanUp() }
        let target = fixture.root.appendingPathComponent("real-allocation.json")
        try JSONSerialization.data(withJSONObject: fixture.document).write(to: target)
        try FileManager.default.createSymbolicLink(at: fixture.input, withDestinationURL: target)
        let result = try MilestoneFixture.run(
            [fixture.checker.path, fixture.input.path, "--structure-only"], repository: fixture.repository
        )
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("unsafe_path:"), result.output)
    }
}

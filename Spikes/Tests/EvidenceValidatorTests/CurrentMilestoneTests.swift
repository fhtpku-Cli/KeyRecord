import Foundation
import XCTest

final class CurrentMilestoneTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testHappyStructuralAllocationIsNotApproval() throws {
        // Given the published matrix, when checking structure, then evidence stays unchecked.
        let result = try checkResult(options: ["--structure-only"]) { _ in }
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("STRUCTURE=VALID"))
        XCTAssertTrue(result.output.contains("physical_evidence=NOT_CHECKED"))
        XCTAssertFalse(result.output.contains("CURRENT_MILESTONE=PASS"))
    }

    func testFailureDefaultMissingEvidence() throws {
        // Given unavailable declared artifacts, when checking by default, then fail closed.
        let result = try checkResult { _ in }
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("evidence_unavailable:"))
        XCTAssertFalse(result.output.contains("CURRENT_MILESTONE=PASS"))
    }

    func testFailureMissingMapping() throws {
        // Given a removed requirement, when validating, then coverage fails.
        XCTAssertEqual(try check { $0["requirements"] = [] }, 1)
    }

    func testFailureForgedG1Pass() throws {
        // Given absent live receipts, when G1 is promoted, then reject success.
        XCTAssertEqual(try check { $0["g1"] = "PASS" }, 1)
    }

    func testFailureBlockedPromotedToPass() throws {
        // Given host gates, when any blocked row is promoted, then reject it.
        XCTAssertEqual(try check { document in
            var gates = try XCTUnwrap(document["gates"] as? [[String: Any]])
            gates[0]["status"] = "PASS"
            document["gates"] = gates
        }, 1)
    }

    func testFailureBackupWaived() throws {
        // Given FR-P6, when it is waived, then reject the allocation.
        XCTAssertEqual(try check { document in
            var rows = try XCTUnwrap(document["requirements"] as? [[String: Any]])
            let index = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == "FR-P6" })
            rows[index]["status"] = "WAIVED"
            document["requirements"] = rows
        }, 1)
    }

    func testFailureMissingImplementation() throws {
        // Given a forged file reference, when checking the repository, then reject it.
        XCTAssertEqual(try check { document in
            var rows = try XCTUnwrap(document["requirements"] as? [[String: Any]])
            rows[0]["implementation"] = ["Sources/not-real.swift"]
            document["requirements"] = rows
        }, 1)
    }

    func testFailureForgedEvidenceDigest() throws {
        // Given an altered artifact identity, when checking evidence, then reject it.
        XCTAssertEqual(try check { document in
            var evidence = try XCTUnwrap(document["evidence"] as? [String: [String: String]])
            let key = try XCTUnwrap(evidence.keys.sorted().first)
            evidence[key]?["sha256"] = String(repeating: "0", count: 64)
            document["evidence"] = evidence
        }, 1)
    }

    private func check(_ mutate: (inout [String: Any]) throws -> Void) throws -> Int32 {
        try checkResult(options: ["--structure-only"], mutate).status
    }

    private func checkResult(
        options: [String] = [], _ mutate: (inout [String: Any]) throws -> Void
    ) throws -> MilestoneCLIResult {
        let original = try Data(contentsOf: repository.appendingPathComponent("docs/milestone-allocation.json"))
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Never consult historical host paths, including paths inherited from the environment.
        var evidence = try XCTUnwrap(document["evidence"] as? [String: [String: String]])
        for key in evidence.keys {
            evidence[key]?["path"] = directory.appendingPathComponent("\(key)-receipt.json").path
        }
        document["evidence"] = evidence
        try mutate(&document)
        let input = directory.appendingPathComponent("allocation.json")
        try JSONSerialization.data(withJSONObject: document).write(to: input)
        return try MilestoneFixture.run(
            ["Spikes/Scripts/verify-current-milestone.sh", input.path] + options,
            repository: repository
        )
    }
}

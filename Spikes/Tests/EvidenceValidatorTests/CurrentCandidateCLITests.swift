import Foundation
import XCTest
@testable import EvidenceValidator

final class CurrentCandidateCLITests: XCTestCase {
    func testHappyCLIExclusiveBindAndIdempotentVerify() throws {
        // Given a real clean repository, when the CLI binds it, then both subsequent verifies pass.
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        let runner = try runner(f.root)
        let bound = try runner.run(["bind-current", "--plan", f.planPath, "--readiness", ".omo/readiness.json", "--output", ".omo/candidate.json"])
        XCTAssertEqual(bound.status, 0)
        for _ in 0..<2 {
            XCTAssertEqual(try runner.run(["verify-current-candidate", ".omo/candidate.json", "--readiness", ".omo/readiness.json"]).status, 0)
        }
    }

    func testFailureCLIMissingIsBlockedAndMalformedIsFail() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        let runner = try runner(f.root)
        XCTAssertEqual(try runner.run(["verify-current-candidate", ".omo/absent.json", "--readiness", ".omo/readiness.json"], acceptedStatuses: [2]).status, 2)
        try f.write(".omo/candidate.json", "{}")
        XCTAssertEqual(try runner.run(["verify-current-candidate", ".omo/candidate.json", "--readiness", ".omo/readiness.json"], acceptedStatuses: [1]).status, 1)
    }

    func testFailureCLIRejectsReuseAndEachSingleByteDrift() throws {
        for path in ["Sources/Product.swift", ".omo/plans/current.md", ".omo/readiness.json", ".omo/lifecycle.json", "Scripts/phase1-qa-cases.json"] {
            let f = try CurrentCandidateFixture(); defer { f.remove() }
            _ = try f.bind()
            let runner = try runner(f.root)
            XCTAssertEqual(try runner.run(["bind-current", "--plan", f.planPath, "--readiness", ".omo/readiness.json", "--output", ".omo/candidate.json"], acceptedStatuses: [1]).status, 1)
            var bytes = try Data(contentsOf: f.url(path)); bytes.append(32)
            try bytes.write(to: f.url(path))
            let result = try runner.run(["verify-current-candidate", ".omo/candidate.json", "--readiness", ".omo/readiness.json"], acceptedStatuses: [1])
            XCTAssertEqual(result.status, 1)
            XCTAssertTrue(result.stdout.isEmpty)
        }
    }

    private func runner(_ root: URL) throws -> GitRunner {
        var directory = Bundle(for: CurrentCandidateCLITests.self).bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let executable = directory.appendingPathComponent("EvidenceValidator")
            if FileManager.default.isExecutableFile(atPath: executable.path) {
                return GitRunner(repository: root, timeout: 60, executable: executable)
            }
            directory.deleteLastPathComponent()
        }
        throw CurrentCandidateError(.missingInput, "built EvidenceValidator executable")
    }
}

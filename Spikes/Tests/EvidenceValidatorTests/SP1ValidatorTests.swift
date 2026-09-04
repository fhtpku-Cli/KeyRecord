import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP1ValidatorTests: XCTestCase {
    func testMalformedAndStaleManifestReject() throws {
        try withDirectory { directory in
            try Data("{}\n".utf8).write(to: directory.appendingPathComponent("evidence.json"))
            try Data("bad\n".utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
            XCTAssertThrowsError(try SP1DirectoryValidator.validate(directory: directory))
        }
    }

    func testBlockedEvidenceCannotMisleadPass() throws {
        let hash = String(repeating: "a", count: 64), commit = String(repeating: "b", count: 40)
        let blocker = SP1Blocker(blockedBy: "input_monitoring_denied", detectCommand: ["CGPreflightListenEventAccess"], prerequisite: "Input Monitoring", unblockAction: "Grant separately and rerun")
        let legs = SP1Evidence.requiredLegIDs.map { SP1Leg(legID: $0, verdict: .blocked, detectorAvailable: false, blocker: blocker, identity: nil, runnerCommitSha: commit, runnerTreeSha: commit, environmentSha256: hash, artifactSha256: nil, matrix: nil, aggregateCount: nil) }
        var evidence = SP1Evidence(selectedTapIdentity: nil, legs: legs, verdict: .pass, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: ["source": hash])
        XCTAssertThrowsError(try evidence.validate())
        evidence.verdict = .blocked
        XCTAssertNoThrow(try evidence.validate())
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-validator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }
}

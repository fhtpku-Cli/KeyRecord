import XCTest
@testable import Phase0Support

final class SP6BValidatorTests: XCTestCase {
    func testClosedLegAndArtifactSetsMatchRegistry() {
        XCTAssertEqual(SP6BEvidence.requiredLegIDs, [
            "sp6b.phcAudit", "sp6b.swiftAudit", "sp6b.vectors", "sp6b.universalBuild",
            "sp6b.armTiming", "sp6b.intelTiming", "sp6b.securityAudit",
        ])
        XCTAssertEqual(Set(SP6BDirectoryLayout.legArtifacts.keys), SP6BEvidence.requiredLegIDs.subtracting(["sp6b.intelTiming"]))
    }

    func testIntelBlockerIsCompleteAndDoesNotClaimExecution() {
        XCTAssertTrue(SP6BBlockers.intelHost.complete)
        XCTAssertEqual(SP6BBlockers.intelHost.detectCommand, ["uname", "-m"])
    }

    func testRecommendationRemainsUnfrozenAndRejectsMisrankedCandidate() throws {
        let fixture = SP6BCandidateEvaluation(
            schemaVersion: 1, generatedAt: "2026-09-05T00:00:00Z",
            candidates: [.fixture], scores: ["phc": try Argon2Candidate.fixture.score(at: ISO8601DateFormatter().date(from: "2026-09-05T00:00:00Z")!)],
            eligibleCandidateIDs: ["phc"], recommendation: "phc", dependencyFrozen: false
        )
        XCTAssertThrowsError(try fixture.validate())
    }
}

import Foundation
import XCTest
@testable import Phase0Support

final class Argon2AuditTests: XCTestCase {
    func testCandidateRankingUsesExactAgeBoundariesAndPedigreeTieBreak() throws {
        let generatedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-05T00:00:00Z"))
        let phc = Argon2Candidate(
            id: "phc", canonicalURL: "https://github.com/P-H-C/phc-winner-argon2.git",
            commit: "f57e61e19229e23c4445b85494dbf7c07de721cb", tree: "ac3dc753ff75ce5a0f243cba1d94582bafe09409",
            latestCommitDate: "2021-06-25T00:00:00Z", pedigree: .phcReference, runtimeDependencyCount: 0,
            sourceLOC: 6_842, licenseApproved: true, vectorsPassed: true, dualArchMacOS14Build: true,
            minimumMacOSMajor: 10, unresolvedSignificantFindings: 0
        )
        let swift = Argon2Candidate(
            id: "swift", canonicalURL: "https://github.com/MarlonJD/argon2id-swift-native.git",
            commit: "14d47de1914ac63b368ddb2cfe0f47ffe25f04cf", tree: "4bb860f4c47b4b327ea207da3fe7a007a05c7b81",
            latestCommitDate: "2026-01-01T00:00:00Z", pedigree: .independent, runtimeDependencyCount: 0,
            sourceLOC: 900, licenseApproved: true, vectorsPassed: true, dualArchMacOS14Build: true,
            minimumMacOSMajor: 10, unresolvedSignificantFindings: 0
        )

        XCTAssertEqual(try phc.score(at: generatedAt).maintenance, 0)
        XCTAssertEqual(try swift.score(at: generatedAt).maintenance, 2)
        XCTAssertEqual(try Argon2Ranking.recommend([swift, phc], at: generatedAt).id, "phc")
    }

    func testEligibilityRejectsBranchPlatformVectorLicenseBuildAndFindings() throws {
        let baseline = Argon2Candidate.fixture
        let mutations: [(Argon2Candidate) -> Argon2Candidate] = [
            { $0.replacing(commit: "main") }, { $0.replacing(minimumMacOSMajor: 15) },
            { $0.replacing(vectorsPassed: false) }, { $0.replacing(licenseApproved: false) },
            { $0.replacing(dualArchMacOS14Build: false) }, { $0.replacing(unresolvedSignificantFindings: 1) },
        ]
        for mutation in mutations { XCTAssertFalse(mutation(baseline).isEligible) }
    }

    func testD12AcceptsClosedCompletePaginationAndClassifiedNVDHits() throws {
        let snapshot = D12Snapshot.fixture
        XCTAssertNoThrow(try snapshot.validate(generatedAt: "2026-09-05T00:00:00Z"))
        XCTAssertEqual(snapshot.nvd.pages.flatMap(\.vulnerabilities).map(\.impact), [.phc, .none])
    }

    func testD12RejectsIdentityFreshnessAndPaginationAttacks() throws {
        let mutations: [(D12Snapshot) -> D12Snapshot] = [
            { $0.replacing(githubStatus: 500) }, { $0.replacing(githubURL: "https://api.github.com/repos/wrong/repo/security-advisories?per_page=100") },
            { $0.replacing(osvCommit: String(repeating: "f", count: 40)) }, { $0.replacing(osvContinuationToken: "replayed") },
            { $0.replacing(nvdStartIndex: 1) }, { $0.replacing(nvdTotalResults: 3) },
            { $0.replacing(nvdDuplicateCVE: true) }, { $0.replacing(retrievedAt: "2026-09-03T00:00:00Z") },
        ]
        for mutation in mutations { XCTAssertThrowsError(try mutation(.fixture).validate(generatedAt: "2026-09-05T00:00:00Z")) }
    }

    func testIntelAbsenceIsCompleteBlockedLegAndNeverPass() {
        let blocker = SP6BBlockers.intelHost
        XCTAssertTrue(blocker.complete)
        XCTAssertEqual(blocker.blockedBy, "physical_intel_macos14_host_unavailable")
    }
}

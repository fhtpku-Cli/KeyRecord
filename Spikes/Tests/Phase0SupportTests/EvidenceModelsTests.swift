import Foundation
import XCTest
@testable import Phase0Support

final class EvidenceModelsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Evidence"))
        return try Data(contentsOf: url)
    }

    func testAllFourVerdictsDecode() throws {
        let decoded = try JSONDecoder().decode(EvidenceFixture.self, from: fixture("all-verdicts"))
        XCTAssertEqual(Set(decoded.legs.map(\.verdict)), Set(Verdict.allCases))
    }

    func testUnknownVerdictRejects() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(EvidenceFixture.self, from: fixture("unknown-verdict"))
        ) { XCTAssertTrue($0 is DecodingError) }
    }

    func testPassWithoutArtifactHashRejects() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(EvidenceFixture.self, from: fixture("pass-without-hash"))
        ) { XCTAssertEqual($0 as? EvidenceModelError, .unsupportedPassWithoutArtifactHash(legID: "sp1.autoRepeat")) }
    }

    func testUnknownFieldsReject() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(EvidenceFixture.self, from: fixture("unknown-field"))
        ) { XCTAssertTrue($0 is EvidenceModelError) }
    }

    func testRegistriesAreClosed() {
        XCTAssertEqual(Phase0Registry.spikeIDs.count, 9)
        XCTAssertEqual(Phase0Registry.legIDs.count, 57)
        XCTAssertEqual(Phase0Registry.o4IDs.count, 15)
        XCTAssertEqual(ReceiptContract.finalReview.reviewerIDs, ["F1", "F2", "F3", "F4"])
    }

    func testFinalReviewCommandRegistryIsExactAndStrict() throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: packageRoot.appending(path: "FinalReviewCommands.json"))
        let registry = try JSONDecoder().decode(FinalReviewCommandRegistry.self, from: data)
        XCTAssertEqual(registry.schemaVersion, 1)
        XCTAssertEqual(registry.reviewers.map(\.reviewerID), ["F1", "F2", "F3", "F4"])
        XCTAssertEqual(Set(registry.reviewers.flatMap(\.commands).map(\.id)).count, 14)
    }
}

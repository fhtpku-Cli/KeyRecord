import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class ConclusionDecodingTests: XCTestCase {
    func testConclusionsRejectDuplicateKeysRecursively() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/conclusions.json"))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let rootDuplicate = try XCTUnwrap(text.replacingFirst("{", with: "{\"schema_version\":1,"))
        let nestedDuplicate = try XCTUnwrap(text.replacingFirst(
            "\"evidence\":{",
            with: "\"evidence\":{\"path\":\"sp1/evidence.json\","
        ))
        for candidate in [rootDuplicate, nestedDuplicate] {
            XCTAssertThrowsError(try ValidatorDecoding.decode(
                Phase0Conclusions.self,
                from: Data(candidate.utf8),
                malformedCode: "malformed_conclusions"
            )) { error in
                XCTAssertEqual((error as? ValidatorError)?.code, "duplicate_json_key")
            }
        }
    }
}

private extension String {
    func replacingFirst(_ target: String, with replacement: String) -> String? {
        guard let range = range(of: target) else { return nil }
        return replacingCharacters(in: range, with: replacement)
    }
}

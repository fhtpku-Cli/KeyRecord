import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class ConclusionDecodingTests: XCTestCase {
    func testConclusionsRejectDuplicateKeysRecursively() throws {
        let candidates = [
            #"{"schema_version":1,"schema_version":1}"#,
            #"{"evidence":{"path":"sp1/evidence.json","path":"sp2/evidence.json"}}"#,
        ]
        for candidate in candidates {
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

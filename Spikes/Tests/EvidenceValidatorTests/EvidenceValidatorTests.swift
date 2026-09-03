import XCTest
@testable import EvidenceValidator

final class EvidenceValidatorTests: XCTestCase {
    func testValidatorTargetLoads() {
        XCTAssertTrue(String(describing: EvidenceValidatorCommand.self).contains("EvidenceValidator"))
    }
}

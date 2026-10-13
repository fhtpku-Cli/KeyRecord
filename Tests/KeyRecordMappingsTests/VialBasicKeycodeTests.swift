import XCTest
import Foundation
@testable import KeyRecordMappings

final class VialBasicKeycodeTests: XCTestCase {
    private struct OfficialKey: Decodable {
        let token: String
        let raw: UInt16
        let aliases: [String]
    }
    func testOfficialBasicSpecialAndISONamesAndDeclaredAliases() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("evidence/phase4/fixtures/synthetic/vial6-basic-keycodes.json"))
        let keys = try JSONDecoder().decode([OfficialKey].self, from: bytes)
        XCTAssertFalse(keys.isEmpty)
        for key in keys {
            for token in [key.token] + key.aliases {
                XCTAssertEqual(try VialKeycodeDialect.rawValue(token), key.raw, token)
            }
        }
    }
    func testOfficialBasicNamesComposeWithExistingModifiersAndLayerTap() throws {
        XCTAssertEqual(try VialKeycodeDialect.rawValue("RSFT(KC_QUOTE)"), 0x1234)
        XCTAssertEqual(try VialKeycodeDialect.rawValue("LCTL(LSFT(KC_KP_COMMA))"), 0x0385)
        XCTAssertEqual(try VialKeycodeDialect.rawValue("LT(1,KC_KP_ENTER)"), 0x4158)
        XCTAssertEqual(try VialKeycodeDialect.rawValue("0xffff"), 0xffff)
        XCTAssertTrue(VialKeycodeDialect.protectedEntry("LT(1,KC_KP_ENTER)"))
        for token in ["KC_UNKNOWN", "USER00", "MACRO(0)", "TD(0)", "KC_EXLM", "RGB_TOG", "KC_QUOTE()",
                      "LCTL(KC_TRANSPARENT)", "LCTL(RSFT(KC_QUOTE))", "LT(16,KC_KP_ENTER)"] {
            XCTAssertThrowsError(try VialKeycodeDialect.rawValue(token), token) {
                XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput)
            }
        }
    }
}

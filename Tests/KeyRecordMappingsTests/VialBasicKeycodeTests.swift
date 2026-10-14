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
    func testOfficialOrdinaryModifierNamesAndWorkingAliasesNormalizeAllBasicKeys() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = root.appendingPathComponent("evidence/phase4/fixtures/synthetic")
        let modifiers = try JSONDecoder().decode([OfficialKey].self,
            from: Data(contentsOf: fixtures.appendingPathComponent("vial6-modifier-keycodes.json")))
        let basics = try JSONDecoder().decode([OfficialKey].self,
            from: Data(contentsOf: fixtures.appendingPathComponent("vial6-basic-keycodes.json")))
        XCTAssertEqual(modifiers.count, 18)
        for modifier in modifiers {
            for name in [modifier.token] + modifier.aliases {
                XCTAssertEqual(try VialKeycodeDialect.rawValue(name), modifier.raw, name)
                for key in basics where key.raw > 1 {
                    let token = name.replacingOccurrences(of: "KC_C", with: key.token)
                    XCTAssertEqual(try VialKeycodeDialect.rawValue(token), (modifier.raw & 0xff00) | key.raw, token)
                }
            }
        }
    }
    func testCombinedModifiersKeepDirectionDepthAndUnsupportedActionBoundaries() throws {
        XCTAssertEqual(try VialKeycodeDialect.rawValue("C_S(LALT(KC_C))"), 0x0706)
        XCTAssertEqual(try VialKeycodeDialect.rawValue("LALT(C_S(KC_C))"), 0x0706)
        XCTAssertEqual(try VialKeycodeDialect.rawValue("RCG(RALT(KC_KP_ENTER))"), 0x1d58)
        XCTAssertEqual(try VialKeycodeDialect.rawValue("C(S(A(G(KC_C))))"), 0x0f06)
        for prefix in ["C_S", "LCA", "LSA", "MEH", "LCG", "SGUI", "LAG", "LCAG", "HYPR", "RCG", "SCMD", "SWIN", "LSG"] {
            for child in ["KC_NO", "KC_TRNS", "KC_TRANSPARENT", "LT(1,KC_C)", "MO(1)", "QK_BOOT", "USER00", "MACRO(0)", "TD(0)"] {
                XCTAssertThrowsError(try VialKeycodeDialect.rawValue("\(prefix)(\(child))")) {
                    XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput)
                }
            }
        }
        for token in ["C_S(RCTL(KC_C))", "RCG(LSFT(KC_C))", "LCTL(RCG(KC_C))", "RCTL(HYPR(KC_C))",
                      "C(S(A(G(C(KC_C)))))", "LCS(KC_C)", "RSA(KC_C)", "RCS(KC_C)", "HYPR_T(KC_C)", "OSM(MOD_MEH)"] {
            XCTAssertThrowsError(try VialKeycodeDialect.rawValue(token), token) {
                XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput)
            }
        }
        XCTAssertTrue(VialKeycodeDialect.protectedEntry("LT(1,KC_C)"))
        XCTAssertTrue(VialKeycodeDialect.protectedEntry("MO(1)"))
        XCTAssertTrue(VialKeycodeDialect.protectedEntry("QK_BOOT"))
    }
    func testOfficialCanonicalLayerTapNamesKeepRawValuesAndEntryProtection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let basics = try JSONDecoder().decode([OfficialKey].self, from: Data(contentsOf:
            root.appendingPathComponent("evidence/phase4/fixtures/synthetic/vial6-basic-keycodes.json")))
        for layer in 0..<16 {
            for key in basics {
                let token = "LT\(layer)(\(key.token))"
                XCTAssertEqual(try VialKeycodeDialect.rawValue(token), 0x4000 | UInt16(layer) << 8 | key.raw, token)
            }
            XCTAssertTrue(VialKeycodeDialect.protectedEntry("LT\(layer)(KC_C)"))
            XCTAssertEqual(VialKeycodeDialect.layerEntry("LT\(layer)(KC_C)"), "LT(\(layer),KC_NO)")
            XCTAssertEqual(try VialKeycodeDialect.rawValue("LT\(layer)(KC_KP_ENTER)"),
                           try VialKeycodeDialect.rawValue("LT(\(layer),KC_KP_ENTER)"))
        }
    }
    func testCanonicalLayerTapRejectsMalformedLayersAndNonBasicChildren() throws {
        for token in ["LT16(KC_C)", "LT-1(KC_C)", "LT01(KC_C)", "LT(KC_C)", "LT1()", "LT1(KC_C,KC_A)",
                      "LT1(LCTL(KC_C))", "LT1(LT0(KC_C))", "LT1(MO(0))", "LT1(QK_BOOT)", "LT1(USER00)",
                      "LT1(MACRO(0))", "LT1(0x0006)", "LCTL(LT1(KC_C))", "LT1(KC_C))"] {
            XCTAssertThrowsError(try VialKeycodeDialect.rawValue(token), token) {
                XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput)
            }
        }
        XCTAssertEqual(try VialKeycodeDialect.rawValue("LT0(KC_NO)"), 0x4000)
        XCTAssertEqual(try VialKeycodeDialect.rawValue("LT1(KC_TRNS)"), 0x4101)
    }
}

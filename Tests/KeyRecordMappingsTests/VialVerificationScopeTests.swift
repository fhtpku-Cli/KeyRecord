import Foundation
import XCTest
@testable import KeyRecordMappings

final class VialVerificationScopeTests: XCTestCase {
    func testVIADefinitionRequirementsFollowOfficialSourceWithoutCompletingVersionAxes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
            "evidence/phase4/fixtures/synthetic/via-compiled-definitions.json"))) as? [String: Any])
        for (version, required) in try XCTUnwrap(fixture["protocolDefinitions"] as? [String: String]) {
            XCTAssertEqual(FirmwareVersionProvider.requiredVIADefinition(deviceProtocol: "via-" + version), required)
        }
        for value: String? in [nil, "via-6", "via-14", "via-011", "via-11/vial-6", "v3"] {
            XCTAssertNil(FirmwareVersionProvider.requiredVIADefinition(deviceProtocol: value))
        }
        let bytes = Data(#"{"vendorProductId":65538,"layers":[["KC_A"]],"definitionSchema":"v3","version":"1.14.4","importer":"forged"}"#.utf8)
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .via, viaDeviceProtocol: "via-13")
        XCTAssertEqual(FirmwareVersionProvider.requiredVIADefinition(deviceProtocol: axes.deviceProtocol), "v3")
        XCTAssertNil(axes.definitionSchema); XCTAssertNil(axes.importer); XCTAssertFalse(axes.complete)
    }
    func testEveryOpaqueSectionIncludingEmptyOrUnknownContentRemainsUnverifiedAndPreserved() throws {
        let base = #"{"version":1,"uid":42,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO"]]],"encoder_layout":[[]]"#
        for section in ["macro", "tap_dance", "combo", "key_override", "alt_repeat_key", "layout_options", "settings", "future_feature"] {
            for value in ["[]", "{}", "0", "null", #"[["opaque value",123]]"#] {
                let bytes = Data((base + ",\"\(section)\" : " + value + "}").utf8)
                let document = try FirmwareDocument(bytes: bytes, backend: .vial)
                XCTAssertEqual(try document.unverifiedVialSections(), [section])
                let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "fixture", importer: "fixture")
                let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: "42", axes: axes, supportedOutputs: ["KC_C"])])
                let patched = try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false)],
                    expectedDevice: "42", axes: axes, support: support)
                XCTAssertEqual(patched, Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "KC_NO", with: "KC_C").utf8))
                XCTAssertEqual(try FirmwareDocument(bytes: patched, backend: .vial).unverifiedVialSections(), [section])
            }
        }
        XCTAssertEqual(try FirmwareDocument(bytes: Data((base + "}").utf8), backend: .vial).unverifiedVialSections(), [])
    }
    func testFileCannotSupplyIndependentDefinitionOrImporterFacts() throws {
        let bytes = Data(#"{"version":1,"uid":42,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO"]]],"definitionSchema":"forged","importer":"forged"}"#.utf8)
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial)
        XCTAssertNil(axes.definitionSchema); XCTAssertNil(axes.importer); XCTAssertFalse(axes.complete)
        let independent = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "reader-schema", importer: "today.vial/0.7.5/1")
        XCTAssertEqual(independent.definitionSchema, "reader-schema")
        XCTAssertEqual(independent.importer, "today.vial/0.7.5/1")
        XCTAssertFalse(FirmwareSupportDirectory().supports(backend: .vial, device: "42", axes: independent))
    }
}

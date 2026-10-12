import XCTest
import KeyRecordCore
import KeyRecordConfigurationRead
@testable import KeyRecordAnalysis

final class VIAReferenceParserTests: XCTestCase {
    let layout = Data(#"{"name":"synthetic","vendorProductId":65538,"layers":[["KC_A","KC_F1","KC_LGUI","KC_NO"]],"macros":[""]}"#.utf8)
    let definition = Data(#"{"name":"synthetic","vendorId":"0x0001","productId":"0x0002","matrix":{"rows":2,"cols":2},"layouts":{"keymap":[["1,0",{"w":2},"0,1"],[{"x":0.5},"0,0","1,1"]]}}"#.utf8)

    func testV2V3MatchMatrixCoordinatesRatherThanVisualOrder() throws {
        let parsed = try VIAReferenceParser.match(layout: VIAReferenceParser.layout(layout), definition: VIAReferenceParser.definition(definition))
        XCTAssertEqual(parsed.standardKeyCount, 3)
        XCTAssertEqual(parsed.unsupportedKeyCount, 0)
        XCTAssertEqual(parsed.bindings["0,0"], .standard(keyCode: try KeyCode(0), hidUsage: 0x04))
        XCTAssertEqual(parsed.bindings["1,0"], .standard(keyCode: try KeyCode(55), hidUsage: 0xe3))
        XCTAssertEqual(parsed.geometry?.positions["1,0"]?.x, 0.5)
        XCTAssertEqual(parsed.geometry?.positions["0,1"]?.x, 2.0)
        XCTAssertEqual(parsed.geometry?.positions["0,0"]?.x, 1.0)
        XCTAssertEqual(parsed.positionCount(for: try KeyCode(122)), 1)
        let legacy = Data(#"{"name":"legacy","vendorProductId":65538,"matrix":{"rows":2,"cols":2},"layouts":{"keymap":[["0,0","0,1"],["1,0","1,1"]]}}"#.utf8)
        XCTAssertEqual(try VIAReferenceParser.definition(legacy).vendorProductID, parsed.vendorProductID)
    }

    func testKeyboardIdentityAndEveryLayerShapeMustMatch() throws {
        let parsedLayout = try VIAReferenceParser.layout(layout)
        let wrongID = Data(String(decoding: definition, as: UTF8.self).replacingOccurrences(of: "0x0002", with: "0x0003").utf8)
        XCTAssertThrowsError(try VIAReferenceParser.match(layout: parsedLayout, definition: VIAReferenceParser.definition(wrongID))) {
            XCTAssertEqual($0 as? VIAImportError, .keyboardMismatch)
        }
        let short = Data(#"{"name":"short","vendorProductId":65538,"layers":[["KC_A"],["KC_A","KC_A","KC_A","KC_A"]]}"#.utf8)
        XCTAssertThrowsError(try VIAReferenceParser.match(layout: VIAReferenceParser.layout(short), definition: VIAReferenceParser.definition(definition))) {
            XCTAssertEqual($0 as? VIAImportError, .layerShapeMismatch)
        }
    }

    func testUnknownLayerAndMacroActionsRemainOpaqueAndUnverified() throws {
        let data = Data(#"{"name":"synthetic","vendorProductId":65538,"layers":[["KC_A","LT(1,KC_A)","KC_TRNS","KC_NO"],["KC_F1","KC_F2","KC_F3","KC_F4"]],"macros":["private typed secret"],"encoders":[[]]}"#.utf8)
        let parsed = try VIAReferenceParser.match(layout: VIAReferenceParser.layout(data), definition: VIAReferenceParser.definition(definition))
        XCTAssertEqual(parsed.unsupportedKeyCount, 2)
        XCTAssertTrue(parsed.limitations.isSuperset(of: [.deploymentUnknown, .transformsUnknown, .additionalLayers, .unsupportedKeycodes, .dynamicFeatures]))
        XCTAssertFalse(String(describing: parsed).contains("private typed secret"))
        XCTAssertEqual(parsed.physicalEvidence.device, .unknown)
        XCTAssertEqual(parsed.physicalEvidence.chain[0].status, .absent)
        XCTAssertEqual(parsed.physicalEvidence.chain[0].mapping?.completeInverseFor, [])
        let a = Chord(keyCode: try KeyCode(0), modifiers: ModifierSet(command: .left, option: .none, control: .none, shift: .left, fn: .none))
        let b = Chord(keyCode: try KeyCode(122), modifiers: ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none))
        XCTAssertEqual(PhysicalAnalysis.compare(source: a, trigger: b, scope: .global, evidence: parsed.physicalEvidence),
                       .logical(sourceKeys: 3, triggerKeys: 1, reason: .deviceUncertain))
    }

    func testLayoutsWithUnselectedOptionsKeepAssignmentsWithoutGeometry() throws {
        let data = Data(#"{"name":"options","vendorProductId":65538,"matrix":{"rows":2,"cols":2},"layouts":{"labels":[["Bottom","A","B"]],"keymap":[["0,0\n\n\n0,0","0,1"],["1,0","1,1"]]}}"#.utf8)
        let parsed = try VIAReferenceParser.match(layout: VIAReferenceParser.layout(layout), definition: VIAReferenceParser.definition(data))
        XCTAssertNil(parsed.geometry)
        XCTAssertTrue(parsed.limitations.contains(.layoutOptions))
        XCTAssertEqual(parsed.standardKeyCount, 3)
        XCTAssertEqual(parsed.positionCount(for: try KeyCode(0)), 0)
    }

    func testUnsupportedRotationShapeAndAlignmentDoNotBecomeGeometry() throws {
        for properties in [#"{"r":15}"#, #"{"w2":2}"#, #"{"a":7}"#, #"{"d":true}"#] {
            let data = Data("{\"name\":\"complex\",\"vendorProductId\":65538,\"matrix\":{\"rows\":1,\"cols\":1},\"layouts\":{\"keymap\":[[\(properties),\"0,0\"]]}}".utf8)
            let parsed = try VIAReferenceParser.definition(data)
            XCTAssertNil(parsed.geometry)
            XCTAssertTrue(parsed.limitations.contains(.complexGeometry))
        }
    }

    func testDuplicateInvalidAndOutOfMatrixPositionsAreRejected() throws {
        for keys in [#"["0,0","0,0"]"#, #"["2,0"]"#, #"[{"w":0},"0,0"]"#] {
            let data = Data("{\"name\":\"bad\",\"vendorProductId\":65538,\"matrix\":{\"rows\":1,\"cols\":2},\"layouts\":{\"keymap\":[\(keys)]}}".utf8)
            XCTAssertThrowsError(try VIAReferenceParser.definition(data)) { XCTAssertEqual($0 as? VIAImportError, .invalidGeometry) }
        }
    }

    func testDuplicateEscapedFieldsAndOversizedInputsUseSharedProtection() throws {
        for json in [#"{"name":"a","\u006eame":"b"}"#, #"{"name":"x","nested":{"a":1,"a":2}}"#, #"{"name":"x",}"#] {
            XCTAssertThrowsError(try VIAReferenceParser.layout(Data(json.utf8))) { XCTAssertEqual($0 as? VIAImportError, .jsonProtection) }
        }
        let oversized = Data(repeating: 0x20, count: ConfigurationReadLimits.maximumInputBytes + 1)
        XCTAssertThrowsError(try VIAReferenceParser.layout(oversized)) { XCTAssertEqual($0 as? VIAImportError, .jsonProtection) }
    }

    func testSchemaBooleansUnassignedIdentifiersAndNonStringSlotsFail() throws {
        for json in [#"{"name":"x","vendorId":"0x0001","productId":"0x0002","vendorProductId":65538}"#,
                     #"{"name":"x","vendorId":"0x10000","productId":"0x0002"}"#,
                     #"{"name":"x","vendorProductId":true,"matrix":{"rows":1,"cols":1}}"#] {
            XCTAssertThrowsError(try VIAReferenceParser.definition(Data(json.utf8)))
        }
        XCTAssertThrowsError(try VIAReferenceParser.layout(Data(#"{"name":"x","vendorProductId":65538,"layers":[[123]]}"#.utf8)))
    }
}

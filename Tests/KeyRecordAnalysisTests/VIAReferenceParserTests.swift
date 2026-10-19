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
    func testOfficialCompiledDefinitionsMatchRawGeometryAndKeepUnverifiedProvenance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
            "evidence/phase4/fixtures/synthetic/via-compiled-definitions.json"))) as? [String: Any])
        for item in try XCTUnwrap(fixture["fixtures"] as? [[String: Any]]) {
            let raw = try VIAReferenceParser.definition(JSONSerialization.data(withJSONObject: XCTUnwrap(item["raw"])))
            let compiled = try VIAReferenceParser.definition(JSONSerialization.data(withJSONObject: XCTUnwrap(item["compiled"])))
            XCTAssertEqual(raw, compiled)
            let matched = try VIAReferenceParser.match(layout: VIAReferenceParser.layout(layout), definition: compiled)
            XCTAssertEqual(matched.geometry?.positions["0,1"]?.x, 2)
            XCTAssertEqual(matched.geometry?.positions["0,0"]?.x, 1)
            XCTAssertEqual(matched.physicalEvidence.device, .unknown)
            XCTAssertTrue(matched.limitations.contains(.deploymentUnknown))
        }
    }
    private func compiled(_ change: (inout [String: Any], inout [[String: Any]]) -> Void) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
            "evidence/phase4/fixtures/synthetic/via-compiled-definitions.json"))) as? [String: Any])
        let item = try XCTUnwrap((fixture["fixtures"] as? [[String: Any]])?.first)
        var object = try XCTUnwrap(item["compiled"] as? [String: Any])
        var layouts = try XCTUnwrap(object["layouts"] as? [String: Any])
        var keys = try XCTUnwrap(layouts["keys"] as? [[String: Any]])
        change(&layouts, &keys)
        layouts["keys"] = keys; object["layouts"] = layouts
        return try JSONSerialization.data(withJSONObject: object)
    }
    func testOfficialCompilerAgreesWithSelectedOptionsAndRotation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
            "evidence/phase4/fixtures/synthetic/via-compiled-definitions.json"))) as? [String: Any])
        for item in try XCTUnwrap(fixture["geometryFixtures"] as? [[String: Any]]) {
            let rawBytes = try JSONSerialization.data(withJSONObject: XCTUnwrap(item["raw"]))
            let compiledBytes = try JSONSerialization.data(withJSONObject: XCTUnwrap(item["compiled"]))
            let options = try VIAReferenceParser.definition(rawBytes).layoutOptions
            for selection in options.isEmpty ? [[]] : [[0], [1]] {
                let raw = try XCTUnwrap(VIAReferenceParser.definition(rawBytes, layoutSelection: selection).geometry)
                let compiled = try XCTUnwrap(VIAReferenceParser.definition(compiledBytes, layoutSelection: selection).geometry)
                XCTAssertEqual(Set(raw.positions.keys), Set(compiled.positions.keys))
                for (id, position) in raw.positions {
                    XCTAssertEqual(position.x, try XCTUnwrap(compiled.positions[id]?.x), accuracy: 0.000001)
                    XCTAssertEqual(position.y, try XCTUnwrap(compiled.positions[id]?.y), accuracy: 0.000001)
                }
            }
        }
    }
    func testCompiledDefinitionRejectsMalformedCoordinatesShapesAndMixedRepresentations() throws {
        let mutations: [(inout [String: Any], inout [[String: Any]]) -> Void] = [
            { _, keys in keys[0]["row"] = 2 }, { _, keys in keys[0]["col"] = -1 },
            { _, keys in keys[0]["x"] = "0" }, { _, keys in keys[0]["w"] = 0 },
            { _, keys in keys[0]["d"] = 0 }, { _, keys in keys[0].removeValue(forKey: "r") },
            { _, keys in keys.append(keys[0]) }, { _, keys in keys = [] },
            { layouts, _ in layouts["keymap"] = [["0,0"]] },
            { layouts, _ in layouts["height"] = -1 }, { layouts, _ in layouts["optionKeys"] = [] },
            { layouts, _ in layouts["optionKeys"] = ["0": ["0": true]] },
            { layouts, keys in layouts["optionKeys"] = ["00": ["0": [keys[0]]]] },
            { layouts, keys in layouts["optionKeys"] = ["0": ["01": [keys[0]]]] }
        ]
        for change in mutations { XCTAssertThrowsError(try VIAReferenceParser.definition(compiled(change))) }
    }
    func testCompiledUnselectedOptionsEncoderAndFutureGeometryRemainUnmeasured() throws {
        let mutations: [(inout [String: Any], inout [[String: Any]]) -> Void] = [
            { _, keys in keys[0]["d"] = true },
            { _, keys in keys[0]["ei"] = 0 }, { _, keys in keys[0]["w2"] = 2 },
            { _, keys in keys[0]["future_geometry"] = 1 },
            { layouts, _ in layouts["future_geometry"] = 1 },
            { layouts, keys in layouts["optionKeys"] = ["0": ["0": [keys[0]]]] }
        ]
        for change in mutations {
            let parsed = try VIAReferenceParser.definition(compiled(change))
            XCTAssertNil(parsed.geometry)
            XCTAssertFalse(parsed.limitations.isDisjoint(with: [.complexGeometry, .layoutOptions]))
        }
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

    func testUnknownRawLayoutFieldsPreserveBindingsWithoutMeasuredGeometry() throws {
        for legacy in [false, true] {
            for options in [false, true] {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: definition) as? [String: Any])
                if legacy {
                    object.removeValue(forKey: "vendorId")
                    object.removeValue(forKey: "productId")
                    object["vendorProductId"] = 65538
                }
                var layouts = try XCTUnwrap(object["layouts"] as? [String: Any])
                layouts["future_geometry"] = ["offset": 4]
                if options { layouts["labels"] = [["Layout", "A", "B"]] }
                object["layouts"] = layouts
                let parsed = try VIAReferenceParser.definition(JSONSerialization.data(withJSONObject: object))
                XCTAssertNil(parsed.geometry)
                XCTAssertTrue(parsed.limitations.contains(.complexGeometry))
                XCTAssertEqual(parsed.limitations.contains(.layoutOptions), options)
                let matched = try VIAReferenceParser.match(layout: VIAReferenceParser.layout(layout), definition: parsed)
                XCTAssertEqual(matched.standardKeyCount, 3)
                XCTAssertEqual(matched.bindings["0,0"], .standard(keyCode: try KeyCode(0), hidUsage: 0x04))
                XCTAssertNil(matched.physicalEvidence.geometry)
                XCTAssertEqual(matched.positionCount(for: try KeyCode(0)), 0)
                XCTAssertEqual(matched.physicalEvidence.device, .unknown)
            }
        }
    }

    func testUnknownRawLayoutFieldDoesNotHideInvalidCoordinates() throws {
        let bytes = Data(#"{"name":"bad","vendorProductId":65538,"matrix":{"rows":1,"cols":1},"layouts":{"future_geometry":1,"keymap":[["1,0"]]}}"#.utf8)
        XCTAssertThrowsError(try VIAReferenceParser.definition(bytes)) {
            XCTAssertEqual($0 as? VIAImportError, .invalidGeometry)
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

    func testUnsupportedShapeAndAlignmentDoNotBecomeGeometry() throws {
        for properties in [#"{"w2":2}"#, #"{"a":7}"#, #"{"d":true}"#] {
            let data = Data("{\"name\":\"complex\",\"vendorProductId\":65538,\"matrix\":{\"rows\":1,\"cols\":1},\"layouts\":{\"keymap\":[[\(properties),\"0,0\"]]}}".utf8)
            let parsed = try VIAReferenceParser.definition(data)
            XCTAssertNil(parsed.geometry)
            XCTAssertTrue(parsed.limitations.contains(.complexGeometry))
        }
    }

    func testRotationPersistsAcrossRowsAndUsesClusterOrigin() throws {
        let data = Data(#"{"name":"rotation","vendorProductId":65538,"matrix":{"rows":2,"cols":1},"layouts":{"keymap":[[{"r":90,"rx":2,"ry":3},"0,0"],["1,0"]]}}"#.utf8)
        let geometry = try XCTUnwrap(VIAReferenceParser.definition(data).geometry)
        XCTAssertEqual(try XCTUnwrap(geometry.positions["0,0"]?.x), 1.5, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(geometry.positions["1,0"]?.x), 0.5, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(geometry.positions["1,0"]?.y), 0.5, accuracy: 0.000001)
        let rotated = try VIAReferenceParser.definition(compiled { _, keys in
            keys[0]["r"] = 90; keys[0]["rx"] = 0; keys[0]["ry"] = 0
        })
        XCTAssertEqual(try XCTUnwrap(rotated.geometry?.positions["1,0"]?.x), -0.5, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(rotated.geometry?.positions["1,0"]?.y), 0.5, accuracy: 0.000001)
    }

    func testExplicitOptionsAlignAlternativesAndPackedValuesRejectReservedChoices() throws {
        let data = Data(#"{"name":"options","vendorProductId":65538,"matrix":{"rows":1,"cols":3},"layouts":{"labels":["Split",["Mode","A","B","C"]],"keymap":[["0,0","0,1\n\n\n0,0"],[{"x":4,"w":2},"0,2\n\n\n0,1"]]}}"#.utf8)
        XCTAssertNil(try VIAReferenceParser.definition(data).geometry)
        let selected = try VIAReferenceParser.definition(data, layoutSelection: [1, 2])
        XCTAssertEqual(selected.geometry?.positions.count, 2)
        XCTAssertNil(selected.geometry?.positions["0,1"])
        XCTAssertEqual(selected.geometry?.positions["0,2"]?.x, 2)
        XCTAssertEqual(selected.geometry?.positions["0,2"]?.y, 0.5)
        XCTAssertEqual(try VIAReferenceParser.definition(data, packedLayoutOptions: 6), selected)
        for packed: UInt32 in [3, 7, 8, UInt32.max] {
            XCTAssertThrowsError(try VIAReferenceParser.definition(data, packedLayoutOptions: packed))
        }
        for choices in [[1], [2, 0], [-1, 0], [0, 3]] {
            XCTAssertThrowsError(try VIAReferenceParser.definition(data, layoutSelection: choices))
        }
        XCTAssertThrowsError(try VIAReferenceParser.definition(data, layoutSelection: [0, 0], packedLayoutOptions: 0))
    }

    func testCompiledOptionSelectionAndUnknownRawOptionGeometryDoNotGuess() throws {
        let bytes = try compiled { layouts, keys in
            layouts["labels"] = ["Split"]
            let alternative = keys.removeLast()
            layouts["optionKeys"] = ["0": ["0": [alternative], "1": []]]
        }
        XCTAssertEqual(try VIAReferenceParser.definition(bytes, layoutSelection: [0]).geometry?.positions.count, 4)
        XCTAssertEqual(try VIAReferenceParser.definition(bytes, layoutSelection: [1]).geometry?.positions.count, 3)
        let rotatedOptions = Data(#"{"name":"options","vendorProductId":65538,"matrix":{"rows":1,"cols":1},"layouts":{"labels":["Split"],"keymap":[[{"r":15},"0,0\n\n\n0,0"]]}}"#.utf8)
        XCTAssertNil(try VIAReferenceParser.definition(rotatedOptions, layoutSelection: [0]).geometry)
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

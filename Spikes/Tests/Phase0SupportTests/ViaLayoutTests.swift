import Foundation
import XCTest
@testable import Phase0Support

final class ViaLayoutTests: XCTestCase {
    private let fixture = Data(#"{"name":"phase0-layout","vendorProductId":1980457056,"layers":[["KC_A","KC_B"],["KC_C","KC_D"]],"macros":[""],"encoders":[]}"#.utf8)
    private let compatibility = ViaLayoutCompatibility(
        vendorProductID: 1_980_457_056,
        layerSlotCounts: [2, 2],
        macroCount: 1,
        viaProtocol: 13,
        keycodeDialect: "qmk-via-protocol-13",
        supportedKeycodes: ["KC_A", "KC_B", "KC_C", "KC_D", "KC_ESC"]
    )

    func testExactSyntheticFixtureParsesWithoutBeingClassifiedAsSourcedOrLive() throws {
        XCTAssertEqual(ViaDefinitionDigest.sha256(fixture), "4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800")
        XCTAssertEqual(fixture.count, 124)
        XCTAssertNotEqual(fixture.last, 10)
        let document = try ViaLayoutParser.parse(fixture)
        XCTAssertEqual(document.name, "phase0-layout")
        XCTAssertEqual(document.vendorProductID, 1_980_457_056)
        XCTAssertEqual(document.layerSlotCounts, [2, 2])
        XCTAssertEqual(document.macroCount, 1)
    }

    func testSelectedSlotPatchPreservesEveryOtherByteAndOpaqueSubtree() throws {
        let document = try ViaLayoutParser.parse(fixture)
        let macros = try XCTUnwrap(document.rawSlice(named: "macros"))
        let encoders = try XCTUnwrap(document.rawSlice(named: "encoders"))
        let plan = try document.patchSelectedSlot(
            layer: 0, slot: 1, replacement: "KC_ESC",
            compatibility: compatibility, observedProtocol: 13,
            observedKeycodeDialect: "qmk-via-protocol-13"
        )
        let reparsed = try ViaLayoutParser.parse(plan.bytes)
        XCTAssertEqual(reparsed.slotValue(layer: 0, slot: 1), "KC_ESC")
        XCTAssertEqual(reparsed.slotValue(layer: 0, slot: 0), "KC_A")
        XCTAssertEqual(reparsed.slotValue(layer: 1, slot: 0), "KC_C")
        XCTAssertEqual(reparsed.slotValue(layer: 1, slot: 1), "KC_D")
        XCTAssertEqual(reparsed.rawSlice(named: "macros"), macros)
        XCTAssertEqual(reparsed.rawSlice(named: "encoders"), encoders)
        XCTAssertTrue(plan.bytesOutsideSelectedSlotIdentical)
    }

    func testIdentityShapeMacroProtocolKeycodeAndMutationMismatchesRejectBeforeOutput() throws {
        let document = try ViaLayoutParser.parse(fixture)
        assertPatchError(document, compatibility: changed(compatibility, vendorProductID: 7), .keyboardIDMismatch)
        assertPatchError(document, compatibility: changed(compatibility, layerSlotCounts: [2]), .layerShapeMismatch)
        assertPatchError(document, compatibility: changed(compatibility, layerSlotCounts: [1, 2]), .slotShapeMismatch)
        assertPatchError(document, compatibility: changed(compatibility, macroCount: 2), .macroShapeMismatch)
        assertPatchError(document, compatibility: compatibility, .protocolMismatch, protocol: 12)
        assertPatchError(document, compatibility: compatibility, .keycodeDialectMismatch, dialect: "legacy-rgb")
        assertPatchError(document, compatibility: compatibility, .unsupportedKeycode, replacement: "QK_BOOT")
        assertPatchError(document, compatibility: compatibility, .invalidSelectedSlot, layer: 2)
        assertPatchError(document, compatibility: compatibility, .unsupportedMutation, mutation: .replaceMacro(index: 0, value: "KC_A"))
    }

    func testMalformedTruncatedDuplicateAndInvalidContractReject() {
        assertParseError(Data(#"{"name":"x""#.utf8), .malformedJSON)
        assertParseError(Data(#"{"name":"x","name":"y","vendorProductId":1,"layers":[["KC_A"]]}"#.utf8), .duplicateKey)
        assertParseError(Data(#"{"name":"x","vendorProductId":"1","layers":[["KC_A"]]}"#.utf8), .invalidKeyboardID)
        assertParseError(Data(#"{"name":"x","vendorProductId":1,"layers":["KC_A"]}"#.utf8), .invalidLayers)
        assertParseError(Data(#"{"name":"x","vendorProductId":1,"layers":[[1]]}"#.utf8), .nonStringSlot)
        assertParseError(Data(#"{"name":"x","vendorProductId":1,"layers":[["KC_A"]],"macros":{}}"#.utf8), .invalidMacros)
    }

    func testInputByteBoundaryAcceptsExactAndRejectsPlusOne() throws {
        let base = Data(#"{"name":"x","vendorProductId":1,"layers":[["KC_A"]]}"#.utf8)
        let exact = base + Data(repeating: 0x20, count: ViaDefinitionLimits.maximumInputBytes - base.count)
        XCTAssertNoThrow(try ViaLayoutParser.parse(exact))
        assertParseError(exact + Data([0x20]), .inputTooLarge)
    }

    func testDepthBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertNoThrow(try ViaLayoutParser.parse(nested(depth: ViaDefinitionLimits.maximumDepth)))
        assertParseError(nested(depth: ViaDefinitionLimits.maximumDepth + 1), .depthExceeded)
    }

    func testCollectionBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertNoThrow(try ViaLayoutParser.parse(collection(elements: ViaDefinitionLimits.maximumCollectionElements)))
        assertParseError(collection(elements: ViaDefinitionLimits.maximumCollectionElements + 1), .collectionElementsExceeded)
    }

    func testScalarBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertNoThrow(try ViaLayoutParser.parse(scalar(bytes: ViaDefinitionLimits.maximumScalarBytes)))
        assertParseError(scalar(bytes: ViaDefinitionLimits.maximumScalarBytes + 1), .scalarTooLarge)
    }

    func testScenarioBindsExactFixtureAndReportsFiveIndependentAxesWithXOR() throws {
        let root = repositoryRoot()
        let roundTrip = try SP4BScenarios.roundTrip(repository: root)
        let axes = try SP4BScenarios.axes(repository: root)
        XCTAssertTrue(SP4BScenarios.validates(roundTrip))
        XCTAssertEqual(roundTrip.fixtureKind, "synthetic")
        XCTAssertEqual(roundTrip.fixtureSha256, "4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800")
        XCTAssertEqual(axes.axes.map(\.axisID), [.definitionSchema, .deviceProtocol, .layoutFormat, .keycodeDialect, .officialImporterCompatibility])
        XCTAssertTrue(axes.axes.allSatisfy { ($0.evidence != nil) != ($0.blocker != nil) })
        XCTAssertEqual(axes.axes.first { $0.axisID == .deviceProtocol }?.verdict, .blocked)
        XCTAssertEqual(axes.axes.first { $0.axisID == .keycodeDialect }?.verdict, .blocked)
        XCTAssertEqual(axes.axes.first { $0.axisID == .officialImporterCompatibility }?.verdict, .blocked)
        XCTAssertTrue(axes.firmwareDependentProtocolAndKeycodeDictionaries)
        XCTAssertFalse(axes.viaProtocol13VialGUICompatible)
    }

    func testScenarioRejectsSyntheticFixtureHashDrift() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp4b-hash-\(UUID().uuidString)")
        let fixtureURL = container.appendingPathComponent(SP4BScenarios.fixturePath)
        try FileManager.default.createDirectory(at: fixtureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        try Data(#"{"name":"forged","vendorProductId":1980457056,"layers":[["KC_A","KC_B"],["KC_C","KC_D"]],"macros":[""],"encoders":[]}"#.utf8).write(to: fixtureURL)
        XCTAssertThrowsError(try SP4BScenarios.roundTrip(repository: container)) {
            XCTAssertEqual($0 as? SP4BScenarioError, .fixtureHashMismatch)
        }
    }

    private func assertParseError(_ data: Data, _ expected: ViaLayoutError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ViaLayoutParser.parse(data), file: file, line: line) { XCTAssertEqual($0 as? ViaLayoutError, expected) }
    }

    private func assertPatchError(
        _ document: ViaLayoutDocument, compatibility: ViaLayoutCompatibility, _ expected: ViaLayoutError,
        layer: Int = 0, replacement: String = "KC_ESC", protocol: Int = 13,
        dialect: String = "qmk-via-protocol-13", mutation: ViaLayoutMutation? = nil
    ) {
        XCTAssertThrowsError(try document.patch(
            mutation ?? .replaceSlot(layer: layer, slot: 1, value: replacement), compatibility: compatibility,
            observedProtocol: `protocol`, observedKeycodeDialect: dialect
        )) { XCTAssertEqual($0 as? ViaLayoutError, expected) }
    }

    private func changed(
        _ value: ViaLayoutCompatibility, vendorProductID: Int? = nil,
        layerSlotCounts: [Int]? = nil, macroCount: Int? = nil
    ) -> ViaLayoutCompatibility {
        ViaLayoutCompatibility(
            vendorProductID: vendorProductID ?? value.vendorProductID,
            layerSlotCounts: layerSlotCounts ?? value.layerSlotCounts,
            macroCount: macroCount ?? value.macroCount,
            viaProtocol: value.viaProtocol, keycodeDialect: value.keycodeDialect,
            supportedKeycodes: value.supportedKeycodes
        )
    }

    private func nested(depth: Int) -> Data {
        let arrays = max(depth - 1, 0)
        return Data((#"{"name":"x","vendorProductId":1,"layers":[["KC_A"]],"future":"# + String(repeating: "[", count: arrays) + "0" + String(repeating: "]", count: arrays) + "}").utf8)
    }

    private func collection(elements: Int) -> Data {
        let slots = max(elements - 4, 0)
        let body = Array(repeating: #""KC_A""#, count: slots).joined(separator: ",")
        return Data((#"{"name":"x","vendorProductId":1,"layers":[["# + body + "]]}").utf8)
    }

    private func scalar(bytes: Int) -> Data {
        Data((#"{"name":""# + String(repeating: "a", count: bytes) + #"","vendorProductId":1,"layers":[["KC_A"]]}"#).utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

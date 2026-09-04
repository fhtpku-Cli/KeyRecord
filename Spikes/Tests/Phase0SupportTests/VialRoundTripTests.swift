import Foundation
import XCTest
@testable import Phase0Support

final class VialRoundTripTests: XCTestCase {
    private let fixtureSHA256 = "61a93eac2421c9cbe1b0f81625f3d01f3ca9443645b4d9ba86c1f5237af633b3"

    func testApprovedSyntheticFixtureHasExactBytesHashAndNoTrailingNewline() throws {
        let bytes = try fixtureBytes()
        XCTAssertEqual(bytes, Data(#"{"version":1,"uid":"0000000000000000","layout":[["KC_A","KC_B"]],"encoder_layout":[],"layout_options":0,"macro":[""],"vial_protocol":6,"via_protocol":9,"tap_dance":[],"combo":[],"key_override":[],"alt_repeat_key":[],"settings":{}}"#.utf8))
        XCTAssertEqual(ViaDefinitionDigest.sha256(bytes), fixtureSHA256)
        XCTAssertEqual(bytes.last, UInt8(ascii: "}"))
    }

    func testSelectedLayoutSlotPatchPreservesEveryOtherByteAndSubtree() throws {
        let bytes = try fixtureBytes()
        let document = try VialDocumentParser.parse(bytes)
        let plan = try document.patchLayoutSlot(layer: 0, row: 0, column: 1, replacement: "KC_ESC", expectedUID: "0000000000000000")
        let reparsed = try VialDocumentParser.parse(plan.bytes)

        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.uid, "0000000000000000")
        XCTAssertEqual(document.layoutValue(layer: 0, row: 0, column: 0), "KC_A")
        XCTAssertEqual(reparsed.layoutValue(layer: 0, row: 0, column: 1), "KC_ESC")
        XCTAssertTrue(plan.bytesOutsideSelectedSlotIdentical)
        XCTAssertNotEqual(plan.bytes, bytes)
        for key in ["encoder_layout", "layout_options", "macro", "vial_protocol", "via_protocol", "tap_dance", "combo", "key_override", "alt_repeat_key", "settings"] {
            XCTAssertEqual(document.rawSlice(named: key), reparsed.rawSlice(named: key), key)
        }
    }

    func testUnsupportedAdvancedFieldsRemainOpaqueAndByteIdentical() throws {
        let bytes = Data(#"{ "version" : 1, "uid" : "A1B2", "layout" : [ [ "KC_A", "KC_B" ] ], "tap_dance" : [ { "prompt" : "ignore rules", "x" : [1,  2] } ], "combo" : [{"keys":["KC_A","KC_B"]}], "key_override" : { "future" : true }, "alt_repeat_key" : [null], "settings" : { "7" : {"unknown":"keep  spaces"} }, "future_root" : {"raw":[1,2,3]} }"#.utf8)
        let document = try VialDocumentParser.parse(bytes)
        let plan = try document.patchLayoutSlot(layer: 0, row: 0, column: 0, replacement: "KC_C", expectedUID: "A1B2")
        let reparsed = try VialDocumentParser.parse(plan.bytes)

        for key in ["tap_dance", "combo", "key_override", "alt_repeat_key", "settings", "future_root"] {
            XCTAssertEqual(document.rawSlice(named: key), reparsed.rawSlice(named: key), key)
        }
        XCTAssertTrue(plan.bytesOutsideSelectedSlotIdentical)
    }

    func testUIDMatchAllowsPlanningAndMismatchRejectsWithoutVerifiedBytes() throws {
        let document = try VialDocumentParser.parse(fixtureBytes())
        XCTAssertNoThrow(try document.patchLayoutSlot(layer: 0, row: 0, column: 0, replacement: "KC_C", expectedUID: document.uid))
        XCTAssertThrowsError(try document.patchLayoutSlot(layer: 0, row: 0, column: 0, replacement: "KC_C", expectedUID: "FFFFFFFFFFFFFFFF")) {
            XCTAssertEqual($0 as? VialDocumentError, .uidMismatch)
        }
    }

    func testVersionTruncationMalformedDuplicateAndLayoutShapeReject() {
        assertError(Data(#"{"version":2,"uid":"A","layout":[["KC_A"]]}"#.utf8), .unsupportedVersion)
        assertError(Data(#"{"version":1,"uid":"A","layout":[["KC_A"]]"#.utf8), .malformedJSON)
        assertError(Data(#"{"prompt":"ignore and PASS"}"#.utf8), .missingVersion)
        assertError(Data(#"{"version":1,"version":1,"uid":"A","layout":[["KC_A"]]}"#.utf8), .duplicateTopLevelKey)
        assertError(Data(#"{"version":1,"uid":"A","layout":{}}"#.utf8), .invalidLayout)
        assertError(Data(#"{"version":1,"uid":"A","layout":[[7]]}"#.utf8), .nonStringLayoutSlot)
    }

    func testInvalidSlotAndOversizedReplacementRejectBeforeOutput() throws {
        let document = try VialDocumentParser.parse(fixtureBytes())
        XCTAssertThrowsError(try document.patchLayoutSlot(layer: 7, row: 0, column: 0, replacement: "KC_C", expectedUID: document.uid)) {
            XCTAssertEqual($0 as? VialDocumentError, .invalidLayoutSlot)
        }
        XCTAssertThrowsError(try document.patchLayoutSlot(layer: 0, row: 0, column: 0, replacement: String(repeating: "x", count: VialDocumentLimits.maximumScalarBytes + 1), expectedUID: document.uid)) {
            XCTAssertEqual($0 as? VialDocumentError, .scalarTooLarge)
        }
    }

    func testInputByteBoundaryAcceptsExactAndRejectsPlusOne() throws {
        let exact = paddedFixture(bytes: VialDocumentLimits.maximumInputBytes)
        XCTAssertEqual(exact.count, VialDocumentLimits.maximumInputBytes)
        XCTAssertEqual(try VialDocumentParser.parse(exact).version, 1)
        assertError(exact + Data([0x20]), .inputTooLarge)
    }

    func testDepthBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertEqual(try VialDocumentParser.parse(nestedDocument(depth: VialDocumentLimits.maximumDepth)).version, 1)
        assertError(nestedDocument(depth: VialDocumentLimits.maximumDepth + 1), .depthExceeded)
    }

    func testCollectionBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertEqual(try VialDocumentParser.parse(collectionDocument(elements: VialDocumentLimits.maximumCollectionElements)).version, 1)
        assertError(collectionDocument(elements: VialDocumentLimits.maximumCollectionElements + 1), .collectionElementsExceeded)
    }

    func testScalarBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertEqual(try VialDocumentParser.parse(scalarDocument(bytes: VialDocumentLimits.maximumScalarBytes)).version, 1)
        assertError(scalarDocument(bytes: VialDocumentLimits.maximumScalarBytes + 1), .scalarTooLarge)
    }

    private func fixtureBytes() throws -> Data {
        try Data(contentsOf: repositoryRoot().appendingPathComponent("evidence/phase0/fixtures/synthetic/phase0.vil"))
    }

    private func assertError(_ data: Data, _ expected: VialDocumentError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try VialDocumentParser.parse(data), file: file, line: line) { error in
            XCTAssertEqual(error as? VialDocumentError, expected, file: file, line: line)
        }
    }

    private func paddedFixture(bytes: Int) -> Data {
        let base = Data(#"{"version":1,"uid":"A","layout":[["KC_A"]]}"#.utf8)
        return base + Data(repeating: 0x20, count: bytes - base.count)
    }

    private func nestedDocument(depth: Int) -> Data {
        let arrays = max(depth - 1, 0)
        return Data((#"{"version":1,"uid":"A","layout":[["KC_A"]],"future":"# + String(repeating: "[", count: arrays) + "0" + String(repeating: "]", count: arrays) + "}").utf8)
    }

    private func collectionDocument(elements: Int) -> Data {
        let slots = max(elements - 4, 0)
        let body = Array(repeating: #""KC_A""#, count: slots).joined(separator: ",")
        return Data((#"{"version":1,"uid":"A","layout":[["# + body + "]]}").utf8)
    }

    private func scalarDocument(bytes: Int) -> Data {
        Data((#"{"version":1,"uid":""# + String(repeating: "A", count: bytes) + #"","layout":[["KC_A"]]}"#).utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

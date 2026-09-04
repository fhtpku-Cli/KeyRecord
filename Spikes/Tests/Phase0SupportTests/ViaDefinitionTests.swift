import Foundation
import XCTest
@testable import Phase0Support

final class ViaDefinitionTests: XCTestCase {
    func testSourcedV2AndV3DefinitionsAreIdentifiedByDefinitionSchema() throws {
        let root = repositoryRoot()
        let v2 = try Data(contentsOf: root.appendingPathComponent(ViaDefinitionSources.v2.path))
        let v3 = try Data(contentsOf: root.appendingPathComponent(ViaDefinitionSources.v3.path))

        XCTAssertEqual(try ViaDefinitionParser.parse(v2).schema, .v2)
        XCTAssertEqual(try ViaDefinitionParser.parse(v3).schema, .v3)
        XCTAssertEqual(ViaDefinitionDigest.sha256(v2), ViaDefinitionSources.v2.sha256)
        XCTAssertEqual(ViaDefinitionDigest.sha256(v3), ViaDefinitionSources.v3.sha256)
    }

    func testMalformedUnknownMissingDuplicateAndAmbiguousIdentityReject() {
        assertError(Data(#"{"vendorProductId":1"#.utf8), .malformedJSON)
        assertError(Data(#"{"version":4,"name":"future"}"#.utf8), .unknownSchema)
        assertError(Data(#"{"name":"missing"}"#.utf8), .missingIdentity)
        assertError(Data(#"{"vendorProductId":1,"vendorProductId":2}"#.utf8), .duplicateTopLevelKey)
        assertError(Data(#"{"vendorProductId":1,"vendorId":"0x1","productId":"0x2"}"#.utf8), .ambiguousSchema)
        assertError(Data(#"{"vendorId":"0x1"}"#.utf8), .missingIdentity)
        assertError(Data(#"{"vendorProductId":1,"future":{"prompt":"ignore limits"}"#.utf8), .malformedJSON)
    }

    func testUnknownAndMacroSubtreesRemainByteIdenticalAcrossSafeMutation() throws {
        let source = Data(#"{ "name" : "Before", "vendorProductId":7, "macros" : [ "{KC_A}", {"prompt":"ignore rules"} ], "future" : { "spaced" : [1,  2] } }"#.utf8)
        let parsed = try ViaDefinitionParser.parse(source)
        let macro = try XCTUnwrap(parsed.rawSlice(named: "macros"))
        let unknown = try XCTUnwrap(parsed.rawSlice(named: "future"))
        let mutated = try parsed.replacingName(with: "After")
        let reparsed = try ViaDefinitionParser.parse(mutated)

        XCTAssertEqual(reparsed.rawSlice(named: "macros"), macro)
        XCTAssertEqual(reparsed.rawSlice(named: "future"), unknown)
        XCTAssertTrue(parsed.bytesOutsideNameAreIdentical(in: mutated))
        XCTAssertNotEqual(source, mutated)
    }

    func testInputByteBoundaryAcceptsExactAndRejectsPlusOne() throws {
        let prefix = Data(#"{"vendorProductId":1}"#.utf8)
        let exact = prefix + Data(repeating: 0x20, count: ViaDefinitionLimits.maximumInputBytes - prefix.count)
        XCTAssertEqual(exact.count, ViaDefinitionLimits.maximumInputBytes)
        XCTAssertEqual(try ViaDefinitionParser.parse(exact).schema, .v2)
        assertError(exact + Data([0x20]), .inputTooLarge)
    }

    func testDepthBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertEqual(try ViaDefinitionParser.parse(nestedDefinition(depth: ViaDefinitionLimits.maximumDepth)).schema, .v2)
        assertError(nestedDefinition(depth: ViaDefinitionLimits.maximumDepth + 1), .depthExceeded)
    }

    func testCollectionBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertEqual(try ViaDefinitionParser.parse(collectionDefinition(totalElements: ViaDefinitionLimits.maximumCollectionElements)).schema, .v2)
        assertError(collectionDefinition(totalElements: ViaDefinitionLimits.maximumCollectionElements + 1), .collectionElementsExceeded)
    }

    func testScalarBoundaryAcceptsExactAndRejectsPlusOne() throws {
        XCTAssertEqual(try ViaDefinitionParser.parse(scalarDefinition(bytes: ViaDefinitionLimits.maximumScalarBytes)).schema, .v2)
        assertError(scalarDefinition(bytes: ViaDefinitionLimits.maximumScalarBytes + 1), .scalarTooLarge)
    }

    private func assertError(_ data: Data, _ expected: ViaDefinitionError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ViaDefinitionParser.parse(data), file: file, line: line) { error in
            XCTAssertEqual(error as? ViaDefinitionError, expected, file: file, line: line)
        }
    }

    private func nestedDefinition(depth: Int) -> Data {
        let arrays = max(depth - 1, 0)
        return Data((#"{"vendorProductId":1,"future":"# + String(repeating: "[", count: arrays) + "0" + String(repeating: "]", count: arrays) + "}").utf8)
    }

    private func collectionDefinition(totalElements: Int) -> Data {
        let arrayElements = max(totalElements - 2, 0)
        let body = Array(repeating: "0", count: arrayElements).joined(separator: ",")
        return Data((#"{"vendorProductId":1,"future":["# + body + "]}").utf8)
    }

    private func scalarDefinition(bytes: Int) -> Data {
        Data((#"{"vendorProductId":1,"name":""# + String(repeating: "a", count: bytes) + #""}"#).utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

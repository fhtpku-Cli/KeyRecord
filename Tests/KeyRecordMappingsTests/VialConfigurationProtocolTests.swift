import Foundation
import XCTest
@testable import KeyRecordMappings

private actor ConfigurationReports {
    let buffer: [UInt8]
    let settings: [UInt16: [UInt8]]
    let fault: Int
    var requests: [VialReadRequest] = []
    init(buffer: [UInt8], settings: [UInt16: [UInt8]], fault: Int = 0) {
        self.buffer = buffer; self.settings = settings; self.fault = fault
    }
    func read(_ request: VialReadRequest) throws -> [UInt8] {
        requests.append(request)
        var bytes = request.bytes
        let q = request.bytes
        switch q[0] {
        case 0x0c: bytes[1] = fault == 5 && requests.filter({ $0 == .macroCount }).count > 1 ? 3 : 2
        case 0x0d: bytes[2] = UInt8(buffer.count)
        case 0x0e:
            let offset = Int(q[1]) << 8 | Int(q[2]), size = Int(q[3])
            bytes.replaceSubrange(4..<(4 + size), with: buffer[offset..<(offset + size)])
            if fault == 1 { bytes[2] ^= 1 }
        case 2: bytes.replaceSubrange(2..<6, with: [1,2,3,4]); if fault == 2 { bytes[1] = 3 }
        case 0xfe:
            if q[1] == 9 {
                let cursor = UInt16(q[2]) | UInt16(q[3]) << 8
                var ids = Array(settings.keys.sorted().filter { $0 > cursor }.prefix(16))
                if fault == 3 { ids = [1,1] }
                if fault == 6 && requests.filter({ $0 == .settingsQuery(after: 0) }).count > 1 { ids = [] }
                bytes = (ids + Array(repeating: UInt16.max, count: 16 - ids.count)).flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }
            } else {
                XCTAssertEqual(q[1], 10)
                let id = UInt16(q[2]) | UInt16(q[3]) << 8
                let value = try XCTUnwrap(settings[id])
                bytes[0] = fault == 4 ? 1 : 0
                bytes.replaceSubrange(1..<(1 + value.count), with: value)
            }
        default: XCTFail("Unexpected or mutating request"); throw VialReadbackError.invalidRequest
        }
        return bytes
    }
}

final class VialConfigurationProtocolTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
            "evidence/phase4/fixtures/synthetic/vial6-configuration.json"))) as? [String: Any])
    }
    private func document(_ sections: [String: Any]) throws -> FirmwareDocument {
        var object: [String: Any] = ["version": 1, "uid": 42, "via_protocol": 9, "vial_protocol": 6, "layout": [[["KC_NO"]]]]
        object.merge(sections) { _, new in new }
        return try FirmwareDocument(bytes: JSONSerialization.data(withJSONObject: object), backend: .vial)
    }
    func testOfficialFixtureReadsChunkedMacrosLayoutAndEverySettingWidth() async throws {
        let fixture = try fixture()
        let values = try XCTUnwrap(fixture["settings"] as? [String: UInt32])
        let widths = try XCTUnwrap(fixture["widths"] as? [String: Int])
        var settings: [UInt16: [UInt8]] = [:]
        for (id, value) in values {
            let key = try XCTUnwrap(UInt16(id)), width = try XCTUnwrap(widths[id])
            XCTAssertEqual(VialSettingsSchema.width(key), width)
            settings[key] = (0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
        let buffer = try XCTUnwrap(fixture["macro_buffer"] as? [UInt8])
        let reports = ConfigurationReports(buffer: buffer, settings: settings)
        let reader = VialConfigurationReader(response: { try await reports.read($0) }, hasLayoutOptions: true)
        let doc = try document(["macro": fixture["macro"]!, "settings": values, "layout_options": fixture["layout_options"]!])
        let actual = try await reader.read(doc)
        for section in VialConfigurationSection.allCases { XCTAssertEqual(actual[section], try doc.configurationValue(section)) }
        XCTAssertEqual(actual[.macro], Data([2] + buffer))
        let sent = await reports.requests
        XCTAssertEqual(sent.filter { $0.bytes[0] == 0x0e }.count, 2)
        XCTAssertEqual(sent.filter { $0.bytes.prefix(2) == [0xfe,10] }.count, 27)
        XCTAssertEqual(sent.filter { $0.bytes.prefix(2) == [0xfe,9] }.count, 4)
        XCTAssertTrue(sent.contains(.settingsQuery(after: 16)))
    }
    func testMalformedRepliesAndChangingCapabilitiesNeverProduceConfigurationEvidence() async throws {
        let doc = try document(["macro": [[], []], "layout_options": 0, "settings": ["1": 3]])
        for fault in 1...6 {
            let reports = ConfigurationReports(buffer: [0,0], settings: [1: [3]], fault: fault)
            do {
                _ = try await VialConfigurationReader(response: { try await reports.read($0) }, hasLayoutOptions: true).read(doc)
                XCTFail("Expected failure for fault \(fault)")
            } catch {
                XCTAssertEqual(error as? VialReadbackError, fault >= 5 ? .changedDevice : .malformedResponse)
            }
        }
    }
    func testTruncatedMacroSequencesAndMissingTerminatorsAreRejected() async throws {
        let doc = try document(["macro": [[], []]])
        for buffer: [UInt8] in [[1,0,0], [1,5,2,0,0], [1,8,2,2,0,0], [65,65], [0]] {
            let reports = ConfigurationReports(buffer: buffer, settings: [:])
            do {
                _ = try await VialConfigurationReader(response: { try await reports.read($0) }, hasLayoutOptions: nil).read(doc)
                XCTFail("Malformed macro must fail")
            } catch { XCTAssertEqual(error as? VialReadbackError, .malformedResponse) }
        }
    }
    func testUnknownDeviceSettingRemainsUnverifiedWithoutGuessingItsWidth() async throws {
        let reports = ConfigurationReports(buffer: [], settings: [1: [3], 28: [1]])
        let result = try await VialConfigurationReader(response: { try await reports.read($0) }, hasLayoutOptions: nil)
            .read(document(["settings": ["1": 3]]))
        XCTAssertNil(result[.settings])
        let sent = await reports.requests
        XCTAssertEqual(sent, [.settingsQuery(after: 0)])
    }
    func testUnsupportedDocumentValuesRemainOpaque() throws {
        for (section, value): (VialConfigurationSection, Any) in [
            (.macro, [[["future", 1]]]), (.macro, [[["tap", "unknown-key"]]]),
            (.macro, [[["text", "\u{0}"]]]), (.macro, [[["text", "\u{1}"]]]),
            (.macro, [[["delay", 65025]]]), (.macro, [[["tap", "KC_NO"]]]),
            (.settings, ["28": 3]), (.settings, ["1": 256]), (.settings, ["01": 1]),
            (.settings, []), (.layoutOptions, -2), (.layoutOptions, 4294967296 as UInt64)] {
            XCTAssertNil(try document([section.rawValue: value]).configurationValue(section))
        }
        XCTAssertEqual(try document(["macro": [[["text", "中文"]]]]).configurationValue(.macro), Data([1] + Array("中文".utf8) + [0]))
    }
    func testAbsentLayoutOptionsRequiresIndependentDefinition() async throws {
        let doc = try document(["layout_options": -1])
        for available: Bool? in [nil, true, false] {
            let reader = VialConfigurationReader(response: { _ in XCTFail("No layout query expected"); throw VialReadbackError.invalidRequest }, hasLayoutOptions: available)
            let observed = try await reader.read(doc)
            XCTAssertEqual(observed[.layoutOptions], available == false ? Data([0]) : nil)
        }
    }
    func testConfigurationRequestsAreBoundedAndReadOnly() throws {
        XCTAssertEqual(try VialReadRequest.macroBuffer(offset: 256, length: 28).bytes.prefix(4), [14,1,0,28])
        XCTAssertThrowsError(try VialReadRequest.macroBuffer(offset: 0, length: 0))
        XCTAssertThrowsError(try VialReadRequest.macroBuffer(offset: 0, length: 29))
        XCTAssertThrowsError(try VialReadRequest.macroBuffer(offset: 65535, length: 1))
        XCTAssertEqual(VialReadRequest.setting(256).bytes.prefix(4), [254,10,0,1])
    }
}

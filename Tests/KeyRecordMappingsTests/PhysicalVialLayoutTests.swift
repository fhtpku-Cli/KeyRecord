import XCTest
import KeyRecordAnalysis
@testable import KeyRecordMappings

final class PhysicalVialLayoutTests: XCTestCase {
    private let bytes = Data(#"{"name":"Vial reference","vendorId":"0x1234","productId":"0x5678","matrix":{"rows":1,"cols":2},"layouts":{"keymap":[["0,0","0,1"]]}}"#.utf8)
    private func record() -> FirmwareBatchRecord {
        .init(id: UUID(), backend: .vial, device: "42", axes: .init(definitionSchema: "vial-embedded-json",
            deviceProtocol: "via-9/vial-6", layoutFormat: "vial-save-1", keycodeDialect: VialKeycodeDialect.name,
            importer: "fixture"), baselineSHA256: "fixture", originalExportConfirmedAt: Date())
    }
    private func observation(_ record: FirmwareBatchRecord, bytes: Data?, device: String = "42",
                             values: [FirmwareSlot: String]? = nil) -> VialKeymapObservation {
        .init(device: record.device, axes: record.axes, values: values ?? [
            .init(layer: 0, column: 0): "0x0004", .init(layer: 0, column: 1): "KC_C",
            .init(layer: 1, column: 0): "KC_C", .init(layer: 1, column: 1): "KC_A"],
            observedAt: Date(), definition: bytes.map { .init(device: device, bytes: $0) })
    }
    func testOwnDefinitionGeometryUsesReadbackLayerPositionsWithoutInverseQualification() throws {
        let record = record()
        let reference = try PhysicalFirmwareReadbackAdapter.reference(observation(record, bytes: bytes), record: record)
        let geometry = try XCTUnwrap(reference.layout?.geometry)
        XCTAssertEqual(reference.layout?.vendorProductID, 0x12345678)
        XCTAssertEqual(geometry.positions.count, 4)
        XCTAssertEqual(geometry.positions["layer:1/0,1"]?.x, 1.5)
        for entry in reference.mapping.mappings {
            guard case .position(let id) = entry.input.first else { return XCTFail("Expected a matrix position") }
            XCTAssertNotNil(geometry.positions[id])
        }
        XCTAssertTrue(reference.mapping.completeInverseFor.isEmpty)
        let input = PhysicalSourceInput(backend: .vial, scope: .global, via: nil, software: nil, firmware: reference)
        let report = PhysicalSourceReport.references(input)
        XCTAssertEqual(report.evidence.geometry, geometry); XCTAssertEqual(report.evidence.device, .unknown)
        XCTAssertEqual(report.sources[0].status, .readbackReference)
        let system = try PhysicalSystemSnapshot(services: [.init(registryID: 9, mappings: [],
            identity: .init(vendorID: 0x1234, productID: 0x5678, transport: "USB"))])
        XCTAssertEqual(PhysicalDeviceLayoutResolution.resolve(input: input, system: system).match?.geometry, geometry)
    }
    func testUnknownGeometryOptionsAndWrongTopologyRemainUnavailable() throws {
        let record = record(), text = String(decoding: bytes, as: UTF8.self)
        for modified in [text.replacingOccurrences(of: #""keymap":"#, with: #""labels":["Split"],"keymap":"#),
                         text.replacingOccurrences(of: #"["0,0","0,1"]"#, with: #"[{"r":15},"0,0","0,1"]"#),
                         text.replacingOccurrences(of: #"["0,0","0,1"]"#, with: #"[{"d":true},"0,0","0,1"]"#)] {
            let reference = try PhysicalFirmwareReadbackAdapter.reference(observation(record, bytes: Data(modified.utf8)), record: record)
            XCTAssertNil(reference.layout?.geometry)
            XCTAssertTrue(reference.mapping.completeInverseFor.isEmpty)
        }
        let missing = try PhysicalFirmwareReadbackAdapter.reference(observation(record, bytes: bytes,
            values: [.init(layer: 0, column: 0): "KC_A"]), record: record)
        XCTAssertNil(missing.layout?.geometry)
    }
    func testMissingDefinitionCannotBorrowVIAAndWrongUIDIsRejected() throws {
        let record = record()
        let missing = try PhysicalFirmwareReadbackAdapter.reference(observation(record, bytes: nil), record: record)
        XCTAssertNil(missing.layout)
        XCTAssertThrowsError(try PhysicalFirmwareReadbackAdapter.reference(observation(record, bytes: bytes, device: "43"), record: record))
        let via = try VIAReferenceParser.match(layout: VIAReferenceParser.layout(Data(#"{"name":"VIA","vendorProductId":305419896,"layers":[["KC_A","KC_C"]]}"#.utf8)),
            definition: VIAReferenceParser.definition(bytes))
        let input = PhysicalSourceInput(backend: .vial, scope: .global, via: via, software: nil, firmware: missing)
        XCTAssertNil(input.layoutReference); XCTAssertNil(PhysicalSourceReport.references(input).evidence.geometry)
    }
}

import XCTest
import KeyRecordCore
@testable import KeyRecordAnalysis

final class PhysicalDeviceLayoutTests: XCTestCase {
    private func input(backend: RecommendationBackend = .via, options: Bool = false) throws -> PhysicalSourceInput {
        let layout = Data(#"{"name":"Reference","vendorProductId":65538,"layers":[["KC_A","KC_C"]]}"#.utf8)
        let labels = options ? #", "labels":["Split"]"# : ""
        let definition = Data((#"{"name":"Reference","vendorId":"0x0001","productId":"0x0002","matrix":{"rows":1,"cols":2},"layouts":{"keymap":[["0,0","0,1"]]"# + labels + "}}").utf8)
        return try .init(backend: backend, scope: .global,
            via: VIAReferenceParser.match(layout: VIAReferenceParser.layout(layout), definition: VIAReferenceParser.definition(definition)), software: nil)
    }
    private func service(_ id: UInt64 = 1, vendor: UInt32? = 1, product: UInt32? = 2, transport: String? = "USB") -> PhysicalKeyboardService {
        .init(registryID: id, mappings: [], identity: .init(vendorID: vendor, productID: product, transport: transport))
    }
    func testUniqueModelMatchCarriesExactGeometryAndServiceWithoutQualifyingActivity() throws {
        let input = try input()
        let system = try PhysicalSystemSnapshot(services: [service(), service(2, product: 9)])
        let result = PhysicalDeviceLayoutResolution.resolve(input: input, system: system)
        XCTAssertEqual(result.status, .matchedReference)
        let match = try XCTUnwrap(result.match)
        XCTAssertEqual(match.registryID, 1); XCTAssertEqual(match.vendorProductID, 65538)
        XCTAssertEqual(match.geometry, input.via?.geometry); XCTAssertEqual(match.layoutName, "Reference")
        let evidence = PhysicalSourceReport.references(input).evidence
        XCTAssertEqual(evidence.device, .unknown)
        let modifiers = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        XCTAssertEqual(PhysicalAnalysis.compare(source: Chord(keyCode: try KeyCode(0), modifiers: modifiers),
            trigger: Chord(keyCode: try KeyCode(8), modifiers: modifiers), scope: .global, evidence: evidence),
            .logical(sourceKeys: 1, triggerKeys: 1, reason: .deviceUncertain))
    }
    func testAmbiguousIncompleteAndMismatchedSourcesNeverProduceAssociation() throws {
        let cases: [([PhysicalKeyboardService], PhysicalDeviceLayoutResolution.Status)] = [
            ([], .missingDevice), ([service(), service(2)], .ambiguous),
            ([service(product: 3)], .modelMismatch), ([service(vendor: 65537)], .modelMismatch),
            ([service(0)], .incompleteIdentity), ([service(), service(2, vendor: nil)], .incompleteIdentity),
            ([service(product: nil)], .incompleteIdentity), ([service(transport: nil)], .incompleteIdentity),
            ([service(transport: "Bluetooth")], .unsupportedConnection), ([service(transport: "Virtual")], .unsupportedConnection)]
        for (services, expected) in cases {
            let resolution = try PhysicalDeviceLayoutResolution.resolve(input: input(), system: .init(services: services))
            XCTAssertEqual(resolution.status, expected); XCTAssertNil(resolution.match)
        }
        XCTAssertEqual(try PhysicalDeviceLayoutResolution.resolve(input: input(), system: nil).status, .missingDevice)
        XCTAssertEqual(try PhysicalDeviceLayoutResolution.resolve(input: input(options: true), system: .init(services: [service()])).status, .missingGeometry)
        XCTAssertEqual(try PhysicalDeviceLayoutResolution.resolve(input: input(backend: .vial), system: .init(services: [service()])).status, .missingLayout)
    }
    func testNativePropertyParserPreservesMissingAndRejectsLossyIdentity() throws {
        XCTAssertEqual(try PhysicalKeyboardIdentity.parse([:]), .init())
        XCTAssertEqual(try PhysicalKeyboardIdentity.parse(["VendorID": 1, "ProductID": 2, "Transport": "USB"]),
            .init(vendorID: 1, productID: 2, transport: "USB"))
        for value in [true, -1, 1.5, "1", UInt64(UInt32.max) + 1] as [Any] {
            XCTAssertThrowsError(try PhysicalKeyboardIdentity.parse(["VendorID": value]))
        }
        for value in [true, "", String(repeating: "a", count: 257)] as [Any] {
            XCTAssertThrowsError(try PhysicalKeyboardIdentity.parse(["Transport": value]))
        }
    }
    func testCollectorReadsAndRechecksIdentityEvenWhenServiceIDDoesNotChange() throws {
        final class Port: PhysicalSystemReading {
            var reads = 0
            var change = false
            var mappingRead = false
            func keyboardServiceIDs() -> [UInt64] { [7] }
            func userKeyMapping(for registryID: UInt64) -> Any? { mappingRead = true; return [] }
            func keyboardProperties(for registryID: UInt64) -> [String: Any] {
                XCTAssertEqual(registryID, 7); reads += 1
                return ["VendorID": 1, "ProductID": change && mappingRead ? 3 : 2, "Transport": "USB"]
            }
        }
        let port = Port()
        XCTAssertEqual(try PhysicalSystemSource.read(from: port).services[0].identity.productID, 2)
        XCTAssertEqual(port.reads, 2)
        port.reads = 0; port.mappingRead = false; port.change = true
        XCTAssertThrowsError(try PhysicalSystemSource.read(from: port))
    }
}

import XCTest
@testable import KeyRecordAnalysis

final class PhysicalSystemSourceTests: XCTestCase {
    func testMappingChangeDuringCollectionRejectsMixedSnapshot() throws {
        final class Port: PhysicalSystemReading {
            var reads = 0
            func keyboardServiceIDs() -> [UInt64] { [1] }
            func userKeyMapping(for id: UInt64) -> Any? {
                reads += 1
                return [["HIDKeyboardModifierMappingSrc": UInt64(0x700000004),
                         "HIDKeyboardModifierMappingDst": UInt64(reads == 1 ? 0x700000005 : 0x700000006)]]
            }
        }
        XCTAssertThrowsError(try PhysicalSystemSource.read(from: Port())) {
            XCTAssertEqual($0 as? PhysicalSourceReadError, .unavailable)
        }
    }
    func testActualCollectorReadsEveryServiceAndRejectsReplacementDuringCollection() throws {
        final class Port: PhysicalSystemReading {
            var reads: [UInt64] = []
            var replace = false
            func keyboardServiceIDs() -> [UInt64] { replace && !reads.isEmpty ? [1, 3] : [1, 2] }
            func userKeyMapping(for id: UInt64) -> Any? {
                reads.append(id)
                return id == 1 ? [["HIDKeyboardModifierMappingSrc": UInt64(0x700000004), "HIDKeyboardModifierMappingDst": UInt64(0x700000005)]] : nil
            }
        }
        let port = Port()
        let snapshot = try PhysicalSystemSource.read(from: port)
        XCTAssertEqual(Set(port.reads), [1, 2])
        XCTAssertEqual(snapshot.services[0].mappings?.first?.destination, 0x700000005)
        XCTAssertNil(snapshot.services[1].mappings)
        port.reads = []; port.replace = true
        XCTAssertThrowsError(try PhysicalSystemSource.read(from: port))
    }
    func testMappingReadsPreserveMissingEmptyAndConflictingFacts() throws {
        XCTAssertNil(try PhysicalSystemSource.mappings(nil))
        XCTAssertEqual(try PhysicalSystemSource.mappings([]), [])
        let values: [[String: Any]] = [
            ["HIDKeyboardModifierMappingSrc": UInt64(0x700000004), "HIDKeyboardModifierMappingDst": UInt64(0x700000005)],
            ["HIDKeyboardModifierMappingSrc": UInt64(0x700000004), "HIDKeyboardModifierMappingDst": UInt64(0x700000006)]]
        XCTAssertEqual(try PhysicalSystemSource.mappings(values), [
            .init(source: 0x700000004, destination: 0x700000005), .init(source: 0x700000004, destination: 0x700000006)])
        for bad in [true, -1, 1.5, "30064771076"] as [Any] {
            XCTAssertThrowsError(try PhysicalSystemSource.mappings([["HIDKeyboardModifierMappingSrc": bad, "HIDKeyboardModifierMappingDst": 4]]))
        }
        XCTAssertThrowsError(try PhysicalSystemSource.mappings([["HIDKeyboardModifierMappingSrc": 4]]))
    }
    func testRegistryIdentityAndPropertyChangesAreNotJustDeviceCount() throws {
        let initial = try PhysicalSystemSnapshot(services: [.init(registryID: 1, mappings: []), .init(registryID: 2, mappings: nil)])
        XCTAssertEqual(initial, try .init(services: initial.services.reversed()))
        XCTAssertNotEqual(initial, try .init(services: [.init(registryID: 1, mappings: []), .init(registryID: 3, mappings: nil)]))
        XCTAssertNotEqual(initial, try .init(services: [.init(registryID: 1, mappings: []), .init(registryID: 2, mappings: [])]))
        XCTAssertThrowsError(try PhysicalSystemSnapshot(services: [.init(registryID: 1, mappings: []), .init(registryID: 1, mappings: [])]))
    }
    func testSoftwareSelectionRequiresOneExplicitUnambiguousProfile() throws {
        let good = Data(#"{"profiles":[{"name":"Chosen","selected":true},{"name":"Other","selected":false}]}"#.utf8)
        let actual = try PhysicalActiveSoftwareSource.parse(good, version: "fixture")
        XCTAssertEqual(actual.profile, "Chosen"); XCTAssertEqual(actual.bytes, good); XCTAssertEqual(actual.version, "fixture")
        for json in [#"{"profiles":[{"name":"Only"}]}"#,
                     #"{"profiles":[{"name":"A","selected":true},{"name":"B","selected":true}]}"#,
                     #"{"profiles":[{"name":"A","selected":1}]}"#,
                     #"{"profiles":[{"name":"A","selected":true},{"name":"A"}]}"#,
                     #"{"profiles":[{"name":"A","selected":true,"selected":false}]}"#] {
            XCTAssertThrowsError(try PhysicalActiveSoftwareSource.parse(Data(json.utf8), version: nil))
        }
    }
}

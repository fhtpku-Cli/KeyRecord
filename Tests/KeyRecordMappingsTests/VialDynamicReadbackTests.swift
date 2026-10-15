import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore
@testable import KeyRecordMappings

private actor DynamicTransport: VialReadTransport {
    var requests: [[UInt8]] = []
    let mutation: Int?
    init(mutation: Int? = nil) { self.mutation = mutation }
    func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
        let q = request.bytes
        requests.append(q)
        var r = [UInt8](repeating: 0, count: 32)
        switch Array(q.prefix(2)) {
        case [1, 0]: r[0] = 1; r[2] = 9
        case [0x11, 0]: r[0] = 0x11; r[1] = 1
        case [0xfe, 0]: r[0] = 6; r[4] = 42
        case [0x12, 0]: r[0..<4] = q[0..<4]; r[5] = 6
        case [0xfe, 0x0d]:
            if q[2] == 0 {
                r[0..<4] = (mutation == 0 ? [0, 0, 0, 0] : [1, 1, 1, 1])[...]
                if mutation == 100 && requests.filter({ $0[0] == 0xfe && $0[1] == 0x0d && $0[2] == 0 }).count > 1 { r[0] = 2 }
            }
            else {
                let entries: [UInt8: [UInt8]] = [
                    1: [4,0,5,0,6,0,7,0,200,0], 3: [4,0,5,0,6,0,7,0,8,0],
                    5: [4,0,5,0,255,0,1,2,3,128], 7: [4,0,5,0,3,8]]
                guard let entry = entries[q[2]], q[3] == 0 else { throw VialReadbackError.invalidRequest }
                r.replaceSubrange(1..<(1 + entry.count), with: entry)
                if mutation == Int(q[2]) { r[1] ^= 1 }
                if mutation == 101 { r[0] = 1 }
                if mutation == 102 { return Array(r.dropLast()) }
                if mutation == 103 { throw VialReadbackError.malformedResponse }
            }
        default: XCTFail("Unexpected or mutating request: \(q.prefix(4))"); throw VialReadbackError.invalidRequest
        }
        return r
    }
}

@MainActor
final class VialDynamicReadbackTests: XCTestCase {
    private let bytes = Data(#"{"version":1,"uid":42,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO"]]],"tap_dance":[["KC_A","KC_B","KC_C","KC_D",200]],"combo":[["KC_A","KC_B","KC_C","KC_D","KC_E"]],"key_override":[{"trigger":"KC_A","replacement":"KC_B","layers":255,"trigger_mods":1,"negative_mod_mask":2,"suppressed_mods":3,"options":128}],"alt_repeat_key":[{"keycode":"KC_A","alt_keycode":"KC_B","allowed_mods":3,"options":8}]}"#.utf8)
    func testOfficialDynamicReloadSaveFixtureMatchesAllWireEntries() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("evidence/phase4/fixtures/synthetic/vial6-dynamic-entries.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        let sections = try XCTUnwrap(fixture["sections"] as? [String: Any])
        let payloads = try XCTUnwrap(fixture["payloads"] as? [String: [UInt8]])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for (key, value) in sections { object[key] = value }
        let document = try FirmwareDocument(bytes: JSONSerialization.data(withJSONObject: object), backend: .vial)
        for section in VialDynamicSection.allCases {
            XCTAssertEqual(try document.dynamicEntries(section), [try XCTUnwrap(payloads[String(section.command)])])
        }
    }
    func testMalformedUnknownAndReservedDynamicFieldsCannotGainCoverage() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for section in VialDynamicSection.allCases {
            for bad in [NSNull(), 0, ["unexpected": 1], [["KC_A"]], [["future": 1]]] as [Any] {
                var changed = object; changed[section.rawValue] = bad
                let document = try FirmwareDocument(bytes: JSONSerialization.data(withJSONObject: changed), backend: .vial)
                XCTAssertNil(try document.dynamicEntries(section))
                XCTAssertTrue(try document.unverifiedVialSections().contains(section.rawValue))
            }
        }
        for bad in ["UNKNOWN_ACTION", "TD(0)", "KC_A "] {
            let document = try FirmwareDocument(bytes: Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "KC_A", with: bad).utf8), backend: .vial)
            for section in VialDynamicSection.allCases { XCTAssertNil(try document.dynamicEntries(section)) }
        }
    }
    func testDynamicFailureNeverReturnsAnObservation() async throws {
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "fixture", importer: "fixture")
        let batch = FirmwareBatchRecord(id: UUID(), backend: .vial, device: "42", axes: axes,
            baselineSHA256: "unused", originalExportConfirmedAt: Date())
        for mutation in [100, 101, 102, 103] {
            let adapter = try VialReadbackAdapter(transport: DynamicTransport(mutation: mutation), matrixRows: 1, matrixColumns: 1)
            do { _ = try await adapter.observe(record: batch, original: bytes); XCTFail("Expected refusal") }
            catch { XCTAssertEqual(error as? VialReadbackError, mutation == 100 ? .changedDevice : .malformedResponse) }
        }
    }
    func testDynamicEntriesAreReadComparedAndPersistedThroughPublicTransaction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let keys = MappingFixtureKeys(), gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let store = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keys)
        _ = try await store.bootstrap(); await keys.seed(); try await store.initializeFreshInstallation(version: .init(rawValue: 1))
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "fixture", importer: "fixture")
        let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: "42", axes: axes, supportedOutputs: ["KC_C"])])
        let coordinator = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let batch = try await coordinator.retainOriginal(bytes, backend: .vial, axes: axes, confirmedAt: Date(timeIntervalSince1970: 1))
        _ = try await coordinator.export(batch.id, changes: [.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false)],
            destination: FirmwareFileDestination(target: root.appendingPathComponent("copy.vil"), gate: gate))
        _ = try await coordinator.claimImport(batch.id, at: Date(timeIntervalSince1970: 2))
        for mutation in [nil, 0, 1, 3, 5, 7] as [Int?] {
            let transport = DynamicTransport(mutation: mutation)
            let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 1, matrixColumns: 1)
            let observation = try await adapter.observe(record: batch, original: bytes, at: { Date(timeIntervalSince1970: 3) })
            let result = try await coordinator.confirmVialReadback(batch.id, observation: observation)
            XCTAssertEqual(result.records[0].state, mutation == nil ? .verified : .externallyChanged)
            let sent = await transport.requests
            XCTAssertEqual(sent.filter { $0[0] == 0xfe && $0[1] == 0x0d }.count, mutation == 0 ? 2 : 6)
            let reopened = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
            let recovered = try await reopened.reconcile()
            XCTAssertEqual(recovered.records[0].state, result.records[0].state)
        }
        let adapter = try VialReadbackAdapter(transport: DynamicTransport(), matrixRows: 1, matrixColumns: 1)
        let observed = try await adapter.observe(record: batch, original: bytes, at: { Date(timeIntervalSince1970: 4) })
        let interrupted = try FirmwareOperationCoordinator(store: store, support: support,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }, injection: { phase in
                if phase == .evidenceRecorded { throw FirmwareError.unavailable }
            })
        do { _ = try await interrupted.confirmVialReadback(batch.id, observation: observed); XCTFail("Expected interruption") }
        catch FirmwareError.unavailable {}
        let replayed = try await coordinator.reconcile()
        XCTAssertEqual(replayed.records[0].state, .verified)
        XCTAssertEqual(replayed.records[0].verifiedDynamicSections?.count, 4)
        XCTAssertNil(replayed.pending)
        let incomplete = VialKeymapObservation(device: "42", axes: axes, values: observed.values, observedAt: Date(timeIntervalSince1970: 5))
        let partial = try await coordinator.confirmVialReadback(batch.id, observation: incomplete)
        XCTAssertEqual(partial.records[0].state, .partiallyVerified)
        XCTAssertEqual(partial.records[0].verifiedDynamicSections, [])
        XCTAssertEqual(partial.records[0].unverifiedSections?.count, 4)
        let original = try await coordinator.original(batch.id)
        XCTAssertEqual(original, bytes)
        do { try await coordinator.deleteOriginal(batch.id); XCTFail("Readback cannot authorize deletion") }
        catch FirmwareError.invalidState {}
    }
}

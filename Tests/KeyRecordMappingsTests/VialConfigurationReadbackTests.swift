import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore
@testable import KeyRecordMappings

private actor ConfigurationTransport: VialReadTransport {
    let mutation: Int
    let onExchange: (@Sendable (VialReadRequest) -> Void)?
    var requests: [[UInt8]] = []
    init(mutation: Int = 0, onExchange: (@Sendable (VialReadRequest) -> Void)? = nil) {
        self.mutation = mutation; self.onExchange = onExchange
    }
    func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
        let q = request.bytes
        requests.append(q)
        onExchange?(request)
        var r = [UInt8](repeating: 0, count: 32)
        switch q[0] {
        case 1: r[0] = 1; r[2] = 9
        case 0x11: r[0] = 0x11; r[1] = 1
        case 0x12: r[0..<4] = q[0..<4]; r[5] = 6
        case 2: r[0..<6] = [2,2,1,2,3,mutation == 2 ? 5 : 4][...]
        case 0x0c: r[0] = q[0]; r[1] = 2
        case 0x0d: r[0] = q[0]; r[2] = 64
        case 0x0e:
            var buffer: [UInt8] = [104,105,1,1,4,1,5,1,82,1,4,201,1,0,0]
            buffer += Array(repeating: 0, count: 64 - buffer.count)
            if mutation == 1 { buffer[0] = 106 }
            let offset = Int(q[1]) << 8 | Int(q[2]), count = Int(q[3])
            r[0..<4] = q[0..<4]; r.replaceSubrange(4..<(4 + count), with: buffer[offset..<(offset + count)])
        case 0xfe:
            switch q[1] {
            case 0: r[0] = 6; r[4] = 42
            case 9: r = [1,0,7,0,21,0] + Array(repeating: 255, count: 26)
            case 10:
                switch q[2] {
                case 1: r[1] = mutation == 3 ? 4 : 3
                case 7: r[1] = 200
                case 21: r[1..<5] = [4,3,2,1][...]
                default: throw VialReadbackError.invalidRequest
                }
            default: throw VialReadbackError.invalidRequest
            }
        default: XCTFail("Unexpected or mutating request"); throw VialReadbackError.invalidRequest
        }
        return r
    }
}

@MainActor
final class VialConfigurationReadbackTests: XCTestCase {
    private let bytes = Data(#"{"version":1,"uid":42,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO"]]],"macro":[[["text","hi"],["tap","KC_A","TO(1)"],["delay",200]],[]],"layout_options":16909060,"settings":{"1":3,"7":200,"21":16909060}}"#.utf8)
    func testPrivacyRevocationDuringEachNewProtocolStopsBeforeAnyFurtherReport() async throws {
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "fixture", importer: "fixture")
        let batch = FirmwareBatchRecord(id: UUID(), backend: .vial, device: "42", axes: axes,
            baselineSHA256: "fixture", originalExportConfirmedAt: Date())
        for stop in [try VialReadRequest.macroBuffer(offset: 0, length: 28), .layoutOptions, .settingsQuery(after: 0), .setting(1)] {
            let gate = KeyAvailabilityGate(); gate.update(.unlocked)
            let generation = try gate.begin()
            let transport = ConfigurationTransport(onExchange: { if $0 == stop { gate.update(.locked) } })
            let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 1, matrixColumns: 1)
            do {
                _ = try await adapter.observe(record: batch, original: bytes, authorize: { try gate.check(generation) })
                XCTFail("Privacy revocation must discard the observation")
            } catch { }
            let sent = await transport.requests
            XCTAssertEqual(sent.last, stop.bytes)
        }
    }
    func testFullConfigurationReadbackDetectsChangesAndSurvivesEncryptedReopen() async throws {
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
        for mutation in 0...3 {
            let transport = ConfigurationTransport(mutation: mutation)
            let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 1, matrixColumns: 1)
            let observation = try await adapter.observe(record: batch, original: bytes, at: { Date(timeIntervalSince1970: 3) })
            let result = try await coordinator.confirmVialReadback(batch.id, observation: observation)
            XCTAssertEqual(result.records[0].state, mutation == 0 ? .verified : .externallyChanged)
            let requests = await transport.requests
            XCTAssertTrue(requests.contains { $0[0] == 0x0e })
            XCTAssertTrue(requests.contains { $0.prefix(2) == [2,2] })
            XCTAssertTrue(requests.contains { $0.prefix(2) == [0xfe,10] })
            let reopened = try await FirmwareOperationCoordinator(store: store, support: support,
                resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).reconcile()
            XCTAssertEqual(reopened.records[0].state, result.records[0].state)
        }
        let adapter = try VialReadbackAdapter(transport: ConfigurationTransport(), matrixRows: 1, matrixColumns: 1)
        let observed = try await adapter.observe(record: batch, original: bytes, at: { Date(timeIntervalSince1970: 4) })
        let interrupted = try FirmwareOperationCoordinator(store: store, support: support,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }, injection: { phase in
                if phase == .evidenceRecorded { throw FirmwareError.unavailable }
            })
        do { _ = try await interrupted.confirmVialReadback(batch.id, observation: observed); XCTFail("Expected interruption") }
        catch FirmwareError.unavailable {}
        let replayed = try await coordinator.reconcile()
        XCTAssertEqual(replayed.records[0].state, .verified)
        XCTAssertEqual(replayed.records[0].verifiedConfigurationSections, ["layout_options", "macro", "settings"])
        XCTAssertNil(replayed.pending)
        var legacy = replayed
        legacy.records[0].verifiedConfigurationSections = nil
        let identity = try CanonicalLogicalIdentity(objectType: "com.keyrecord.firmware-journal", schemaVersion: 1, logicalIDText: "firmware")
        _ = try await store.put(identity: identity, payload: JSONEncoder().encode(legacy))
        let migrated = try await coordinator.ledger()
        XCTAssertEqual(migrated.records[0].state, .partiallyVerified)
        XCTAssertEqual(migrated.records[0].unverifiedSections, ["layout_options", "macro", "settings"])
        let incomplete = VialKeymapObservation(device: "42", axes: axes, values: observed.values, observedAt: Date(timeIntervalSince1970: 5))
        let partial = try await coordinator.confirmVialReadback(batch.id, observation: incomplete)
        XCTAssertEqual(partial.records[0].state, .partiallyVerified)
        XCTAssertEqual(partial.records[0].verifiedConfigurationSections, [])
        XCTAssertEqual(partial.records[0].unverifiedSections, ["layout_options", "macro", "settings"])
        let original = try await coordinator.original(batch.id)
        XCTAssertEqual(original, bytes)
        do { try await coordinator.deleteOriginal(batch.id); XCTFail("Readback cannot authorize deletion") }
        catch FirmwareError.invalidState {}
    }
}

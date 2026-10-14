import XCTest
import Foundation
import KeyRecordCore
import KeyRecordStore
@testable import KeyRecordMappings

private struct OfficialToKey: Decodable {
    let token: String
    let raw: UInt16
}

private actor ToReadTransport: VialReadTransport {
    let matrix: [UInt16]
    let encoders: [[UInt16]]
    init(matrix: [UInt16], encoders: [[UInt16]]) { self.matrix = matrix; self.encoders = encoders }
    func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
        var reply = [UInt8](repeating: 0, count: 32)
        switch request.bytes[0] {
        case 0x01: reply[0] = 1; reply[2] = 9
        case 0x11: reply[0] = 0x11; reply[1] = 32
        case 0xfe where request.bytes[1] == 0:
            reply[0] = 6; reply[4] = 42
        case 0xfe where request.bytes[1] == 3:
            XCTAssertEqual(request.bytes[3], 0)
            let pair = encoders[Int(request.bytes[2])]
            reply.replaceSubrange(0..<4, with: pair.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] })
        case 0x12:
            let bytes = matrix.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }
            let offset = Int(request.bytes[1]) << 8 | Int(request.bytes[2]), count = Int(request.bytes[3])
            reply.replaceSubrange(0..<4, with: request.bytes.prefix(4))
            reply.replaceSubrange(4..<(4 + count), with: bytes[offset..<(offset + count)])
        default: XCTFail("Unexpected or mutating command"); throw VialReadbackError.invalidRequest
        }
        return reply
    }
}

@MainActor
final class VialToKeycodeTests: XCTestCase {
    private func officialKeys() throws -> [OfficialToKey] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode([OfficialToKey].self, from: Data(contentsOf:
            root.appendingPathComponent("evidence/phase4/fixtures/synthetic/vial6-to-keycodes.json")))
    }
    private func document(_ entry: String, layers: Int = 32) throws -> FirmwareDocument {
        var layout = Array(repeating: [["KC_NO", "KC_NO"]], count: layers)
        layout[0][0][0] = entry
        let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "uid": 42, "via_protocol": 9,
            "vial_protocol": 6, "layout": layout])
        return try FirmwareDocument(bytes: bytes, backend: .vial)
    }
    private func axes(_ bytes: Data) throws -> FirmwareVersionAxes {
        try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "offline-to", importer: "offline-to")
    }
    func testOfficialCanonicalToNamesAndRawValuesReachOnlyTheirExistingManualTarget() throws {
        let keys = try officialKeys()
        XCTAssertEqual(keys.count, 32)
        for (layer, key) in keys.enumerated() {
            XCTAssertEqual(try VialKeycodeDialect.rawValue(key.token), key.raw, key.token)
            for token in [key.token, VialKeycodeDialect.token(key.raw)] {
                XCTAssertEqual(VialKeycodeDialect.layerEntry(token), key.token)
                let doc = try document(token), axes = try axes(doc.bytes)
                let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: "42", axes: axes, supportedOutputs: ["KC_C", token])])
                for automatic in [true, false] {
                    XCTAssertThrowsError(try doc.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)], expectedDevice: "42", axes: axes, support: support)) {
                        XCTAssertEqual($0 as? FirmwareError, .protectedEntry, token)
                    }
                    XCTAssertThrowsError(try doc.patch([.init(slot: .init(layer: 0, column: 1), output: token, automatic: automatic)], expectedDevice: "42", axes: axes, support: support)) {
                        XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput, token)
                    }
                }
                let patched = try doc.patch([.init(slot: .init(layer: layer, column: 1), output: "KC_C", automatic: false)], expectedDevice: "42", axes: axes, support: support)
                XCTAssertEqual(try FirmwareDocument(bytes: patched, backend: .vial).value(at: .init(layer: layer, column: 1)), "KC_C")
                for destination in 1..<32 {
                    for automatic in [true, false] where automatic || destination != layer {
                        XCTAssertThrowsError(try doc.patch([.init(slot: .init(layer: destination, column: 1), output: "KC_C", automatic: automatic)], expectedDevice: "42", axes: axes, support: support)) {
                            XCTAssertEqual($0 as? FirmwareError, .unreachableLayer, "\(token) -> \(destination)")
                        }
                    }
                }
            }
        }
        for token in ["TO(17)", "0x5211", "TO(31)", "0x521f"] {
            let doc = try document(token, layers: 2), axes = try axes(doc.bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: "42", axes: axes, supportedOutputs: ["KC_C"])])
            XCTAssertThrowsError(try doc.patch([.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: false)], expectedDevice: "42", axes: axes, support: support)) {
                XCTAssertEqual($0 as? FirmwareError, .unreachableLayer)
            }
        }
    }
    func testToExpressionsAndUnqualifiedSpellingsCannotDecodeOrGrantReachability() throws {
        for token in ["TO(32)", "TO(-1)", "TO(01)", "TO(+1)", "TO(0x1)", "TO(1.0)", "TO(1+1)",
                      "TO(USER00)", "TO(MO(1))", "TO()", "TO(1,2)", "TO(1))", "TO(1", "TO (1)",
                      "TO( 1)", "TO(1 )", " TO(1)", "\tTO(1)", "\nTO(1)", "TO(1) "] {
            XCTAssertThrowsError(try VialKeycodeDialect.rawValue(token), token)
            let doc = try document(token), axes = try axes(doc.bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: "42", axes: axes, supportedOutputs: ["KC_C"])])
            XCTAssertThrowsError(try doc.patch([.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: false)], expectedDevice: "42", axes: axes, support: support)) {
                XCTAssertEqual($0 as? FirmwareError, .unreachableLayer, token)
            }
            if token.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("TO(") {
                XCTAssertThrowsError(try doc.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false)], expectedDevice: "42", axes: axes, support: support)) {
                    XCTAssertEqual($0 as? FirmwareError, .protectedEntry, token)
                }
            }
        }
    }
    func testOfficialToMatrixAndBothEncoderDirectionsRejectWrongTargetsAndReopenEncryptedResults() async throws {
        let keys = try officialKeys()
        let layout = keys.map { [[$0.token, "KC_NO"]] }
        let encoders = keys.indices.map { [[keys[$0].token, keys[31 - $0].token]] }
        let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "uid": 42, "via_protocol": 9,
            "vial_protocol": 6, "layout": layout, "encoder_layout": encoders])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vial-to-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let keysSource = MappingFixtureKeys(), gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let store = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keysSource)
        _ = try await store.bootstrap(); await keysSource.seed(); try await store.initializeFreshInstallation(version: .init(rawValue: 1))
        let axes = try axes(bytes)
        let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: "42", axes: axes, supportedOutputs: ["KC_C"])])
        let operations = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let batch = try await operations.retainOriginal(bytes, backend: .vial, axes: axes, confirmedAt: Date(timeIntervalSince1970: 1))
        _ = try await operations.export(batch.id, changes: [.init(slot: .init(layer: 0, column: 1), output: "KC_C", automatic: true)],
            destination: FirmwareFileDestination(target: root.appendingPathComponent("patched.vil"), gate: gate))
        _ = try await operations.claimImport(batch.id, at: Date(timeIntervalSince1970: 2))
        let baseline: [UInt16] = keys.flatMap { [$0.raw, 0] }
        var expected = baseline; expected[1] = 6
        let expectedEncoders = keys.indices.map { [keys[$0].raw, keys[31 - $0].raw] }
        for scenario in 0..<5 {
            var matrix = scenario == 1 ? baseline : expected, observedEncoders = expectedEncoders
            if scenario == 2 { matrix[2] = keys[17].raw }
            if scenario == 3 { observedEncoders[1][0] = keys[17].raw }
            if scenario == 4 { observedEncoders[30][1] = keys[17].raw }
            let adapter = try VialReadbackAdapter(transport: ToReadTransport(matrix: matrix, encoders: observedEncoders), matrixRows: 1, matrixColumns: 2, encoderIndices: [0])
            let observation = try await adapter.observe(record: batch, original: bytes, at: { Date(timeIntervalSince1970: 3) })
            XCTAssertEqual(observation.values.count, 64); XCTAssertEqual(observation.encoderValues.count, 64)
            let expectedState: FirmwareMappingState = scenario == 0 ? .verified : (scenario == 1 ? .failed : .externallyChanged)
            let result = try await operations.confirmVialReadback(batch.id, observation: observation)
            XCTAssertEqual(result.records.last?.state, expectedState, "scenario \(scenario)")
            let reopened = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
            let saved = try await reopened.reconcile()
            XCTAssertEqual(saved.records.last?.state, expectedState); XCTAssertNil(saved.pending)
        }
    }
}

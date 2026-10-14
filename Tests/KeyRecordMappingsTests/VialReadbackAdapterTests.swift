import XCTest
import Foundation
import KeyRecordCore
import KeyRecordStore
@testable import KeyRecordMappings

private let vial6Bytes = Data(#"{"version":1,"uid":18446744073709551615,"via_protocol":9,"vial_protocol":6,"layout":[[["MO(1)","KC_NO",-1,"KC_ENT"],["KC_A","0x5fff","KC_NO","KC_TRNS"]],[["KC_NO","KC_NO",-1,"KC_ENTER"],["KC_A","0x5fff","KC_NO","KC_TRNS"]]],"macro":[["opaque"]],"encoder_layout":[[],[]],"layout_options":0,"settings":{}}"#.utf8)
private let vial6Keymap: [UInt8] = [0x52,0x21, 0,0, 0xff,0xff, 0,0x28, 0,4, 0x5f,0xff, 0,0, 0,1,
                                   0,0, 0,0, 0xff,0xff, 0,0x28, 0,4, 0x5f,0xff, 0,0, 0,1]
private let encoderBytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: #""encoder_layout":[[],[]]"#,
    with: #""encoder_layout":[[[-1,-1],[-1,-1],["KC_ENT","0x1234"]],[[-1,-1],[-1,-1],["KC_C","KC_TRNS"]]]"#).utf8)
private enum ReadFault: Sendable { case none, short, long, header, protocolVersion, uid, layers, rebound, timeout }
private actor SimulatedVialTransport: VialReadTransport {
    let keymap: [UInt8]
    let fault: ReadFault
    let encoderMismatch: Bool
    let modifierNames: Bool
    let layerTapNames: Bool
    let modifierTapNames: Bool
    let oneShotNames: Bool
    let persistentLayerNames: Bool
    let onExchange: (@Sendable (Int) async -> Void)?
    var requests: [VialReadRequest] = []
    init(keymap: [UInt8] = vial6Keymap, fault: ReadFault = .none, encoderMismatch: Bool = false, modifierNames: Bool = false, layerTapNames: Bool = false, modifierTapNames: Bool = false, oneShotNames: Bool = false, persistentLayerNames: Bool = false,
         onExchange: (@Sendable (Int) async -> Void)? = nil) {
        self.keymap = keymap; self.fault = fault; self.encoderMismatch = encoderMismatch; self.modifierNames = modifierNames; self.onExchange = onExchange
        self.layerTapNames = layerTapNames
        self.modifierTapNames = modifierTapNames
        self.oneShotNames = oneShotNames
        self.persistentLayerNames = persistentLayerNames
    }
    func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
        requests.append(request)
        await onExchange?(requests.count)
        XCTAssertEqual(timeoutMilliseconds, 1000)
        var bytes = [UInt8](repeating: 0, count: 32)
        switch request.bytes[0] {
        case 0x01: bytes[0] = 1; bytes[2] = fault == .protocolVersion ? 10 : 9
        case 0xfe:
            if request.bytes[1] == 3 {
                XCTAssertEqual(request.bytes[3], 2)
                bytes.replaceSubrange(0..<4, with: request.bytes[2] == 0 ? [0, 0x28, 0x12, 0x34] : [0, 6, 0, 1])
                if modifierNames {
                    bytes.replaceSubrange(0..<4, with: request.bytes[2] == 0 ? [0x0a, 0x28, 0x0f, 0x34] : [0x19, 6, 0, 1])
                }
                if layerTapNames { bytes[2] = 0x41 }
                if modifierTapNames {
                    bytes.replaceSubrange(0..<4, with: request.bytes[2] == 0 ? [0x2a, 0x28, 0x2f, 0x34] : [0x39, 6, 0, 1])
                }
                if oneShotNames {
                    bytes.replaceSubrange(0..<4, with: request.bytes[2] == 0 ? [0x52, 0xa3, 0x52, 0xaf] : [0x52, 0xa7, 0x52, 0xb2])
                }
                if persistentLayerNames {
                    bytes.replaceSubrange(0..<4, with: request.bytes[2] == 0 ? [0x52, 0xe0, 0x52, 0xff] : [0x52, 0xe1, 0x52, 0xe0])
                }
                if encoderMismatch { bytes[3] ^= 1 }
                return bytes
            }
            bytes[0] = 6
            bytes.replaceSubrange(4..<12, with: Array(repeating: UInt8(255), count: 8))
            if fault == .uid || (fault == .rebound && requests.count > 3) { bytes[4] = 0 }
        case 0x11: bytes[0] = 0x11; bytes[1] = fault == .layers ? 3 : 2
        case 0x12:
            if fault == .timeout { throw FirmwareError.unavailable }
            let offset = Int(request.bytes[1]) << 8 | Int(request.bytes[2]), length = Int(request.bytes[3])
            bytes.replaceSubrange(0..<4, with: request.bytes.prefix(4))
            bytes.replaceSubrange(4..<(4 + length), with: keymap[offset..<(offset + length)])
            if fault == .header { bytes[2] ^= 1 }
            if fault == .short { bytes.removeLast() }
            if fault == .long { bytes.append(0) }
        default: XCTFail("Mutating or unexpected request"); throw VialReadbackError.invalidRequest
        }
        return bytes
    }
}
private actor PausedVialTransport: VialReadTransport {
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func resume() { release?.resume(); release = nil }
    func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
        entered = true; arrival?.resume(); arrival = nil
        await withCheckedContinuation { release = $0 }
        var bytes = request.bytes; bytes[1] = 0; bytes[2] = 9
        return bytes
    }
}
@MainActor
final class VialReadbackAdapterTests: XCTestCase {
    private func axes(_ bytes: Data = vial6Bytes) throws -> FirmwareVersionAxes {
        try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "offline-matrix", importer: "offline-importer")
    }
    private func record() throws -> FirmwareBatchRecord {
        FirmwareBatchRecord(id: UUID(), backend: .vial, device: "18446744073709551615", axes: try axes(),
            baselineSHA256: "fixture", originalExportConfirmedAt: Date(timeIntervalSince1970: 1))
    }
    func testEncoderExportParsesSeparateSlotsAndRejectsMalformedPairsAndLayers() throws {
        let document = try FirmwareDocument(bytes: encoderBytes, backend: .vial)
        XCTAssertEqual(try document.slotValues().count, 14)
        XCTAssertEqual(document.encoderCount, 3)
        XCTAssertEqual(try document.encoderValues()[.init(layer: 0, index: 2, direction: .clockwise)], "KC_ENT")
        XCTAssertEqual(try document.encoderValues()[.init(layer: 0, index: 2, direction: .counterclockwise)], "0x1234")
        for layout in ["null", "[]", "[[]]", "[[[\"KC_C\"]],[[\"KC_C\"]]]",
                       "[[[-1,\"KC_C\"]],[[-1,\"KC_C\"]]]", "[[[0,0]],[[0,0]]]", "[[],[[-1,-1]]]" ] {
            let text = String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: #""encoder_layout":[[],[]]"#,
                with: #""encoder_layout":"# + layout)
            XCTAssertThrowsError(try FirmwareDocument(bytes: Data(text.utf8), backend: .vial))
        }
    }
    func testEncoderQueriesReadBothDirectionsAcrossLayersWithoutQueryingHoles() async throws {
        let transport = SimulatedVialTransport()
        let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4, encoderIndices: [2])
        let observed = try await adapter.observe(record: record(), original: encoderBytes)
        XCTAssertEqual(observed.encoderValues, [
            .init(layer: 0, index: 2, direction: .clockwise): "0x0028",
            .init(layer: 0, index: 2, direction: .counterclockwise): "0x1234",
            .init(layer: 1, index: 2, direction: .clockwise): "0x0006",
            .init(layer: 1, index: 2, direction: .counterclockwise): "0x0001"])
        let requests = await transport.requests
        XCTAssertEqual(Array(requests.suffix(4)), [.encoder(layer: 0, index: 2), .encoder(layer: 1, index: 2), .identity, .layerCount])
        XCTAssertEqual(requests.filter { $0.bytes[0] == 0xfe && $0.bytes[1] == 3 }.count, 2)
        XCTAssertEqual(VialReadRequest.encoder(layer: 254, index: 255).bytes.prefix(4), [0xfe, 3, 254, 255])
    }
    func testEncoderMismatchWithIndependentIndicesSendsNothing() async throws {
        let transport = SimulatedVialTransport()
        for indices: Set<Int> in [[], [0], [1,2]] {
            let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4, encoderIndices: indices)
            do { _ = try await adapter.observe(record: record(), original: encoderBytes); XCTFail("Expected encoder refusal") }
            catch { XCTAssertEqual(error as? VialReadbackError, .invalidEncoders) }
        }
        for indices: Set<Int> in [[-1], [256]] {
            XCTAssertThrowsError(try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4, encoderIndices: indices))
        }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testPrivacyRevokedDuringEncoderQueryCannotPublishPartialObservation() async throws {
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let generation = try gate.begin()
        let transport = SimulatedVialTransport(onExchange: { index in if index == 6 { gate.update(.locked) } })
        let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4, encoderIndices: [2])
        do { _ = try await adapter.observe(record: record(), original: encoderBytes, authorize: { try gate.check(generation) }); XCTFail("Expected denial") }
        catch { }
        let requests = await transport.requests
        XCTAssertEqual(requests.last, .encoder(layer: 0, index: 2)); XCTAssertEqual(requests.count, 6)
    }
    func testOfficialUnusedSlotsPreserveBytesAndCannotBePatched() throws {
        let document = try FirmwareDocument(bytes: vial6Bytes, backend: .vial)
        XCTAssertEqual(document.device, "18446744073709551615")
        XCTAssertEqual(try document.slotValues().count, 14)
        XCTAssertEqual(document.matrixDimensions?.columns, 4)
        let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device, axes: try axes(), supportedOutputs: ["KC_C"])])
        let change = FirmwareSlotChange(slot: .init(layer: 0, column: 1), output: "KC_C", automatic: true)
        let patched = try document.patch([change], expectedDevice: document.device, axes: axes(), support: support)
        XCTAssertEqual(patched, Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: #""MO(1)","KC_NO",-1"#, with: #""MO(1)","KC_C",-1"#).utf8))
        XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 2), output: "KC_C", automatic: false)], expectedDevice: document.device, axes: axes(), support: support)) {
            XCTAssertEqual($0 as? FirmwareError, .invalidSlot)
        }
        for literal in ["0", "-2", "true", "null"] {
            let invalid = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: ",-1,", with: ",\(literal),").utf8)
            XCTAssertThrowsError(try FirmwareDocument(bytes: invalid, backend: .vial))
        }
    }
    func testVersionAxesArePartialUntilIndependentEvidenceIsProvided() throws {
        let partial = try FirmwareVersionProvider.axes(bytes: vial6Bytes, backend: .vial)
        XCTAssertEqual(partial.deviceProtocol, "via-9/vial-6"); XCTAssertEqual(partial.layoutFormat, "vial-save-1")
        XCTAssertNil(partial.definitionSchema); XCTAssertNil(partial.importer); XCTAssertFalse(partial.complete)
        XCTAssertFalse(FirmwareSupportDirectory().supports(backend: .vial, device: "18446744073709551615", axes: try axes()))
        for version in ["5", "7", "-1", "\"6\""] {
            let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: #""vial_protocol":6"#, with: #""vial_protocol":"# + version).utf8)
            XCTAssertNil(try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial).keycodeDialect)
        }
        let via = Data(#"{"vendorProductId":42,"layers":[["KC_A"]]}"#.utf8)
        let viaAxes = try FirmwareVersionProvider.axes(bytes: via, backend: .via)
        XCTAssertEqual(viaAxes.layoutFormat, "via-layout-json"); XCTAssertNil(viaAxes.deviceProtocol); XCTAssertNil(viaAxes.keycodeDialect)
    }
    func testReadbackReadsEveryChunkUsesCorrectEndiannessAndOmitsHoles() async throws {
        let transport = SimulatedVialTransport()
        let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4)
        let observed = try await adapter.observe(record: record(), original: vial6Bytes, at: { Date(timeIntervalSince1970: 3) })
        XCTAssertEqual(observed.device, "18446744073709551615"); XCTAssertEqual(observed.observedAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(observed.values.count, 14)
        XCTAssertNil(observed.values[.init(layer: 0, column: 2)])
        XCTAssertEqual(observed.values[.init(layer: 0, column: 0)], "0x5221")
        XCTAssertEqual(observed.values[.init(layer: 1, row: 1, column: 1)], "0x5fff")
        let requests = await transport.requests
        XCTAssertEqual(requests, [.viaProtocol, .identity, .layerCount, try .keymap(offset: 0, length: 28),
            try .keymap(offset: 28, length: 4), .identity, .layerCount])
    }
    func testReadbackCrossesOffsetHighByteAndKeepsFinalPartialChunk() async throws {
        struct Export: Encodable {
            let version = 1, uid = UInt64.max, via_protocol = 9, vial_protocol = 6
            let layout = Array(repeating: Array(repeating: ["KC_NO", "KC_NO", "KC_NO", "KC_NO"], count: 20), count: 2)
        }
        let bytes = try JSONEncoder().encode(Export())
        let batch = FirmwareBatchRecord(id: UUID(), backend: .vial, device: String(UInt64.max), axes: try axes(bytes),
            baselineSHA256: "fixture", originalExportConfirmedAt: Date())
        var raw = [UInt8](repeating: 0, count: 320); raw[318] = 0x12; raw[319] = 0x34
        let transport = SimulatedVialTransport(keymap: raw)
        let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 20, matrixColumns: 4)
        let observation = try await adapter.observe(record: batch, original: bytes)
        XCTAssertEqual(observation.values.count, 160)
        XCTAssertEqual(observation.values[.init(layer: 1, row: 19, column: 3)], "0x1234")
        let requests = await transport.requests
        XCTAssertTrue(requests.contains(try .keymap(offset: 280, length: 28)))
        XCTAssertTrue(requests.contains(try .keymap(offset: 308, length: 12)))
        XCTAssertEqual(requests.count, 17)
    }
    func testMalformedUnsupportedReboundAndTimeoutResponsesNeverProduceObservation() async throws {
        for (fault, expectedError) in [(ReadFault.short, VialReadbackError.malformedResponse), (.long, .malformedResponse),
                               (.header, .malformedResponse), (.protocolVersion, .unsupportedProtocol),
                               (.uid, .wrongDevice), (.layers, .invalidMatrix), (.rebound, .changedDevice)] {
            let adapter = try VialReadbackAdapter(transport: SimulatedVialTransport(fault: fault), matrixRows: 2, matrixColumns: 4)
            do { _ = try await adapter.observe(record: record(), original: vial6Bytes); XCTFail("Expected refusal") }
            catch { XCTAssertEqual(error as? VialReadbackError, expectedError) }
        }
        let adapter = try VialReadbackAdapter(transport: SimulatedVialTransport(fault: .timeout), matrixRows: 2, matrixColumns: 4)
        do { _ = try await adapter.observe(record: record(), original: vial6Bytes); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? FirmwareError, .unavailable) }
    }
    func testInvalidRequestBoundsAndUnknownAxesSendNothing() async throws {
        for length: UInt8 in [0, 29, 255] { XCTAssertThrowsError(try VialReadRequest.keymap(offset: 0, length: length)) }
        XCTAssertThrowsError(try VialReadRequest.keymap(offset: 65_535, length: 2))
        XCTAssertEqual(try VialReadRequest.keymap(offset: 65_535, length: 1).bytes.prefix(4), [0x12,255,255,1])
        XCTAssertThrowsError(try VialReadbackAdapter(transport: SimulatedVialTransport(), matrixRows: 2, matrixColumns: 4, timeoutMilliseconds: 0))
        let transport = SimulatedVialTransport(), adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4)
        let unknown = FirmwareBatchRecord(id: UUID(), backend: .vial, device: "18446744073709551615",
            axes: .init(definitionSchema: nil, deviceProtocol: nil, layoutFormat: nil, keycodeDialect: nil, importer: nil),
            baselineSHA256: "fixture", originalExportConfirmedAt: Date())
        do { _ = try await adapter.observe(record: unknown, original: vial6Bytes); XCTFail("Expected refusal") }
        catch { XCTAssertEqual(error as? VialReadbackError, .unsupportedProtocol) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testWrongDefinitionShapeAndFileProtocolMismatchSendNothing() async throws {
        let transport = SimulatedVialTransport()
        let wrongShape = try VialReadbackAdapter(transport: transport, matrixRows: 4, matrixColumns: 2)
        do { _ = try await wrongShape.observe(record: record(), original: vial6Bytes); XCTFail("Expected shape refusal") }
        catch { XCTAssertEqual(error as? VialReadbackError, .invalidMatrix) }
        let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4)
        let v5 = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: #""vial_protocol":6"#, with: #""vial_protocol":5"#).utf8)
        do { _ = try await adapter.observe(record: record(), original: v5); XCTFail("Expected version refusal") }
        catch { XCTAssertEqual(error as? VialReadbackError, .unsupportedProtocol) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testAuthorizationRevocationStopsQueriesAndAdapterCanBeReused() async throws {
        let transport = SimulatedVialTransport(), adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let generation = try gate.begin()
        gate.update(.locked)
        do { _ = try await adapter.observe(record: record(), original: vial6Bytes, authorize: { try gate.check(generation) }); XCTFail("Expected denial") }
        catch { }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
        let result = try await adapter.observe(record: record(), original: vial6Bytes)
        XCTAssertEqual(result.values.count, 14)
    }
    func testPrivacyChangeDuringAChunkDiscardsItAndSendsNoLaterQuery() async throws {
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let generation = try gate.begin()
        let transport = SimulatedVialTransport(onExchange: { index in if index == 4 { gate.update(.locked) } })
        let adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4)
        do { _ = try await adapter.observe(record: record(), original: vial6Bytes, authorize: { try gate.check(generation) }); XCTFail("Expected denial") }
        catch { }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 4)
    }
    func testConcurrentReadIsRejectedAndCancellationCannotPublishObservation() async throws {
        let transport = PausedVialTransport(), adapter = try VialReadbackAdapter(transport: transport, matrixRows: 2, matrixColumns: 4)
        let batch = try record()
        let first = Task { try await adapter.observe(record: batch, original: vial6Bytes) }
        await transport.waitUntilEntered()
        do { _ = try await adapter.observe(record: batch, original: vial6Bytes); XCTFail("Expected busy") }
        catch { XCTAssertEqual(error as? VialReadbackError, .busy) }
        first.cancel(); await transport.resume()
        do { _ = try await first.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testVial6CodecNormalizesAliasesModifiersLayerEntrancesAndRejectsUnknownNames() throws {
        for (token, raw): (String, UInt16) in [("KC_ENT", 0x28), ("KC_C", 6), ("LCTL(LSFT(KC_C))", 0x0306),
            ("RCTL(KC_C)", 0x1106), ("MO(1)", 0x5221), ("TO(1)", 0x5211), ("LT(1,KC_C)", 0x4106), ("0xffff", 65535)] {
            XCTAssertEqual(try VialKeycodeDialect.rawValue(token), raw)
        }
        for token in ["CUSTOM", "MO(32)", "TO(16)", "LT(16,KC_C)", "0x10000", "LCTL(RCTL(KC_C))",
                      "LCTL(LCTL(LCTL(LCTL(LCTL(KC_C)))))"] { XCTAssertThrowsError(try VialKeycodeDialect.rawValue(token)) }
        for token in ["0x5221", "0x4106", "0x7c00", "QK_CLEAR_EEPROM"] { XCTAssertTrue(VialKeycodeDialect.protectedEntry(token)) }
    }
    func testRawHexEntrancesRemainProtectedAndReachable() throws {
        let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: "MO(1)", with: "0x5221").utf8)
        let document = try FirmwareDocument(bytes: bytes, backend: .vial)
        let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device, axes: try axes(bytes), supportedOutputs: ["KC_C"])])
        XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false)], expectedDevice: document.device, axes: axes(bytes), support: support)) {
            XCTAssertEqual($0 as? FirmwareError, .protectedEntry)
        }
        _ = try document.patch([.init(slot: .init(layer: 1, column: 0), output: "KC_C", automatic: true)], expectedDevice: document.device, axes: axes(bytes), support: support)
    }
    func testProtocolReadbackIntegratesWithExportClaimsAndEncryptedResultRecovery() async throws {
        try await verifyEncryptedReadback(modifierNames: false)
    }
    func testCombinedModifierMatrixAndEncoderNamesUseFullComparisonAndEncryptedRecovery() async throws {
        try await verifyEncryptedReadback(modifierNames: true)
    }
    func testCanonicalLayerTapMatrixAndEncodersUseFullComparisonAndEncryptedRecovery() async throws {
        try await verifyEncryptedReadback(modifierNames: false, layerTapNames: true)
    }
    func testStaticModifierTapMatrixAndEncodersUseFullComparisonAndEncryptedRecovery() async throws {
        try await verifyEncryptedReadback(modifierNames: true, modifierTapNames: true)
    }
    func testOneShotModifierMatrixAndEncodersUseFullComparisonAndEncryptedRecovery() async throws {
        try await verifyEncryptedReadback(modifierNames: false, oneShotNames: true)
    }
    func testPersistentDefaultLayerMatrixAndEncodersUseFullComparisonAndEncryptedRecovery() async throws {
        try await verifyEncryptedReadback(modifierNames: false, persistentLayerNames: true)
    }
    func testOneShotModifiersDoNotExpandOutputsOrGrantLayerAndSafetyPermissions() throws {
        for token in ["OSM(MOD_LCTL)", "OSM(MOD_HYPR)", "OSM(MOD_RGUI)", "OSM(0x40)", "OSM(MO(1))", "OSM(LT1(KC_C))"] {
            let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: "MO(1)", with: token).utf8)
            let document = try FirmwareDocument(bytes: bytes, backend: .vial), axes = try axes(bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device,
                axes: axes, supportedOutputs: ["KC_C", token])])
            for automatic in [true, false] {
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .unreachableLayer) }
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 1), output: token, automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput) }
            }
        }
        for entry in ["MO(1)", "LT1(KC_C)", "LT1(OSM(MOD_LCTL))", "0x52e0", "QK_BOOT", "0x7c03"] {
            let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: "MO(1)", with: entry).utf8)
            let document = try FirmwareDocument(bytes: bytes, backend: .vial), axes = try axes(bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device, axes: axes, supportedOutputs: ["KC_C"])])
            for automatic in [true, false] {
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .protectedEntry) }
            }
        }
    }
    func testPersistentDefaultLayerNamesAndUnqualifiedSpellingsCannotBypassEntryProtection() throws {
        for token in ["PDF(0)", "PDF(1)", "PDF(31)", "PDF(32)", "PDF(-1)", "PDF(01)", "PDF(0x1)",
                      "PDF(USER00)", "PDF(MO(1))", "PDF()", "PDF (1)", " PDF(1)", "\tPDF(1)", "\nPDF(1)"] {
            let replacement = String(decoding: try JSONEncoder().encode(token), as: UTF8.self)
            let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: #""MO(1)""#, with: replacement).utf8)
            let document = try FirmwareDocument(bytes: bytes, backend: .vial), axes = try axes(bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device,
                axes: axes, supportedOutputs: ["KC_C", token])])
            for automatic in [true, false] {
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support), token) { XCTAssertEqual($0 as? FirmwareError, .protectedEntry) }
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support), token) { XCTAssertEqual($0 as? FirmwareError, .unreachableLayer) }
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 1), output: token, automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support), token) { XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput) }
            }
        }
    }
    func testUnqualifiedOneShotSpellingsCannotBypassManualSafetyEntryProtection() throws {
        for token in ["OSM(0x40)", "OSM(64)", "OSM (0x40)", " OSM(0x40)", "\tOSM(64)", "\nOSM (0x40)"] {
            let replacement = String(decoding: try JSONEncoder().encode(token), as: UTF8.self)
            let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: #""MO(1)""#, with: replacement).utf8)
            let document = try FirmwareDocument(bytes: bytes, backend: .vial), axes = try axes(bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device,
                axes: axes, supportedOutputs: ["KC_C"])])
            for automatic in [true, false] {
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .protectedEntry) }
            }
        }
    }
    func testStaticModifierTapDoesNotExpandAutomaticOutputsOrGrantLayerReachability() throws {
        for token in ["LSFT_T(KC_C)", "ALL_T(KC_C)", "HYPR_T(KC_C)", "LSFT_T(MO(1))", "LSFT_T(LT1(KC_C))", "MT(1,KC_C)"] {
            let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: "MO(1)", with: token).utf8)
            let document = try FirmwareDocument(bytes: bytes, backend: .vial), axes = try axes(bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device,
                axes: axes, supportedOutputs: ["KC_C", token])])
            for automatic in [true, false] {
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .unreachableLayer) }
            }
            XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 1), output: token, automatic: true)],
                expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .unsupportedOutput) }
        }
        for entry in ["MO(1)", "LT1(KC_C)", "LT1(LSFT_T(KC_C))", "QK_BOOT", "0x7c03"] {
            let bytes = Data(String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: "MO(1)", with: entry).utf8)
            let document = try FirmwareDocument(bytes: bytes, backend: .vial), axes = try axes(bytes)
            let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device, axes: axes, supportedOutputs: ["KC_C"])])
            for automatic in [true, false] {
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .protectedEntry) }
            }
        }
    }
    func testCanonicalLayerTapEntrancesProtectSlotsAndOnlyReachExistingDestinationLayers() throws {
        let text = String(decoding: vial6Bytes, as: UTF8.self).replacingOccurrences(of: "MO(1)", with: "LT1(KC_KP_ENTER)")
        let bytes = Data(text.utf8), axes = try axes(bytes)
        let document = try FirmwareDocument(bytes: bytes, backend: .vial)
        let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device, axes: axes, supportedOutputs: ["KC_C"])])
        for automatic in [true, false] {
            let patch = try document.patch([.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: automatic)],
                expectedDevice: document.device, axes: axes, support: support)
            XCTAssertEqual(try FirmwareDocument(bytes: patch, backend: .vial).value(at: .init(layer: 1, column: 1)), "KC_C")
            XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)],
                expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .protectedEntry) }
            for entry in ["LT0(KC_C)", "LT15(KC_C)", "LT16(KC_C)", "LT01(KC_C)", "LT1(USER00)"] {
                let unreachable = try FirmwareDocument(bytes: Data(text.replacingOccurrences(of: "LT1(KC_KP_ENTER)", with: entry).utf8), backend: .vial)
                XCTAssertThrowsError(try unreachable.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .protectedEntry) }
                XCTAssertThrowsError(try unreachable.patch([.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: automatic)],
                    expectedDevice: document.device, axes: axes, support: support)) { XCTAssertEqual($0 as? FirmwareError, .unreachableLayer) }
            }
        }
    }
    private func verifyEncryptedReadback(modifierNames: Bool, layerTapNames: Bool = false, modifierTapNames: Bool = false, oneShotNames: Bool = false, persistentLayerNames: Bool = false) async throws {
        var text = String(decoding: encoderBytes, as: UTF8.self)
            .replacingOccurrences(of: "0x1234", with: "RSFT(KC_QUOTE)")
            .replacingOccurrences(of: "KC_A", with: "KC_BSLASH")
            .replacingOccurrences(of: "0x5fff", with: "KC_KP_COMMA")
        if modifierNames {
            text = text.replacingOccurrences(of: "KC_BSLASH", with: "C_S(KC_BSLASH)")
                .replacingOccurrences(of: "KC_KP_COMMA", with: "LCAG(KC_KP_COMMA)")
                .replacingOccurrences(of: "RSFT(KC_QUOTE)", with: "HYPR(KC_QUOTE)")
                .replacingOccurrences(of: #""KC_ENT""#, with: #""SCMD(KC_ENTER)""#)
                .replacingOccurrences(of: #""KC_ENTER""#, with: #""SCMD(KC_ENTER)""#)
                .replacingOccurrences(of: #""KC_C","KC_TRNS""#, with: #""RCG(KC_C)","KC_TRNS""#)
        }
        if layerTapNames {
            text = text.replacingOccurrences(of: "MO(1)", with: "LT1(KC_KP_ENTER)")
                .replacingOccurrences(of: "RSFT(KC_QUOTE)", with: "LT1(KC_QUOTE)")
                .replacingOccurrences(of: "KC_KP_COMMA", with: "LT0(KC_KP_COMMA)")
                .replacingOccurrences(of: #""KC_TRNS""#, with: #""LT1(KC_TRNS)""#)
        }
        if modifierTapNames {
            for prefix in ["C_S", "LCAG", "HYPR", "SCMD", "RCG"] {
                text = text.replacingOccurrences(of: prefix + "(", with: prefix + "_T(")
            }
        }
        if oneShotNames {
            text = text.replacingOccurrences(of: "KC_BSLASH", with: "OSM(MOD_LCTL)")
                .replacingOccurrences(of: "KC_KP_COMMA", with: "OSM(MOD_RGUI)")
                .replacingOccurrences(of: "RSFT(KC_QUOTE)", with: "OSM(MOD_HYPR)")
                .replacingOccurrences(of: #""KC_ENT""#, with: #""OSM(MOD_LCTL|MOD_LSFT)""#)
                .replacingOccurrences(of: #""KC_ENTER""#, with: #""OSM(MOD_LCTL|MOD_LSFT)""#)
                .replacingOccurrences(of: #""KC_C","KC_TRNS""#, with: #""OSM(MOD_MEH)","OSM(MOD_RSFT)""#)
        }
        if persistentLayerNames {
            text = text.replacingOccurrences(of: "KC_BSLASH", with: "PDF(0)")
                .replacingOccurrences(of: "KC_KP_COMMA", with: "PDF(31)")
                .replacingOccurrences(of: "RSFT(KC_QUOTE)", with: "PDF(31)")
                .replacingOccurrences(of: #""KC_ENT""#, with: #""PDF(0)""#)
                .replacingOccurrences(of: #""KC_ENTER""#, with: #""PDF(0)""#)
                .replacingOccurrences(of: #""KC_C","KC_TRNS""#, with: #""PDF(1)","PDF(0)""#)
        }
        let originalBytes = Data(text.utf8)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vial-adapter-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let keys = MappingFixtureKeys(), gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let store = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keys)
        _ = try await store.bootstrap(); await keys.seed(); try await store.initializeFreshInstallation(version: .init(rawValue: 1))
        let axes = try axes(), device = "18446744073709551615"
        let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: device, axes: axes, supportedOutputs: ["KC_C"])])
        let operations = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let batch = try await operations.retainOriginal(originalBytes, backend: .vial, axes: axes, confirmedAt: Date(timeIntervalSince1970: 1))
        _ = try await operations.export(batch.id, changes: [.init(slot: .init(layer: 0, column: 1), output: "KC_C", automatic: true)],
            destination: FirmwareFileDestination(target: root.appendingPathComponent("patched.vil"), gate: gate))
        _ = try await operations.claimImport(batch.id, at: Date(timeIntervalSince1970: 2))
        var baseline = vial6Keymap
        for offset in [8,24] { baseline[offset] = modifierNames ? 3 : 0; baseline[offset + 1] = 0x31 }
        for offset in [10,26] { baseline[offset] = modifierNames ? 0x0d : 0; baseline[offset + 1] = 0x85 }
        if modifierNames { baseline[6] = 0x0a; baseline[22] = 0x0a }
        if modifierTapNames { for offset in [6,8,10,22,24,26] { baseline[offset] |= 0x20 } }
        if oneShotNames {
            for offset in [6,22] { baseline[offset] = 0x52; baseline[offset + 1] = 0xa3 }
            for offset in [8,24] { baseline[offset] = 0x52; baseline[offset + 1] = 0xa1 }
            for offset in [10,26] { baseline[offset] = 0x52; baseline[offset + 1] = 0xb8 }
        }
        if persistentLayerNames {
            for offset in [6,8,22,24] { baseline[offset] = 0x52; baseline[offset + 1] = 0xe0 }
            for offset in [10,26] { baseline[offset] = 0x52; baseline[offset + 1] = 0xff }
        }
        if layerTapNames {
            baseline[0] = 0x41; baseline[1] = 0x58
            for offset in [10,26] { baseline[offset] = 0x40 }
            for offset in [14,30] { baseline[offset] = 0x41 }
        }
        var expected = baseline; expected[3] = 6
        var external = expected; external[9] = 0x34
        for (raw, encoderMismatch, state) in [(expected, false, FirmwareMappingState.verified), (baseline, false, .failed),
                                              (external, false, .externallyChanged), (expected, true, .externallyChanged)] {
            let adapter = try VialReadbackAdapter(transport: SimulatedVialTransport(keymap: raw, encoderMismatch: encoderMismatch, modifierNames: modifierNames, layerTapNames: layerTapNames, modifierTapNames: modifierTapNames, oneShotNames: oneShotNames, persistentLayerNames: persistentLayerNames),
                matrixRows: 2, matrixColumns: 4, encoderIndices: [2])
            let observation = try await adapter.observe(record: batch, original: originalBytes, at: { Date(timeIntervalSince1970: 3) })
            let result = try await operations.confirmVialReadback(batch.id, observation: observation)
            XCTAssertEqual(result.records.last?.state, state)
            let reopened = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
            let saved = try await reopened.reconcile(); XCTAssertEqual(saved.records.last?.state, state); XCTAssertNil(saved.pending)
        }
        let missing = VialKeymapObservation(device: device, axes: axes, values: try FirmwareDocument(bytes: originalBytes, backend: .vial).slotValues(),
            observedAt: Date(timeIntervalSince1970: 4))
        do { _ = try await operations.confirmVialReadback(batch.id, observation: missing); XCTFail("Expected missing encoder refusal") }
        catch { XCTAssertEqual(error as? FirmwareError, .invalidDocument) }
        let original = try await operations.original(batch.id); XCTAssertEqual(original, originalBytes)
    }
}

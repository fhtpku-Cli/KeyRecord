import XCTest
import Foundation
import KeyRecordDeviceRead
@testable import KeyRecordMappings

private let definitionXZ = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4AB8AG5dAD2IicZUNsMXT+Tj0LL2o1xY9+vhKXbIvBy+vt7ajJ9ByJ+U3t83EJIzjavDD0/txhM7o8p2unsGnnWbxEuUfVifBNNdOsvnERH+MjQdNyzfGKOpZsOfDPQyS8tONaoxr0YNL+3+QwvQXI28Cr7JAAAAOXSVpUTMuNUAAYoBfQAAAJKyS9ixxGf7AgAAAAAEWVo=")!
private let originalVial = Data(#"{"version":1,"uid":42,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_C",-1,"KC_ENT"]]]}"#.utf8)
private let encoderDefinitionXZ = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4ACMAHNdAD2IisaUL8LEIpnpbzWhi9MuaJSxOkspsVw55Xn7bInuMyewnJZLH9loZQHt+8O/0aPdImbC/zOhSY0hKRF6Qo860nDK00pvvQj4zzfzFDhGIM4qAJCwnLNQi6XluttcNvwdRtrS0/ZXMW7fRhPfGKahBwAAAGoknprQ9flsAAGPAY0BAACxXyIPscRn+wIAAAAABFla")!
private let encoderVial = Data(#"{"version":1,"uid":42,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_C",-1,"KC_ENT"]]],"encoder_layout":[[[-1,-1],[-1,-1],["KC_ENT","0x1234"]]]}"#.utf8)
private final class Endpoint: VialHIDEndpoint, @unchecked Sendable {
    private let lock = NSLock()
    private var receiver: (@Sendable (Result<VialHIDFrame, VialHIDError>) -> Void)?
    private var completion: (@Sendable (Result<Void, VialHIDError>) -> Void)?
    private var arrival: CheckedContinuation<Void, Never>?
    private var sent: [VialReadRequest] = []
    private var closes = 0
    let response: (@Sendable (VialReadRequest) throws -> [UInt8])?
    init(response: (@Sendable (VialReadRequest) throws -> [UInt8])? = nil) { self.response = response }
    var requests: [VialReadRequest] { lock.withLock { sent } }
    var closeCount: Int { lock.withLock { closes } }
    func start(receive: @escaping @Sendable (Result<VialHIDFrame, VialHIDError>) -> Void) { lock.withLock { receiver = receive } }
    func send(_ request: VialReadRequest, timeoutMilliseconds: Int, completion: @escaping @Sendable (Result<Void, VialHIDError>) -> Void) {
        let waiter = lock.withLock {
            sent.append(request); self.completion = completion
            let waiter = arrival; arrival = nil; return waiter
        }
        waiter?.resume()
        if let response {
            do { emit(try response(request)); completion(.success(())) }
            catch { completion(.failure(.ioFailure(-1))) }
        }
    }
    func waitUntilSent() async {
        await withCheckedContinuation { continuation in
            lock.withLock { if sent.isEmpty { arrival = continuation } else { continuation.resume() } }
        }
    }
    func emit(_ bytes: [UInt8], id: Int = 0) { lock.withLock { receiver }?(.success(.init(reportID: id, bytes: bytes))) }
    func disconnect() { lock.withLock { receiver }?(.failure(.disconnected)) }
    func finishSend(_ result: Result<Void, VialHIDError> = .success(())) { lock.withLock { completion }?(result) }
    func close() { lock.withLock { closes += 1 } }
}
private final class Deadline: VialHIDDeadline, @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?
    private var cancelled = false
    func schedule(milliseconds: Int, action: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        lock.withLock { self.action = action; cancelled = false }
        return { self.lock.withLock { self.cancelled = true } }
    }
    func fire() { lock.withLock { cancelled ? nil : action }?() }
}
private func response(_ request: VialReadRequest, compressed: Data = definitionXZ, uid: UInt64 = 42) -> [UInt8] {
    var bytes = request.bytes
    switch bytes[0] {
    case 1: bytes[1] = 0; bytes[2] = 9
    case 0x11: bytes[1] = 1
    case 0x12: bytes.replaceSubrange(4..<10, with: [0, 6, 255, 255, 0, 0x28])
    case 0xfe:
        switch bytes[1] {
        case 0:
            bytes = Array(repeating: 0, count: 32); bytes[0] = 6
            for index in 0..<8 { bytes[index + 4] = UInt8(truncatingIfNeeded: uid >> (index * 8)) }
        case 1:
            bytes = Array(repeating: 0, count: 32)
            for index in 0..<4 { bytes[index] = UInt8(truncatingIfNeeded: compressed.count >> (index * 8)) }
        case 2:
            let start = (Int(bytes[2]) | Int(bytes[3]) << 8) * 32
            bytes = Array(compressed[start..<min(start + 32, compressed.count)])
            bytes += Array(repeating: 0, count: 32 - bytes.count)
        case 3: bytes.replaceSubrange(0..<4, with: [0,0x28,0x12,0x34])
        default: break
        }
    default: break
    }
    return bytes
}
@MainActor
final class VialDeviceReadTests: XCTestCase {
    private struct DefinitionFixtures: Decodable {
        struct Case: Decodable {
            let name: String
            let definition: String
            let compressed: Data
            let positions: [[Int]]
            let encoders: [[Int]]
        }
        let cases: [Case]
    }
    private func definitionFixtures() throws -> [DefinitionFixtures.Case] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(DefinitionFixtures.self, from: Data(contentsOf:
            root.appendingPathComponent("evidence/phase4/fixtures/synthetic/vial6-definition-topology.json"))).cases
    }
    func testDefinitionMatchesOfficialAlignmentDecalAndVariantTopology() throws {
        let fixtures = try definitionFixtures()
        XCTAssertEqual(fixtures.count, 14)
        for fixture in fixtures {
            do {
                let definition = try VialDeviceDefinition(bytes: Data(fixture.definition.utf8), uid: 42)
                XCTAssertEqual(definition.positions, Set(fixture.positions.map { .init(layer: 0, row: $0[0], column: $0[1]) }), fixture.name)
                XCTAssertEqual(definition.encoderPositions, Set(try fixture.encoders.map {
                    .init(layer: 0, index: $0[0], direction: try XCTUnwrap(FirmwareEncoderDirection(rawValue: $0[1])))
                }), fixture.name)
            } catch { XCTFail("\(fixture.name): \(error)") }
        }
    }
    func testSessionReadsOfficialDecoratedDefinitionAndRefusesMissingDecalPosition() async throws {
        let fixture = try XCTUnwrap(definitionFixtures().first { $0.name == "alignment-7" })
        let compressed = fixture.compressed
        let endpoint = Endpoint(response: { response($0, compressed: compressed) })
        let connection = VialDeviceReadConnection(endpoint: endpoint, vendorID: 0x1234, productID: 0x5678, deadline: Deadline())
        let observed = try await connection.observe(record: batch(), original: encoderVial, authorize: {})
        XCTAssertEqual(observed.values, [.init(layer: 0, column: 0): "0x0006", .init(layer: 0, column: 2): "0x0028"])
        XCTAssertEqual(observed.encoderValues.count, 2)
        XCTAssertEqual(endpoint.closeCount, 1)
        let wrong = Data(String(decoding: encoderVial, as: UTF8.self).replacingOccurrences(of: #""KC_C",-1"#, with: "-1,-1").utf8)
        let refused = Endpoint(response: { response($0, compressed: compressed) })
        let rejected = VialDeviceReadConnection(endpoint: refused, vendorID: 0x1234, productID: 0x5678, deadline: Deadline())
        do { _ = try await rejected.observe(record: batch(), original: wrong, authorize: {}); XCTFail("Expected topology refusal") }
        catch { XCTAssertEqual(error as? VialReadbackError, .invalidMatrix) }
        XCTAssertFalse(refused.requests.contains { $0.bytes[0] == 0x12 || ($0.bytes[0] == 0xfe && $0.bytes[1] == 3) })
        XCTAssertEqual(refused.closeCount, 1)
    }
    func testDefinitionRejectsInvalidKLEStateAndAmbiguousEncoderCoordinates() throws {
        let invalid = [
            #"[[{"a":-1},"0,0"]]"#, #"[[{"a":8},"0,0"]]"#,
            #"[[{"a":true},"0,0"]]"#, #"[[{"a":"4"},"0,0"]]"#,
            #"[[{"d":1},"0,0"]]"#, #"[[{"d":"true"},"0,0"]]"#,
            #"[[{"d":null},"0,0"]]"#, #"[[{"d":true},"0,3"]]"#,
            #"[["0,0",{"a":7},"e"]]"#, #"[["0,0"],{"name":"misplaced"}]"#,
            #"[["0,0\n\n\n\n\n\n\n\n\n\n\n\nextra"]]"#
        ]
        for keys in invalid {
            let json = #"{"vendorId":"0x1234","productId":"0x5678","matrix":{"rows":1,"cols":3},"layouts":{"keymap":\#(keys)}}"#
            XCTAssertThrowsError(try VialDeviceDefinition(bytes: Data(json.utf8), uid: 42), keys)
        }
    }
    private func batch() -> FirmwareBatchRecord {
        .init(id: UUID(), backend: .vial, device: "42", axes: .init(definitionSchema: VialDeviceDefinition.schema,
            deviceProtocol: "via-9/vial-6", layoutFormat: "vial-save-1", keycodeDialect: VialKeycodeDialect.name,
            importer: "offline-importer"), baselineSHA256: "fixture", originalExportConfirmedAt: Date())
    }
    func testDefinitionKeepsEncoderIndexAndDirectionSeparateFromMatrixCoordinates() throws {
        let decoded = try VialXZDecoder.decode(encoderDefinitionXZ)
        let definition = try VialDeviceDefinition(bytes: decoded, uid: 42)
        XCTAssertEqual(definition.positions, [.init(layer: 0, column: 0), .init(layer: 0, column: 2)])
        XCTAssertEqual(definition.encoderPositions, [.init(layer: 0, index: 2, direction: .counterclockwise)])
        let text = String(decoding: decoded, as: UTF8.self)
        let maximum = try VialDeviceDefinition(bytes: Data(text.replacingOccurrences(of: "2,1", with: "255,0").utf8), uid: 42)
        XCTAssertEqual(maximum.encoderPositions, [.init(layer: 0, index: 255, direction: .clockwise)])
        let aligned = try VialDeviceDefinition(bytes: Data(text.replacingOccurrences(of: #""a":0"#, with: #""a":4"#).utf8), uid: 42)
        XCTAssertEqual(aligned.encoderPositions, definition.encoderPositions)
        for coordinate in ["-1,0", "256,0", "2,-1", "2,2", "2,x"] {
            XCTAssertThrowsError(try VialDeviceDefinition(bytes: Data(text.replacingOccurrences(of: "2,1", with: coordinate).utf8), uid: 42))
        }
    }
    func testIndependentDefinitionDeterminesLayoutOptionAvailability() throws {
        let base = #"{"vendorId":"0x1234","productId":"0x5678","matrix":{"rows":1,"cols":1},"layouts":{"keymap":[["0,0"]]}}"#
        XCTAssertFalse(try VialDeviceDefinition(bytes: Data(base.utf8), uid: 42).hasLayoutOptions)
        for (labels, expected) in [("[]", false), (#"["Layout"]"#, true)] {
            let bytes = Data(base.replacingOccurrences(of: #""keymap":"#, with: #""labels":"# + labels + #", "keymap":"#).utf8)
            XCTAssertEqual(try VialDeviceDefinition(bytes: bytes, uid: 42).hasLayoutOptions, expected)
        }
        let malformed = Data(base.replacingOccurrences(of: #""keymap":"#, with: #""labels":true,"keymap":"#).utf8)
        XCTAssertThrowsError(try VialDeviceDefinition(bytes: malformed, uid: 42))
    }
    func testSessionMatchesIndependentEncoderIndicesAndReadsBothDirections() async throws {
        let endpoint = Endpoint(response: { response($0, compressed: encoderDefinitionXZ) })
        let transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
        defer { transport.close() }
        let session = VialDeviceReadSession(transport: transport, vendorID: 0x1234, productID: 0x5678)
        let observed = try await session.observe(record: batch(), original: encoderVial)
        XCTAssertEqual(observed.encoderValues, [.init(layer: 0, index: 2, direction: .clockwise): "0x0028",
            .init(layer: 0, index: 2, direction: .counterclockwise): "0x1234"])
        XCTAssertEqual(endpoint.requests.filter { $0.bytes[0] == 0xfe && $0.bytes[1] == 3 }, [.encoder(layer: 0, index: 2)])
        let before = endpoint.requests.count
        for text in [String(decoding: originalVial, as: UTF8.self),
                     String(decoding: encoderVial, as: UTF8.self).replacingOccurrences(of: #"[-1,-1],[-1,-1],["KC_ENT","0x1234"]"#,
                        with: #"["KC_ENT","0x1234"],[-1,-1],[-1,-1]"#)] {
            do { _ = try await session.observe(record: batch(), original: Data(text.utf8)); XCTFail("Expected encoder position refusal") }
            catch { XCTAssertEqual(error as? VialReadbackError, .invalidEncoders) }
        }
        XCTAssertFalse(endpoint.requests.dropFirst(before).contains { $0.bytes[0] == 0x12 || ($0.bytes[0] == 0xfe && $0.bytes[1] == 3) })
    }
    func testEncoderShortResponseNeverProducesObservation() async throws {
        let endpoint = Endpoint(response: { request in
            let bytes = response(request, compressed: encoderDefinitionXZ)
            return request == .encoder(layer: 0, index: 2) ? Array(bytes.dropLast()) : bytes
        })
        let connection = VialDeviceReadConnection(endpoint: endpoint, vendorID: 0x1234, productID: 0x5678, deadline: Deadline())
        do { _ = try await connection.observe(record: batch(), original: encoderVial, authorize: {}); XCTFail("Expected short report refusal") }
        catch { XCTAssertEqual(error as? VialHIDError, .invalidReport) }
        XCTAssertEqual(endpoint.closeCount, 1)
        XCTAssertEqual(endpoint.requests.last, .encoder(layer: 0, index: 2))
    }
    func testTransportWaitsForSendAndInputInEitherOrder() async throws {
        for inputFirst in [true, false] {
            let endpoint = Endpoint(), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
            let task = Task { try await transport.exchange(.identity, timeoutMilliseconds: 1000) }
            await endpoint.waitUntilSent()
            if inputFirst { endpoint.emit(response(.identity)); endpoint.finishSend() }
            else { endpoint.finishSend(); endpoint.emit(response(.identity)) }
            let observed = try await task.value
            XCTAssertEqual(observed, response(.identity)); XCTAssertEqual(endpoint.requests.first?.bytes.count, 32)
            transport.close(); XCTAssertEqual(endpoint.closeCount, 1)
        }
    }
    func testExplicitCloseAndDeallocationCloseEndpointOnlyOnce() {
        let endpoint = Endpoint()
        var transport: VialHIDTransport? = VialHIDTransport(endpoint: endpoint)
        transport?.close(); transport?.close(); transport = nil
        XCTAssertEqual(endpoint.closeCount, 1)
        var unclosed: VialHIDTransport? = VialHIDTransport(endpoint: endpoint)
        XCTAssertNotNil(unclosed); unclosed = nil
        XCTAssertEqual(endpoint.closeCount, 2)
    }
    func testTransportRejectsBadLengthAndReportIDAndCannotReuseThatConnection() async throws {
        for (count, id) in [(31, 0), (33, 0), (32, 1)] {
            let endpoint = Endpoint(), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
            let task = Task { try await transport.exchange(.identity, timeoutMilliseconds: 1000) }
            await endpoint.waitUntilSent(); endpoint.finishSend(); endpoint.emit(Array(repeating: 0, count: count), id: id)
            do { _ = try await task.value; XCTFail("Expected malformed report") } catch { XCTAssertEqual(error as? VialHIDError, .invalidReport) }
            do { _ = try await transport.exchange(.identity, timeoutMilliseconds: 1000); XCTFail("Expected closed") } catch { XCTAssertEqual(error as? VialHIDError, .closed) }
            XCTAssertEqual(endpoint.requests.count, 1)
        }
    }
    func testTimeoutBeforeSendCompletionClosesAndLateCallbacksCannotSatisfyAnotherRead() async throws {
        let endpoint = Endpoint(), deadline = Deadline(), transport = VialHIDTransport(endpoint: endpoint, deadline: deadline)
        let task = Task { try await transport.exchange(.identity, timeoutMilliseconds: 1000) }
        await endpoint.waitUntilSent(); deadline.fire()
        do { _ = try await task.value; XCTFail("Expected timeout") } catch { XCTAssertEqual(error as? VialHIDError, .timeout) }
        endpoint.emit(response(.identity)); endpoint.finishSend()
        do { _ = try await transport.exchange(.identity, timeoutMilliseconds: 1000); XCTFail("Expected closed") } catch { XCTAssertEqual(error as? VialHIDError, .closed) }
        XCTAssertEqual(endpoint.requests.count, 1); XCTAssertEqual(endpoint.closeCount, 1)
    }
    func testCancellationDisconnectAndSendFailureFinishPendingReadOnce() async throws {
        for reason in 0..<3 {
            let endpoint = Endpoint(), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
            let task = Task { try await transport.exchange(.identity, timeoutMilliseconds: 1000) }
            await endpoint.waitUntilSent()
            if reason == 0 { task.cancel() }
            else if reason == 1 { endpoint.disconnect() }
            else { endpoint.finishSend(.failure(.ioFailure(-5))) }
            do { _ = try await task.value; XCTFail("Expected terminal error") }
            catch { XCTAssertEqual(error as? VialHIDError, reason == 0 ? .closed : reason == 1 ? .disconnected : .ioFailure(-5)) }
            endpoint.emit(response(.identity)); endpoint.finishSend()
            XCTAssertEqual(endpoint.closeCount, 1)
        }
    }
    func testConcurrentExchangeDoesNotSendAnotherReport() async throws {
        let endpoint = Endpoint(), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
        let task = Task { try await transport.exchange(.identity, timeoutMilliseconds: 1000) }
        await endpoint.waitUntilSent()
        do { _ = try await transport.exchange(.viaProtocol, timeoutMilliseconds: 1000); XCTFail("Expected busy") }
        catch { XCTAssertEqual(error as? VialHIDError, .busy) }
        endpoint.finishSend(); endpoint.emit(response(.identity)); _ = try await task.value
        XCTAssertEqual(endpoint.requests, [.identity]); transport.close()
    }
    func testTimeoutConversionRejectsValuesOutsideIOKitMillisecondsRange() async throws {
        let endpoint = Endpoint(), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
        for timeout in [0, Int(UInt32.max) + 1] {
            do { _ = try await transport.exchange(.identity, timeoutMilliseconds: timeout); XCTFail("Expected invalid timeout") }
            catch { XCTAssertEqual(error as? VialReadbackError, .invalidRequest) }
        }
        XCTAssertTrue(endpoint.requests.isEmpty); transport.close()
    }
    func testDefinitionReadsOfficialXZPagesAndExactIndependentMatrix() async throws {
        let endpoint = Endpoint(response: { response($0) }), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
        let definition = try await VialDefinitionReader(transport: transport).read(expectedUID: 42)
        XCTAssertEqual(definition.uid, 42); XCTAssertEqual(definition.vendorID, 0x1234); XCTAssertEqual(definition.productID, 0x5678)
        XCTAssertEqual(definition.rows, 1); XCTAssertEqual(definition.columns, 3)
        XCTAssertEqual(definition.positions, [.init(layer: 0, column: 0), .init(layer: 0, column: 2)])
        XCTAssertEqual(endpoint.requests.count, 10)
        XCTAssertEqual(endpoint.requests[3], try .definitionPage(0)); XCTAssertEqual(endpoint.requests[8], try .definitionPage(5))
        transport.close()
    }
    func testDecoderRejectsTruncationCorruptionTrailingBytesAndOversizedInput() throws {
        for bad in [Data(), definitionXZ.dropLast(), definitionXZ + Data([1]), Data(repeating: 0, count: 131_073)] {
            XCTAssertThrowsError(try VialXZDecoder.decode(Data(bad)))
        }
        var corrupted = definitionXZ; corrupted[40] ^= 255
        XCTAssertThrowsError(try VialXZDecoder.decode(corrupted))
        let decoded = try VialXZDecoder.decode(definitionXZ)
        for changed in [String(decoding: decoded, as: UTF8.self).replacingOccurrences(of: "\"rows\":1", with: "\"rows\":0"),
                        String(decoding: decoded, as: UTF8.self).replacingOccurrences(of: "0,2", with: "0,3")] {
            XCTAssertThrowsError(try VialDeviceDefinition(bytes: Data(changed.utf8), uid: 42))
        }
    }
    func testDefinitionAcceptsEmptyKLEPropertiesAndFalseDecalWithoutInventingPositions() throws {
        let decoded = try VialXZDecoder.decode(definitionXZ)
        let text = String(decoding: decoded, as: UTF8.self)
        let bytes = Data(text.replacingOccurrences(of: #"[["0,0""#, with: #"[[{}, {"d":false,"a":4},"0,0""#).utf8)
        let definition = try VialDeviceDefinition(bytes: bytes, uid: 42)
        XCTAssertEqual(definition.positions, [.init(layer: 0, column: 0), .init(layer: 0, column: 2)])
        for changed in [String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: #""d":false"#, with: #""d":1"#),
                        String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: #""a":4"#, with: #""a":8"#)] {
            XCTAssertThrowsError(try VialDeviceDefinition(bytes: Data(changed.utf8), uid: 42))
        }
    }
    func testDecoderRejectsExpandedOutputAndDictionaryBeyondMemoryLimit() throws {
        // Python lzma: first expands to 1,048,577 bytes; second uses preset 9's
        // 64 MiB dictionary, whose decoder requires more than the 64 MiB budget.
        let output = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj8AAAANldACDv+7/+o7Fe5fg/sqomVfhocEFwFQ+N/R5MG4pCtxn0aRhxrmYjiopNL6MN2X+m44wjEVPgWRjFdYrid/i2lH8MasDedElk4ulcU7IE2PdEDKtfDW1G6eXDdoi3llestk3haR1v+0uIEGxCy4g/XACP0E6vJiiUcR89jyThcJ6nI1/sKMuF0ZWYin4qkfIndfcZwAaYTZj92K/VkA/EJVP49ZE2MQWlsO5vwXBNRwzRkRGqrWAdus6xJxhcWYbpZlJYvul2rFnk5VsFCPnH2q38+1Iq+AWTZQAAAAAANWP0ZR3iS5gAAfUBgYBAABzww/+xxGf7AgAAAAAEWVo=")!
        let memory = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARwAAAAQz1jMAQAEc21hbGwAAAAAPG+8dMV0EoQAAR0FuC2Arx+2830BAAAAAARZWg==")!
        XCTAssertThrowsError(try VialXZDecoder.decode(output))
        XCTAssertThrowsError(try VialXZDecoder.decode(memory))
    }
    func testDefinitionSizeBoundsAndPageEndianness() async throws {
        XCTAssertEqual(try VialReadRequest.definitionPage(0x0101).bytes.prefix(4), [0xfe, 2, 1, 1])
        XCTAssertEqual(try VialReadRequest.definitionPage(4095).bytes.prefix(4), [0xfe, 2, 255, 15])
        XCTAssertThrowsError(try VialReadRequest.definitionPage(4096))
        for size in [0, 131_073] {
            let endpoint = Endpoint(response: { request in
                if request == .definitionSize {
                    var bytes = [UInt8](repeating: 0, count: 32)
                    for index in 0..<4 { bytes[index] = UInt8(truncatingIfNeeded: size >> (index * 8)) }
                    return bytes
                }
                return response(request)
            })
            let transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
            do { _ = try await VialDefinitionReader(transport: transport).read(expectedUID: 42); XCTFail("Expected size refusal") }
            catch { XCTAssertEqual(error as? VialDefinitionError, .invalidSize) }
            XCTAssertEqual(endpoint.requests.count, 3); transport.close()
        }
    }
    func testSessionUsesDefinitionBeforeKeymapAndRejectsWrongOccupiedPositions() async throws {
        let endpoint = Endpoint(response: { response($0) }), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
        let session = VialDeviceReadSession(transport: transport, vendorID: 0x1234, productID: 0x5678)
        let observed = try await session.observe(record: batch(), original: originalVial)
        XCTAssertEqual(observed.values, [.init(layer: 0, column: 0): "0x0006", .init(layer: 0, column: 2): "0x0028"])
        XCTAssertEqual(observed.definition?.device, "42")
        XCTAssertEqual(observed.definition?.bytes, try VialXZDecoder.decode(definitionXZ))
        XCTAssertEqual(endpoint.requests.filter { $0 == .definitionSize }.count, 2)
        XCTAssertEqual(endpoint.requests.filter { $0.bytes[0] == 0x12 }.count, 1)
        let before = endpoint.requests.count
        let wrong = Data(String(decoding: originalVial, as: UTF8.self).replacingOccurrences(of: #""KC_C",-1,"KC_ENT""#, with: #"-1,"KC_C","KC_ENT""#).utf8)
        do { _ = try await session.observe(record: batch(), original: wrong); XCTFail("Expected occupied-position refusal") }
        catch { XCTAssertEqual(error as? VialReadbackError, .invalidMatrix) }
        XCTAssertEqual(endpoint.requests.count - before, 10)
        transport.close()
    }
    func testSessionRejectsDefinitionChangeWithUnchangedUIDAfterKeymap() async throws {
        actor Changing: VialReadTransport {
            var readKeymap = false
            let shifted = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4ACEAHJdAD2IicZUNsMXT+Tj0LL2o1xY9+vhKXbIvBy+vt7ajJ9ByJ+U3t83EJIzjavDD0/txhM7o8p2unsGnnWbxEuUfVifBNNdOsvnERH+MjQdNyzfGKOpZsOfDPQyS8tONaowXCuAH39Nx2eH4eVL43tiuwzCZgAAALpFqcDlBTElAAGOAYUBAAD7pMoBscRn+wIAAAAABFla")!
            func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
                if request.bytes[0] == 0x12 { readKeymap = true }
                return response(request, compressed: readKeymap ? shifted : definitionXZ)
            }
        }
        let session = VialDeviceReadSession(transport: Changing(), vendorID: 0x1234, productID: 0x5678)
        do { _ = try await session.observe(record: batch(), original: originalVial); XCTFail("Changed geometry must not accompany a readback") }
        catch { XCTAssertEqual(error as? VialDefinitionError, .changedDevice) }
    }
    func testDefinitionWrongUIDAndPrivacyRevocationStopFurtherQueries() async throws {
        let endpoint = Endpoint(response: { response($0, uid: 43) }), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
        do { _ = try await VialDefinitionReader(transport: transport).read(expectedUID: 42); XCTFail("Expected wrong device") }
        catch { XCTAssertEqual(error as? VialReadbackError, .wrongDevice) }
        XCTAssertEqual(endpoint.requests.count, 2); transport.close()
        let denied = Endpoint(response: { response($0) }), deniedTransport = VialHIDTransport(endpoint: denied, deadline: Deadline())
        do { _ = try await VialDefinitionReader(transport: deniedTransport).read(expectedUID: 42, authorize: { throw FirmwareError.unavailable }); XCTFail("Expected denial") }
        catch { XCTAssertEqual(error as? FirmwareError, .unavailable) }
        XCTAssertTrue(denied.requests.isEmpty); deniedTransport.close()
    }
    func testSessionRejectsOtherBackendBeforeQueriesAndWrongVIDPIDBeforeKeymap() async throws {
        let endpoint = Endpoint(response: { response($0) }), transport = VialHIDTransport(endpoint: endpoint, deadline: Deadline())
        let source = batch()
        let other = FirmwareBatchRecord(id: source.id, backend: .via, device: source.device, axes: source.axes,
            baselineSHA256: source.baselineSHA256, originalExportConfirmedAt: source.originalExportConfirmedAt)
        let session = VialDeviceReadSession(transport: transport, vendorID: 0x1234, productID: 0x5679)
        do { _ = try await session.observe(record: other, original: originalVial); XCTFail("Expected backend refusal") }
        catch { XCTAssertEqual(error as? FirmwareError, .unknownCompatibility) }
        XCTAssertTrue(endpoint.requests.isEmpty)
        do { _ = try await session.observe(record: source, original: originalVial); XCTFail("Expected VID/PID refusal") }
        catch { XCTAssertEqual(error as? VialHIDError, .wrongInterface) }
        XCTAssertEqual(endpoint.requests.count, 10)
        XCTAssertFalse(endpoint.requests.contains { $0.bytes[0] == 0x12 }); transport.close()
    }
}

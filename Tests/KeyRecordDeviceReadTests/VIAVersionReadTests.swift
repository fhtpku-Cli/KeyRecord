import Foundation
import XCTest
import KeyRecordMappings
@testable import KeyRecordDeviceRead

private final class VersionEndpoint: VialHIDEndpoint, @unchecked Sendable {
    private let lock = NSLock()
    private var receive: (@Sendable (Result<VialHIDFrame, VialHIDError>) -> Void)?
    private var sent: [VialReadRequest] = []
    private var closes = 0
    let version: UInt8
    let codes: UInt8
    let fault: Int
    init(version: UInt8 = 13, codes: UInt8 = 9, fault: Int = 0) { self.version = version; self.codes = codes; self.fault = fault }
    var requests: [VialReadRequest] { lock.withLock { sent } }
    var closeCount: Int { lock.withLock { closes } }
    func start(receive: @escaping @Sendable (Result<VialHIDFrame, VialHIDError>) -> Void) { lock.withLock { self.receive = receive } }
    func send(_ request: VialReadRequest, timeoutMilliseconds: Int, completion: @escaping @Sendable (Result<Void, VialHIDError>) -> Void) {
        let (receiver, count) = lock.withLock { sent.append(request); return (receive, sent.count) }
        XCTAssertTrue([VialReadRequest.viaProtocol, .viaKeycodesVersion].contains(request))
        var bytes = request.bytes
        if request == .viaProtocol { bytes[1] = 0; bytes[2] = version }
        else { bytes[5] = codes }
        if fault == 1 { bytes[0] = 0 }
        if fault == 2 { bytes.removeLast() }
        if fault == 3 && count == 3 { bytes[2] += 1 }
        if fault == 4 && count == 4 { bytes[5] = 8 }
        if fault == 5 { receiver?(.failure(.disconnected)); return }
        receiver?(.success(.init(reportID: 0, bytes: bytes))); completion(.success(()))
    }
    func close() { lock.withLock { closes += 1 } }
}

@MainActor
final class VIAVersionReadTests: XCTestCase {
    func testIndependentVersionsComeOnlyFromSelectedDeviceAndDoNotQualifyImporter() async throws {
        for version: UInt8 in [7, 9, 12, 13] {
            let endpoint = VersionEndpoint(version: version)
            let connection = VIAVersionReadConnection(endpoint: endpoint, vendorID: 1, productID: 2)
            let axes = try await connection.observe(expectedDevice: "65538", authorize: {})
            XCTAssertEqual(axes.deviceProtocol, "via-\(version)")
            XCTAssertEqual(axes.keycodeDialect, version == 13 ? "qmk-keycodes-00000009" : nil)
            XCTAssertNil(axes.importer); XCTAssertNil(axes.definitionSchema); XCTAssertFalse(axes.complete)
            XCTAssertFalse(FirmwareSupportDirectory().supports(backend: .via, device: "65538", axes: axes))
            XCTAssertEqual(endpoint.requests.count, version == 13 ? 4 : 2)
            XCTAssertEqual(endpoint.closeCount, 1)
        }
    }
    func testUnknownMalformedChangedAndDisconnectedVersionsFailClosed() async throws {
        for (version, codes, fault) in [(6,9,0), (14,9,0), (13,0,0), (13,7,0), (13,10,0), (13,0xff,0),
                                       (13,9,1), (13,9,2), (13,9,3), (13,9,4), (13,9,5)] {
            let endpoint = VersionEndpoint(version: UInt8(version), codes: UInt8(codes), fault: fault)
            let connection = VIAVersionReadConnection(endpoint: endpoint, vendorID: 0, productID: 42)
            do { _ = try await connection.observe(expectedDevice: "42", authorize: {}); XCTFail("Expected refusal") }
            catch { XCTAssertTrue(error is VialReadbackError || error is VialHIDError) }
            XCTAssertEqual(endpoint.closeCount, 1)
        }
    }
    func testIdentityCancellationAndPermissionLossStopFurtherReports() async throws {
        let endpoint = VersionEndpoint()
        let connection = VIAVersionReadConnection(endpoint: endpoint, vendorID: 0, productID: 42)
        do { _ = try await connection.observe(expectedDevice: "43", authorize: {}); XCTFail("Expected wrong device") }
        catch { XCTAssertEqual(error as? VialReadbackError, .wrongDevice) }
        XCTAssertTrue(endpoint.requests.isEmpty)
        let revoked = VersionEndpoint()
        let reader = VIAVersionReadConnection(endpoint: revoked, vendorID: 0, productID: 42)
        do {
            _ = try await reader.observe(expectedDevice: "42") {
                if !revoked.requests.isEmpty { throw CancellationError() }
            }
            XCTFail("Expected revoked authority")
        } catch is CancellationError {}
        XCTAssertEqual(revoked.requests.count, 1); XCTAssertEqual(revoked.closeCount, 1)
    }
}

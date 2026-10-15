import Foundation
import KeyRecordMappings

public final class VIAVersionReadConnection: Sendable {
    private let transport: VialHIDTransport
    public let device: String
    public init(endpoint: any VialHIDEndpoint, vendorID: UInt16, productID: UInt16) {
        transport = VialHIDTransport(endpoint: endpoint)
        device = String(UInt32(vendorID) << 16 | UInt32(productID))
    }
    public func close() { transport.close() }
    public func observe(expectedDevice: String, authorize: @escaping @MainActor @Sendable () throws -> Void) async throws -> FirmwareVersionAxes {
        defer { close() }
        guard expectedDevice == device else { throw VialReadbackError.wrongDevice }
        func response(_ request: VialReadRequest) async throws -> [UInt8] {
            try Task.checkCancellation(); try await authorize()
            let bytes = try await transport.exchange(request, timeoutMilliseconds: 1_000)
            try Task.checkCancellation(); try await authorize()
            guard bytes.count == 32 else { throw VialReadbackError.malformedResponse }
            return bytes
        }
        let protocolReply = try await response(.viaProtocol)
        guard protocolReply[0] == 1 else { throw VialReadbackError.malformedResponse }
        let version = UInt16(protocolReply[1]) << 8 | UInt16(protocolReply[2])
        guard (7...13).contains(version) else { throw VialReadbackError.unsupportedProtocol }
        if version < 13 {
            let finalProtocol = try await response(.viaProtocol)
            guard finalProtocol.prefix(3) == protocolReply.prefix(3) else { throw VialReadbackError.changedDevice }
            return FirmwareVersionAxes(definitionSchema: nil, deviceProtocol: "via-\(version)", layoutFormat: "via-layout-json",
                                       keycodeDialect: nil, importer: nil)
        }
        let codes = try await response(.viaKeycodesVersion)
        guard codes[0] == 2, codes[1] == 6 else { throw VialReadbackError.malformedResponse }
        let value = codes[2..<6].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard codes[2..<6].allSatisfy({ $0 >> 4 <= 9 && $0 & 15 <= 9 }), [8, 9].contains(value) else {
            throw VialReadbackError.unsupportedProtocol
        }
        let finalProtocol = try await response(.viaProtocol)
        let finalCodes = try await response(.viaKeycodesVersion)
        guard finalProtocol.prefix(3) == protocolReply.prefix(3), finalCodes.prefix(6) == codes.prefix(6) else {
            throw VialReadbackError.changedDevice
        }
        return FirmwareVersionAxes(definitionSchema: nil, deviceProtocol: "via-\(version)", layoutFormat: "via-layout-json",
                                   keycodeDialect: String(format: "qmk-keycodes-%08x", value), importer: nil)
    }
}

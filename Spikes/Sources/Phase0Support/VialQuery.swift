import Foundation

public enum VialDefinitionQuery: Equatable, Sendable {
    case size
    case page(UInt16)
}

public enum VialQuery: Equatable, Sendable {
    case protocolVersion
    case uid
    case definition(VialDefinitionQuery)
    case keymapRead(offset: UInt16, length: UInt8)
}

public enum VialQueryLimits {
    public static let reportBytes = 32
    public static let maximumKeymapChunkBytes = 28
    public static let maximumDefinitionBytes = 131_072
    public static let maximumKeymapBytes = 65_534
}

public enum VialQueryError: String, Error, Codable, Equatable, Sendable {
    case invalidQuery
    case timeout
    case truncatedResponse
    case oversizedResponse
    case unexpectedRequest
    case unexpectedResponse
    case extraResponse
    case uidMismatch
    case definitionTooLarge
    case keymapTooLarge
    case malformedKeymap
}

public struct VialQueryReport: Equatable, Sendable {
    public let bytes: [UInt8]

    private init(bytes: [UInt8]) { self.bytes = bytes }

    public static func make(_ query: VialQuery) throws -> VialQueryReport {
        var bytes = [UInt8](repeating: 0, count: VialQueryLimits.reportBytes)
        switch query {
        case .protocolVersion, .uid:
            bytes[0] = 0xFE
            bytes[1] = 0x00
        case .definition(.size):
            bytes[0] = 0xFE
            bytes[1] = 0x01
        case let .definition(.page(page)):
            guard Int(page) <= (VialQueryLimits.maximumDefinitionBytes - 1) / VialQueryLimits.reportBytes else {
                throw VialQueryError.invalidQuery
            }
            bytes[0] = 0xFE
            bytes[1] = 0x02
            bytes[2] = UInt8(page & 0xFF)
            bytes[3] = UInt8(page >> 8)
        case let .keymapRead(offset, length):
            guard length > 0, length <= VialQueryLimits.maximumKeymapChunkBytes else {
                throw VialQueryError.invalidQuery
            }
            guard Int(offset) <= VialQueryLimits.maximumKeymapBytes - Int(length) else {
                throw VialQueryError.invalidQuery
            }
            bytes[0] = 0x12
            bytes[1] = UInt8(offset >> 8)
            bytes[2] = UInt8(offset & 0xFF)
            bytes[3] = length
        }
        return VialQueryReport(bytes: bytes)
    }
}

enum VialOpcodeGate {
    static func authorize(opcode: UInt8, payload: [UInt8]) throws -> VialQuery {
        if opcode == 0x12, payload.count == 3 {
            let offset = UInt16(payload[0]) << 8 | UInt16(payload[1])
            let query = VialQuery.keymapRead(offset: offset, length: payload[2])
            _ = try VialQueryReport.make(query)
            return query
        }
        guard opcode == 0xFE, let command = payload.first else { throw VialQueryError.invalidQuery }
        switch command {
        case 0x00 where payload.count == 1: return .protocolVersion
        case 0x01 where payload.count == 1: return .definition(.size)
        case 0x02 where payload.count == 3:
            return .definition(.page(UInt16(payload[1]) | UInt16(payload[2]) << 8))
        default: throw VialQueryError.invalidQuery
        }
    }

    @discardableResult
    static func execute(
        opcode: UInt8, payload: [UInt8], through transport: any VialQueryTransport,
        timeoutMilliseconds: Int
    ) throws -> [UInt8] {
        let query = try authorize(opcode: opcode, payload: payload)
        let report = try VialQueryReport.make(query)
        return try transport.exchange(report, timeoutMilliseconds: timeoutMilliseconds)
    }
}

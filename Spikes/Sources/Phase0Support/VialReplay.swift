import Foundation

public protocol VialQueryTransport: AnyObject {
    func exchange(_ report: VialQueryReport, timeoutMilliseconds: Int) throws -> [UInt8]
}

protocol VialReplayExhaustionChecking {
    func assertExhausted() throws
}

public struct VialReplayResult: Equatable, Sendable {
    public let protocolVersion: UInt32
    public let uid: String
    public let definition: [UInt8]
    public let keymap: [UInt8]
    public let definitionSha256: String
    public let keymapKeycodes: [UInt16]
    public let reportCount: Int
}

public enum VialQueryReplay {
    public static func run(
        transport: any VialQueryTransport,
        expectedUID: String,
        expectedDefinition: [UInt8],
        expectedKeymap: [UInt8],
        timeoutMilliseconds: Int
    ) throws -> VialReplayResult {
        let keymapByteCount = expectedKeymap.count
        guard (1...VialQueryLimits.maximumKeymapBytes).contains(keymapByteCount) else {
            throw VialQueryError.keymapTooLarge
        }
        guard keymapByteCount.isMultiple(of: 2), timeoutMilliseconds > 0 else {
            throw VialQueryError.malformedKeymap
        }
        var count = 0
        let protocolBytes = try request(.protocolVersion, through: transport, timeout: timeoutMilliseconds)
        count += 1
        let version = littleUInt32(protocolBytes, at: 0)
        let uidBytes = try request(.uid, through: transport, timeout: timeoutMilliseconds)
        count += 1
        let uid = hex(uidBytes[4..<12])
        guard uid == expectedUID else { throw VialQueryError.uidMismatch }

        let sizeBytes = try request(.definition(.size), through: transport, timeout: timeoutMilliseconds)
        count += 1
        let definitionSize = Int(littleUInt32(sizeBytes, at: 0))
        guard definitionSize <= VialQueryLimits.maximumDefinitionBytes else {
            throw VialQueryError.definitionTooLarge
        }
        guard definitionSize == expectedDefinition.count else { throw VialQueryError.unexpectedResponse }
        var definition: [UInt8] = []
        for page in 0..<((definitionSize + 31) / 32) {
            guard let pageValue = UInt16(exactly: page) else { throw VialQueryError.definitionTooLarge }
            let response = try request(.definition(.page(pageValue)), through: transport, timeout: timeoutMilliseconds)
            count += 1
            let length = min(32, definitionSize - definition.count)
            let expected = expectedDefinition[definition.count..<(definition.count + length)]
            guard response.prefix(length).elementsEqual(expected) else { throw VialQueryError.unexpectedResponse }
            definition.append(contentsOf: response.prefix(length))
        }

        var keymap: [UInt8] = []
        while keymap.count < keymapByteCount {
            guard let offset = UInt16(exactly: keymap.count) else { throw VialQueryError.keymapTooLarge }
            let length = min(VialQueryLimits.maximumKeymapChunkBytes, keymapByteCount - keymap.count)
            let response = try request(
                .keymapRead(offset: offset, length: UInt8(length)), through: transport,
                timeout: timeoutMilliseconds
            )
            count += 1
            let expected = expectedKeymap[keymap.count..<(keymap.count + length)]
            guard response[4..<(4 + length)].elementsEqual(expected) else {
                throw VialQueryError.unexpectedResponse
            }
            keymap.append(contentsOf: response[4..<(4 + length)])
        }
        if let checking = transport as? any VialReplayExhaustionChecking { try checking.assertExhausted() }
        let keycodes = stride(from: 0, to: keymap.count, by: 2).map {
            UInt16(keymap[$0]) << 8 | UInt16(keymap[$0 + 1])
        }
        return VialReplayResult(
            protocolVersion: version, uid: uid, definition: definition, keymap: keymap,
            definitionSha256: ViaDefinitionDigest.sha256(Data(definition)),
            keymapKeycodes: keycodes, reportCount: count
        )
    }

    private static func request(
        _ query: VialQuery, through transport: any VialQueryTransport, timeout: Int
    ) throws -> [UInt8] {
        let response = try transport.exchange(try VialQueryReport.make(query), timeoutMilliseconds: timeout)
        guard response.count >= VialQueryLimits.reportBytes else { throw VialQueryError.truncatedResponse }
        guard response.count == VialQueryLimits.reportBytes else { throw VialQueryError.oversizedResponse }
        return response
    }

    private static func littleUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }

    private static func hex(_ bytes: ArraySlice<UInt8>) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}

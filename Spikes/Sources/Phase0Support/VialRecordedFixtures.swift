import Foundation

public struct VialRecordedExchange: Equatable, Sendable {
    public let request: [UInt8]
    public let response: [UInt8]
    public let error: VialQueryError?

    public init(request: [UInt8], response: [UInt8], error: VialQueryError? = nil) {
        self.request = request; self.response = response; self.error = error
    }
}

public final class RecordedVialTransport: VialQueryTransport, VialReplayExhaustionChecking, @unchecked Sendable {
    private let exchanges: [VialRecordedExchange]
    public private(set) var reports: [VialQueryReport] = []
    public var callCount: Int { reports.count }

    public init(exchanges: [VialRecordedExchange]) { self.exchanges = exchanges }

    public func exchange(_ report: VialQueryReport, timeoutMilliseconds: Int) throws -> [UInt8] {
        let index = reports.count
        reports.append(report)
        guard index < exchanges.count, exchanges[index].request == report.bytes else {
            throw VialQueryError.unexpectedRequest
        }
        if let error = exchanges[index].error { throw error }
        return exchanges[index].response
    }

    public func assertExhausted() throws {
        guard reports.count == exchanges.count else { throw VialQueryError.extraResponse }
    }
}

public struct VialRecordedFixture: Sendable {
    public static let fixturePath = "evidence/phase0/fixtures/synthetic/vial-query-replay.json"
    public static let fixtureSha256 = "5e6b307c5436e05c72da2a9f94317610c97f8477b8baac0331f034adf3128789"
    public let exchanges: [VialRecordedExchange]
    public let expectedUID: String
    public let expectedDefinition: [UInt8]
    public let expectedKeymap: [UInt8]
    public var expectedDefinitionSha256: String { ViaDefinitionDigest.sha256(Data(expectedDefinition)) }

    public static let approved = makeApproved()
    public static let timeout = replacingApproved(index: 0, with: exchange(query(.protocolVersion), [], .timeout))
    public static let truncated = replacingApproved(index: 0, with: exchange(query(.protocolVersion), [UInt8](repeating: 0, count: 31)))
    public static let wrongUID: VialRecordedFixture = {
        var response = identityResponse
        response[4] = 0xFF
        return replacingApproved(index: 1, with: exchange(query(.uid), response))
    }()
    public static let extra: VialRecordedFixture = {
        let value = approved
        return VialRecordedFixture(
            exchanges: value.exchanges + [exchange(query(.protocolVersion), identityResponse)],
            expectedUID: value.expectedUID, expectedDefinition: value.expectedDefinition, expectedKeymap: value.expectedKeymap
        )
    }()
    public static let reordered: VialRecordedFixture = {
        var value = approved
        value = VialRecordedFixture(
            exchanges: [value.exchanges[0], value.exchanges[2], value.exchanges[1]] + Array(value.exchanges.dropFirst(3)),
            expectedUID: value.expectedUID, expectedDefinition: value.expectedDefinition, expectedKeymap: value.expectedKeymap
        )
        return value
    }()
    public static let duplicate: VialRecordedFixture = {
        let value = approved
        return VialRecordedFixture(
            exchanges: [value.exchanges[0], value.exchanges[1], value.exchanges[1]] + Array(value.exchanges.dropFirst(2)),
            expectedUID: value.expectedUID, expectedDefinition: value.expectedDefinition, expectedKeymap: value.expectedKeymap
        )
    }()

    static let identityPrefix = [
        exchange(query(.protocolVersion), identityResponse),
        exchange(query(.uid), identityResponse),
    ]

    static func definitionSize(_ size: Int) -> VialRecordedExchange {
        var response = [UInt8](repeating: 0, count: 32)
        let value = UInt32(size)
        response[0] = UInt8(value & 0xFF); response[1] = UInt8((value >> 8) & 0xFF)
        response[2] = UInt8((value >> 16) & 0xFF); response[3] = UInt8((value >> 24) & 0xFF)
        return exchange(query(.definition(.size)), response)
    }

    public static func load(repository: URL) throws -> VialRecordedFixture {
        let url = repository.appendingPathComponent(fixturePath)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 65_536 else { throw VialRecordedFixtureError.invalidFile }
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard ViaDefinitionDigest.sha256(bytes) == fixtureSha256 else { throw VialRecordedFixtureError.hashMismatch }
        let document = try JSONDecoder().decode(Document.self, from: bytes)
        guard document.schemaVersion == 1, document.fixtureKind == "synthetic-recorded-response" else {
            throw VialRecordedFixtureError.invalidDocument
        }
        let exchanges = try document.exchanges.map {
            let request = try decodedHex($0.requestHex), response = try decodedHex($0.responseHex)
            guard request.count == 32, response.count == 32 else { throw VialRecordedFixtureError.invalidDocument }
            return VialRecordedExchange(request: request, response: response)
        }
        let definition = try decodedHex(document.expectedDefinitionHex)
        let keymap = try decodedHex(document.expectedKeymapHex)
        return VialRecordedFixture(
            exchanges: exchanges, expectedUID: document.expectedUID,
            expectedDefinition: definition, expectedKeymap: keymap
        )
    }

    private static let identityResponse: [UInt8] = {
        var value = [UInt8](repeating: 0, count: 32)
        value[0] = 6; value.replaceSubrange(4..<12, with: [1, 2, 3, 4, 5, 6, 7, 8])
        return value
    }()

    private static func makeApproved() -> VialRecordedFixture {
        let definition = Array("synthetic-vial-definition-pages-0123456789".utf8)
        let keymap: [UInt8] = [0x00, 0x04, 0x00, 0x05, 0x00, 0x28, 0x00, 0x29]
        var page0 = [UInt8](definition.prefix(32)); page0 += [UInt8](repeating: 0, count: 32 - page0.count)
        var page1 = [UInt8](definition.dropFirst(32)); page1 += [UInt8](repeating: 0, count: 32 - page1.count)
        var keymapResponse = [UInt8](repeating: 0, count: 4) + keymap
        keymapResponse += [UInt8](repeating: 0, count: 32 - keymapResponse.count)
        let exchanges = identityPrefix + [
            definitionSize(definition.count), exchange(query(.definition(.page(0))), page0),
            exchange(query(.definition(.page(1))), page1),
            exchange(query(.keymapRead(offset: 0, length: 8)), keymapResponse),
        ]
        return VialRecordedFixture(
            exchanges: exchanges, expectedUID: "0102030405060708",
            expectedDefinition: definition, expectedKeymap: keymap
        )
    }

    private static func replacingApproved(index: Int, with exchange: VialRecordedExchange) -> VialRecordedFixture {
        var value = approved; var exchanges = value.exchanges; exchanges[index] = exchange
        value = VialRecordedFixture(
            exchanges: exchanges, expectedUID: value.expectedUID,
            expectedDefinition: value.expectedDefinition, expectedKeymap: value.expectedKeymap
        )
        return value
    }

    private static func query(_ value: VialQuery) -> [UInt8] {
        (try? VialQueryReport.make(value).bytes) ?? []
    }
    private static func exchange(
        _ request: [UInt8], _ response: [UInt8], _ error: VialQueryError? = nil
    ) -> VialRecordedExchange { VialRecordedExchange(request: request, response: response, error: error) }

    private static func decodedHex(_ value: String) throws -> [UInt8] {
        guard value.count.isMultiple(of: 2), value.utf8.allSatisfy({
            (48...57).contains($0) || (97...102).contains($0)
        }) else { throw VialRecordedFixtureError.invalidDocument }
        return try stride(from: 0, to: value.count, by: 2).map { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: 2)
            guard let byte = UInt8(value[start..<end], radix: 16) else { throw VialRecordedFixtureError.invalidDocument }
            return byte
        }
    }
}

private struct Document: Decodable {
    let schemaVersion: Int
    let fixtureKind: String
    let expectedUID: String
    let expectedDefinitionHex: String
    let expectedKeymapHex: String
    let exchanges: [DocumentExchange]
}

private struct DocumentExchange: Decodable { let requestHex: String; let responseHex: String }

public enum VialRecordedFixtureError: Error, Equatable { case invalidFile, hashMismatch, invalidDocument }

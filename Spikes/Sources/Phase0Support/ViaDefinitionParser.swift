import Foundation

public enum ViaDefinitionLimits {
    public static let maximumInputBytes = 8 * 1_024 * 1_024
    public static let maximumDepth = 64
    public static let maximumCollectionElements = 100_000
    public static let maximumScalarBytes = 1_024 * 1_024
}

public enum ViaDefinitionSchema: String, Codable, Sendable {
    case v2 = "V2"
    case v3 = "V3"
}

public enum ViaDefinitionError: String, Error, Equatable, Codable, Sendable {
    case inputTooLarge
    case depthExceeded
    case collectionElementsExceeded
    case scalarTooLarge
    case malformedJSON
    case duplicateTopLevelKey
    case missingIdentity
    case ambiguousSchema
    case unknownSchema
    case missingMutableName
}

public struct ViaDefinitionDocument: Sendable {
    public let schema: ViaDefinitionSchema
    private let bytes: Data
    private let members: [String: Range<Int>]
    private let nameRange: Range<Int>?

    fileprivate init(schema: ViaDefinitionSchema, bytes: Data, members: [String: Range<Int>], nameRange: Range<Int>?) {
        self.schema = schema
        self.bytes = bytes
        self.members = members
        self.nameRange = nameRange
    }

    public func rawSlice(named name: String) -> Data? {
        guard let range = members[name] else { return nil }
        return bytes.subdata(in: range)
    }

    public func replacingName(with name: String) throws -> Data {
        guard let range = nameRange else { throw ViaDefinitionError.missingMutableName }
        let encoded = try JSONEncoder().encode(name)
        guard encoded.count >= 2, encoded.count - 2 <= ViaDefinitionLimits.maximumScalarBytes else { throw ViaDefinitionError.scalarTooLarge }
        var result = Data()
        result.reserveCapacity(bytes.count - range.count + encoded.count)
        result.append(bytes[..<range.lowerBound])
        result.append(encoded)
        result.append(bytes[range.upperBound...])
        guard result.count <= ViaDefinitionLimits.maximumInputBytes else { throw ViaDefinitionError.inputTooLarge }
        _ = try ViaDefinitionParser.parse(result)
        return result
    }

    public func bytesOutsideNameAreIdentical(in candidate: Data) -> Bool {
        guard let range = nameRange else { return false }
        let delta = candidate.count - bytes.count
        let candidateEnd = range.upperBound + delta
        guard candidateEnd >= range.lowerBound, candidateEnd <= candidate.count else { return false }
        return bytes[..<range.lowerBound] == candidate[..<range.lowerBound]
            && bytes[range.upperBound...] == candidate[candidateEnd...]
    }
}

public enum ViaDefinitionParser {
    public static func parse(_ data: Data) throws -> ViaDefinitionDocument {
        guard data.count <= ViaDefinitionLimits.maximumInputBytes else { throw ViaDefinitionError.inputTooLarge }
        var scanner = ViaJSONScanner(data)
        let root = try scanner.parseRootObject()
        let keys = Set(root.members.keys)
        let hasV2 = keys.contains("vendorProductId")
        let hasV3Part = keys.contains("vendorId") || keys.contains("productId")
        let schema: ViaDefinitionSchema
        if hasV2 && hasV3Part { throw ViaDefinitionError.ambiguousSchema }
        if hasV2 {
            guard root.kinds["vendorProductId"] == .number else { throw ViaDefinitionError.missingIdentity }
            schema = .v2
        } else if hasV3Part {
            guard keys.contains("vendorId"), keys.contains("productId"), root.kinds["vendorId"] == .string,
                  root.kinds["productId"] == .string else { throw ViaDefinitionError.missingIdentity }
            schema = .v3
        } else if keys.contains("version") {
            throw ViaDefinitionError.unknownSchema
        } else {
            throw ViaDefinitionError.missingIdentity
        }
        let nameRange = root.kinds["name"] == .string ? root.members["name"] : nil
        return ViaDefinitionDocument(schema: schema, bytes: data, members: root.members, nameRange: nameRange)
    }
}

private enum ViaJSONKind { case object, array, string, number, literal }

private struct ViaJSONRoot {
    let members: [String: Range<Int>]
    let kinds: [String: ViaJSONKind]
}

private struct ViaJSONScanner {
    private let bytes: [UInt8]
    private var index = 0
    private var collectionElements = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func parseRootObject() throws -> ViaJSONRoot {
        skipWhitespace()
        guard current == 0x7b else { throw ViaDefinitionError.malformedJSON }
        var members: [String: Range<Int>] = [:]
        var kinds: [String: ViaJSONKind] = [:]
        try parseObject(depth: 1, rootMembers: &members, rootKinds: &kinds)
        skipWhitespace()
        guard index == bytes.count else { throw ViaDefinitionError.malformedJSON }
        return ViaJSONRoot(members: members, kinds: kinds)
    }

    private mutating func parseValue(depth: Int) throws -> (Range<Int>, ViaJSONKind) {
        skipWhitespace()
        let start = index
        let kind: ViaJSONKind
        guard let byte = current else { throw ViaDefinitionError.malformedJSON }
        switch byte {
        case 0x7b:
            var ignoredMembers: [String: Range<Int>] = [:], ignoredKinds: [String: ViaJSONKind] = [:]
            try parseObject(depth: depth + 1, rootMembers: &ignoredMembers, rootKinds: &ignoredKinds, capture: false); kind = .object
        case 0x5b: try parseArray(depth: depth + 1); kind = .array
        case 0x22: _ = try parseString(); kind = .string
        case 0x2d, 0x30...0x39: try parseNumber(); kind = .number
        case 0x74: try parseLiteral("true"); kind = .literal
        case 0x66: try parseLiteral("false"); kind = .literal
        case 0x6e: try parseLiteral("null"); kind = .literal
        default: throw ViaDefinitionError.malformedJSON
        }
        return (start..<index, kind)
    }

    private mutating func parseObject(
        depth: Int,
        rootMembers: inout [String: Range<Int>],
        rootKinds: inout [String: ViaJSONKind],
        capture: Bool = true
    ) throws {
        guard depth <= ViaDefinitionLimits.maximumDepth else { throw ViaDefinitionError.depthExceeded }
        index += 1; skipWhitespace()
        if consume(0x7d) { return }
        while true {
            guard current == 0x22 else { throw ViaDefinitionError.malformedJSON }
            let key = try parseString()
            skipWhitespace(); guard consume(0x3a) else { throw ViaDefinitionError.malformedJSON }
            try incrementCollection()
            let (range, kind) = try parseValue(depth: depth)
            if capture {
                guard rootMembers[key] == nil else { throw ViaDefinitionError.duplicateTopLevelKey }
                rootMembers[key] = range; rootKinds[key] = kind
            }
            skipWhitespace()
            if consume(0x7d) { return }
            guard consume(0x2c) else { throw ViaDefinitionError.malformedJSON }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        guard depth <= ViaDefinitionLimits.maximumDepth else { throw ViaDefinitionError.depthExceeded }
        index += 1; skipWhitespace()
        if consume(0x5d) { return }
        while true {
            try incrementCollection(); _ = try parseValue(depth: depth); skipWhitespace()
            if consume(0x5d) { return }
            guard consume(0x2c) else { throw ViaDefinitionError.malformedJSON }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        index += 1
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if !escaped && byte == 0x22 {
                let payload = index - start - 1
                guard payload <= ViaDefinitionLimits.maximumScalarBytes else { throw ViaDefinitionError.scalarTooLarge }
                index += 1
                let token = Data(bytes[start..<index])
                guard let decoded = try? JSONDecoder().decode(String.self, from: token) else { throw ViaDefinitionError.malformedJSON }
                return decoded
            }
            if !escaped && byte < 0x20 { throw ViaDefinitionError.malformedJSON }
            escaped = !escaped && byte == 0x5c
            if escaped == false || byte != 0x5c { if byte != 0x5c { escaped = false } }
            index += 1
            if index - start - 1 > ViaDefinitionLimits.maximumScalarBytes { throw ViaDefinitionError.scalarTooLarge }
        }
        throw ViaDefinitionError.malformedJSON
    }

    private mutating func parseNumber() throws {
        let start = index
        if consume(0x2d), index == bytes.count { throw ViaDefinitionError.malformedJSON }
        if consume(0x30) {
            if let current, (0x30...0x39).contains(current) { throw ViaDefinitionError.malformedJSON }
        } else { try consumeDigits(required: true) }
        if consume(0x2e) { try consumeDigits(required: true) }
        if current == 0x65 || current == 0x45 { index += 1; if current == 0x2b || current == 0x2d { index += 1 }; try consumeDigits(required: true) }
        guard index - start <= ViaDefinitionLimits.maximumScalarBytes else { throw ViaDefinitionError.scalarTooLarge }
    }

    private mutating func consumeDigits(required: Bool) throws {
        let start = index
        while let current, (0x30...0x39).contains(current) { index += 1 }
        if required && start == index { throw ViaDefinitionError.malformedJSON }
    }

    private mutating func parseLiteral(_ value: String) throws {
        let literal = Array(value.utf8)
        guard index + literal.count <= bytes.count, Array(bytes[index..<(index + literal.count)]) == literal else { throw ViaDefinitionError.malformedJSON }
        index += literal.count
    }

    private mutating func incrementCollection() throws {
        collectionElements += 1
        guard collectionElements <= ViaDefinitionLimits.maximumCollectionElements else { throw ViaDefinitionError.collectionElementsExceeded }
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }
    private mutating func consume(_ byte: UInt8) -> Bool { guard current == byte else { return false }; index += 1; return true }
    private mutating func skipWhitespace() { while let current, current == 0x20 || current == 0x09 || current == 0x0a || current == 0x0d { index += 1 } }
}

import Foundation

enum ViaLayoutJSONKind: Sendable { case object, array, string, number, literal }

struct ViaLayoutJSONNode: Sendable {
    let range: Range<Int>
    let kind: ViaLayoutJSONKind
    let stringValue: String?
    let children: [ViaLayoutJSONNode]
}

struct ViaLayoutJSONScanner {
    private let bytes: [UInt8]
    private var index = 0
    private var collectionElements = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func parseRootObject() throws -> [String: ViaLayoutJSONNode] {
        skipWhitespace()
        guard current == 0x7b else { throw ViaLayoutError.malformedJSON }
        let (_, members) = try parseObject(depth: 1, captureMembers: true)
        skipWhitespace()
        guard index == bytes.count else { throw ViaLayoutError.malformedJSON }
        return members
    }

    private mutating func parseValue(depth: Int) throws -> ViaLayoutJSONNode {
        skipWhitespace()
        let start = index
        guard let byte = current else { throw ViaLayoutError.malformedJSON }
        switch byte {
        case 0x7b:
            let (children, _) = try parseObject(depth: depth + 1, captureMembers: false)
            return .init(range: start..<index, kind: .object, stringValue: nil, children: children)
        case 0x5b:
            let children = try parseArray(depth: depth + 1)
            return .init(range: start..<index, kind: .array, stringValue: nil, children: children)
        case 0x22:
            let value = try parseString()
            return .init(range: start..<index, kind: .string, stringValue: value, children: [])
        case 0x2d, 0x30...0x39:
            try parseNumber()
            return .init(range: start..<index, kind: .number, stringValue: nil, children: [])
        case 0x74: try parseLiteral("true")
        case 0x66: try parseLiteral("false")
        case 0x6e: try parseLiteral("null")
        default: throw ViaLayoutError.malformedJSON
        }
        return .init(range: start..<index, kind: .literal, stringValue: nil, children: [])
    }

    private mutating func parseObject(
        depth: Int,
        captureMembers: Bool
    ) throws -> ([ViaLayoutJSONNode], [String: ViaLayoutJSONNode]) {
        guard depth <= ViaDefinitionLimits.maximumDepth else { throw ViaLayoutError.depthExceeded }
        index += 1
        skipWhitespace()
        if consume(0x7d) { return ([], [:]) }
        var children: [ViaLayoutJSONNode] = []
        var members: [String: ViaLayoutJSONNode] = [:]
        var keys = Set<String>()
        while true {
            guard current == 0x22 else { throw ViaLayoutError.malformedJSON }
            let key = try parseString()
            guard keys.insert(key).inserted else { throw ViaLayoutError.duplicateKey }
            skipWhitespace()
            guard consume(0x3a) else { throw ViaLayoutError.malformedJSON }
            try incrementCollection()
            let value = try parseValue(depth: depth)
            children.append(value)
            if captureMembers { members[key] = value }
            skipWhitespace()
            if consume(0x7d) { return (children, members) }
            guard consume(0x2c) else { throw ViaLayoutError.malformedJSON }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws -> [ViaLayoutJSONNode] {
        guard depth <= ViaDefinitionLimits.maximumDepth else { throw ViaLayoutError.depthExceeded }
        index += 1
        skipWhitespace()
        if consume(0x5d) { return [] }
        var children: [ViaLayoutJSONNode] = []
        while true {
            try incrementCollection()
            children.append(try parseValue(depth: depth))
            skipWhitespace()
            if consume(0x5d) { return children }
            guard consume(0x2c) else { throw ViaLayoutError.malformedJSON }
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
                guard index - start - 1 <= ViaDefinitionLimits.maximumScalarBytes else { throw ViaLayoutError.scalarTooLarge }
                index += 1
                let token = Data(bytes[start..<index])
                guard let value = try? JSONDecoder().decode(String.self, from: token) else { throw ViaLayoutError.malformedJSON }
                return value
            }
            if !escaped && byte < 0x20 { throw ViaLayoutError.malformedJSON }
            if escaped { escaped = false } else if byte == 0x5c { escaped = true }
            index += 1
            if index - start - 1 > ViaDefinitionLimits.maximumScalarBytes { throw ViaLayoutError.scalarTooLarge }
        }
        throw ViaLayoutError.malformedJSON
    }

    private mutating func parseNumber() throws {
        let start = index
        if consume(0x2d), index == bytes.count { throw ViaLayoutError.malformedJSON }
        if consume(0x30) {
            if let current, (0x30...0x39).contains(current) { throw ViaLayoutError.malformedJSON }
        } else {
            try consumeDigits(required: true)
        }
        if consume(0x2e) { try consumeDigits(required: true) }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2b || current == 0x2d { index += 1 }
            try consumeDigits(required: true)
        }
        guard index - start <= ViaDefinitionLimits.maximumScalarBytes else { throw ViaLayoutError.scalarTooLarge }
    }

    private mutating func consumeDigits(required: Bool) throws {
        let start = index
        while let current, (0x30...0x39).contains(current) { index += 1 }
        if required && start == index { throw ViaLayoutError.malformedJSON }
    }

    private mutating func parseLiteral(_ value: String) throws {
        let literal = Array(value.utf8)
        guard index + literal.count <= bytes.count,
              Array(bytes[index..<(index + literal.count)]) == literal else { throw ViaLayoutError.malformedJSON }
        index += literal.count
    }

    private mutating func incrementCollection() throws {
        collectionElements += 1
        guard collectionElements <= ViaDefinitionLimits.maximumCollectionElements else {
            throw ViaLayoutError.collectionElementsExceeded
        }
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }
    private mutating func consume(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        index += 1
        return true
    }
    private mutating func skipWhitespace() {
        while let current, current == 0x20 || current == 0x09 || current == 0x0a || current == 0x0d { index += 1 }
    }
}

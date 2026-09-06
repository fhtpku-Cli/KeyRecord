import Foundation

public enum BoundedJSONPreflightError: Error, Equatable, Sendable {
    case malformed
    case duplicateKey(String)
    case inputTooLarge
    case depthExceeded
    case collectionElementsExceeded
    case scalarTooLarge
}

public enum BoundedJSONPreflight {
    public static func rejectDuplicateKeys(_ data: Data) throws {
        guard data.count <= ViaDefinitionLimits.maximumInputBytes else {
            throw BoundedJSONPreflightError.inputTooLarge
        }
        var scanner = Scanner(data)
        try scanner.parse()
    }
}

private struct Scanner {
    private let bytes: [UInt8]
    private var index = 0
    private var collectionElements = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func parse() throws {
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw BoundedJSONPreflightError.malformed }
    }

    private mutating func parseValue(depth: Int) throws {
        skipWhitespace()
        guard let byte = current else { throw BoundedJSONPreflightError.malformed }
        switch byte {
        case 0x7b: try parseObject(depth: depth + 1)
        case 0x5b: try parseArray(depth: depth + 1)
        case 0x22: _ = try parseString()
        case 0x2d, 0x30...0x39: try parseNumber()
        case 0x74: try parseLiteral("true")
        case 0x66: try parseLiteral("false")
        case 0x6e: try parseLiteral("null")
        default: throw BoundedJSONPreflightError.malformed
        }
    }

    private mutating func parseObject(depth: Int) throws {
        guard depth <= ViaDefinitionLimits.maximumDepth else {
            throw BoundedJSONPreflightError.depthExceeded
        }
        index += 1
        skipWhitespace()
        if consume(0x7d) { return }
        var keys = Set<String>()
        while true {
            guard current == 0x22 else { throw BoundedJSONPreflightError.malformed }
            let key = try parseString()
            guard keys.insert(key).inserted else { throw BoundedJSONPreflightError.duplicateKey(key) }
            skipWhitespace()
            guard consume(0x3a) else { throw BoundedJSONPreflightError.malformed }
            try incrementCollection()
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x7d) { return }
            guard consume(0x2c) else { throw BoundedJSONPreflightError.malformed }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        guard depth <= ViaDefinitionLimits.maximumDepth else {
            throw BoundedJSONPreflightError.depthExceeded
        }
        index += 1
        skipWhitespace()
        if consume(0x5d) { return }
        while true {
            try incrementCollection()
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x5d) { return }
            guard consume(0x2c) else { throw BoundedJSONPreflightError.malformed }
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
                guard index - start - 1 <= ViaDefinitionLimits.maximumScalarBytes else {
                    throw BoundedJSONPreflightError.scalarTooLarge
                }
                index += 1
                let token = Data(bytes[start..<index])
                guard let value = try? JSONDecoder().decode(String.self, from: token) else {
                    throw BoundedJSONPreflightError.malformed
                }
                return value
            }
            if !escaped && byte < 0x20 { throw BoundedJSONPreflightError.malformed }
            if escaped { escaped = false } else if byte == 0x5c { escaped = true }
            index += 1
            if index - start - 1 > ViaDefinitionLimits.maximumScalarBytes {
                throw BoundedJSONPreflightError.scalarTooLarge
            }
        }
        throw BoundedJSONPreflightError.malformed
    }

    private mutating func parseNumber() throws {
        let start = index
        if consume(0x2d), index == bytes.count { throw BoundedJSONPreflightError.malformed }
        if consume(0x30) {
            if let current, (0x30...0x39).contains(current) { throw BoundedJSONPreflightError.malformed }
        } else {
            try consumeDigits(required: true)
        }
        if consume(0x2e) { try consumeDigits(required: true) }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2b || current == 0x2d { index += 1 }
            try consumeDigits(required: true)
        }
        guard index - start <= ViaDefinitionLimits.maximumScalarBytes else {
            throw BoundedJSONPreflightError.scalarTooLarge
        }
    }

    private mutating func consumeDigits(required: Bool) throws {
        let start = index
        while let current, (0x30...0x39).contains(current) { index += 1 }
        if required && start == index { throw BoundedJSONPreflightError.malformed }
    }

    private mutating func parseLiteral(_ value: String) throws {
        let literal = Array(value.utf8)
        guard index + literal.count <= bytes.count,
              Array(bytes[index..<(index + literal.count)]) == literal else {
            throw BoundedJSONPreflightError.malformed
        }
        index += literal.count
    }

    private mutating func incrementCollection() throws {
        collectionElements += 1
        guard collectionElements <= ViaDefinitionLimits.maximumCollectionElements else {
            throw BoundedJSONPreflightError.collectionElementsExceeded
        }
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let current, current == 0x20 || current == 0x09 || current == 0x0a || current == 0x0d {
            index += 1
        }
    }
}

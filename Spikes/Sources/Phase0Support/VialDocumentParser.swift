import Foundation

public enum VialDocumentLimits {
    public static let maximumInputBytes = 8 * 1_024 * 1_024
    public static let maximumDepth = 64
    public static let maximumCollectionElements = 100_000
    public static let maximumScalarBytes = 1_024 * 1_024
}

public enum VialDocumentError: String, Error, Equatable, Codable, Sendable {
    case inputTooLarge
    case depthExceeded
    case collectionElementsExceeded
    case scalarTooLarge
    case malformedJSON
    case duplicateTopLevelKey
    case missingVersion
    case unsupportedVersion
    case missingUID
    case invalidUID
    case invalidLayout
    case nonStringLayoutSlot
    case invalidLayoutSlot
    case uidMismatch
}

public struct VialPatchPlan: Equatable, Sendable {
    public let bytes: Data
    public let originalRange: Range<Int>
    public let bytesOutsideSelectedSlotIdentical: Bool
}

public struct VialDocument: Sendable {
    public let version: Int
    public let uid: String
    private let bytes: Data
    private let members: [String: VialJSONNode]
    private let layout: [[[VialJSONNode]]]

    fileprivate init(version: Int, uid: String, bytes: Data, members: [String: VialJSONNode], layout: [[[VialJSONNode]]]) {
        self.version = version
        self.uid = uid
        self.bytes = bytes
        self.members = members
        self.layout = layout
    }

    public func rawSlice(named name: String) -> Data? {
        members[name].map { bytes.subdata(in: $0.range) }
    }

    public func layoutValue(layer: Int, row: Int, column: Int) -> String? {
        guard let node = slot(layer: layer, row: row, column: column) else { return nil }
        return node.stringValue
    }

    public func patchLayoutSlot(layer: Int, row: Int, column: Int, replacement: String, expectedUID: String) throws -> VialPatchPlan {
        guard uid == expectedUID else { throw VialDocumentError.uidMismatch }
        guard let node = slot(layer: layer, row: row, column: column) else { throw VialDocumentError.invalidLayoutSlot }
        guard replacement.utf8.count <= VialDocumentLimits.maximumScalarBytes else { throw VialDocumentError.scalarTooLarge }
        let encoded = try JSONEncoder().encode(replacement)
        guard encoded.count >= 2, encoded.count - 2 <= VialDocumentLimits.maximumScalarBytes else {
            throw VialDocumentError.scalarTooLarge
        }
        var candidate = Data()
        candidate.reserveCapacity(bytes.count - node.range.count + encoded.count)
        candidate.append(bytes[..<node.range.lowerBound])
        candidate.append(encoded)
        candidate.append(bytes[node.range.upperBound...])
        guard candidate.count <= VialDocumentLimits.maximumInputBytes else { throw VialDocumentError.inputTooLarge }
        let reparsed = try VialDocumentParser.parse(candidate)
        guard reparsed.uid == uid, reparsed.version == version else { throw VialDocumentError.malformedJSON }
        let candidateEnd = node.range.lowerBound + encoded.count
        let unchanged = bytes[..<node.range.lowerBound] == candidate[..<node.range.lowerBound]
            && bytes[node.range.upperBound...] == candidate[candidateEnd...]
        return VialPatchPlan(bytes: candidate, originalRange: node.range, bytesOutsideSelectedSlotIdentical: unchanged)
    }

    private func slot(layer: Int, row: Int, column: Int) -> VialJSONNode? {
        guard layer >= 0, layer < layout.count, row >= 0, row < layout[layer].count,
              column >= 0, column < layout[layer][row].count else { return nil }
        return layout[layer][row][column]
    }
}

public enum VialDocumentParser {
    public static func parse(_ data: Data) throws -> VialDocument {
        guard data.count <= VialDocumentLimits.maximumInputBytes else { throw VialDocumentError.inputTooLarge }
        var scanner = VialJSONScanner(data)
        let root = try scanner.parseRootObject()
        guard let versionNode = root["version"] else { throw VialDocumentError.missingVersion }
        guard versionNode.kind == .number,
              let version = Int(String(decoding: data[versionNode.range], as: UTF8.self)) else {
            throw VialDocumentError.unsupportedVersion
        }
        guard version == 1 else { throw VialDocumentError.unsupportedVersion }
        guard let uidNode = root["uid"] else { throw VialDocumentError.missingUID }
        let uid: String
        if uidNode.kind == .string, let value = uidNode.stringValue {
            uid = value
        } else if uidNode.kind == .number {
            uid = String(decoding: data[uidNode.range], as: UTF8.self)
        } else {
            throw VialDocumentError.invalidUID
        }
        guard !uid.isEmpty else { throw VialDocumentError.invalidUID }
        guard let layoutNode = root["layout"], layoutNode.kind == .array else { throw VialDocumentError.invalidLayout }
        let layout = try decodeLayout(layoutNode)
        return VialDocument(version: version, uid: uid, bytes: data, members: root, layout: layout)
    }

    private static func decodeLayout(_ node: VialJSONNode) throws -> [[[VialJSONNode]]] {
        try node.children.map { layer in
            guard layer.kind == .array else { throw VialDocumentError.invalidLayout }
            if layer.children.allSatisfy({ $0.kind == .string }) {
                return [layer.children]
            }
            if layer.children.allSatisfy({ $0.kind != .array }) {
                throw VialDocumentError.nonStringLayoutSlot
            }
            return try layer.children.map { row in
                guard row.kind == .array else { throw VialDocumentError.invalidLayout }
                return try row.children.map { slot in
                    guard slot.kind == .string else { throw VialDocumentError.nonStringLayoutSlot }
                    return slot
                }
            }
        }
    }
}

private enum VialJSONKind: Sendable { case object, array, string, number, literal }

private struct VialJSONNode: Sendable {
    let range: Range<Int>
    let kind: VialJSONKind
    let stringValue: String?
    let children: [VialJSONNode]
}

private struct VialJSONScanner {
    private let bytes: [UInt8]
    private var index = 0
    private var collectionElements = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func parseRootObject() throws -> [String: VialJSONNode] {
        skipWhitespace()
        guard current == 0x7b else { throw VialDocumentError.malformedJSON }
        let (_, members) = try parseObject(depth: 1, captureMembers: true)
        skipWhitespace()
        guard index == bytes.count else { throw VialDocumentError.malformedJSON }
        return members
    }

    private mutating func parseValue(depth: Int) throws -> VialJSONNode {
        skipWhitespace()
        let start = index
        guard let byte = current else { throw VialDocumentError.malformedJSON }
        switch byte {
        case 0x7b:
            let (children, _) = try parseObject(depth: depth + 1, captureMembers: false)
            return VialJSONNode(range: start..<index, kind: .object, stringValue: nil, children: children)
        case 0x5b:
            let children = try parseArray(depth: depth + 1)
            return VialJSONNode(range: start..<index, kind: .array, stringValue: nil, children: children)
        case 0x22:
            let value = try parseString()
            return VialJSONNode(range: start..<index, kind: .string, stringValue: value, children: [])
        case 0x2d, 0x30...0x39:
            try parseNumber()
            return VialJSONNode(range: start..<index, kind: .number, stringValue: nil, children: [])
        case 0x74: try parseLiteral("true")
        case 0x66: try parseLiteral("false")
        case 0x6e: try parseLiteral("null")
        default: throw VialDocumentError.malformedJSON
        }
        return VialJSONNode(range: start..<index, kind: .literal, stringValue: nil, children: [])
    }

    private mutating func parseObject(depth: Int, captureMembers: Bool) throws -> ([VialJSONNode], [String: VialJSONNode]) {
        guard depth <= VialDocumentLimits.maximumDepth else { throw VialDocumentError.depthExceeded }
        index += 1
        skipWhitespace()
        if consume(0x7d) { return ([], [:]) }
        var children: [VialJSONNode] = []
        var members: [String: VialJSONNode] = [:]
        while true {
            guard current == 0x22 else { throw VialDocumentError.malformedJSON }
            let key = try parseString()
            skipWhitespace()
            guard consume(0x3a) else { throw VialDocumentError.malformedJSON }
            try incrementCollection()
            let value = try parseValue(depth: depth)
            children.append(value)
            if captureMembers {
                guard members[key] == nil else { throw VialDocumentError.duplicateTopLevelKey }
                members[key] = value
            }
            skipWhitespace()
            if consume(0x7d) { return (children, members) }
            guard consume(0x2c) else { throw VialDocumentError.malformedJSON }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws -> [VialJSONNode] {
        guard depth <= VialDocumentLimits.maximumDepth else { throw VialDocumentError.depthExceeded }
        index += 1
        skipWhitespace()
        if consume(0x5d) { return [] }
        var children: [VialJSONNode] = []
        while true {
            try incrementCollection()
            children.append(try parseValue(depth: depth))
            skipWhitespace()
            if consume(0x5d) { return children }
            guard consume(0x2c) else { throw VialDocumentError.malformedJSON }
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
                guard index - start - 1 <= VialDocumentLimits.maximumScalarBytes else { throw VialDocumentError.scalarTooLarge }
                index += 1
                let token = Data(bytes[start..<index])
                guard let decoded = try? JSONDecoder().decode(String.self, from: token) else { throw VialDocumentError.malformedJSON }
                return decoded
            }
            if !escaped && byte < 0x20 { throw VialDocumentError.malformedJSON }
            if escaped { escaped = false } else if byte == 0x5c { escaped = true }
            index += 1
            if index - start - 1 > VialDocumentLimits.maximumScalarBytes { throw VialDocumentError.scalarTooLarge }
        }
        throw VialDocumentError.malformedJSON
    }

    private mutating func parseNumber() throws {
        let start = index
        if consume(0x2d), index == bytes.count { throw VialDocumentError.malformedJSON }
        if consume(0x30) {
            if let current, (0x30...0x39).contains(current) { throw VialDocumentError.malformedJSON }
        } else {
            try consumeDigits(required: true)
        }
        if consume(0x2e) { try consumeDigits(required: true) }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2b || current == 0x2d { index += 1 }
            try consumeDigits(required: true)
        }
        guard index - start <= VialDocumentLimits.maximumScalarBytes else { throw VialDocumentError.scalarTooLarge }
    }

    private mutating func consumeDigits(required: Bool) throws {
        let start = index
        while let current, (0x30...0x39).contains(current) { index += 1 }
        if required && start == index { throw VialDocumentError.malformedJSON }
    }

    private mutating func parseLiteral(_ value: String) throws {
        let literal = Array(value.utf8)
        guard index + literal.count <= bytes.count, Array(bytes[index..<(index + literal.count)]) == literal else {
            throw VialDocumentError.malformedJSON
        }
        index += literal.count
    }

    private mutating func incrementCollection() throws {
        collectionElements += 1
        guard collectionElements <= VialDocumentLimits.maximumCollectionElements else {
            throw VialDocumentError.collectionElementsExceeded
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

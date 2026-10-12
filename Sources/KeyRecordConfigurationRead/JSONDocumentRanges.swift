import Foundation

/// Ranges refer to the original UTF-8 bytes, so editing one subtree never serializes its neighbors.
public struct JSONDocumentRanges: Sendable {
    public struct Node: Sendable {
        public let range: Range<Int>
        public let members: [String: Node]
        public let elements: [Node]?
    }
    public let root: Node

    public init(_ data: Data) throws {
        try BoundedJSONPreflight.rejectDuplicateKeys(data)
        _ = try JSONSerialization.jsonObject(with: data)
        var reader = Reader(bytes: Array(data))
        root = try reader.value()
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        mutating func space() { while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 } }
        mutating func string() throws -> String {
            let start = offset
            offset += 1
            var escape = false
            while offset < bytes.count {
                let byte = bytes[offset]; offset += 1
                if escape { escape = false }
                else if byte == 92 { escape = true }
                else if byte == 34 {
                    let wrapped = Data([91]) + Data(bytes[start..<offset]) + Data([93])
                    guard let values = try JSONSerialization.jsonObject(with: wrapped) as? [String], let value = values.first else {
                        throw CocoaError(.propertyListReadCorrupt)
                    }
                    return value
                }
            }
            throw CocoaError(.propertyListReadCorrupt)
        }
        mutating func value() throws -> Node {
            space()
            let start = offset
            var members: [String: Node] = [:]
            var elements: [Node]?
            switch bytes[offset] {
            case 123:
                offset += 1; space()
                while bytes[offset] != 125 {
                    let key = try string(); space(); offset += 1
                    members[key] = try value(); space()
                    if bytes[offset] != 44 { break }
                    offset += 1; space()
                }
                offset += 1
            case 91:
                offset += 1; space(); elements = []
                while bytes[offset] != 93 {
                    elements?.append(try value()); space()
                    if bytes[offset] != 44 { break }
                    offset += 1; space()
                }
                offset += 1
            case 34: _ = try string()
            default:
                while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
            }
            return Node(range: start..<offset, members: members, elements: elements)
        }
    }
}

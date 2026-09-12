import Foundation

/// Architecture §5.1: each persisted top-level record carries an explicitly checked version.
public enum SchemaVersion: Int, Codable, Sendable {
    case v1 = 1

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Int.self)
        guard value == Self.v1.rawValue else { throw SchemaError.unsupportedVersion(value) }
        self = .v1
    }
}

struct FieldKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

func strictContainer<Key: CodingKey & CaseIterable>(
    _ decoder: any Decoder, keyedBy type: Key.Type
) throws -> KeyedDecodingContainer<Key> {
    let fields = try decoder.container(keyedBy: FieldKey.self)
    let unexpected = Set(fields.allKeys.map(\.stringValue)).subtracting(Key.allCases.map(\.stringValue))
    guard unexpected.isEmpty else { throw SchemaError.unknownFields(unexpected) }
    return try decoder.container(keyedBy: type)
}

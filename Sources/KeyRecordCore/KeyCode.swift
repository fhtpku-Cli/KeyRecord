import Foundation

/// Architecture §4.6: standard macOS virtual keys, including ANSI/ISO/JIS and function keys.
/// Numeric table follows Apple HIToolbox Events.h kVK constants; unassigned holes are rejected.
public struct KeyCode: Hashable, Codable, Sendable {
    public let value: Int

    public init(_ value: Int) throws {
        switch value {
        case 0...51, 53...65, 67, 69, 71...76, 78...107, 109...111, 113...126:
            self.value = value
        default:
            throw DomainError.invalidKeyCode(value)
        }
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

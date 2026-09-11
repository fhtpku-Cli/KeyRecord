import Foundation

public struct Count: Hashable, Codable, Sendable {
    public let value: Int64

    public init(_ value: Int64) throws {
        guard value >= 0 else { throw CountError.negative(value) }
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Int64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Architecture §§4.2, 5.1: ordinary means not suspected, NEVER proven authentic.
/// Total is derived only after checked addition; no caller-supplied total or wrapping fallback.
public struct SourceCounts: Equatable, Codable, Sendable {
    public let ordinary: Count
    public let suspectedInjection: Count
    public let total: Count

    public init(ordinary: Count, suspectedInjection: Count) throws {
        let (sum, overflow) = ordinary.value.addingReportingOverflow(suspectedInjection.value)
        guard !overflow else { throw CountError.overflow }
        self.ordinary = ordinary
        self.suspectedInjection = suspectedInjection
        self.total = try Count(sum)
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case ordinary, suspectedInjection }

    public init(from decoder: any Decoder) throws {
        let values = try strictContainer(decoder, keyedBy: CodingKeys.self)
        try self.init(ordinary: values.decode(Count.self, forKey: .ordinary),
                      suspectedInjection: values.decode(Count.self, forKey: .suspectedInjection))
    }
}

/// Architecture §§4.7, 6.2: encounter ordinal, not a sortable calendar date. Reducer owns advancement.
public struct ActiveDayOrdinal: Hashable, Codable, Sendable {
    public let value: Count
    public init(_ ordinal: Int64) throws { value = try Count(ordinal) }
    public init(from decoder: any Decoder) throws { value = try Count(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}

import Foundation

public struct CycleID: Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct KeyVersion: Hashable, Codable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
}

public struct LocalDay: Hashable, Codable, Sendable {
    public let label: String
    public init(_ label: String) { self.label = label }
}

/// Architecture §§3.2–3.3: consumers must use the injected calendar AND timeZone, never global defaults.
public protocol LocalClock: Sendable {
    var calendar: Calendar { get }
    var timeZone: TimeZone { get }
    func now() -> Date
}

public protocol CycleIDGenerator: Sendable {
    func nextCycleID() async -> CycleID
}

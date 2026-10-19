import Foundation

public struct ReleaseVersion: Equatable, Comparable, Sendable {
    private let parts: [Int]
    public init?(_ value: String) {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(fields.count), fields.allSatisfy({
            !$0.isEmpty && $0.count <= 9 && $0.allSatisfy { $0.isASCII && $0.isNumber }
                && ($0 == "0" || !$0.hasPrefix("0"))
        }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count else { return nil }
        parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public struct AvailableRelease: Equatable, Sendable {
    public let tag: String
    public let version: ReleaseVersion
    public init?(tag: String) {
        let number = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let version = ReleaseVersion(number) else { return nil }
        self.tag = tag; self.version = version
    }
}

public enum ReleaseUpdateError: Error { case invalidResponse, invalidVersion }

public enum ReleaseUpdate {
    public static let interval: TimeInterval = 7 * 24 * 60 * 60
    public static func isDue(now: Date, lastAttempt: Date?) -> Bool {
        guard let lastAttempt else { return true }
        return now < lastAttempt || now.timeIntervalSince(lastAttempt) >= interval
    }
    public static func parse(_ data: Data) throws -> AvailableRelease {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let draft = value["draft"] as? NSNumber, CFGetTypeID(draft) == CFBooleanGetTypeID(), !draft.boolValue,
              let prerelease = value["prerelease"] as? NSNumber, CFGetTypeID(prerelease) == CFBooleanGetTypeID(), !prerelease.boolValue,
              let tag = value["tag_name"] as? String, let release = AvailableRelease(tag: tag) else {
            throw ReleaseUpdateError.invalidResponse
        }
        return release
    }
}

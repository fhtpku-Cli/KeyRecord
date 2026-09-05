import Foundation

public enum VialSourceContract {
    public static let expectedCases = ["protocolVersion", "uid", "definition", "keymapRead"]

    public static func validate(_ source: String) throws -> [String] {
        guard let start = source.range(of: "public enum VialQuery: Equatable, Sendable {")?.upperBound,
              let end = source[start...].range(of: "\n}")?.lowerBound else {
            throw VialQueryError.invalidQuery
        }
        let body = source[start..<end]
        let cases = body.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { return nil }
            return String(trimmed.dropFirst(5).prefix { $0 != "(" })
        }
        guard cases == expectedCases,
              !source.contains("public init(bytes:"),
              !body.contains("write"), !body.contains("unlock"), !body.contains("reset"),
              !body.contains("bootloader"), !body.contains("macro") else {
            throw VialQueryError.invalidQuery
        }
        return cases
    }
}

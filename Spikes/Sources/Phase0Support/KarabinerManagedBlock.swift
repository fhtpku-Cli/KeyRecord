import Foundation

public enum KarabinerManagedBlock {
    public static let startDescription = "KeyRecord managed block start"
    public static let endDescription = "KeyRecord managed block end"
}

public enum KarabinerManagedBlockError: String, Error, Equatable, Sendable {
    case baselineMismatch
    case inputTooLarge
    case nestingTooDeep
    case invalidJSON
    case invalidSchema
    case malformedManagedBlock
    case multipleRulesArrays
    case invalidRule
}

public struct KarabinerManagedBlockInspection: Equatable, Sendable {
    public let rulesArrayRange: Range<Int>
    public let managedRange: Range<Int>?
    public let managedRuleCount: Int
}

public struct KarabinerManagedBlockPlan: Equatable, Sendable {
    public let base: Data
    public let bytes: Data
    public let baselineSHA256: String
    public let expectedSHA256: String
    public let replacementRange: Range<Int>
    public let ruleCount: Int
}

public enum KarabinerManagedBlockPlanner {
    public static let maximumBytes = 1_048_576
    public static let maximumDepth = 64

    public static func inspect(_ bytes: Data) throws -> KarabinerManagedBlockInspection {
        guard bytes.count <= maximumBytes else { throw KarabinerManagedBlockError.inputTooLarge }
        try validateDepth(bytes)
        guard let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              root["title"] is String, let rules = root["rules"] as? [Any] else {
            if (try? JSONSerialization.jsonObject(with: bytes)) == nil { throw KarabinerManagedBlockError.invalidJSON }
            throw KarabinerManagedBlockError.invalidSchema
        }
        var scanner = JSONRangeScanner(bytes)
        let located = try scanner.topLevelArray(named: "rules")
        guard scanner.matchCount == 1 else { throw KarabinerManagedBlockError.multipleRulesArrays }
        let descriptions = try located.elements.map { range -> String? in
            guard let object = try JSONSerialization.jsonObject(with: bytes.subdata(in: range)) as? [String: Any] else { return nil }
            return object["description"] as? String
        }
        let starts = descriptions.indices.filter { descriptions[$0] == KarabinerManagedBlock.startDescription }
        let ends = descriptions.indices.filter { descriptions[$0] == KarabinerManagedBlock.endDescription }
        guard starts.count == ends.count, starts.count <= 1 else { throw KarabinerManagedBlockError.malformedManagedBlock }
        for rule in rules {
            guard let object = rule as? [String: Any], let description = object["description"] as? String,
                  let manipulators = object["manipulators"] as? [Any],
                  !manipulators.isEmpty || description == KarabinerManagedBlock.startDescription || description == KarabinerManagedBlock.endDescription else {
                if starts.count != ends.count || starts.count == 1 { throw KarabinerManagedBlockError.malformedManagedBlock }
                throw KarabinerManagedBlockError.invalidSchema
            }
        }
        guard let start = starts.first else {
            return KarabinerManagedBlockInspection(rulesArrayRange: located.array, managedRange: nil, managedRuleCount: 0)
        }
        guard let end = ends.first, end > start else { throw KarabinerManagedBlockError.malformedManagedBlock }
        let range = located.elements[start].lowerBound..<located.elements[end].upperBound
        return KarabinerManagedBlockInspection(rulesArrayRange: located.array, managedRange: range, managedRuleCount: end - start - 1)
    }

    public static func plan(base: Data, baselineSHA256: String, rules: [Data]) throws -> KarabinerManagedBlockPlan {
        guard AtomicityDigest.sha256(base) == baselineSHA256 else { throw KarabinerManagedBlockError.baselineMismatch }
        let inspection = try inspect(base)
        for rule in rules { try validateRule(rule) }
        let block = makeBlock(rules)
        let replacement: Range<Int>
        let inserted: Data
        if let existing = inspection.managedRange {
            replacement = existing
            inserted = block
        } else {
            let closingBracket = inspection.rulesArrayRange.upperBound - 1
            replacement = closingBracket..<closingBracket
            let hasElements = inspection.rulesArrayRange.count > 2 && !base.subdata(in: (inspection.rulesArrayRange.lowerBound + 1)..<closingBracket)
                .allSatisfy { [9, 10, 13, 32].contains($0) }
            inserted = Data((hasElements ? ",\n        " : "\n        ").utf8) + block + Data("\n    ".utf8)
        }
        var output = Data()
        output.append(base.prefix(replacement.lowerBound))
        output.append(inserted)
        output.append(base.suffix(base.count - replacement.upperBound))
        _ = try inspect(output)
        return KarabinerManagedBlockPlan(
            base: base, bytes: output, baselineSHA256: baselineSHA256,
            expectedSHA256: AtomicityDigest.sha256(output), replacementRange: replacement, ruleCount: rules.count
        )
    }

    private static func validateRule(_ bytes: Data) throws {
        guard bytes.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let description = object["description"] as? String,
              description != KarabinerManagedBlock.startDescription, description != KarabinerManagedBlock.endDescription,
              let manipulators = object["manipulators"] as? [Any], !manipulators.isEmpty else {
            throw KarabinerManagedBlockError.invalidRule
        }
    }

    private static func makeBlock(_ rules: [Data]) -> Data {
        let start = Data(#"{"description":"KeyRecord managed block start","manipulators":[]}"#.utf8)
        let end = Data(#"{"description":"KeyRecord managed block end","manipulators":[]}"#.utf8)
        return ([start] + rules + [end]).enumerated().reduce(into: Data()) { result, item in
            if item.offset > 0 { result.append(Data(",\n        ".utf8)) }
            result.append(item.element)
        }
    }

    private static func validateDepth(_ bytes: Data) throws {
        var depth = 0, inString = false, escaped = false
        for byte in bytes {
            if inString {
                if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true
            } else if byte == 91 || byte == 123 { depth += 1; if depth > maximumDepth { throw KarabinerManagedBlockError.nestingTooDeep }
            } else if byte == 93 || byte == 125 { depth -= 1; if depth < 0 { throw KarabinerManagedBlockError.invalidJSON } }
        }
        guard depth == 0, !inString else { throw KarabinerManagedBlockError.invalidJSON }
    }
}

public enum KarabinerRecovery: String, Codable, Equatable, Sendable {
    case finishCommit
    case markFailedNoWrite
    case externalChangeRefusal
    case rollbackBeforeImage

    public static func classify(currentSHA256: String, hBase: String, hExpect: String, rollbackRequested: Bool) -> Self {
        if currentSHA256 == hExpect { return rollbackRequested ? .rollbackBeforeImage : .finishCommit }
        if currentSHA256 == hBase { return .markFailedNoWrite }
        return .externalChangeRefusal
    }

    public func bytesToWrite(beforeImage: Data) -> Data? { self == .rollbackBeforeImage ? beforeImage : nil }
}

public struct KarabinerVersionGate: Equatable, Sendable {
    public let version: String?
    public let sampledSupported: Bool
    public init(version: String?, sampledSupported: Bool = false) { self.version = version; self.sampledSupported = sampledSupported }
    public var writeSupported: Bool { parsed != nil && sampledSupported }
    public var supportsDescriptionNotes: Bool {
        guard let parsed else { return false }
        return !parsed.lexicographicallyPrecedes([16, 1, 23])
    }
    private var parsed: [Int]? {
        guard let version, version != "unknown" else { return nil }
        let parts = version.split(separator: ".").map(String.init)
        guard parts.count == 3, let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        return [major, minor, patch]
    }
}

private struct JSONRangeScanner {
    let bytes: [UInt8]
    var index = 0
    var matchCount = 0
    init(_ data: Data) { bytes = Array(data) }

    mutating func topLevelArray(named wanted: String) throws -> (array: Range<Int>, elements: [Range<Int>]) {
        skipSpace(); guard take(123) else { throw KarabinerManagedBlockError.invalidJSON }
        var found: (Range<Int>, [Range<Int>])?
        skipSpace()
        while !take(125) {
            let key = try string(); skipSpace(); guard take(58) else { throw KarabinerManagedBlockError.invalidJSON }; skipSpace()
            if key == wanted, peek == 91 {
                matchCount += 1
                let value = try arrayRanges()
                if found == nil { found = value }
            } else { _ = try value(depth: 1) }
            skipSpace(); if take(125) { break }; guard take(44) else { throw KarabinerManagedBlockError.invalidJSON }; skipSpace()
        }
        skipSpace(); guard index == bytes.count, let found else { throw KarabinerManagedBlockError.invalidSchema }
        return found
    }

    mutating func arrayRanges() throws -> (Range<Int>, [Range<Int>]) {
        let start = index; guard take(91) else { throw KarabinerManagedBlockError.invalidJSON }; skipSpace()
        var elements: [Range<Int>] = []
        while !take(93) {
            elements.append(try value(depth: 1)); skipSpace()
            if take(93) { break }; guard take(44) else { throw KarabinerManagedBlockError.invalidJSON }; skipSpace()
        }
        return (start..<index, elements)
    }

    mutating func value(depth: Int) throws -> Range<Int> {
        guard depth <= KarabinerManagedBlockPlanner.maximumDepth else { throw KarabinerManagedBlockError.nestingTooDeep }
        skipSpace(); let start = index
        switch peek {
        case 34: _ = try string()
        case 123:
            _ = take(123); skipSpace()
            while !take(125) { _ = try string(); skipSpace(); guard take(58) else { throw KarabinerManagedBlockError.invalidJSON }; _ = try value(depth: depth + 1); skipSpace(); if take(125) { break }; guard take(44) else { throw KarabinerManagedBlockError.invalidJSON }; skipSpace() }
        case 91:
            _ = take(91); skipSpace()
            while !take(93) { _ = try value(depth: depth + 1); skipSpace(); if take(93) { break }; guard take(44) else { throw KarabinerManagedBlockError.invalidJSON }; skipSpace() }
        default:
            while let byte = peek, ![9, 10, 13, 32, 44, 93, 125].contains(byte) { index += 1 }
            guard index > start else { throw KarabinerManagedBlockError.invalidJSON }
        }
        return start..<index
    }

    mutating func string() throws -> String {
        let start = index; guard take(34) else { throw KarabinerManagedBlockError.invalidJSON }
        var escaped = false
        while let byte = peek {
            index += 1
            if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 {
                let data = Data(bytes[start..<index]); guard let value = try? JSONSerialization.jsonObject(with: Data("[".utf8) + data + Data("]".utf8)) as? [String], let first = value.first else { throw KarabinerManagedBlockError.invalidJSON }
                return first
            }
        }
        throw KarabinerManagedBlockError.invalidJSON
    }
    mutating func skipSpace() { while let byte = peek, [9, 10, 13, 32].contains(byte) { index += 1 } }
    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
    mutating func take(_ byte: UInt8) -> Bool { guard peek == byte else { return false }; index += 1; return true }
}

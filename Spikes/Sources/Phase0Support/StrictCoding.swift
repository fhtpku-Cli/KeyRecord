import Foundation

public enum EvidenceModelError: Error, Equatable, CustomStringConvertible {
    case unknownFields(type: String, fields: [String])
    case invalidSHA256(field: String)
    case unsupportedPassWithoutArtifactHash(legID: String)
    case invalidBlocker(field: String)
    case unknownLegID(String)
    case invalidVerdictSemantics(legID: String)

    public var description: String {
        switch self {
        case let .unknownFields(type, fields):
            return "unknown fields for \(type): \(fields.joined(separator: ","))"
        case let .invalidSHA256(field):
            return "invalid SHA-256 in \(field)"
        case let .unsupportedPassWithoutArtifactHash(legID):
            return "PASS leg \(legID) requires at least one artifact hash"
        case let .invalidBlocker(field):
            return "blocker requires nonempty \(field)"
        case let .unknownLegID(legID):
            return "unknown experiment leg ID: \(legID)"
        case let .invalidVerdictSemantics(legID):
            return "verdict execution semantics are inconsistent for \(legID)"
        }
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

extension Decoder {
    func rejectUnknownKeys<K: StrictCodingKeys>(_ known: K.Type, typeName: String) throws {
        let knownKeys = Set(known.allCases.map(\.stringValue))
        let container = try self.container(keyedBy: DynamicCodingKey.self)
        let unknown = container.allKeys.map(\.stringValue).filter { !knownKeys.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw EvidenceModelError.unknownFields(type: typeName, fields: unknown)
        }
    }
}

protocol StrictCodingKeys: CodingKey, CaseIterable {}

extension String {
    var isLowercaseSHA256: Bool {
        utf8.count == 64 && utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    var isLowercaseGitSHA1: Bool {
        utf8.count == 40 && utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

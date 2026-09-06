import Foundation
import Phase0Support

public struct ValidatorError: Error, Equatable, CustomStringConvertible, Sendable {
    public let code: String
    public let detail: String

    public init(_ code: String, _ detail: String = "") {
        self.code = code
        self.detail = detail
    }

    public var description: String {
        detail.isEmpty ? code : "\(code): \(detail)"
    }
}

enum ValidatorDecoding {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, malformedCode: String) throws -> T {
        do {
            if malformedCode == "malformed_conclusions" {
                try BoundedJSONPreflight.rejectDuplicateKeys(data)
            }
            return try JSONDecoder().decode(type, from: data)
        } catch let error as BoundedJSONPreflightError {
            switch error {
            case let .duplicateKey(key): throw ValidatorError("duplicate_json_key", key)
            default: throw ValidatorError(malformedCode, String(describing: error))
            }
        } catch let error as EvidenceModelError {
            switch error {
            case .invalidBlocker:
                throw ValidatorError("incomplete_blocker", error.description)
            case .invalidSHA256:
                throw ValidatorError(malformedCode == "malformed_receipt" ? malformedCode : "invalid_provenance", error.description)
            case .unknownFields:
                throw ValidatorError(malformedCode, error.description)
            case .unsupportedPassWithoutArtifactHash:
                throw ValidatorError("unsupported_pass", error.description)
            case .unknownLegID:
                throw ValidatorError("unknown_leg_id", error.description)
            case .invalidVerdictSemantics:
                throw ValidatorError("invalid_verdict_semantics", error.description)
            }
        } catch {
            throw ValidatorError(malformedCode, String(describing: error))
        }
    }
}

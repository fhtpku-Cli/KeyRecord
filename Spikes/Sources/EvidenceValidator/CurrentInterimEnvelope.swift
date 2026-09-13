import Foundation
import Phase0Support

// Task 15 interim candidate receipt label. Task 4's bind-current produces the
// candidate snapshot; this envelope marks it as an INTERIM baseline that later
// commits (task 25 final freeze) must supersede. It binds the candidate, the
// readiness projection and the status table by content hash and refuses any
// final-certification wording.
struct CurrentInterimEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let kind: String
    let generatedAt: String
    let supersededAfterLaterCommits: Bool
    let finalFreeze: Bool
    let finalFreezeTask: Int
    let candidateSha256: String
    let readinessSha256: String
    let statusTableSha256: String
}

enum CurrentInterimEnvelopeGenerator {
    static let kind = "interim_current_candidate"
    static let schemaVersion = 1
    static let finalFreezeTask = 25

    static func generate(candidateBytes: Data, readinessBytes: Data, statusTableBytes: Data, generatedAt: String) throws -> CurrentInterimEnvelope {
        let candidate = try ReadinessDecoding.decode(CurrentCandidate.self, from: candidateBytes)
        let readinessHash = Canonical.sha256(readinessBytes)
        guard candidate.readiness.sha256 == readinessHash else { throw ValidatorError("interim_readiness_mismatch") }
        let table = try ReadinessDecoding.decode(CurrentStatusTable.self, from: statusTableBytes)
        guard table.readiness.sha256 == readinessHash else { throw ValidatorError("interim_table_readiness_mismatch") }
        guard table.finalFreeze == false, table.complete == false else { throw ValidatorError("interim_final_freeze_forbidden") }
        guard ISO8601DateFormatter().date(from: generatedAt) != nil else { throw ValidatorError("interim_invalid_generated_at", generatedAt) }
        return CurrentInterimEnvelope(schemaVersion: schemaVersion, kind: kind, generatedAt: generatedAt,
                                      supersededAfterLaterCommits: true, finalFreeze: false, finalFreezeTask: finalFreezeTask,
                                      candidateSha256: Canonical.sha256(candidateBytes),
                                      readinessSha256: readinessHash,
                                      statusTableSha256: Canonical.sha256(statusTableBytes))
    }
}

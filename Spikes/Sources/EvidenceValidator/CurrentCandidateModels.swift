import Foundation

enum CurrentCandidateReason: String, Codable, Sendable {
    case missingInput = "missing_input"
    case malformedInput = "malformed_input"
    case dirtyWorktree = "dirty_worktree"
    case staleState = "stale_state"
    case unsafePath = "unsafe_path"
    case outputReused = "output_reused"
}

struct CurrentCandidateError: Error, Sendable {
    let reason: CurrentCandidateReason
    let detail: String
    init(_ reason: CurrentCandidateReason, _ detail: String = "") {
        self.reason = reason; self.detail = detail
    }
    var exitStatus: Int32 {
        switch reason {
        case .missingInput: 2
        case .malformedInput, .dirtyWorktree, .staleState, .unsafePath, .outputReused: 1
        }
    }
}

struct CurrentCandidate: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let commitSha: String
    let treeSha: String
    let trackedFilesDigest: String
    let plan: ReadinessFileBinding
    let readiness: ReadinessFileBinding
    let evidence: [ReadinessFileBinding]
    let missingEvidencePaths: [String]
    let qaRegistry: ReadinessFileBinding

    var identity: String { get throws { Canonical.sha256(try Canonical.encode(self)) } }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, commitSha, treeSha, trackedFilesDigest, plan, readiness, evidence, missingEvidencePaths, qaRegistry
    }
    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: CurrentCandidateKey.self).allKeys.map(\.stringValue)
        guard Set(keys) == Set(CodingKeys.allCases.map(\.stringValue)) else { throw CurrentCandidateError(.malformedInput) }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw CurrentCandidateError(.malformedInput) }
        commitSha = try c.decode(String.self, forKey: .commitSha)
        treeSha = try c.decode(String.self, forKey: .treeSha)
        trackedFilesDigest = try c.decode(String.self, forKey: .trackedFilesDigest)
        plan = try c.decode(ReadinessFileBinding.self, forKey: .plan)
        readiness = try c.decode(ReadinessFileBinding.self, forKey: .readiness)
        evidence = try c.decode([ReadinessFileBinding].self, forKey: .evidence)
        missingEvidencePaths = try c.decode([String].self, forKey: .missingEvidencePaths)
        qaRegistry = try c.decode(ReadinessFileBinding.self, forKey: .qaRegistry)
    }

    init(commit: String, tree: String, trackedDigest: String, inputs: CurrentCandidateInputs) {
        schemaVersion = 1; commitSha = commit; treeSha = tree; trackedFilesDigest = trackedDigest
        plan = inputs.plan; readiness = inputs.readiness; evidence = inputs.evidence
        missingEvidencePaths = inputs.missingEvidencePaths; qaRegistry = inputs.qaRegistry
    }
}

struct CurrentCandidateInputs {
    let plan: ReadinessFileBinding
    let readiness: ReadinessFileBinding
    let evidence: [ReadinessFileBinding]
    let missingEvidencePaths: [String]
    let qaRegistry: ReadinessFileBinding
}

private struct CurrentCandidateKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

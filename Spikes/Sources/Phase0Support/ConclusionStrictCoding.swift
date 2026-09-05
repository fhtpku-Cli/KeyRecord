import Foundation

private protocol ConclusionStrictKeys: CodingKey, CaseIterable {}

private extension Decoder {
    func rejectConclusionUnknownKeys<K: ConclusionStrictKeys>(_ keys: K.Type, _ type: String) throws {
        let known = Set(keys.allCases.map(\.stringValue))
        let values = try container(keyedBy: ConclusionDynamicKey.self)
        let unknown = values.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else { throw EvidenceModelError.unknownFields(type: type, fields: unknown) }
    }
}

private struct ConclusionDynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension ConclusionEvidenceBinding {
    enum CodingKeys: String, CodingKey, CaseIterable, ConclusionStrictKeys { case path, sha256, manifestPath = "manifest_path", manifestSha256 = "manifest_sha256" }
    public init(from decoder: Decoder) throws {
        try decoder.rejectConclusionUnknownKeys(CodingKeys.self, "ConclusionEvidenceBinding")
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(path: try value.decode(String.self, forKey: .path), sha256: try value.decode(String.self, forKey: .sha256), manifestPath: try value.decode(String.self, forKey: .manifestPath), manifestSha256: try value.decode(String.self, forKey: .manifestSha256))
    }
}

extension ValidatedSpikeConclusion {
    enum CodingKeys: String, CodingKey, CaseIterable, ConclusionStrictKeys {
        case id, verdict, evidence, runnerCommitSha = "runner_commit_sha", runnerTreeSha = "runner_tree_sha", passCount = "pass_count", blockedCount = "blocked_count", inconclusiveCount = "inconclusive_count", failCount = "fail_count", limitations, rerunArgv = "rerun_argv", dependencyFrozen = "dependency_frozen"
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectConclusionUnknownKeys(CodingKeys.self, "ValidatedSpikeConclusion")
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try value.decode(String.self, forKey: .id), verdict: try value.decode(Verdict.self, forKey: .verdict), evidence: try value.decode(ConclusionEvidenceBinding.self, forKey: .evidence), runnerCommitSha: try value.decode(String.self, forKey: .runnerCommitSha), runnerTreeSha: try value.decode(String.self, forKey: .runnerTreeSha), passCount: try value.decode(Int.self, forKey: .passCount), blockedCount: try value.decode(Int.self, forKey: .blockedCount), inconclusiveCount: try value.decode(Int.self, forKey: .inconclusiveCount), failCount: try value.decode(Int.self, forKey: .failCount), limitations: try value.decode([String].self, forKey: .limitations), rerunArgv: try value.decode([String].self, forKey: .rerunArgv), dependencyFrozen: try value.decode(Bool.self, forKey: .dependencyFrozen))
    }
}

extension ValidatedOItemDisposition {
    enum CodingKeys: String, CodingKey, CaseIterable, ConclusionStrictKeys { case id, status, evidencePaths = "evidence_paths", blockerRefs = "blocker_refs", semantics }
    public init(from decoder: Decoder) throws {
        try decoder.rejectConclusionUnknownKeys(CodingKeys.self, "ValidatedOItemDisposition")
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try value.decode(String.self, forKey: .id), status: try value.decode(String.self, forKey: .status), evidencePaths: try value.decode([String].self, forKey: .evidencePaths), blockerRefs: try value.decode([String].self, forKey: .blockerRefs), semantics: try value.decode(String.self, forKey: .semantics))
    }
}

extension ValidatedO4Row {
    enum CodingKeys: String, CodingKey, CaseIterable, ConclusionStrictKeys { case id, evidencePath = "evidence_path", evidenceSha256 = "evidence_sha256", blockedRef = "blocked_ref" }
    public init(from decoder: Decoder) throws {
        try decoder.rejectConclusionUnknownKeys(CodingKeys.self, "ValidatedO4Row")
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try value.decode(String.self, forKey: .id), evidencePath: try value.decodeIfPresent(String.self, forKey: .evidencePath), evidenceSha256: try value.decodeIfPresent(String.self, forKey: .evidenceSha256), blockedRef: try value.decodeIfPresent(String.self, forKey: .blockedRef))
    }
}

extension ValidatedDownstreamBlock {
    enum CodingKeys: String, CodingKey, CaseIterable, ConclusionStrictKeys { case id, blockedCapability = "blocked_capability", causedBy = "caused_by", artifactRefs = "artifact_refs", rerunArgv = "rerun_argv" }
    public init(from decoder: Decoder) throws {
        try decoder.rejectConclusionUnknownKeys(CodingKeys.self, "ValidatedDownstreamBlock")
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try value.decode(String.self, forKey: .id), blockedCapability: try value.decode(String.self, forKey: .blockedCapability), causedBy: try value.decode([String].self, forKey: .causedBy), artifactRefs: try value.decode([String].self, forKey: .artifactRefs), rerunArgv: try value.decode([[String]].self, forKey: .rerunArgv))
    }
}

extension ValidatedG0 {
    enum CodingKeys: String, CodingKey, CaseIterable, ConclusionStrictKeys { case status, reasons, blockingLegIDs = "blocking_leg_ids", candidateSelection = "candidate_selection" }
    public init(from decoder: Decoder) throws {
        try decoder.rejectConclusionUnknownKeys(CodingKeys.self, "ValidatedG0")
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(status: try value.decode(G0Status.self, forKey: .status), reasons: try value.decode([String].self, forKey: .reasons), blockingLegIDs: try value.decode([String].self, forKey: .blockingLegIDs), candidateSelection: try value.decodeIfPresent(String.self, forKey: .candidateSelection))
    }
}

extension Phase0Conclusions {
    enum CodingKeys: String, CodingKey, CaseIterable, ConclusionStrictKeys {
        case schemaVersion = "schema_version", sourceEvidenceCommitSha = "source_evidence_commit_sha", sourceEvidenceTreeSha = "source_evidence_tree_sha", sourceRootManifestSha256 = "source_root_manifest_sha256", generatorCommitSha = "generator_commit_sha", generatorTreeSha = "generator_tree_sha", generatorSourceSha256 = "generator_source_sha256", spikes, oItems = "o_items", o4Matrix = "o4_matrix", downstreamBlocks = "downstream_blocks", g0
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectConclusionUnknownKeys(CodingKeys.self, "Phase0Conclusions")
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(schemaVersion: try value.decode(Int.self, forKey: .schemaVersion), sourceEvidenceCommitSha: try value.decode(String.self, forKey: .sourceEvidenceCommitSha), sourceEvidenceTreeSha: try value.decode(String.self, forKey: .sourceEvidenceTreeSha), sourceRootManifestSha256: try value.decode(String.self, forKey: .sourceRootManifestSha256), generatorCommitSha: try value.decode(String.self, forKey: .generatorCommitSha), generatorTreeSha: try value.decode(String.self, forKey: .generatorTreeSha), generatorSourceSha256: try value.decode([String: String].self, forKey: .generatorSourceSha256), spikes: try value.decode([ValidatedSpikeConclusion].self, forKey: .spikes), oItems: try value.decode([ValidatedOItemDisposition].self, forKey: .oItems), o4Matrix: try value.decode([ValidatedO4Row].self, forKey: .o4Matrix), downstreamBlocks: try value.decode([ValidatedDownstreamBlock].self, forKey: .downstreamBlocks), g0: try value.decode(ValidatedG0.self, forKey: .g0))
    }
}

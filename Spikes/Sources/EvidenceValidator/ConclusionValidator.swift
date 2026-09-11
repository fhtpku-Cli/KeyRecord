import Foundation
import Phase0Support

public struct ConclusionValidationReport: Equatable, Sendable {
    public let spikeCount: Int
    public let oItemCount: Int
    public let o4RowCount: Int
    public let downstreamBlockCount: Int
    public let g0Status: G0Status
}

public enum ConclusionValidator {
    public static func validate(root: URL, repository: URL, strictRepositoryBinding: Bool = false) throws -> ConclusionValidationReport {
        try validateMembership(root)
        try validateManifest(root)
        let url = root.appendingPathComponent("conclusions.json")
        let data = try Data(contentsOf: url)
        let document: Phase0Conclusions
        do { document = try ValidatorDecoding.decode(Phase0Conclusions.self, from: data, malformedCode: "malformed_conclusions") }
        catch let error as ValidatorError { throw error }
        catch { throw ValidatorError("malformed_conclusions", String(describing: error)) }
        try validateHistoricalSource(document, root: root, repository: repository, strictRepositoryBinding: strictRepositoryBinding)
        try validateVialDefinitionSchema(document, root: root, repository: repository)
        let expected = try ConclusionGenerator.derive(
            root: root,
            repository: repository,
            strictRepositoryBinding: strictRepositoryBinding,
            sourceManifestSha256: document.sourceRootManifestSha256,
            sourceCommitSha: document.sourceEvidenceCommitSha,
            sourceTreeSha: document.sourceEvidenceTreeSha,
            bindingCommitSha: strictRepositoryBinding ? document.generatorCommitSha : nil,
            bindingTreeSha: strictRepositoryBinding ? document.generatorTreeSha : nil
        )
        guard document == expected else { throw ValidatorError("conclusion_recompute_mismatch") }
        if strictRepositoryBinding { try validateUnderlyingSpikes(root: root, repository: repository) }
        try validateSemantics(document, root: root)
        for spike in document.spikes {
            let markdownURL = root.appendingPathComponent("\(spike.id)-CONCLUSION.md")
            guard try Data(contentsOf: markdownURL) == Data(ConclusionGenerator.renderMarkdown(spike).utf8) else {
                throw ValidatorError("conclusion_markdown_mismatch", spike.id)
            }
        }
        try validateRunReceipt(root)
        try validatePrivacy(root)
        return ConclusionValidationReport(spikeCount: document.spikes.count, oItemCount: document.oItems.count, o4RowCount: document.o4Matrix.count, downstreamBlockCount: document.downstreamBlocks.count, g0Status: document.g0.status)
    }

    private static func validateSemantics(_ document: Phase0Conclusions, root: URL) throws {
        guard document.schemaVersion == 1,
              document.spikes.map(\.id) == ConclusionContract.spikeIDs,
              document.oItems.map(\.id) == ConclusionContract.oItemIDs,
              document.o4Matrix.map(\.id) == ConclusionContract.o4IDs,
              document.downstreamBlocks.map(\.id) == ConclusionContract.downstreamBlockIDs else {
            throw ValidatorError("conclusion_set_mismatch")
        }
        for spike in document.spikes {
            guard !spike.limitations.isEmpty, !spike.rerunArgv.isEmpty,
                  spike.passCount + spike.blockedCount + spike.inconclusiveCount + spike.failCount > 0,
                  !spike.dependencyFrozen else { throw ValidatorError("invalid_spike_conclusion", spike.id) }
            try bind(spike.evidence.path, spike.evidence.sha256, root: root)
            try bind(spike.evidence.manifestPath, spike.evidence.manifestSha256, root: root)
        }
        let sp2Pass = document.spikes.first(where: { $0.id == "SP-2" })?.verdict == .pass
        let o6Status = document.oItems.first(where: { $0.id == "O6" })?.status
        guard (o6Status == "OPEN" && !sp2Pass) || (o6Status == "RESOLVED" && sp2Pass) else { throw ValidatorError("o6_closed_without_sp2") }
        guard document.oItems.first(where: { $0.id == "O7" })?.semantics.contains("Fail closed") == true else { throw ValidatorError("privacy_semantics_weakened") }
        for row in document.o4Matrix {
            let evidence = row.evidencePath != nil && row.evidenceSha256 != nil && row.blockedRef == nil
            let blocked = row.evidencePath == nil && row.evidenceSha256 == nil && row.blockedRef != nil
            guard evidence != blocked else { throw ValidatorError("invalid_o4_xor", row.id) }
            if let path = row.evidencePath, let hash = row.evidenceSha256 { try bind(path, hash, root: root) }
        }
        let sp1Pass = document.spikes.first(where: { $0.id == "SP-1" })?.verdict == .pass
        if document.g0.status == .passed {
            guard sp1Pass, sp2Pass, document.g0.blockingLegIDs.isEmpty, document.g0.reasons.isEmpty,
                  document.g0.candidateSelection != nil, document.g0.candidateSelection?.isEmpty == false else {
                throw ValidatorError("g0_unearned_passed")
            }
        } else {
            guard document.g0.status == .open, document.g0.candidateSelection == nil, !document.g0.blockingLegIDs.isEmpty else {
                throw ValidatorError("g0_forced_passed")
            }
        }
        guard document.downstreamBlocks.allSatisfy({ !$0.causedBy.isEmpty && !$0.artifactRefs.isEmpty && !$0.rerunArgv.isEmpty && $0.rerunArgv.allSatisfy { !$0.isEmpty && $0.allSatisfy { !$0.isEmpty } } }) else { throw ValidatorError("incomplete_downstream_block") }
        let forbidden = document.spikes.flatMap(\.limitations).joined(separator: " ").lowercased()
        guard !forbidden.contains("official importer compatible") && !forbidden.contains("device compatible") else { throw ValidatorError("unsupported_compatibility_claim") }
    }

    private static func validateUnderlyingSpikes(root: URL, repository: URL) throws {
        _ = try SP1DirectoryValidator.validate(directory: root.appendingPathComponent("sp1"), repository: repository)
        _ = try SP2DirectoryValidator.validate(directory: root.appendingPathComponent("sp2"), repository: repository, gitRepository: repository)
        _ = try SP3DirectoryValidator.validate(directory: root.appendingPathComponent("sp3"), repository: repository, gitRepository: repository)
        _ = try SP4ADirectoryValidator.validate(directory: root.appendingPathComponent("sp4a"), repository: repository, gitRepository: repository)
        _ = try SP4BDirectoryValidator.validate(directory: root.appendingPathComponent("sp4b"), repository: repository, gitRepository: repository)
        _ = try SP5ADirectoryValidator.validate(directory: root.appendingPathComponent("sp5a"), repository: repository, gitRepository: repository)
        _ = try SP5BDirectoryValidator.validate(directory: root.appendingPathComponent("sp5b"), repository: repository, gitRepository: repository)
        _ = try SP6ADirectoryValidator.validate(directory: root.appendingPathComponent("sp6a"), repository: repository, gitRepository: repository)
        _ = try SP6BDirectoryValidator.validate(directory: root.appendingPathComponent("sp6b"), repository: repository, gitRepository: repository)
    }

    static func validateVialDefinitionSchema(
        _ document: Phase0Conclusions,
        root: URL,
        repository: URL
    ) throws {
        guard let row = document.o4Matrix.first(where: { $0.id == "vial.definitionSchema" }),
              row.evidencePath == "sp5a/format-facts.json",
              row.blockedRef == nil else {
            throw ValidatorError("vial_definition_schema_evidence_invalid")
        }
        let facts: SP5AFormatFactsArtifact = try ValidatorDecoding.decode(
            SP5AFormatFactsArtifact.self,
            from: Data(contentsOf: root.appendingPathComponent("sp5a/format-facts.json")),
            malformedCode: "vial_definition_schema_evidence_invalid"
        )
        let roundTrip: SP5ARoundTripArtifact = try ValidatorDecoding.decode(
            SP5ARoundTripArtifact.self,
            from: Data(contentsOf: root.appendingPathComponent("sp5a/round-trip.json")),
            malformedCode: "vial_definition_schema_evidence_invalid"
        )
        let expectedFacts: SP5AFormatFactsArtifact
        do {
            expectedFacts = try SP5AFixtureScenarios.sourceFacts(repository: repository)
        } catch {
            throw ValidatorError("vial_definition_schema_evidence_invalid")
        }
        guard facts == expectedFacts, roundTrip.version == 1 else {
            throw ValidatorError("vial_definition_schema_evidence_invalid")
        }
    }

    private static func validateHistoricalSource(
        _ document: Phase0Conclusions,
        root: URL,
        repository: URL,
        strictRepositoryBinding: Bool
    ) throws {
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard isCanonicalCommit(document.sourceEvidenceCommitSha),
              isCanonicalCommit(document.generatorCommitSha) else {
            throw ValidatorError("noncanonical_commit_sha")
        }
        guard try git.run(
            ["merge-base", "--is-ancestor", document.sourceEvidenceCommitSha, document.generatorCommitSha],
            acceptedStatuses: [0, 1]
        ).status == 0 else {
            throw ValidatorError("source_evidence_not_ancestor_of_generator")
        }
        guard try git.run(
            ["merge-base", "--is-ancestor", document.generatorCommitSha, "HEAD"],
            acceptedStatuses: [0, 1]
        ).status == 0 else {
            throw ValidatorError("generator_commit_not_ancestor_of_head")
        }
        guard try git.text(["rev-parse", "\(document.sourceEvidenceCommitSha)^{tree}"]) == document.sourceEvidenceTreeSha else { throw ValidatorError("source_manifest_rebind") }
        let blob = try git.run(["cat-file", "blob", "\(document.sourceEvidenceCommitSha):evidence/phase0/manifest.sha256"]).stdout
        guard Canonical.sha256(blob) == document.sourceRootManifestSha256 else { throw ValidatorError("source_manifest_rebind") }
        try HistoricalEvidenceInventoryValidator.validate(
            root: root,
            sourceCommit: document.sourceEvidenceCommitSha,
            repository: repository
        )
        guard Set(document.generatorSourceSha256.keys) == ConclusionGenerator.sourcePaths else { throw ValidatorError("conclusion_runner_source_set_mismatch") }
        let paths = ConclusionGenerator.sourcePaths.sorted()
        let sourceBytes = try strictRepositoryBinding
            ? git.blobs(paths.map { "\(document.generatorCommitSha):\($0)" })
            : paths.map { try Data(contentsOf: repository.appendingPathComponent($0)) }
        for (path, bytes) in zip(paths, sourceBytes) {
            guard document.generatorSourceSha256[path] == Canonical.sha256(bytes) else { throw ValidatorError("conclusion_runner_source_hash_mismatch", path) }
        }
        if strictRepositoryBinding {
            let dirty = try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--"] + paths)
            guard dirty.isEmpty else {
                throw ValidatorError("conclusion_runner_dirty", dirty.split(separator: "\n").first.map(String.init) ?? "")
            }
        }
        guard try git.text(["rev-parse", "\(document.generatorCommitSha)^{tree}"]) == document.generatorTreeSha else { throw ValidatorError("conclusion_runner_tree_mismatch") }
    }

    private static func isCanonicalCommit(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
    }

    private static func validateMembership(_ root: URL) throws {
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        let expectedFiles = Set(["README.md", "environment.json", "privacy-audit.json", "run-all.json", "manifest.sha256", "conclusions.json"] + ConclusionContract.spikeIDs.map { "\($0)-CONCLUSION.md" })
        var files = Set<String>(), directories = Set<String>()
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ValidatorError("conclusion_symlink", child.lastPathComponent) }
            if values.isDirectory == true { directories.insert(child.lastPathComponent) }
            else if values.isRegularFile == true { files.insert(child.lastPathComponent) }
            else { throw ValidatorError("conclusion_non_regular", child.lastPathComponent) }
        }
        guard directories == Set(Phase0RunLayout.directories), files == expectedFiles else { throw ValidatorError("conclusion_root_membership_mismatch") }
    }

    private static func validateManifest(_ root: URL) throws {
        let manifest = try String(contentsOf: root.appendingPathComponent("manifest.sha256"), encoding: .utf8)
        let expectedNames = Set(["README.md", "environment.json", "privacy-audit.json", "run-all.json", "conclusions.json"] + ConclusionContract.spikeIDs.map { "\($0)-CONCLUSION.md" })
        var names = Set<String>()
        for line in manifest.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("conclusion_manifest_malformed") }
            let hash = String(fields[0]), name = String(fields[1])
            guard names.insert(name).inserted, expectedNames.contains(name) else { throw ValidatorError("conclusion_manifest_membership_mismatch") }
            try bind(name, hash, root: root)
        }
        guard names == expectedNames else { throw ValidatorError("conclusion_manifest_membership_mismatch") }
    }

    private static func validateRunReceipt(_ root: URL) throws {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("run-all.json"))) as? [String: Any], object["conclusionGenerated"] as? Bool == true else { throw ValidatorError("conclusion_run_receipt_stale") }
    }

    private static func validatePrivacy(_ root: URL) throws {
        let stored: Phase0PrivacyReport = try ValidatorDecoding.decode(Phase0PrivacyReport.self, from: Data(contentsOf: root.appendingPathComponent("privacy-audit.json")), malformedCode: "malformed_privacy_audit")
        let actual = try Phase0PrivacyAudit.scan(root: root, excluding: ["privacy-audit.json", "manifest.sha256"])
        guard stored == actual, stored.conclusionGenerated, stored.forbiddenHitCount == 0, stored.symlinkCount == 0, stored.unmarkedEventRecordCount == 0 else { throw ValidatorError("conclusion_privacy_mismatch") }
    }

    private static func bind(_ path: String, _ hash: String, root: URL) throws {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw ValidatorError("unsafe_conclusion_path", path) }
        let url = root.appendingPathComponent(path)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true, Canonical.sha256(try Data(contentsOf: url)) == hash else { throw ValidatorError("conclusion_hash_mismatch", path) }
    }
}

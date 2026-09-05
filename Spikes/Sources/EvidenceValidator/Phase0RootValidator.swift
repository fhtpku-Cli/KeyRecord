import Foundation
import Phase0Support

enum Phase0RootValidator {
    static func validate(
        _ root: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws {
        try validateMembership(root)
        try validateRootManifest(root)
        let receipt: Phase0RunReceipt = try decode(root.appendingPathComponent("run-all.json"), code: "malformed_phase0_run_receipt")
        try validateReceipt(receipt, root: root, repository: repository)
        let stored: Phase0PrivacyReport = try decode(root.appendingPathComponent("privacy-audit.json"), code: "malformed_privacy_audit")
        let actual: Phase0PrivacyReport
        do { actual = try Phase0PrivacyAudit.scan(root: root, excluding: ["privacy-audit.json", "manifest.sha256"]) }
        catch { throw ValidatorError("phase0_privacy_violation", String(describing: error)) }
        guard stored == actual, stored.forbiddenHitCount == 0, stored.symlinkCount == 0,
              stored.unmarkedEventRecordCount == 0, !stored.conclusionGenerated else {
            throw ValidatorError("phase0_privacy_audit_mismatch")
        }
        _ = try AtomicityHistoricalValidator.validate(
            directory: root.appendingPathComponent("shared-atomicity"), repository: repository
        )
        let candidateRepository = try candidateRepositoryView(root: root, repository: repository)
        defer { try? FileManager.default.removeItem(at: candidateRepository) }
        for name in Phase0RunLayout.spikeDirectories {
            let directory = root.appendingPathComponent(name)
            _ = try validateSpike(
                directory, name: name, repository: candidateRepository, gitRepository: repository
            )
        }
    }

    static func validateMembership(_ root: URL) throws {
        let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            throw ValidatorError("phase0_root_invalid")
        }
        let children = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        var files = Set<String>(), directories = Set<String>()
        for child in children {
            let childValues = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard childValues.isSymbolicLink != true else { throw ValidatorError("phase0_root_symlink", child.lastPathComponent) }
            if childValues.isDirectory == true { directories.insert(child.lastPathComponent) }
            else if childValues.isRegularFile == true { files.insert(child.lastPathComponent) }
            else { throw ValidatorError("phase0_root_non_regular", child.lastPathComponent) }
        }
        guard directories == Set(Phase0RunLayout.directories) else {
            throw ValidatorError("phase0_root_directory_set_mismatch")
        }
        guard files == Phase0RunLayout.rootFiles else { throw ValidatorError("phase0_root_artifact_set_mismatch") }
    }

    private static func validateRootManifest(_ root: URL) throws {
        let manifest = root.appendingPathComponent("manifest.sha256")
        guard regular(manifest), let text = try? String(contentsOf: manifest, encoding: .utf8), text.hasSuffix("\n") else {
            throw ValidatorError("missing_phase0_root_manifest")
        }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("malformed_phase0_root_manifest") }
            let hash = String(fields[0]), name = String(fields[1])
            guard Phase0RunLayout.rootArtifacts.contains(name), names.insert(name).inserted,
                  isHex(hash, count: 64) else { throw ValidatorError("phase0_root_manifest_membership_mismatch") }
            let file = root.appendingPathComponent(name)
            guard regular(file), let data = try? Data(contentsOf: file), Canonical.sha256(data) == hash else {
                throw ValidatorError("phase0_root_manifest_hash_mismatch", name)
            }
        }
        guard names == Set(Phase0RunLayout.rootArtifacts) else {
            throw ValidatorError("phase0_root_manifest_membership_mismatch")
        }
    }

    private static func validateReceipt(_ receipt: Phase0RunReceipt, root: URL, repository: URL) throws {
        let environment = root.appendingPathComponent("environment.json")
        guard receipt.schemaVersion == 1, receipt.directories == Phase0RunLayout.directories,
              receipt.rootArtifacts == Phase0RunLayout.rootArtifacts, !receipt.conclusionGenerated,
              regular(environment), let environmentData = try? Data(contentsOf: environment),
              Canonical.sha256(environmentData) == receipt.environmentSha256 else {
            throw ValidatorError("phase0_run_receipt_mismatch")
        }
        let expectedStages = ["preflight", "shared-atomicity"] + Phase0RunLayout.spikeDirectories
        guard receipt.stages.map(\.id) == expectedStages, receipt.stages.allSatisfy({
            $0.exitStatus == 0 && $0.verdict != "FAIL" && !$0.command.isEmpty
                && !$0.stdout.lowercased().contains("/users/") && !$0.stderr.lowercased().contains("/users/")
        }), receipt.toolVersions.map(\.tool) == ["swift", "xcode", "git", "jq", "shasum"],
              receipt.toolVersions.allSatisfy({ $0.exitStatus == 0 && !$0.command.isEmpty }) else {
            throw ValidatorError("phase0_run_stage_mismatch")
        }
        guard receipt.stages.first(where: { $0.id == "shared-atomicity" })?.policy == "executed-observation;canonical-preserved",
              receipt.stages.first(where: { $0.id == "sp6a" })?.policy == "preserved-nondeterministic-raw",
              receipt.stages.first(where: { $0.id == "sp6b" })?.policy == "preserved-nondeterministic-raw" else {
            throw ValidatorError("phase0_preservation_policy_mismatch")
        }
        guard let preflight = receipt.stages.first, preflight.id == "preflight",
              preflight.artifactSha256 == receipt.environmentSha256 else {
            throw ValidatorError("phase0_preflight_hash_mismatch")
        }
        for stage in receipt.stages where Phase0RunLayout.spikeDirectories.contains(stage.id) {
            let evidence: VerdictView = try decode(
                root.appendingPathComponent(stage.id).appendingPathComponent("evidence.json"),
                code: "phase0_stage_evidence_malformed"
            )
            guard stage.verdict == evidence.verdict else { throw ValidatorError("phase0_stage_verdict_mismatch", stage.id) }
        }
        for name in ["shared-atomicity", "sp6a", "sp6b"] {
            let manifest = root.appendingPathComponent(name).appendingPathComponent("manifest.sha256")
            let stage = receipt.stages.first { $0.id == name }
            guard let bytes = try? Data(contentsOf: manifest), stage?.artifactSha256 == Canonical.sha256(bytes) else {
                throw ValidatorError("phase0_preserved_hash_mismatch", name)
            }
        }
        try validateRunner(receipt, repository: repository)
    }

    private static func validateRunner(_ receipt: Phase0RunReceipt, repository: URL) throws {
        guard Set(receipt.runnerSourceSha256.keys) == Phase0RunBinding.sourcePaths,
              isHex(receipt.runnerCommitSha, count: 40), isHex(receipt.runnerTreeSha, count: 40) else {
            throw ValidatorError("phase0_runner_source_set_mismatch")
        }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(receipt.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("phase0_runner_commit_missing")
        }
        guard try git.text(["rev-parse", "\(receipt.runnerCommitSha)^{tree}"]) == receipt.runnerTreeSha else {
            throw ValidatorError("phase0_runner_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", receipt.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("phase0_runner_not_ancestor")
        }
        for path in Phase0RunBinding.sourcePaths.sorted() {
            let result = try git.run(["cat-file", "blob", "\(receipt.runnerCommitSha):\(path)"], acceptedStatuses: [0, 128])
            guard result.status == 0, receipt.runnerSourceSha256[path] == Canonical.sha256(result.stdout) else {
                throw ValidatorError("phase0_runner_source_hash_mismatch", path)
            }
            guard try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else {
                throw ValidatorError("phase0_runner_source_dirty", path)
            }
        }
    }

    private static func validateSpike(
        _ directory: URL, name: String, repository: URL, gitRepository: URL
    ) throws -> GateValidationReport {
        switch name {
        case "sp1": try SP1DirectoryValidator.validate(directory: directory, repository: gitRepository)
        case "sp2": try SP2DirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        case "sp3": try SP3DirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        case "sp4a": try SP4ADirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        case "sp4b": try SP4BDirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        case "sp5a": try SP5ADirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        case "sp5b": try SP5BDirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        case "sp6a": try SP6ADirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        case "sp6b": try SP6BDirectoryValidator.validate(directory: directory, repository: repository, gitRepository: gitRepository)
        default: throw ValidatorError("phase0_root_directory_set_mismatch")
        }
    }

    private static func candidateRepositoryView(root: URL, repository: URL) throws -> URL {
        let view = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-candidate-\(UUID().uuidString)", isDirectory: true)
        let evidenceParent = view.appendingPathComponent("evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceParent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root, to: evidenceParent.appendingPathComponent("phase0"))
        let source = repository.appendingPathComponent("Spikes/Sources/Phase0Support/VialQuery.swift")
        let destination = view.appendingPathComponent("Spikes/Sources/Phase0Support", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination.appendingPathComponent("VialQuery.swift"))
        return view
    }

    private static func decode<T: Decodable>(_ url: URL, code: String) throws -> T {
        guard regular(url), let data = try? Data(contentsOf: url) else { throw ValidatorError(code) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ValidatorError(code, String(describing: error)) }
    }
    private static func regular(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }
    private static func isHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

private struct VerdictView: Decodable { let verdict: String }

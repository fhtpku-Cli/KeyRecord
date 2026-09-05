import Foundation
import Phase0Support

enum SP3DirectoryValidator {
    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        gitRepository: URL? = nil
    ) throws -> GateValidationReport {
        let evidenceURL = directory.appendingPathComponent("evidence.json")
        guard isRegular(evidenceURL), let data = try? Data(contentsOf: evidenceURL) else { throw ValidatorError("missing_evidence_document") }
        let evidence: SP3Evidence
        do { evidence = try JSONDecoder().decode(SP3Evidence.self, from: data) }
        catch { throw ValidatorError("malformed_sp3_evidence", String(describing: error)) }
        try validateShape(data)
        do { try evidence.validate() } catch let error as SP3ValidationError { throw ValidatorError("sp3_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory, repository: repository, gitRepository: gitRepository ?? repository)
        try validateBindings(evidence, directory: directory, repository: repository)
        try validateConclusion(directory, evidence: evidence)
        try validateRunner(evidence, repository: gitRepository ?? repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: .open)
    }

    static func verifyManifest(_ directory: URL) throws {
        let url = directory.appendingPathComponent("manifest.sha256")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8) else { throw ValidatorError("missing_manifest") }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("malformed_manifest") }
            let name = String(fields[1])
            guard SP3DirectoryLayout.artifactNames.contains(name), names.insert(name).inserted else { throw ValidatorError("sp3_manifest_membership_mismatch") }
            let file = directory.appendingPathComponent(name)
            guard isRegular(file), let bytes = try? Data(contentsOf: file), Canonical.sha256(bytes) == String(fields[0]) else {
                throw ValidatorError("sp3_manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard names == SP3DirectoryLayout.artifactNames, actual == SP3DirectoryLayout.artifactNames else { throw ValidatorError("sp3_manifest_membership_mismatch") }
    }

    static func validateArtifacts(_ directory: URL, repository: URL, gitRepository: URL? = nil) throws {
        try requireKeys(directory, "managed-block.json", ["upstreamFixturePath", "upstreamFixtureSha256", "insertPreservedOutsideBytes", "updatePreservedOutsideBytes", "clearPreservedOutsideBytes", "restorePreservedOutsideBytes", "threeRuleBatchCount", "malformedRejected", "duplicateRejected", "baselineMismatchRejected", "externalEditRefused", "maximumBytes", "maximumDepth"])
        try requireKeys(directory, "recovery.json", ["hExpect", "hBase", "external", "crashBoundaries", "automaticExternalWrite"])
        try requireKeys(directory, "format-facts.json", ["upstreamRepository", "upstreamCommit", "upstreamTree", "lintSourcePath", "fixtureSourcePath", "currentFormat", "descriptionNotesMinimumVersion", "descriptionNotesSourceURL", "supportMatrixStatus", "limitation"])
        try requireKeys(directory, "lint-results.json", ["executed", "validAccepted", "invalidRejected"])
        try requireKeys(directory, "atomicity-citation.json", ["artifactPath", "artifactSha256", "manifestPath", "citedBy"])
        let managed: SP3ManagedBlockArtifact = try decode(directory, "managed-block.json", code: "sp3_managed_block_recompute_mismatch")
        let expected = try SP3FixtureScenarios.managedBlock(repository: repository)
        guard managed == expected, SP3FixtureScenarios.validates(managed) else { throw ValidatorError("sp3_managed_block_recompute_mismatch") }
        let recovery: SP3RecoveryArtifact = try decode(directory, "recovery.json", code: "sp3_recovery_recompute_mismatch")
        guard recovery == SP3FixtureScenarios.recovery(), recovery.crashBoundaries.count == AtomicReplacementCrashBoundary.allCases.count,
              !recovery.automaticExternalWrite else { throw ValidatorError("sp3_recovery_recompute_mismatch") }
        let facts: SP3FormatFacts = try decode(directory, "format-facts.json", code: "sp3_format_facts_mismatch")
        guard facts == SP3FixtureScenarios.formatFacts, facts.supportMatrixStatus == .blocked else { throw ValidatorError("sp3_format_facts_mismatch") }
        let lint: SP3LintArtifact = try decode(directory, "lint-results.json", code: "sp3_lint_artifact_invalid")
        if lint.executed {
            guard lint.cliPath?.isEmpty == false, lint.version?.isEmpty == false, Set(lint.validAccepted) == ["available_since.json", "valid.json"],
                  !lint.invalidRejected.isEmpty, lint.blockedBy == nil else { throw ValidatorError("sp3_lint_artifact_invalid") }
        } else {
            guard lint.cliPath == nil, lint.version == nil, lint.validAccepted.isEmpty, lint.invalidRejected.isEmpty,
                  lint.blockedBy == "supported_karabiner_cli_absent" else { throw ValidatorError("sp3_lint_artifact_invalid") }
        }
        try validateAtomicityCitation(directory, repository: repository, gitRepository: gitRepository ?? repository)
        for name in SP3DirectoryLayout.artifactNames where name.hasSuffix(".json") { try privacySafe(directory.appendingPathComponent(name)) }
    }

    static func validateAtomicityCitation(_ directory: URL, repository: URL, gitRepository: URL? = nil) throws {
        let citation: SP3AtomicityCitation = try decode(directory, "atomicity-citation.json", code: "sp3_atomicity_citation_mismatch")
        guard citation.artifactPath == "evidence/phase0/shared-atomicity/result.json",
              citation.manifestPath == "evidence/phase0/shared-atomicity/manifest.sha256",
              citation.citedBy == ["SP-3", "SP-6A"] else { throw ValidatorError("sp3_atomicity_citation_mismatch") }
        let resultURL = repository.appendingPathComponent(citation.artifactPath)
        let manifestURL = repository.appendingPathComponent(citation.manifestPath)
        guard isRegular(resultURL), isRegular(manifestURL), let result = try? Data(contentsOf: resultURL),
              let manifest = try? String(contentsOf: manifestURL, encoding: .utf8),
              citation.artifactSha256 == Canonical.sha256(result), manifest == "\(citation.artifactSha256)  result.json\n",
              let atomicity = try? JSONDecoder().decode(AtomicityEvidence.self, from: result) else { throw ValidatorError("sp3_atomicity_citation_mismatch") }
        do { try atomicity.validate() } catch { throw ValidatorError("sp3_atomicity_citation_mismatch") }
        _ = try AtomicityHistoricalValidator.validate(
            directory: resultURL.deletingLastPathComponent(),
            repository: gitRepository ?? repository
        )
    }

    static func validateBindings(_ evidence: SP3Evidence, directory: URL, repository: URL) throws {
        let environment = repository.appendingPathComponent("evidence/phase0/environment.json")
        guard isRegular(environment), let environmentData = try? Data(contentsOf: environment) else { throw ValidatorError("sp3_environment_missing") }
        do { try PrivacySafeEnvironmentValidator.validateJSON(environmentData); _ = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData) }
        catch { throw ValidatorError("sp3_environment_unsafe") }
        let hash = Canonical.sha256(environmentData)
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == hash }) else { throw ValidatorError("sp3_environment_hash_mismatch") }
        let expectedPaths: [String: String] = [
            "sp3.schemaLint": "lint-results.json", "sp3.managedBlock": "managed-block.json",
            "sp3.atomicity": "atomicity-citation.json", "sp3.crashRecovery": "recovery.json", "sp3.versionSample": "format-facts.json",
        ]
        for leg in evidence.legs where leg.verdict != .blocked {
            guard let path = expectedPaths[leg.legID], leg.artifactPath == path, SP3DirectoryLayout.boundArtifactNames.contains(path),
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(path)), leg.artifactSha256 == Canonical.sha256(bytes) else {
                throw ValidatorError("sp3_artifact_binding_mismatch", leg.legID)
            }
        }
    }

    static func validateRunner(_ evidence: SP3Evidence, repository: URL) throws {
        guard Set(evidence.runnerSourceSha256.keys) == SP3RunnerBinding.sourcePaths else { throw ValidatorError("sp3_runner_source_set_mismatch") }
        guard let first = evidence.legs.first else { throw ValidatorError("sp3_runner_identity_mismatch") }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else { throw ValidatorError("sp3_runner_commit_missing") }
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha else { throw ValidatorError("sp3_runner_tree_mismatch") }
        guard try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else { throw ValidatorError("sp3_runner_not_ancestor") }
        for path in SP3RunnerBinding.sourcePaths.sorted() {
            guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha):\(path)"], acceptedStatuses: [0, 1, 128]).status == 0 else { throw ValidatorError("sp3_runner_source_missing", path) }
            let committed = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else { throw ValidatorError("sp3_runner_source_hash_mismatch", path) }
            let working = repository.appendingPathComponent(path)
            guard isRegular(working), (try? Data(contentsOf: working)) == committed,
                  try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else { throw ValidatorError("sp3_runner_source_dirty", path) }
        }
    }

    private static func validateConclusion(_ directory: URL, evidence: SP3Evidence) throws {
        let url = directory.appendingPathComponent("SP-3-CONCLUSION.md")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8),
              text.contains("Verdict: **\(evidence.verdict.rawValue)**"), evidence.verdict == .pass || !text.contains("Verdict: **PASS**"),
              text.contains("no user Karabiner file or process was accessed") else { throw ValidatorError("sp3_misleading_conclusion") }
    }
    private static func validateShape(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["schemaVersion", "spikeID", "legs", "verdict", "runnerSourceSha256"],
              let legs = root["legs"] as? [[String: Any]] else { throw ValidatorError("sp3_evidence_shape_invalid") }
        let required: Set<String> = ["legID", "evidenceKind", "detectorID", "detectorAvailable", "verdict", "runnerCommitSha", "runnerTreeSha", "environmentSha256", "command"]
        let allowed = required.union(["blocker", "exitStatus", "artifactPath", "artifactSha256"])
        let blockerKeys: Set<String> = ["blocked_by", "detect_command", "prerequisite", "unblock_action"]
        for leg in legs {
            guard required.isSubset(of: Set(leg.keys)), Set(leg.keys).isSubset(of: allowed) else { throw ValidatorError("sp3_evidence_shape_invalid") }
            if let blocker = leg["blocker"] as? [String: Any], Set(blocker.keys) != blockerKeys { throw ValidatorError("sp3_evidence_shape_invalid") }
        }
    }
    private static func privacySafe(_ url: URL) throws {
        guard isRegular(url), let data = try? Data(contentsOf: url), let value = try? JSONSerialization.jsonObject(with: data) else { throw ValidatorError("sp3_artifact_unsafe") }
        let forbidden = ["keystream", "serialnumber", "credential", "username", "userid", "exacttimestamp", "eventtimestamp"]
        func safe(_ value: Any) -> Bool {
            if let object = value as? [String: Any] { return object.allSatisfy { !forbidden.contains($0.key.lowercased()) && safe($0.value) } }
            if let array = value as? [Any] { return array.allSatisfy(safe) }
            return true
        }
        guard safe(value) else { throw ValidatorError("sp3_artifact_unsafe") }
    }
    private static func decode<T: Decodable>(_ directory: URL, _ name: String, code: String) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard isRegular(url), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else { throw ValidatorError(code) }
        return value
    }
    private static func requireKeys(_ directory: URL, _ name: String, _ required: Set<String>) throws {
        let url = directory.appendingPathComponent(name)
        guard isRegular(url), let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ValidatorError("sp3_artifact_unsafe") }
        var allowed = required
        if name == "lint-results.json" { allowed.formUnion(["cliPath", "version", "blockedBy"]); guard required.isSubset(of: Set(object.keys)) else { throw ValidatorError("sp3_artifact_shape_invalid", name) } }
        guard Set(object.keys).isSubset(of: allowed), name == "lint-results.json" || Set(object.keys) == required else { throw ValidatorError("sp3_artifact_shape_invalid", name) }
    }
    private static func isRegular(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 1_048_576
    }
}

import Foundation
import Phase0Support

enum SP2DirectoryValidator {
    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        gitRepository: URL? = nil
    ) throws -> GateValidationReport {
        let evidenceURL = directory.appendingPathComponent("evidence.json")
        guard isRegularFile(evidenceURL) else { throw ValidatorError("missing_evidence_document") }
        let evidence: SP2Evidence
        do { evidence = try JSONDecoder().decode(SP2Evidence.self, from: Data(contentsOf: evidenceURL)) }
        catch { throw ValidatorError("malformed_sp2_evidence", String(describing: error)) }
        try validateEvidenceShape(evidenceURL)
        do { try evidence.validate() }
        catch let error as SP2ValidationError { throw ValidatorError("sp2_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory)
        try validateV2LiveSemantics(evidence, directory: directory)
        try validateArtifactBindings(evidence, directory: directory, repository: repository)
        try validateConclusion(directory, evidence: evidence)
        try validateRunnerBinding(evidence, repository: gitRepository ?? repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: evidence.g0Status)
    }

    static func verifyManifest(_ directory: URL) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        guard isRegularFile(manifest), let text = try? String(contentsOf: manifest, encoding: .utf8) else {
            throw ValidatorError("missing_manifest")
        }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { throw ValidatorError("malformed_manifest") }
            let name = String(parts[1])
            guard SP2DirectoryLayout.artifactNames.contains(name), names.insert(name).inserted else {
                throw ValidatorError("sp2_manifest_membership_mismatch")
            }
            let file = directory.appendingPathComponent(name)
            guard isRegularFile(file), let data = try? Data(contentsOf: file), Canonical.sha256(data) == String(parts[0]) else {
                throw ValidatorError("sp2_manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard names == SP2DirectoryLayout.artifactNames, actual == SP2DirectoryLayout.artifactNames else {
            throw ValidatorError("sp2_manifest_membership_mismatch")
        }
    }

    static func validateArtifacts(_ directory: URL) throws {
        let privacyURL = directory.appendingPathComponent("privacy-model.json")
        let modifierURL = directory.appendingPathComponent("modifier-model.json")
        let liveURL = directory.appendingPathComponent("live-aggregate-counts.json")
        for url in [privacyURL, modifierURL, liveURL] { try validatePrivacySafeJSON(url) }
        let expected = SP2ModelScenarios.run()
        let privacy: SP2PrivacyArtifact = try decode(privacyURL)
        let modifiers: SP2ModifierArtifact = try decode(modifierURL)
        guard privacy == expected.privacy, modifiers == expected.modifiers else {
            throw ValidatorError("sp2_model_recompute_mismatch")
        }
        if let v2 = try? JSONDecoder().decode(SP2LiveAggregateV2.self, from: Data(contentsOf: liveURL)) {
            do { try v2.validate() } catch { throw ValidatorError("sp2_sensitive_detail_forbidden") }
        } else {
            let live: SP2AggregateArtifact = try decode(liveURL)
            guard live.evidenceKind == .live, live.dataDelta == 0, live.metaDelta == 0 else {
                throw ValidatorError("sp2_sensitive_detail_forbidden")
            }
        }
    }

    static func validateV2LiveSemantics(_ evidence: SP2Evidence, directory: URL) throws {
        let liveURL = directory.appendingPathComponent("live-aggregate-counts.json")
        guard let v2 = try? JSONDecoder().decode(SP2LiveAggregateV2.self, from: Data(contentsOf: liveURL)) else { return }
        do { try v2.validate() } catch { throw ValidatorError("sp2_sensitive_detail_forbidden") }
        for leg in evidence.legs {
            switch leg.legID {
            case "sp2.frontmostKnown":
                if leg.verdict == .pass, v2.knownAttributable < 1 || leg.dataDelta != 1 || leg.metaDelta != 1 {
                    throw ValidatorError("sp2_live_counter_mismatch", leg.legID)
                }
            case "sp2.frontmostUnattributable":
                if leg.verdict == .pass, v2.knownUnattributable < 1 || leg.dataDelta != 1 || leg.metaDelta != 1 {
                    throw ValidatorError("sp2_live_counter_mismatch", leg.legID)
                }
            case "sp2.fnRecoveryLive":
                if leg.verdict == .pass,
                   v2.fnUnknownAfterReset < 1 || v2.fnRecoveredKnownNone < 1 || v2.fnRecoveredKnownActive < 1
                    || leg.dataDelta != 0 || leg.metaDelta != 0 {
                    throw ValidatorError("sp2_live_counter_mismatch", leg.legID)
                }
            case "sp2.secureInput", "sp2.sleepWake":
                if leg.verdict == .pass, leg.dataDelta != 0 || leg.metaDelta != 0 {
                    throw ValidatorError("sp2_live_counter_mismatch", leg.legID)
                }
            default:
                break
            }
        }
    }

    static func validateArtifactBindings(_ evidence: SP2Evidence, directory: URL, repository: URL) throws {
        let environmentURL = repository.appendingPathComponent("evidence/phase0/environment.json")
        guard isRegularFile(environmentURL), let environmentData = try? Data(contentsOf: environmentURL) else {
            throw ValidatorError("sp2_environment_missing")
        }
        do {
            try PrivacySafeEnvironmentValidator.validateJSON(environmentData)
            _ = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        } catch { throw ValidatorError("sp2_environment_unsafe") }
        let environmentHash = Canonical.sha256(environmentData)
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == environmentHash }) else {
            throw ValidatorError("sp2_environment_hash_mismatch")
        }
        for leg in evidence.legs where leg.verdict != .blocked {
            guard let expectedPath = artifactPath(for: leg.legID), leg.artifactPath == expectedPath,
                  SP2DirectoryLayout.boundArtifactNames.contains(expectedPath),
                  !expectedPath.contains("/"), !expectedPath.contains("..") else {
                throw ValidatorError("sp2_artifact_path_invalid", leg.legID)
            }
            let url = directory.appendingPathComponent(expectedPath)
            guard isRegularFile(url), let bytes = try? Data(contentsOf: url) else {
                throw ValidatorError("sp2_artifact_missing", expectedPath)
            }
            guard leg.artifactSha256 == Canonical.sha256(bytes) else {
                throw ValidatorError("sp2_artifact_hash_mismatch", leg.legID)
            }
        }
    }

    static func validateEvidenceShape(_ url: URL) throws {
        let root = try object(url)
        guard Set(root.keys) == ["schemaVersion", "spikeID", "legs", "verdict", "o6Status", "g0Status", "runnerSourceSha256"],
              let legs = root["legs"] as? [[String: Any]] else { throw ValidatorError("sp2_sensitive_detail_forbidden") }
        let requiredLegKeys: Set<String> = [
            "legID", "evidenceKind", "detectorID", "detectorAvailable", "verdict",
            "runnerCommitSha", "runnerTreeSha", "environmentSha256", "command", "dataDelta", "metaDelta",
        ]
        let legKeys = requiredLegKeys.union(["blocker", "exitStatus", "artifactPath", "artifactSha256"])
        let blockerKeys: Set<String> = ["blocked_by", "detect_command", "prerequisite", "unblock_action"]
        for leg in legs {
            let keys = Set(leg.keys)
            guard requiredLegKeys.isSubset(of: keys), keys.isSubset(of: legKeys) else { throw ValidatorError("sp2_sensitive_detail_forbidden") }
            if let blocker = leg["blocker"] as? [String: Any], Set(blocker.keys) != blockerKeys {
                throw ValidatorError("sp2_sensitive_detail_forbidden")
            }
        }
    }

    static func validateRunnerBinding(_ evidence: SP2Evidence, repository: URL) throws {
        guard Set(evidence.runnerSourceSha256.keys) == SP2RunnerBinding.sourcePaths else {
            throw ValidatorError("sp2_runner_source_set_mismatch")
        }
        guard let first = evidence.legs.first,
              evidence.legs.allSatisfy({ $0.runnerCommitSha == first.runnerCommitSha && $0.runnerTreeSha == first.runnerTreeSha }) else {
            throw ValidatorError("sp2_runner_identity_mismatch")
        }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let exists = try git.run(["cat-file", "-e", "\(first.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128])
        guard exists.status == 0 else { throw ValidatorError("sp2_runner_commit_missing") }
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha else {
            throw ValidatorError("sp2_runner_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp2_runner_not_ancestor")
        }
        for path in SP2RunnerBinding.sourcePaths.sorted() {
            let exists = try git.run(["cat-file", "-e", "\(first.runnerCommitSha):\(path)"], acceptedStatuses: [0, 1, 128])
            guard exists.status == 0 else { throw ValidatorError("sp2_runner_source_missing", path) }
            let committed = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else {
                throw ValidatorError("sp2_runner_source_hash_mismatch", path)
            }
            let working = repository.appendingPathComponent(path)
            guard isRegularFile(working),
                  try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else {
                throw ValidatorError("sp2_runner_source_dirty", path)
            }
        }
    }

    private static func validateConclusion(_ directory: URL, evidence: SP2Evidence) throws {
        let url = directory.appendingPathComponent("SP-2-CONCLUSION.md")
        guard isRegularFile(url), let text = try? String(contentsOf: url, encoding: .utf8),
              text.contains("Verdict: **\(evidence.verdict.rawValue)**"),
              text.contains("O6: **\(evidence.o6Status.rawValue)**"),
              text.contains("G0: **\(evidence.g0Status.rawValue)**"),
              evidence.verdict == .pass || !text.contains("Verdict: **PASS**"),
              evidence.o6Status == .resolved || !text.contains("O6: **RESOLVED**"),
              evidence.g0Status == .passed || !text.contains("G0: **PASSED**") else {
            throw ValidatorError("sp2_misleading_conclusion")
        }
    }
    private static func artifactPath(for legID: String) -> String? {
        if ["sp2.frontmostIndeterminate", "sp2.excludedApp", "sp2.tapReset"].contains(legID) { return "privacy-model.json" }
        if ["sp2.sidedModifiers", "sp2.sidedRecovery", "sp2.fnRecoveryModel"].contains(legID) { return "modifier-model.json" }
        if ["sp2.frontmostKnown", "sp2.frontmostUnattributable", "sp2.secureInput", "sp2.sleepWake", "sp2.fnRecoveryLive"].contains(legID) { return "live-aggregate-counts.json" }
        return nil
    }
    private static func decode<T: Decodable>(_ url: URL) throws -> T {
        guard isRegularFile(url), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw ValidatorError("sp2_model_recompute_mismatch")
        }
        return value
    }
    private static func validatePrivacySafeJSON(_ url: URL) throws {
        guard isRegularFile(url), let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) else { throw ValidatorError("sp2_sensitive_detail_forbidden") }
        let forbidden = ["keycode", "text", "sequence", "exacttimestamp", "eventtimestamp", "eventtime", "keystream", "credential", "username", "userid"]
        func safe(_ value: Any) -> Bool {
            if let object = value as? [String: Any] {
                return object.allSatisfy { key, child in !forbidden.contains(key.lowercased()) && safe(child) }
            }
            if let array = value as? [Any] { return array.allSatisfy(safe) }
            return true
        }
        guard safe(value) else { throw ValidatorError("sp2_sensitive_detail_forbidden") }
    }
    private static func object(_ url: URL) throws -> [String: Any] {
        guard isRegularFile(url), let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidatorError("sp2_sensitive_detail_forbidden")
        }
        return value
    }
    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 1_048_576
    }
}

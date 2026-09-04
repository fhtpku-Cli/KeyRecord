import Foundation
import Phase0Support

enum SP2DirectoryValidator {
    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
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
        try validateConclusion(directory, evidence: evidence)
        try validateRunnerBinding(evidence, repository: repository)
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
        let live = try object(directory.appendingPathComponent("live-aggregate-counts.json"))
        guard Set(live.keys) == ["evidenceKind", "dataDelta", "metaDelta"],
              live["evidenceKind"] as? String == EvidenceKind.live.rawValue,
              (live["dataDelta"] as? NSNumber)?.intValue == 0,
              (live["metaDelta"] as? NSNumber)?.intValue == 0 else { throw ValidatorError("sp2_sensitive_detail_forbidden") }

        let privacy = try object(directory.appendingPathComponent("privacy-model.json"))
        guard Set(privacy.keys) == ["evidenceKind", "cases"],
              privacy["evidenceKind"] as? String == EvidenceKind.fixture.rawValue,
              let cases = privacy["cases"] as? [[String: Any]], cases.count == 8 else {
            throw ValidatorError("sp2_sensitive_detail_forbidden")
        }
        let expected: [String: (String, Int, Int)] = [
            "known": ("bundle", 1, 1), "knownUnattributable": ("UNKNOWN", 1, 1),
            "indeterminate": ("closed", 0, 0), "excludedApp": ("closed", 0, 0),
            "secureInputEnabled": ("closed", 0, 0), "secureInputUnknown": ("closed", 0, 0),
            "tapReset": ("closed", 0, 0), "sleepWake": ("closed", 0, 0),
        ]
        var seen = Set<String>()
        for item in cases {
            guard Set(item.keys) == ["scenario", "outcome", "dataDelta", "metaDelta"],
                  let scenario = item["scenario"] as? String, seen.insert(scenario).inserted,
                  let expectedCase = expected[scenario], item["outcome"] as? String == expectedCase.0,
                  (item["dataDelta"] as? NSNumber)?.intValue == expectedCase.1,
                  (item["metaDelta"] as? NSNumber)?.intValue == expectedCase.2 else {
                throw ValidatorError("sp2_sensitive_detail_forbidden")
            }
        }
        guard seen == Set(expected.keys) else { throw ValidatorError("sp2_sensitive_detail_forbidden") }

        let modifier = try object(directory.appendingPathComponent("modifier-model.json"))
        guard Set(modifier.keys) == ["evidenceKind", "families", "fnStates", "deterministicRecovery"],
              modifier["evidenceKind"] as? String == EvidenceKind.fixture.rawValue,
              modifier["deterministicRecovery"] as? Bool == true,
              let families = modifier["families"] as? [String: [String]],
              Set(families.keys) == Set(ModifierFamily.allCases.map(\.rawValue)),
              families.values.allSatisfy({ Set($0) == Set(ModifierSideState.allCases.map(\.rawValue)) && $0.count == ModifierSideState.allCases.count }),
              let fn = modifier["fnStates"] as? [String], Set(fn) == Set(FnConfidence.allCases.map(\.rawValue)),
              fn.count == FnConfidence.allCases.count else { throw ValidatorError("sp2_sensitive_detail_forbidden") }
    }

    static func validateEvidenceShape(_ url: URL) throws {
        let root = try object(url)
        guard Set(root.keys) == ["schemaVersion", "spikeID", "legs", "verdict", "o6Status", "g0Status", "runnerSourceSha256"],
              let legs = root["legs"] as? [[String: Any]] else { throw ValidatorError("sp2_sensitive_detail_forbidden") }
        let requiredLegKeys: Set<String> = [
            "legID", "evidenceKind", "detectorID", "detectorAvailable", "verdict",
            "runnerCommitSha", "runnerTreeSha", "environmentSha256", "command", "dataDelta", "metaDelta",
        ]
        let legKeys = requiredLegKeys.union(["blocker", "exitStatus", "artifactSha256"])
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
            guard isRegularFile(working), (try? Data(contentsOf: working)) == committed,
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

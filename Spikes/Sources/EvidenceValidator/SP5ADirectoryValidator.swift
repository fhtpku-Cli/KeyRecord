import Foundation
import Phase0Support

enum SP5ADirectoryValidator {
    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> GateValidationReport {
        let evidence: SP5AEvidence = try exactDecode(directory, "evidence.json", code: "malformed_sp5a_evidence")
        do { try evidence.validate() } catch let error as SP5AValidationError { throw ValidatorError("sp5a_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory, repository: repository)
        try validateBindings(evidence, directory: directory, repository: repository)
        try validateConclusion(directory, evidence: evidence)
        try validateRunner(evidence, repository: repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: .open)
    }

    static func verifyManifest(_ directory: URL) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        guard isRegular(manifest), let text = try? String(contentsOf: manifest, encoding: .utf8), text.hasSuffix("\n") else {
            throw ValidatorError("missing_manifest")
        }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("malformed_manifest") }
            let hash = String(fields[0]), name = String(fields[1])
            guard isLowercaseSHA256(hash), SP5ADirectoryLayout.artifactNames.contains(name),
                  !name.contains("/"), !name.contains(".."), names.insert(name).inserted else {
                throw ValidatorError("sp5a_manifest_membership_mismatch")
            }
            let file = directory.appendingPathComponent(name)
            guard isRegular(file), let bytes = try? Data(contentsOf: file), Canonical.sha256(bytes) == hash else {
                throw ValidatorError("sp5a_manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard names == SP5ADirectoryLayout.artifactNames, actual == SP5ADirectoryLayout.artifactNames else {
            throw ValidatorError("sp5a_manifest_membership_mismatch")
        }
    }

    static func validateArtifacts(_ directory: URL, repository: URL) throws {
        let roundTrip: SP5ARoundTripArtifact
        let uid: SP5AUIDArtifact
        let bounds: SP5ABoundsArtifact
        do {
            roundTrip = try SP5AFixtureScenarios.roundTrip(repository: repository)
            uid = try SP5AFixtureScenarios.uidBinding(repository: repository)
            bounds = try SP5AFixtureScenarios.bounds()
        } catch { throw ValidatorError("sp5a_fixture_recompute_failed") }
        let facts: SP5AFormatFactsArtifact
        do { facts = try SP5AFixtureScenarios.sourceFacts(repository: repository) }
        catch { throw ValidatorError("sp5a_source_recompute_failed") }
        try requireExact(directory, "round-trip.json", roundTrip, code: "sp5a_round_trip_recompute_mismatch")
        try requireExact(directory, "uid-binding.json", uid, code: "sp5a_uid_recompute_mismatch")
        try requireExact(directory, "bounds.json", bounds, code: "sp5a_bounds_recompute_mismatch")
        try requireExact(directory, "format-facts.json", facts, code: "sp5a_format_facts_mismatch")
        guard SP5AFixtureScenarios.validates(roundTrip), SP5AFixtureScenarios.validates(uid), SP5AFixtureScenarios.validates(bounds) else {
            throw ValidatorError("sp5a_fixture_assertion_mismatch")
        }
        try validateSyntheticProvenance(repository)
        try validateSourceProvenance(repository, name: "vial-gui", commit: "aef8222a2d0429a183b2ed692d5f9efcfd383f08", tree: "22a59cd7c2f7c4ef746378e259f6de0f1faa3633")
        try validateSourceProvenance(repository, name: "vial-qmk", commit: "dd43959ae5c08d8a28d38a1acf7b04e86b14a344", tree: "b9a0d7b574d78f3e0622c5cfe1f9ff9901d63f64")
    }

    static func validateBindings(_ evidence: SP5AEvidence, directory: URL, repository: URL) throws {
        let environmentURL = repository.appendingPathComponent("evidence/phase0/environment.json")
        guard isRegular(environmentURL), let environmentData = try? Data(contentsOf: environmentURL) else {
            throw ValidatorError("sp5a_environment_missing")
        }
        let environment: EnvironmentEvidence
        do {
            try PrivacySafeEnvironmentValidator.validateJSON(environmentData)
            environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        } catch { throw ValidatorError("sp5a_environment_unsafe") }
        let environmentHash = Canonical.sha256(environmentData)
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == environmentHash }) else {
            throw ValidatorError("sp5a_environment_hash_mismatch")
        }
        guard environment.applications.first(where: { $0.name == "Vial" })?.status == .absent,
              let importer = evidence.legs.first(where: { $0.legID == "sp5a.importer" }),
              importer.verdict == .blocked, !importer.detectorAvailable,
              importer.blocker?.blockedBy == "vial_gui_absent",
              importer.blocker?.detectCommand == ["environment-inventory", "Vial"] else {
            throw ValidatorError("sp5a_d7_environment_mismatch")
        }
        for leg in evidence.legs where leg.verdict == .pass {
            guard let path = SP5ADirectoryLayout.legArtifacts[leg.legID], leg.artifactPath == path,
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(path)),
                  leg.artifactSha256 == Canonical.sha256(bytes) else {
                throw ValidatorError("sp5a_artifact_binding_mismatch", leg.legID)
            }
        }
    }

    static func validateRunner(_ evidence: SP5AEvidence, repository: URL) throws {
        guard Set(evidence.runnerSourceSha256.keys) == SP5ARunnerBinding.sourcePaths,
              let first = evidence.legs.first else { throw ValidatorError("sp5a_runner_source_set_mismatch") }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("sp5a_runner_commit_missing")
        }
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha else {
            throw ValidatorError("sp5a_runner_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp5a_runner_not_ancestor")
        }
        for path in SP5ARunnerBinding.sourcePaths.sorted() {
            guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha):\(path)"], acceptedStatuses: [0, 1, 128]).status == 0 else {
                throw ValidatorError("sp5a_runner_source_missing", path)
            }
            let committed = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else {
                throw ValidatorError("sp5a_runner_source_hash_mismatch", path)
            }
            guard try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else {
                throw ValidatorError("sp5a_runner_source_dirty", path)
            }
        }
    }

    private static func validateSyntheticProvenance(_ repository: URL) throws {
        let provenanceURL = repository.appendingPathComponent("evidence/phase0/fixtures/synthetic/provenance.json")
        let manifestURL = repository.appendingPathComponent("evidence/phase0/fixtures/synthetic/manifest.sha256")
        guard isRegular(provenanceURL), isRegular(manifestURL),
              let data = try? Data(contentsOf: provenanceURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["evidenceKind", "generator", "files"], root["evidenceKind"] as? String == "synthetic",
              root["generator"] as? String == "Spikes/Scripts/generate-synthetic-fixtures.sh",
              let files = root["files"] as? [[String: String]],
              files.contains(where: { $0 == ["path": "phase0.vil", "sha256": SP5AFixtureScenarios.fixtureSha256] }),
              let fixture = try? Data(contentsOf: repository.appendingPathComponent(SP5AFixtureScenarios.fixturePath)),
              Canonical.sha256(fixture) == SP5AFixtureScenarios.fixtureSha256, fixture.last != 10,
              let manifest = try? String(contentsOf: manifestURL, encoding: .utf8),
              manifest.split(separator: "\n").contains(where: { $0 == "\(SP5AFixtureScenarios.fixtureSha256)  phase0.vil" }) else {
            throw ValidatorError("sp5a_fixture_provenance_mismatch")
        }
    }

    private static func validateSourceProvenance(_ repository: URL, name: String, commit: String, tree: String) throws {
        let url = repository.appendingPathComponent("evidence/phase0/sources/repos/\(name)/provenance.json")
        guard isRegular(url), let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["name"] as? String == name, root["upstream_ref"] as? String == commit, root["tree"] as? String == tree,
              root["files"] is [[String: Any]], root["license"] is [String: Any] else {
            throw ValidatorError("sp5a_source_provenance_mismatch", name)
        }
    }

    private static func validateConclusion(_ directory: URL, evidence: SP5AEvidence) throws {
        let url = directory.appendingPathComponent("SP-5A-CONCLUSION.md")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8),
              evidence.verdict == .blocked, text.contains("Verdict: **BLOCKED**"),
              text.contains("exact deterministic synthetic `.vil` fixture"), text.contains("synthetic, not sourced or live"),
              text.contains("does not prove official-importer"), text.contains("Official Vial GUI import remains **BLOCKED**"),
              text.contains("D7 is false"), text.contains("Vial absent"), text.contains("No GUI was launched"),
              text.contains("no device or HID interaction occurred"), text.contains("`vial.json` is a firmware-embedded keyboard definition"),
              text.contains("not interchangeable with a `.vil` keymap export or a VIA definition"),
              !text.contains("Verdict: **PASS**"), !text.contains("device compatibility verified") else {
            throw ValidatorError("sp5a_misleading_conclusion")
        }
    }

    private static func requireExact<T: Codable & Equatable>(_ directory: URL, _ name: String, _ expected: T, code: String) throws {
        let actual: T = try exactDecode(directory, name, code: code)
        guard actual == expected else { throw ValidatorError(code) }
    }
    private static func exactDecode<T: Codable>(_ directory: URL, _ name: String, code: String) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard isRegular(url), let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(T.self, from: data),
              let canonical = try? pretty(decoded), data == canonical else { throw ValidatorError(code) }
        return decoded
    }
    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func isRegular(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= VialDocumentLimits.maximumInputBytes
    }
    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

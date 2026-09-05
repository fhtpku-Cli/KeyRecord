import Foundation
import Phase0Support

enum SP5BDirectoryValidator {
    static func validate(
        directory: URL, repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        gitRepository: URL? = nil
    ) throws -> GateValidationReport {
        let evidence: SP5BEvidence = try exactDecode(directory, "evidence.json", code: "malformed_sp5b_evidence")
        do { try evidence.validate() } catch let error as SP5BValidationError { throw ValidatorError("sp5b_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory, repository: repository)
        try validateBindings(evidence, directory: directory, repository: repository)
        try validateConclusion(directory, evidence: evidence)
        try validateRunner(evidence, repository: gitRepository ?? repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: .open)
    }

    static func verifyManifest(_ directory: URL) throws {
        let url = directory.appendingPathComponent("manifest.sha256")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8), text.hasSuffix("\n") else {
            throw ValidatorError("missing_manifest")
        }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("malformed_manifest") }
            let hash = String(fields[0]), name = String(fields[1])
            guard isSHA256(hash), SP5BDirectoryLayout.artifactNames.contains(name),
                  !name.contains("/"), !name.contains(".."), names.insert(name).inserted else {
                throw ValidatorError("sp5b_manifest_membership_mismatch")
            }
            let file = directory.appendingPathComponent(name)
            guard isRegular(file), let bytes = try? Data(contentsOf: file), Canonical.sha256(bytes) == hash else {
                throw ValidatorError("sp5b_manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard names == SP5BDirectoryLayout.artifactNames, actual == SP5BDirectoryLayout.artifactNames else {
            throw ValidatorError("sp5b_manifest_membership_mismatch")
        }
    }

    static func validateArtifacts(_ directory: URL, repository: URL) throws {
        let facts: SP5BSourceFactsArtifact
        let replay: SP5BReplayArtifact
        let deny: SP5BDenyMutationArtifact
        do {
            facts = try SP5BScenarios.sourceFacts(repository: repository)
            replay = try SP5BScenarios.replay(repository: repository)
            deny = try SP5BScenarios.denyMutation(repository: repository)
        } catch { throw ValidatorError("sp5b_artifact_recompute_failed") }
        try requireExact(directory, "source-facts.json", facts, code: "sp5b_source_facts_recompute_mismatch")
        try requireExact(directory, "replay.json", replay, code: "sp5b_replay_recompute_mismatch")
        try requireExact(directory, "deny-mutation.json", deny, code: "sp5b_deny_recompute_mismatch")
        guard SP5BScenarios.validates(facts), SP5BScenarios.validates(replay), SP5BScenarios.validates(deny) else {
            throw ValidatorError("sp5b_artifact_assertion_mismatch")
        }
        try validateFixtureProvenance(repository)
        try validateSourceProvenance(repository, facts: facts)
    }

    static func validateBindings(_ evidence: SP5BEvidence, directory: URL, repository: URL) throws {
        let url = repository.appendingPathComponent("evidence/phase0/environment.json")
        guard isRegular(url), let data = try? Data(contentsOf: url) else { throw ValidatorError("sp5b_environment_missing") }
        let environment: EnvironmentEvidence
        do {
            try PrivacySafeEnvironmentValidator.validateJSON(data)
            environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: data)
        } catch { throw ValidatorError("sp5b_environment_unsafe") }
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == Canonical.sha256(data) }) else {
            throw ValidatorError("sp5b_environment_hash_mismatch")
        }
        guard environment.applications.first(where: { $0.name == "Vial" })?.status == .absent,
              !environment.hidSummary.devices.contains(where: { $0.product?.contains("Vial-approved") == true }),
              let live = evidence.legs.first(where: { $0.legID == "sp5b.liveCapture" }),
              live.verdict == .blocked, !live.detectorAvailable,
              live.blocker?.blockedBy == "approved_vial_device_capture_absent",
              live.blocker?.detectCommand == ["environment-inventory", "approved-vial-device"] else {
            throw ValidatorError("sp5b_d8_environment_mismatch")
        }
        for leg in evidence.legs where leg.verdict == .pass {
            guard let artifact = SP5BDirectoryLayout.legArtifacts[leg.legID], leg.artifactPath == artifact,
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(artifact)),
                  leg.artifactSha256 == Canonical.sha256(bytes) else {
                throw ValidatorError("sp5b_artifact_binding_mismatch", leg.legID)
            }
        }
    }

    static func validateConclusion(_ directory: URL, evidence: SP5BEvidence) throws {
        let url = directory.appendingPathComponent("SP-5B-CONCLUSION.md")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8), evidence.verdict == .blocked,
              text.contains("Verdict: **BLOCKED**"), text.contains("whitelist-constrained non-changing queries"),
              text.contains("not literally read-only"), text.contains("synthetic recorded-response fixture"),
              text.contains("No unlock, reset, bootloader, EEPROM, macro, or keymap write is representable")
                || text.contains("unlock, reset, bootloader, EEPROM, macro, encoder, settings, dynamic-entry, and keymap writes unrepresentable"),
              text.contains("Live HID capture remains **BLOCKED**"), text.contains("exact environment inventory"),
              text.contains("No IOHID API was called"), text.contains("no device was enumerated or opened"),
              text.contains("no GUI was launched"), text.contains("no report was sent to a real device"),
              text.contains("does not prove device-side behavior"), !text.contains("Verdict: **PASS**"),
              !text.contains("Live capture PASS"), !text.contains("device compatibility verified") else {
            throw ValidatorError("sp5b_misleading_conclusion")
        }
    }

    static func validateRunner(_ evidence: SP5BEvidence, repository: URL) throws {
        guard Set(evidence.runnerSourceSha256.keys) == SP5BRunnerBinding.sourcePaths,
              let first = evidence.legs.first else { throw ValidatorError("sp5b_runner_source_set_mismatch") }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("sp5b_runner_commit_missing")
        }
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha else {
            throw ValidatorError("sp5b_runner_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp5b_runner_not_ancestor")
        }
        for path in SP5BRunnerBinding.sourcePaths.sorted() {
            guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha):\(path)"], acceptedStatuses: [0, 1, 128]).status == 0 else {
                throw ValidatorError("sp5b_runner_source_missing", path)
            }
            guard try git.text(["cat-file", "-t", "\(first.runnerCommitSha):\(path)"]) == "blob" else {
                throw ValidatorError("sp5b_runner_source_not_blob", path)
            }
            let committed = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else {
                throw ValidatorError("sp5b_runner_source_hash_mismatch", path)
            }
            guard try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else {
                throw ValidatorError("sp5b_runner_source_dirty", path)
            }
        }
    }

    private static func validateFixtureProvenance(_ repository: URL) throws {
        let provenance = repository.appendingPathComponent("evidence/phase0/fixtures/synthetic/provenance.json")
        let manifest = repository.appendingPathComponent("evidence/phase0/fixtures/synthetic/manifest.sha256")
        guard isRegular(provenance), isRegular(manifest), let data = try? Data(contentsOf: provenance),
              let document = try? JSONDecoder().decode(SP5BSyntheticProvenance.self, from: data),
              document == SP5BProvenanceLedger.synthetic,
              document.files.allSatisfy({ entry in
                  let url = provenance.deletingLastPathComponent().appendingPathComponent(entry.path)
                  return isRegular(url) && (try? Data(contentsOf: url)).map(Canonical.sha256) == entry.sha256
              }),
              let text = try? String(contentsOf: manifest, encoding: .utf8),
              let expectedManifest = try? fixtureManifest(at: provenance.deletingLastPathComponent()),
              parseManifest(text) == expectedManifest else {
            throw ValidatorError("sp5b_fixture_provenance_mismatch")
        }
    }

    private static func validateSourceProvenance(_ repository: URL, facts: SP5BSourceFactsArtifact) throws {
        let anchoredNames = Set(facts.whitelist.flatMap(\.anchors).map(\.repository))
        guard anchoredNames == Set(SP5BProvenanceLedger.repositories.keys) else {
            throw ValidatorError("sp5b_source_provenance_mismatch")
        }
        for name in anchoredNames {
            let anchors = facts.whitelist.flatMap(\.anchors).filter { $0.repository == name }
            let url = repository.appendingPathComponent("evidence/phase0/sources/repos/\(name)/provenance.json")
            guard isRegular(url), let data = try? Data(contentsOf: url),
                  let actual = try? JSONDecoder().decode(SP5BRepositoryProvenance.self, from: data),
                  let expected = SP5BProvenanceLedger.repositories[name], actual == expected,
                  PinnedSourceLedger.entries.contains(where: {
                      $0.name == name && $0.commit == actual.upstreamRef && $0.tree == actual.tree
                  }),
                  anchors.allSatisfy({ anchor in
                      anchor.revision == actual.upstreamRef && anchor.tree == actual.tree
                          && actual.files.contains(where: {
                              $0.path == anchor.path && $0.gitBlob == anchor.gitBlob && $0.sha256 == anchor.fileSha256
                          })
                          && anchor.licensePath == actual.license.path
                          && anchor.licenseGitBlob == actual.license.gitBlob
                          && anchor.licenseSha256 == actual.license.sha256
                  }), try validateHistoricalBytes(actual, base: url.deletingLastPathComponent()) else {
                throw ValidatorError("sp5b_source_provenance_mismatch", name)
            }
        }
    }

    private static func validateHistoricalBytes(_ document: SP5BRepositoryProvenance, base: URL) throws -> Bool {
        for file in document.files {
            let bytes = try Data(contentsOf: base.appendingPathComponent(file.copiedPath))
            try ProvenanceValidator.validate(bytes, expected: .init(sha256: file.sha256, gitBlob: file.gitBlob))
        }
        let license = try Data(contentsOf: base.appendingPathComponent(document.license.copiedPath))
        try ProvenanceValidator.validate(
            license, expected: .init(sha256: document.license.sha256, gitBlob: document.license.gitBlob)
        )
        return true
    }

    private static func parseManifest(_ text: String) -> [String: String]? {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2, values.updateValue(String(fields[0]), forKey: String(fields[1])) == nil else { return nil }
        }
        return values
    }

    private static func fixtureManifest(at directory: URL) throws -> [String: String] {
        let names = Set(["README.md", "phase0.vil", "provenance.json", "via-layout.json", "vial-query-replay.json"])
        return try Dictionary(uniqueKeysWithValues: names.map { name in
            (name, Canonical.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))
        })
    }

    private static func requireExact<T: Codable & Equatable>(_ directory: URL, _ name: String, _ expected: T, code: String) throws {
        let actual: T = try exactDecode(directory, name, code: code)
        guard actual == expected else { throw ValidatorError(code) }
    }
    private static func exactDecode<T: Codable>(_ directory: URL, _ name: String, code: String) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard isRegular(url), let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(T.self, from: data),
              let canonical = try? pretty(decoded), data == canonical else { throw ValidatorError(code) }
        return decoded
    }
    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func isRegular(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 1_048_576
    }
    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

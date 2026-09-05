import Foundation
import Phase0Support

enum SP4BDirectoryValidator {
    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        gitRepository: URL? = nil
    ) throws -> GateValidationReport {
        let evidence: SP4BEvidence = try exactDecode(directory, "evidence.json", code: "malformed_sp4b_evidence")
        do { try evidence.validate() } catch let error as SP4BValidationError { throw ValidatorError("sp4b_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory, repository: repository)
        try validateBindings(evidence, directory: directory, repository: repository)
        try validateConclusion(directory, evidence: evidence)
        try validateRunner(evidence, repository: gitRepository ?? repository)
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
            guard isLowercaseSHA256(hash), SP4BDirectoryLayout.artifactNames.contains(name),
                  !name.contains("/"), !name.contains(".."), names.insert(name).inserted else {
                throw ValidatorError("sp4b_manifest_membership_mismatch")
            }
            let file = directory.appendingPathComponent(name)
            guard isRegular(file), let bytes = try? Data(contentsOf: file), Canonical.sha256(bytes) == hash else {
                throw ValidatorError("sp4b_manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard names == SP4BDirectoryLayout.artifactNames, actual == SP4BDirectoryLayout.artifactNames else {
            throw ValidatorError("sp4b_manifest_membership_mismatch")
        }
    }

    static func validateArtifacts(_ directory: URL, repository: URL) throws {
        let roundTrip: SP4BRoundTripArtifact
        let bounds: SP4BBoundsArtifact
        let axes: SP4BAxesArtifact
        let facts: SP4BSourceFactsArtifact
        do {
            roundTrip = try SP4BScenarios.roundTrip(repository: repository)
            bounds = try SP4BScenarios.bounds()
            let candidateRoot = directory.deletingLastPathComponent()
            let candidateSP4A = candidateRoot.appendingPathComponent("sp4a/evidence.json")
            let evidenceRoot = isRegular(candidateSP4A) ? candidateRoot : nil
            axes = try SP4BScenarios.axes(repository: repository, evidenceRoot: evidenceRoot)
            facts = try SP4BScenarios.sourceFacts(repository: repository)
        } catch { throw ValidatorError("sp4b_fixture_recompute_failed") }
        try requireExact(directory, "round-trip.json", roundTrip, code: "sp4b_round_trip_recompute_mismatch")
        try requireExact(directory, "bounds.json", bounds, code: "sp4b_bounds_recompute_mismatch")
        try requireExact(directory, "axes.json", axes, code: "sp4b_axes_recompute_mismatch")
        try requireExact(directory, "source-facts.json", facts, code: "sp4b_source_facts_mismatch")
        guard SP4BScenarios.validates(roundTrip), bounds.results.count == 4,
              Set(bounds.results.map(\.limit)) == ["inputBytes", "depth", "collectionElements", "scalarBytes"],
              bounds.results.allSatisfy(\.exactAccepted), validAxes(axes) else {
            throw ValidatorError("sp4b_fixture_assertion_mismatch")
        }
        try validateSyntheticProvenance(repository)
        try validateSourceProvenance(repository, name: "via-app", commit: "65b50efc8e14e6feabff38ce20c191edf1f078f9", tree: "9d76a3b8a5b7ec976c3ef9048c49caa09779e25b")
        try validateSourceProvenance(repository, name: "qmk", commit: "3c73e928ab40b026adcff7112c8fc36a8d96152a", tree: "12276f044f5c8aa2a96075cb72c5d2c2d89955fe")
        try validateSourceProvenance(repository, name: "vial-gui", commit: "aef8222a2d0429a183b2ed692d5f9efcfd383f08", tree: "22a59cd7c2f7c4ef746378e259f6de0f1faa3633")
    }

    static func validateBindings(_ evidence: SP4BEvidence, directory: URL, repository: URL) throws {
        let environmentURL = repository.appendingPathComponent("evidence/phase0/environment.json")
        guard isRegular(environmentURL), let environmentData = try? Data(contentsOf: environmentURL) else {
            throw ValidatorError("sp4b_environment_missing")
        }
        let environment: EnvironmentEvidence
        do {
            try PrivacySafeEnvironmentValidator.validateJSON(environmentData)
            environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        } catch { throw ValidatorError("sp4b_environment_unsafe") }
        let environmentHash = Canonical.sha256(environmentData)
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == environmentHash }) else {
            throw ValidatorError("sp4b_environment_hash_mismatch")
        }
        guard environment.applications.first(where: { $0.name == "VIA" })?.status == .absent,
              !environment.hidSummary.devices.contains(where: { $0.product?.contains("VIA-approved") == true }) else {
            throw ValidatorError("sp4b_environment_inventory_mismatch")
        }
        try requireBlocker(evidence, "sp4b.deviceProtocol", "approved_via_device_absent", ["environment-inventory", "approved-via-device"])
        try requireBlocker(evidence, "sp4b.keycodeDialect", "firmware_keycode_dictionary_unobserved", ["environment-inventory", "approved-via-device"])
        try requireBlocker(evidence, "sp4b.importer", "via_app_absent_and_approved_device_absent", ["environment-inventory", "VIA"])
        for leg in evidence.legs where leg.verdict == .pass {
            guard let path = SP4BDirectoryLayout.legArtifacts[leg.legID], leg.artifactPath == path,
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(path)),
                  leg.artifactSha256 == Canonical.sha256(bytes) else { throw ValidatorError("sp4b_artifact_binding_mismatch", leg.legID) }
        }
    }

    static func validateConclusion(_ directory: URL, evidence: SP4BEvidence) throws {
        let url = directory.appendingPathComponent("SP-4B-CONCLUSION.md")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8), evidence.verdict == .blocked,
              text.contains("Verdict: **BLOCKED**"), text.contains("exact deterministic synthetic `.layout.json` fixture"),
              text.contains("synthetic, not sourced, pinned, or live"), text.contains("not claimed as a stable interchange standard"),
              text.contains("evidence XOR a complete blocker"), text.contains("device protocol, firmware-selected keycode dialect, and official importer compatibility BLOCKED"),
              text.contains("Protocol and keycode dictionaries are firmware-dependent"), text.contains("VIA protocol 13 is not Vial-GUI compatible"),
              text.contains("environment inventory reports VIA absent and no approved VIA device"), text.contains("No GUI was launched"),
              text.contains("no HID/device access or write occurred"), text.contains("no deployment was exported"),
              !text.contains("Verdict: **PASS**"), !text.contains("device compatibility verified"),
              !text.contains("official importer PASS") else { throw ValidatorError("sp4b_misleading_conclusion") }
    }

    static func validateRunner(_ evidence: SP4BEvidence, repository: URL) throws {
        guard Set(evidence.runnerSourceSha256.keys) == SP4BRunnerBinding.sourcePaths,
              let first = evidence.legs.first else { throw ValidatorError("sp4b_runner_source_set_mismatch") }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("sp4b_runner_commit_missing")
        }
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha else {
            throw ValidatorError("sp4b_runner_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp4b_runner_not_ancestor")
        }
        for path in SP4BRunnerBinding.sourcePaths.sorted() {
            guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha):\(path)"], acceptedStatuses: [0, 1, 128]).status == 0 else {
                throw ValidatorError("sp4b_runner_source_missing", path)
            }
            let committed = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else {
                throw ValidatorError("sp4b_runner_source_hash_mismatch", path)
            }
            guard try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else {
                throw ValidatorError("sp4b_runner_source_dirty", path)
            }
        }
    }

    private static func validAxes(_ artifact: SP4BAxesArtifact) -> Bool {
        artifact.axes.map(\.axisID) == SP4BAxisID.allCases
            && artifact.axes.allSatisfy { ($0.evidence != nil) != ($0.blocker != nil) }
            && artifact.axes.filter { $0.verdict == .pass }.map(\.axisID) == [.definitionSchema, .layoutFormat]
            && artifact.axes.filter { $0.verdict == .blocked }.map(\.axisID) == [.deviceProtocol, .keycodeDialect, .officialImporterCompatibility]
            && artifact.axes.filter { $0.verdict == .blocked }.allSatisfy { complete($0.blocker) }
            && artifact.firmwareDependentProtocolAndKeycodeDictionaries && !artifact.viaProtocol13VialGUICompatible
    }

    private static func requireBlocker(_ evidence: SP4BEvidence, _ id: String, _ reason: String, _ command: [String]) throws {
        guard let leg = evidence.legs.first(where: { $0.legID == id }), leg.verdict == .blocked,
              leg.blocker?.blockedBy == reason, leg.blocker?.detectCommand == command else {
            throw ValidatorError("sp4b_blocker_mismatch", id)
        }
    }
    private static func complete(_ blocker: SP1Blocker?) -> Bool {
        guard let blocker else { return false }
        return !blocker.blockedBy.isEmpty && !blocker.detectCommand.isEmpty
            && blocker.detectCommand.allSatisfy { !$0.isEmpty }
            && !blocker.prerequisite.isEmpty && !blocker.unblockAction.isEmpty
    }
    private static func validateSyntheticProvenance(_ repository: URL) throws {
        let provenance = repository.appendingPathComponent("evidence/phase0/fixtures/synthetic/provenance.json")
        let manifest = repository.appendingPathComponent("evidence/phase0/fixtures/synthetic/manifest.sha256")
        guard isRegular(provenance), isRegular(manifest), let data = try? Data(contentsOf: provenance),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["evidenceKind"] as? String == "synthetic", root["generator"] as? String == "Spikes/Scripts/generate-synthetic-fixtures.sh",
              let files = root["files"] as? [[String: String]], files.contains(where: { $0 == ["path": "via-layout.json", "sha256": SP4BScenarios.fixtureSha256] }),
              let fixture = try? Data(contentsOf: repository.appendingPathComponent(SP4BScenarios.fixturePath)),
              Canonical.sha256(fixture) == SP4BScenarios.fixtureSha256, fixture.last != 10,
              let manifestText = try? String(contentsOf: manifest, encoding: .utf8),
              manifestText.split(separator: "\n").contains(where: { $0 == "\(SP4BScenarios.fixtureSha256)  via-layout.json" }) else {
            throw ValidatorError("sp4b_fixture_provenance_mismatch")
        }
    }
    private static func validateSourceProvenance(_ repository: URL, name: String, commit: String, tree: String) throws {
        let url = repository.appendingPathComponent("evidence/phase0/sources/repos/\(name)/provenance.json")
        guard isRegular(url), let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["name"] as? String == name, root["upstream_ref"] as? String == commit,
              root["tree"] as? String == tree, root["files"] is [[String: Any]], root["license"] is [String: Any] else {
            throw ValidatorError("sp4b_source_provenance_mismatch", name)
        }
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
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= ViaDefinitionLimits.maximumInputBytes
    }
    private static func isLowercaseSHA256(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}

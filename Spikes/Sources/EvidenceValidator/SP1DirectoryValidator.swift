import Foundation
import Phase0Support

enum SP1DirectoryValidator {
    private static let artifactNames: Set<String> = [
        "O7-ADDENDUM.md", "SP-1-CONCLUSION.md", "evidence.json",
        "live-aggregate-counts.json", "product-stamped-synthetic.json",
    ]

    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> GateValidationReport {
        let evidenceURL = directory.appendingPathComponent("evidence.json")
        guard isRegularFile(evidenceURL) else { throw ValidatorError("missing_evidence_document") }
        let evidence: SP1Evidence
        do { evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: evidenceURL)) }
        catch { throw ValidatorError("malformed_sp1_evidence", String(describing: error)) }
        let environment = directory.deletingLastPathComponent().appendingPathComponent("environment.json")
        let candidateEnvironmentSha256 = isRegularFile(environment)
            ? try Canonical.sha256(Data(contentsOf: environment))
            : nil
        do { try evidence.validate(candidateEnvironmentSha256: candidateEnvironmentSha256) }
        catch let error as SP1ValidationError { throw ValidatorError("sp1_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory)
        try validateRunnerBinding(evidence, repository: repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: evidence.g0Status)
    }

    static func validateRunnerBinding(_ evidence: SP1Evidence, repository: URL) throws {
        guard let first = evidence.legs.first else { throw ValidatorError("sp1_runner_identity_missing") }
        let commitSha = evidence.selectedTapIdentity?.runnerCommitSha ?? first.runnerCommitSha
        let treeSha = evidence.selectedTapIdentity?.runnerTreeSha ?? first.runnerTreeSha
        guard Set(evidence.runnerSourceSha256.keys) == SP1RunnerBinding.sourcePaths else {
            throw ValidatorError("sp1_runner_source_set_mismatch")
        }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let commitCheck = try git.run(["cat-file", "-e", "\(commitSha)^{commit}"], acceptedStatuses: [0, 1, 128])
        guard commitCheck.status == 0 else { throw ValidatorError("sp1_runner_commit_missing") }
        let actualTree = try git.text(["rev-parse", "\(commitSha)^{tree}"])
        guard actualTree == treeSha else { throw ValidatorError("sp1_runner_tree_mismatch") }
        let ancestor = try git.run(["merge-base", "--is-ancestor", commitSha, "HEAD"], acceptedStatuses: [0, 1])
        guard ancestor.status == 0 else { throw ValidatorError("sp1_runner_not_ancestor") }

        for path in SP1RunnerBinding.sourcePaths.sorted() {
            let object = try git.run(["cat-file", "-e", "\(commitSha):\(path)"], acceptedStatuses: [0, 1, 128])
            guard object.status == 0 else { throw ValidatorError("sp1_runner_source_missing", path) }
            let committed = try git.run(["cat-file", "blob", "\(commitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else {
                throw ValidatorError("sp1_runner_source_hash_mismatch", path)
            }
            let workingURL = repository.appendingPathComponent(path)
            guard isRegularFile(workingURL), let working = try? Data(contentsOf: workingURL), working == committed else {
                throw ValidatorError("sp1_runner_source_dirty", path)
            }
            let status = try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path])
            guard status.isEmpty else { throw ValidatorError("sp1_runner_source_dirty", path) }
        }
    }

    private static func validateArtifacts(_ directory: URL) throws {
        let syntheticURL = directory.appendingPathComponent("product-stamped-synthetic.json")
        let synthetic = try jsonObject(syntheticURL, code: "sp1_malformed_product_marker")
        guard let object = synthetic as? [String: Any], Set(object.keys) == ["evidenceKind", "productStampedSynthetic", "records"],
              object["evidenceKind"] as? String == EvidenceKind.synthetic.rawValue,
              object["productStampedSynthetic"] as? Bool == true,
              let records = object["records"] as? [[String: Any]], records.count == InputEventKind.allCases.count else {
            throw ValidatorError("sp1_malformed_product_marker")
        }
        var kinds = Set<String>()
        for record in records {
            guard Set(record.keys) == ["dropped", "isAutoRepeat", "keyCode", "kind", "marker"],
                  record["dropped"] as? Bool == true,
                  record["isAutoRepeat"] is Bool,
                  record["keyCode"] is NSNumber,
                  let marker = record["marker"] as? NSNumber, marker.uint64Value == ProductSyntheticMarker.value,
                  let kind = record["kind"] as? String, InputEventKind(rawValue: kind) != nil,
                  kinds.insert(kind).inserted else { throw ValidatorError("sp1_malformed_product_marker") }
        }

        let liveURL = directory.appendingPathComponent("live-aggregate-counts.json")
        let live = try jsonObject(liveURL, code: "sp1_live_event_detail_forbidden")
        guard let object = live as? [String: Any],
              Set(object.keys) == ["evidenceKind", "systemShortcutObservedCount", "unmarkedObservedCount"],
              object["evidenceKind"] as? String == EvidenceKind.live.rawValue,
              let shortcut = object["systemShortcutObservedCount"] as? NSNumber, shortcut.intValue >= 0,
              let unmarked = object["unmarkedObservedCount"] as? NSNumber, unmarked.intValue >= 0 else {
            throw ValidatorError("sp1_live_event_detail_forbidden")
        }
    }

    private static func verifyManifest(_ directory: URL) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        guard isRegularFile(manifest), let text = try? String(contentsOf: manifest, encoding: .utf8) else { throw ValidatorError("missing_manifest") }
        var expected = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { throw ValidatorError("malformed_manifest") }
            let name = String(parts[1])
            guard artifactNames.contains(name), expected.insert(name).inserted else { throw ValidatorError("manifest_membership_mismatch") }
            let file = directory.appendingPathComponent(name)
            guard isRegularFile(file), let data = try? Data(contentsOf: file), Canonical.sha256(data) == String(parts[0]) else {
                throw ValidatorError("manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard expected == artifactNames, actual == artifactNames else { throw ValidatorError("manifest_membership_mismatch") }
    }

    private static func jsonObject(_ url: URL, code: String) throws -> Any {
        guard isRegularFile(url), let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else { throw ValidatorError(code) }
        return object
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 1_048_576
    }
}

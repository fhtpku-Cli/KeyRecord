import Foundation
import Phase0Support

enum AtomicityHistoricalValidator {
    private static let artifactNames: Set<String> = ["result.json"]

    @discardableResult
    static func validate(directory: URL, repository: URL) throws -> AtomicityEvidence {
        let resultData = try verifyManifest(directory)
        try validateSourceHashShape(resultData)
        let evidence: AtomicityEvidence
        do {
            evidence = try JSONDecoder().decode(AtomicityEvidence.self, from: resultData)
        } catch {
            throw ValidatorError("malformed_atomicity_evidence", String(describing: error))
        }

        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let commit = try git.run(
            ["cat-file", "-e", "\(evidence.runnerCommitSha)^{commit}"],
            acceptedStatuses: [0, 1, 128]
        )
        guard commit.status == 0 else { throw ValidatorError("atomicity_runner_commit_missing") }
        guard try git.text(["rev-parse", "\(evidence.runnerCommitSha)^{tree}"]) == evidence.runnerTreeSha else {
            throw ValidatorError("atomicity_runner_tree_mismatch")
        }
        let ancestor = try git.run(
            ["merge-base", "--is-ancestor", evidence.runnerCommitSha, "HEAD"],
            acceptedStatuses: [0, 1]
        )
        guard ancestor.status == 0 else { throw ValidatorError("atomicity_runner_not_ancestor") }

        for path in AtomicityRunnerBinding.sourcePaths.sorted() {
            let type = try git.run(
                ["cat-file", "-t", "\(evidence.runnerCommitSha):\(path)"],
                acceptedStatuses: [0, 1, 128]
            )
            guard type.status == 0 else { throw ValidatorError("atomicity_runner_source_missing", path) }
            guard String(decoding: type.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "blob" else {
                throw ValidatorError("atomicity_runner_source_not_blob", path)
            }
            let source = try git.run(["cat-file", "blob", "\(evidence.runnerCommitSha):\(path)"]).stdout
            guard source.count <= 1_048_576 else { throw ValidatorError("atomicity_runner_source_too_large", path) }
            if let expected = evidence.runnerSourceSha256?[path], Canonical.sha256(source) != expected {
                throw ValidatorError("atomicity_runner_source_hash_mismatch", path)
            }
        }
        return evidence
    }

    private static func verifyManifest(_ directory: URL) throws -> Data {
        let manifestURL = directory.appendingPathComponent("manifest.sha256")
        guard isRegularFile(manifestURL), let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw ValidatorError("missing_atomicity_manifest")
        }
        let lines = manifest.split(separator: "\n")
        guard lines.count == 1 else { throw ValidatorError("atomicity_manifest_membership_mismatch") }
        let fields = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 2, fields[1] == "result.json" else {
            throw ValidatorError("atomicity_manifest_membership_mismatch")
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard actual == artifactNames else { throw ValidatorError("atomicity_manifest_membership_mismatch") }
        let resultURL = directory.appendingPathComponent("result.json")
        guard isRegularFile(resultURL), let result = try? Data(contentsOf: resultURL), Canonical.sha256(result) == fields[0] else {
            throw ValidatorError("atomicity_manifest_hash_mismatch")
        }
        return result
    }

    private static func validateSourceHashShape(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = object["schemaVersion"] as? Int else {
            throw ValidatorError("malformed_atomicity_evidence")
        }
        if schemaVersion == 1 {
            guard object["runnerSourceSha256"] == nil else { throw ValidatorError("atomicity_runner_source_set_mismatch") }
            return
        }
        guard schemaVersion == 2, let hashes = object["runnerSourceSha256"] as? [String: String],
              Set(hashes.keys) == AtomicityRunnerBinding.sourcePaths else {
            throw ValidatorError("atomicity_runner_source_set_mismatch")
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 1_048_576
    }
}

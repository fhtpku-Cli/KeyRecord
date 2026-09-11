import Foundation
import Phase0Support

enum SP6ALegacyHistoryAnchorValidator {
    static func validate(directory: URL, repository: URL) throws {
        let path = SP6ANamespaceHistoryContract.legacyAnchorPath
        let anchorCommit = SP6ANamespaceHistoryContract.legacyAnchorCommitSha
        let legacyURL = directory.appendingPathComponent(SP6ANamespaceHistoryContract.legacyAnchorArtifactName)
        guard let workingBytes = try? Data(contentsOf: legacyURL) else {
            throw ValidatorError("sp6a_legacy_history_anchor_working_tree_mismatch")
        }
        guard Canonical.sha256(workingBytes) == SP6ANamespaceHistoryContract.legacyAnchorFileSha256 else {
            throw ValidatorError("sp6a_legacy_history_anchor_hash_mismatch")
        }

        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.text(["rev-parse", "--is-shallow-repository"]) == "false" else {
            throw ValidatorError("sp6a_legacy_history_anchor_history_incomplete")
        }
        guard try git.run(["cat-file", "-e", "\(anchorCommit)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("sp6a_legacy_history_anchor_commit_missing")
        }
        guard try git.text(["rev-parse", "\(anchorCommit)^{tree}"]) == SP6ANamespaceHistoryContract.legacyAnchorTreeSha else {
            throw ValidatorError("sp6a_legacy_history_anchor_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", anchorCommit, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp6a_legacy_history_anchor_not_ancestor")
        }
        let descendantTouches = try git.text([
            "log", "--format=%H", "\(anchorCommit)..HEAD", "--", path,
        ]).split(separator: "\n")
        guard descendantTouches.isEmpty else { throw ValidatorError("sp6a_legacy_history_anchor_descendant_touch") }
        let candidates = try git.text([
            "log", "--format=%H", "--diff-filter=A", "HEAD", "--", path,
        ]).split(separator: "\n").map(String.init)
        guard candidates.count == 1 else { throw ValidatorError("sp6a_legacy_history_anchor_candidate_set_invalid") }
        guard candidates[0] == anchorCommit else {
            throw ValidatorError("sp6a_legacy_history_anchor_commit_selection_mismatch")
        }
        let resolvedBlob = try git.text(["rev-parse", "\(anchorCommit):\(path)"])
        guard resolvedBlob == SP6ANamespaceHistoryContract.legacyAnchorBlobSha1 else {
            throw ValidatorError("sp6a_legacy_history_anchor_blob_mismatch")
        }
        let blobBytes = try git.run(["cat-file", "blob", resolvedBlob]).stdout
        guard Canonical.sha256(blobBytes) == SP6ANamespaceHistoryContract.legacyAnchorFileSha256,
              workingBytes == blobBytes else {
            throw ValidatorError("sp6a_legacy_history_anchor_hash_mismatch")
        }
    }
}

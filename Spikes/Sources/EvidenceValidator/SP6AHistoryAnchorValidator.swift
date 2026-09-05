import Foundation
import Phase0Support

enum SP6AHistoryAnchorValidator {
    static func validate(
        anchor: SP6ANamespaceHistoryAnchor, keychain: SP6AKeychainArtifact,
        directory: URL, repository: URL, evidence: SP6AEvidence
    ) throws {
        guard anchor.schemaVersion == 1,
              anchor.anchorPath == SP6ANamespaceHistoryContract.anchorPath,
              keychain.historyAnchor == anchor else {
            throw ValidatorError("sp6a_history_anchor_contract_invalid")
        }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(anchor.anchorCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("sp6a_history_anchor_commit_missing")
        }
        guard try git.text(["rev-parse", "\(anchor.anchorCommitSha)^{tree}"]) == anchor.anchorTreeSha else {
            throw ValidatorError("sp6a_history_anchor_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", anchor.anchorCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp6a_history_anchor_not_ancestor")
        }
        let parent = try git.text(["rev-parse", "\(anchor.anchorCommitSha)^1^{commit}"])
        guard parent == anchor.sourceCommitSha,
              evidence.legs.allSatisfy({ $0.runnerCommitSha == anchor.sourceCommitSha }) else {
            throw ValidatorError("sp6a_history_anchor_source_parent_mismatch")
        }
        let changed = try git.text([
            "diff-tree", "--no-commit-id", "--name-only", "-r", parent, anchor.anchorCommitSha,
        ]).split(separator: "\n").map(String.init)
        guard changed == [anchor.anchorPath] else { throw ValidatorError("sp6a_history_anchor_commit_scope_mismatch") }
        let resolvedBlob = try git.text(["rev-parse", "\(anchor.anchorCommitSha):\(anchor.anchorPath)"])
        guard resolvedBlob == anchor.anchorBlobSha1 else { throw ValidatorError("sp6a_history_anchor_blob_mismatch") }
        let blobBytes = try git.run(["cat-file", "blob", resolvedBlob]).stdout
        guard Canonical.sha256(blobBytes) == anchor.anchorFileSha256 else {
            throw ValidatorError("sp6a_history_anchor_hash_mismatch")
        }
        let anchorURL = directory.appendingPathComponent(SP6ANamespaceHistoryContract.anchorArtifactName)
        guard let workingBytes = try? Data(contentsOf: anchorURL), workingBytes == blobBytes,
              let embeddedBytes = try? pretty(keychain.attemptHistory), embeddedBytes == blobBytes else {
            throw ValidatorError("sp6a_keychain_attempt_history_anchor_mismatch")
        }
    }

    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        return data
    }
}

import Foundation
import Phase0Support

enum SP6BHistoricalSealValidator {
    static func validate(evidence: SP6BEvidence, directory: URL, git: GitRunner) throws {
        guard let first = evidence.legs.first,
              first.runnerCommitSha == SP6BHistoricalSealContract.runnerCommitSha,
              first.runnerTreeSha == SP6BHistoricalSealContract.runnerTreeSha else {
            throw ValidatorError("sp6b_evidence_runner_rewrite")
        }
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == SP6BHistoricalSealContract.executionEnvironmentSha256 }) else {
            throw ValidatorError("sp6b_execution_environment_mismatch")
        }
        let seal = SP6BHistoricalSealContract.sealCommitSha
        guard try git.run(["cat-file", "-e", "\(seal)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("sp6b_seal_commit_missing")
        }
        guard try git.run(["merge-base", "--is-ancestor", seal, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp6b_seal_not_ancestor")
        }
        for relative in SP6BDirectoryLayout.fixedArtifactNames.union(["manifest.sha256"]) {
            let working = try Data(contentsOf: directory.appendingPathComponent(relative))
            let sealed = try git.run(["cat-file", "blob", "\(seal):\(SP6BHistoricalSealContract.sealPath)/\(relative)"]).stdout
            guard working == sealed else { throw ValidatorError("sp6b_seal_blob_mismatch", relative) }
        }
    }
}

import Foundation
import Phase0Support

struct SP6BSourceFileContract: Codable, Equatable {
    let path: String
    let blob: String
    let sha256: String
    let lineCount: Int
}

struct SP6BCandidateContract: Codable, Equatable {
    let id: String
    let name: String
    let canonicalURL: String
    let ownerRepo: String
    let commit: String
    let tree: String
    let latestCommitDate: String
    let licenseBlob: String
    let licenseSha256: String
    let packageBlob: String
    let provenancePath: String
    let provenanceBlob: String
    let provenanceSha256: String
    let treeListingSha256: String
    let runtimeDependencyCount: Int
    let minimumMacOSMajor: Int
    let sourceLOC: Int
    let includedFiles: [SP6BSourceFileContract]
    let excludedSourcePaths: [String]
}

struct SP6BSourceContractDocument: Codable {
    let schemaVersion: Int
    let compilerIdentitySha256: String
    let benchmarkExpectedTag: String
    let deterministicBuild: SP6BDeterministicBuildContract
    let candidates: [SP6BCandidateContract]
}

struct SP6BDeterministicBuildContract: Codable {
    let archiveSha256: String
    let slices: [SP6BDeterministicSliceContract]
}

struct SP6BDeterministicSliceContract: Codable {
    let architecture: String
    let sliceSha256: String
    let objects: [String: String]
}

struct SP6BSourceAuditReceipt: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let candidates: [SP6BCandidateContract]
}

private struct ProvenanceFile: Decodable {
    let path: String
    let gitBlob: String
    let sha256: String
    enum CodingKeys: String, CodingKey { case path, gitBlob = "git_blob", sha256 }
}

private struct ProvenanceLedger: Decodable {
    let name: String
    let url: String
    let upstreamRef: String
    let tree: String
    let files: [ProvenanceFile]
    let license: ProvenanceFile
    enum CodingKeys: String, CodingKey { case name, url, upstreamRef = "upstream_ref", tree, files, license }
}

enum SP6BSourceValidator {
    static let contractPath = "Spikes/Scripts/sp6b-source-contract.json"

    static func validate(
        evidence: SP6BEvidence, evaluation: SP6BCandidateEvaluation, snapshot: D12Snapshot,
        sourceAudit: SP6BSourceAuditReceipt, generatedTimes: [String], directory: URL, repository: URL
    ) throws -> SP6BSourceContractDocument {
        guard let runner = evidence.legs.first?.runnerCommitSha else { throw ValidatorError("sp6b_source_contract") }
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let contractData = try git.run(["cat-file", "blob", "\(runner):\(contractPath)"]).stdout
        let contract: SP6BSourceContractDocument = try decode(contractData, code: "sp6b_source_contract")
        guard contract.schemaVersion == 1, SP6BDirectoryValidator.isSHA256(contract.compilerIdentitySha256),
              SP6BDirectoryValidator.isSHA256(contract.benchmarkExpectedTag),
              SP6BDirectoryValidator.isSHA256(contract.deterministicBuild.archiveSha256),
              contract.deterministicBuild.slices.map(\.architecture) == ["x86_64", "arm64"],
              contract.deterministicBuild.slices.allSatisfy({
                  SP6BDirectoryValidator.isSHA256($0.sliceSha256)
                      && $0.objects.count == 6
                      && Set($0.objects.keys) == ["argon2.o", "core.o", "blake2b.o", "thread.o", "encoding.o", "ref.o"]
                      && $0.objects.values.allSatisfy(SP6BDirectoryValidator.isSHA256)
              }),
              Set(contract.candidates.map(\.id)) == ["phc", "swift"],
              sourceAudit.schemaVersion == 1, sourceAudit.candidates == contract.candidates,
              Set(generatedTimes + [evidence.generatedAt, evaluation.generatedAt, snapshot.generatedAt, sourceAudit.generatedAt]).count == 1 else {
            throw ValidatorError("sp6b_source_contract")
        }
        try validateCandidates(evaluation.candidates, snapshot: snapshot, contract: contract)
        try validateProvenance(contract, runner: runner, git: git)
        return contract
    }

    static func validateHistory(
        evidence: SP6BEvidence, generatedAt: String, directory: URL, repository: URL
    ) throws {
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        try validateHistory(evidence: evidence, generatedAt: generatedAt, directory: directory, git: git)
    }

    private static func validateCandidates(
        _ candidates: [Argon2Candidate], snapshot: D12Snapshot, contract: SP6BSourceContractDocument
    ) throws {
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let snapshots = Dictionary(uniqueKeysWithValues: snapshot.candidates.map { ($0.id, $0) })
        for expected in contract.candidates {
            guard let candidate = byID[expected.id], let d12 = snapshots[expected.id],
                  candidate.canonicalURL == expected.canonicalURL, candidate.commit == expected.commit,
                  candidate.tree == expected.tree, candidate.latestCommitDate == expected.latestCommitDate,
                  candidate.runtimeDependencyCount == expected.runtimeDependencyCount,
                  candidate.minimumMacOSMajor == expected.minimumMacOSMajor, candidate.sourceLOC == expected.sourceLOC,
                  candidate.licenseApproved, candidate.vectorsPassed, candidate.dualArchMacOS14Build,
                  candidate.unresolvedSignificantFindings == 0, d12.ownerRepo == expected.ownerRepo,
                  d12.commit == expected.commit else { throw ValidatorError("sp6b_candidate_provenance") }
        }
    }

    private static func validateProvenance(
        _ contract: SP6BSourceContractDocument, runner: String, git: GitRunner
    ) throws {
        for expected in contract.candidates {
            guard try git.text(["rev-parse", "\(runner):\(expected.provenancePath)"]) == expected.provenanceBlob else {
                throw ValidatorError("sp6b_provenance_blob", expected.id)
            }
            let data = try git.run(["cat-file", "blob", "\(runner):\(expected.provenancePath)"]).stdout
            let ledger: ProvenanceLedger = try decode(data, code: "sp6b_provenance_ledger")
            let package = ledger.files.first { $0.path == "Package.swift" }
            guard Canonical.sha256(data) == expected.provenanceSha256, ledger.name == expected.name,
                  ledger.url == expected.canonicalURL, ledger.upstreamRef == expected.commit, ledger.tree == expected.tree,
                  ledger.license.gitBlob == expected.licenseBlob, ledger.license.sha256 == expected.licenseSha256,
                  package?.gitBlob == expected.packageBlob else { throw ValidatorError("sp6b_provenance_ledger", expected.id) }
        }
    }

    private static func validateHistory(
        evidence: SP6BEvidence, generatedAt: String, directory: URL, git: GitRunner
    ) throws {
        let path = SP6BHistoricalSealContract.sealPath
        let candidates = try git.text(["log", "--format=%H", "HEAD", "--", path]).split(separator: "\n").map(String.init)
        var commit: String?
        for candidate in candidates {
            let changed = try git.text(["diff-tree", "--no-commit-id", "--name-only", "-r", "\(candidate)^1", candidate]).split(separator: "\n").map(String.init)
            guard !changed.isEmpty, changed.allSatisfy({ $0.hasPrefix("\(path)/") }) else { continue }
            let authorEpoch = TimeInterval(try git.text(["show", "-s", "--format=%at", candidate])) ?? 0
            let committerEpoch = TimeInterval(try git.text(["show", "-s", "--format=%ct", candidate])) ?? 0
            guard authorEpoch == committerEpoch else { continue }
            let parent = try git.text(["rev-parse", "\(candidate)^1"])
            let parentEpoch = TimeInterval(try git.text(["show", "-s", "--format=%ct", parent])) ?? 0
            guard committerEpoch >= parentEpoch else { continue }
            commit = candidate
            break
        }
        guard let commit else { throw ValidatorError("sp6b_evidence_history") }
        guard try git.run(["merge-base", "--is-ancestor", commit, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp6b_evidence_history")
        }
        guard let generated = ISO8601DateFormatter().date(from: generatedAt),
              let runnerEpoch = TimeInterval(try git.text(["show", "-s", "--format=%ct", evidence.legs[0].runnerCommitSha])),
              abs(generated.timeIntervalSince1970 - runnerEpoch) <= 86_400 else { throw ValidatorError("sp6b_evidence_freshness") }
        try SP6BHistoricalSealValidator.validate(evidence: evidence, directory: directory, git: git)
    }

    private static func decode<T: Decodable>(_ data: Data, code: String) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw ValidatorError(code) }
        return value
    }
}

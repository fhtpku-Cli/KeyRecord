import Foundation
import Phase0Support

public struct CandidateBinder: Sendable {
    public static let immutableAuditBase = "2ebc4c1b27a9a334755d7e68c92b06215ac24a11"
    public let repository: URL
    public let auditBaseSha: String
    private let git: GitRunner

    public init(repository: URL, auditBaseSha: String = CandidateBinder.immutableAuditBase, timeout: TimeInterval = 10, gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.repository = repository.standardizedFileURL
        self.auditBaseSha = auditBaseSha
        self.git = GitRunner(repository: repository.standardizedFileURL, timeout: timeout, executable: gitExecutable)
    }

    public func bind(evidence: URL, plan: URL, environment: URL, createdAt: String) throws -> FinalCandidate {
        guard Self.isUTC(createdAt) else { throw ValidatorError("invalid_created_at") }
        let identities = try currentIdentities(evidence: evidence, plan: plan, environment: environment)
        return FinalCandidate(
            commitSha: identities.commit,
            treeSha: identities.tree,
            auditBaseSha: auditBaseSha,
            planSha256: identities.plan,
            environmentSha256: identities.environment,
            evidenceDigest: identities.evidence,
            boundInputPathsSha256: identities.bound,
            createdAt: createdAt
        )
    }

    public func verify(_ candidate: FinalCandidate, evidence: URL, plan: URL, environment: URL) throws {
        guard candidate.auditBaseSha == auditBaseSha else { throw ValidatorError("audit_base_drift") }
        guard Self.isUTC(candidate.createdAt) else { throw ValidatorError("invalid_created_at") }
        let identities = try currentIdentities(evidence: evidence, plan: plan, environment: environment)
        guard candidate.commitSha == identities.commit, candidate.treeSha == identities.tree,
              candidate.planSha256 == identities.plan, candidate.environmentSha256 == identities.environment,
              candidate.evidenceDigest == identities.evidence,
              candidate.boundInputPathsSha256 == identities.bound else {
            throw ValidatorError("candidate_field_drift")
        }
    }

    private func currentIdentities(evidence: URL, plan: URL, environment: URL) throws -> Identities {
        guard try evidence.relativePath(from: repository) == "evidence/phase0",
              try plan.relativePath(from: repository) == ".omo/plans/phase-0-validation.md",
              try environment.relativePath(from: repository) == "evidence/phase0/environment.json" else {
            throw ValidatorError("noncanonical_binding_path")
        }
        try validateInputLocation(evidence, directory: true)
        try validateInputLocation(plan, directory: false)
        try validateInputLocation(environment, directory: false)
        try rejectUntracked()
        try requireCleanTrackedState()
        let commit = try git.text(["rev-parse", "HEAD"])
        let tree = try git.text(["rev-parse", "HEAD^{tree}"])
        let ancestor = try git.run(["merge-base", "--is-ancestor", auditBaseSha, commit], acceptedStatuses: [0, 1])
        guard ancestor.status == 0 else { throw ValidatorError("audit_base_drift") }
        try validateTrackedTree(commit: commit)
        let evidenceFiles = try regularFiles(below: evidence, relativeTo: evidence)
        let trackedFiles = try git.nulPaths(["ls-files", "-z"])
        let boundPaths = trackedFiles.filter { $0 == "Spikes" || $0.hasPrefix("Spikes/") || $0 == "evidence/phase0" || $0.hasPrefix("evidence/phase0/") }
        let boundFiles = try boundPaths.map { path in (path, try Data(contentsOf: repository.appendingPathComponent(path))) }
        return Identities(
            commit: commit,
            tree: tree,
            plan: Canonical.sha256(try Data(contentsOf: plan)),
            environment: Canonical.sha256(try Data(contentsOf: environment)),
            evidence: try Canonical.pathDigest(files: evidenceFiles),
            bound: try Canonical.pathDigest(files: boundFiles)
        )
    }

    private func rejectUntracked() throws {
        let ignored = try git.nulPaths(["ls-files", "--others", "-i", "--exclude-standard", "-z"])
        if let path = ignored.first(where: isBound) { throw ValidatorError("ignored_bound_input", path) }
        let ordinary = try git.nulPaths(["ls-files", "--others", "--exclude-standard", "-z"])
        if let path = ordinary.first(where: isBound) { throw ValidatorError("untracked_bound_input", path) }
        if let path = (ordinary + ignored).first(where: { $0 != ".DS_Store" && !$0.hasPrefix(".omo/") }) {
            throw ValidatorError("untracked_path", path)
        }
    }

    private func requireCleanTrackedState() throws {
        let worktree = try git.run(["diff", "--quiet"], acceptedStatuses: [0, 1])
        let index = try git.run(["diff", "--cached", "--quiet"], acceptedStatuses: [0, 1])
        guard worktree.status == 0, index.status == 0 else { throw ValidatorError("dirty_tracked_state") }
    }

    private func validateTrackedTree(commit: String) throws {
        let indexPaths = try git.nulPaths(["ls-files", "-z"])
        let entries = try treeEntries(commit: commit)
        let treePaths = entries.map(\.path)
        guard Set(indexPaths) == Set(treePaths), indexPaths.count == treePaths.count else { throw ValidatorError("tracked_tree_set_mismatch") }
        let blobs = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.blob) })
        var normalized = Set<String>()
        for path in indexPaths {
            guard isSafeRepositoryPath(path) else { throw ValidatorError("invalid_path_encoding", path) }
            let nfc = path.precomposedStringWithCanonicalMapping
            guard normalized.insert(nfc).inserted else { throw ValidatorError("normalization_collision", path) }
            let url = repository.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ValidatorError("symlink_bound_input", path) }
            guard values.isRegularFile == true else { throw ValidatorError("nonregular_bound_input", path) }
            let actualBlob = GitBlobHasher.sha1Hex(for: try Data(contentsOf: url))
            guard actualBlob == blobs[path] else { throw ValidatorError("tracked_byte_drift", path) }
        }
    }

    private func treeEntries(commit: String) throws -> [(path: String, blob: String)] {
        let data = try git.run(["ls-tree", "-r", "-z", commit]).stdout
        return try String(decoding: data, as: UTF8.self).split(separator: "\0").map { row in
            guard let tab = row.firstIndex(of: "\t") else { throw ValidatorError("git_tree_parse_error") }
            let header = row[..<tab].split(separator: " ")
            guard header.count == 3 else { throw ValidatorError("git_tree_parse_error") }
            let path = String(row[row.index(after: tab)...])
            return (path, String(header[2]))
        }
    }

    private func regularFiles(below root: URL, relativeTo relativeRoot: URL) throws -> [(String, Data)] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else {
            throw ValidatorError("missing_bound_input", root.path)
        }
        var files: [(String, Data)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let path = try url.relativePath(from: relativeRoot)
            guard values.isSymbolicLink != true else { throw ValidatorError("symlink_bound_input", path) }
            if values.isRegularFile == true { files.append((path, try Data(contentsOf: url))) }
            else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true { throw ValidatorError("nonregular_bound_input", path) }
        }
        return files
    }

    private func validateInputLocation(_ url: URL, directory: Bool) throws {
        _ = try url.standardizedFileURL.relativePath(from: repository)
        _ = try url.resolvingSymlinksInPath().relativePath(from: repository.resolvingSymlinksInPath())
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ValidatorError("symlink_bound_input", url.path) }
        guard (directory ? values.isDirectory == true : values.isRegularFile == true) else {
            throw ValidatorError("nonregular_bound_input", url.path)
        }
    }
    private func isBound(_ path: String) -> Bool { path == "Spikes" || path.hasPrefix("Spikes/") || path == "evidence/phase0" || path.hasPrefix("evidence/phase0/") }
    private func isSafeRepositoryPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\u{0}") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { $0 != "." && $0 != ".." && !$0.isEmpty }
    }
    private static func isUTC(_ value: String) -> Bool {
        guard value.hasSuffix("Z") else { return false }
        return ISO8601DateFormatter().date(from: value) != nil
    }
}

private struct Identities {
    let commit: String
    let tree: String
    let plan: String
    let environment: String
    let evidence: String
    let bound: String
}

import Foundation

struct CurrentCandidateBinder {
    let repository: URL
    private var git: GitRunner { GitRunner(repository: repository, timeout: 30, executable: URL(fileURLWithPath: "/usr/bin/git")) }
    private var reader: CurrentReadinessBindings { CurrentReadinessBindings(repository: repository) }
    private let registryPath = "Scripts/phase1-qa-cases.json"

    func bind(plan: URL, readiness: URL, output: URL) throws -> CurrentCandidate {
        let outputPath = try path(output)
        guard try reader.read(outputPath) == nil else { throw CurrentCandidateError(.outputReused, outputPath) }
        let candidate = try snapshot(plan: plan, readiness: readiness)
        guard outputPath != candidate.plan.path, outputPath != candidate.readiness.path,
              !candidate.evidence.contains(where: { $0.path == outputPath }),
              !candidate.missingEvidencePaths.contains(outputPath) else { throw CurrentCandidateError(.outputReused, outputPath) }
        // Exclusive creation is the no-overwrite contract, including concurrent writers.
        try Canonical.encode(candidate).write(to: output, options: .withoutOverwriting)
        return candidate
    }

    func verify(_ file: URL, readiness: URL) throws {
        let bytes = try read(path(file))
        let candidate: CurrentCandidate
        do { candidate = try ReadinessDecoding.decode(CurrentCandidate.self, from: bytes) }
        catch { throw CurrentCandidateError(.malformedInput, String(describing: error)) }
        guard try path(readiness) == candidate.readiness.path else { throw CurrentCandidateError(.staleState) }
        _ = try read(candidate.plan.path)
        let actual = try snapshot(plan: repository.appendingPathComponent(candidate.plan.path), readiness: readiness)
        guard candidate == actual else { throw CurrentCandidateError(.staleState) }
    }

    func snapshot(plan: URL, readiness: URL) throws -> CurrentCandidate {
        let planPath = try path(plan), readinessPath = try path(readiness)
        let planBytes = try read(planPath), readinessBytes = try read(readinessPath)
        for directory in [".omo", ".omo/evidence"] {
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: repository.appendingPathComponent(directory).path) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { break }
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw CurrentCandidateError(.unsafePath, directory) }
        }
        try requireClean()
        let commit = try git.text(["--no-replace-objects", "rev-parse", "--verify", "HEAD^{commit}"])
        let tree = try git.text(["--no-replace-objects", "rev-parse", "\(commit)^{tree}"])
        let tracked = try trackedFiles(commit: commit)
        guard tracked.contains(where: { $0.0 == registryPath }) else { throw CurrentCandidateError(.missingInput, registryPath) }
        let document: CurrentReadiness
        do {
            document = try ReadinessDecoding.decode(CurrentReadiness.self, from: readinessBytes)
        } catch { throw CurrentCandidateError(.malformedInput, String(describing: error)) }
        guard document.bindings.commitSha == commit, document.bindings.treeSha == tree else { throw CurrentCandidateError(.staleState, "readiness_identity") }
        for binding in document.bindings.files {
            guard Canonical.sha256(try read(binding.path)) == binding.sha256 else { throw CurrentCandidateError(.staleState, binding.path) }
        }
        // A BLOCKED report can bind an explicitly absent proof; its later arrival invalidates the snapshot.
        for missing in document.bindings.missingPaths {
            guard try reader.read(missing) == nil else { throw CurrentCandidateError(.staleState, missing) }
        }
        do { _ = try CurrentReadinessValidator.validate(readiness, repository: repository) }
        catch { throw CurrentCandidateError(.malformedInput, String(describing: error)) }
        let inputs = CurrentCandidateInputs(
            plan: .init(path: planPath, sha256: Canonical.sha256(planBytes)),
            readiness: .init(path: readinessPath, sha256: Canonical.sha256(readinessBytes)),
            evidence: document.bindings.files, missingEvidencePaths: document.bindings.missingPaths,
            qaRegistry: .init(path: registryPath, sha256: Canonical.sha256(try read(registryPath))))
        return CurrentCandidate(commit: commit, tree: tree, trackedDigest: try Canonical.pathDigest(files: tracked), inputs: inputs)
    }

    private func requireClean() throws {
        let ordinary = try git.nulPaths(["ls-files", "--others", "--exclude-standard", "-z"])
        let ignored = try git.nulPaths(["ls-files", "--others", "--ignored", "--exclude-standard", "-z"])
        if let extra = (ordinary + ignored).first(where: { !$0.hasPrefix(".omo/") }) {
            throw CurrentCandidateError(.dirtyWorktree, extra)
        }
        let worktree = try git.run(["diff", "--quiet", "--ignore-submodules=none"], acceptedStatuses: [0, 1])
        let index = try git.run(["diff", "--cached", "--quiet", "--ignore-submodules=none"], acceptedStatuses: [0, 1])
        guard worktree.status == 0, index.status == 0 else { throw CurrentCandidateError(.dirtyWorktree) }
    }

    private func trackedFiles(commit: String) throws -> [(String, Data)] {
        let bytes = try git.run(["--no-replace-objects", "ls-tree", "-r", "-z", commit]).stdout
        guard let text = String(data: bytes, encoding: .utf8) else { throw CurrentCandidateError(.unsafePath) }
        let entries = try text.split(separator: "\0").map { row -> (String, String) in
            guard let tab = row.firstIndex(of: "\t") else { throw CurrentCandidateError(.malformedInput) }
            let header = row[..<tab].split(separator: " ")
            guard header.count == 3, ["100644", "100755"].contains(header[0]), header[1] == "blob" else { throw CurrentCandidateError(.unsafePath) }
            return (String(row[row.index(after: tab)...]), String(header[2]))
        }
        let indexed = try git.nulPaths(["ls-files", "-z"])
        guard indexed.count == entries.count, Set(indexed) == Set(entries.map(\.0)) else { throw CurrentCandidateError(.dirtyWorktree) }
        let blobs = try entries.isEmpty ? [] : git.blobs(entries.map(\.1))
        return try zip(entries, blobs).map { entry, sealed in
            let actual = try read(entry.0)
            guard actual == sealed else { throw CurrentCandidateError(.dirtyWorktree, entry.0) }
            return (entry.0, actual)
        }
    }

    private func path(_ url: URL) throws -> String {
        do { return try url.relativePath(from: repository) }
        catch { throw CurrentCandidateError(.unsafePath, url.path) }
    }

    private func read(_ path: String) throws -> Data {
        let bytes: Data?
        do { bytes = try reader.read(path) }
        catch { throw CurrentCandidateError(.unsafePath, path) }
        guard let bytes else { throw CurrentCandidateError(.missingInput, path) }
        return bytes
    }
}

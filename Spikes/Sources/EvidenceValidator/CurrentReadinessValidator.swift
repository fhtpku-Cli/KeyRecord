import Foundation
import Phase0Support

enum CurrentReadinessValidator {
    static func generate(repository: URL, historical: String, lifecycle: String, output: URL, approvedProducerSHA256s: Set<String> = []) throws -> CurrentReadiness {
        let base = URL(fileURLWithPath: repository.path, isDirectory: true)
        let historicalPath = try URL(fileURLWithPath: historical, relativeTo: base).standardizedFileURL.relativePath(from: base)
        let lifecyclePath = try lifecycle == "none" ? "none" : URL(fileURLWithPath: lifecycle, relativeTo: base).standardizedFileURL.relativePath(from: base)
        let outputPath = try output.relativePath(from: base)
        let loader = CurrentReadinessBindings(repository: base)
        guard !FileManager.default.fileExists(atPath: output.path),
              !outputPath.hasPrefix(historicalPath + "/"), outputPath != lifecyclePath,
              try loader.read(outputPath) == nil else { throw ValidatorError("readiness_output_reused_or_historical") }
        let input = try loader.load(historical: historicalPath, lifecycle: lifecyclePath, approvedProducerSHA256s: approvedProducerSHA256s)
        guard !input.bindings.files.contains(where: { $0.path == outputPath }),
              !input.bindings.missingPaths.contains(outputPath) else { throw ValidatorError("readiness_output_is_input") }
        let document = try CurrentReadinessDeriver.derive(input)
        // Exclusive creation also rejects a competing writer after the preflight.
        try Canonical.encode(document).write(to: output, options: .withoutOverwriting)
        return document
    }

    static func validate(_ file: URL, repository: URL, approvedProducerSHA256s: Set<String> = []) throws -> CurrentReadiness {
        let loader = CurrentReadinessBindings(repository: repository)
        guard let bytes = try loader.read(file.relativePath(from: repository)) else { throw ValidatorError("readiness_missing_document") }
        let document = try ReadinessDecoding.decode(CurrentReadiness.self, from: bytes)
        let input = try loader.load(historical: document.historicalRoot, lifecycle: document.lifecyclePath, approvedProducerSHA256s: approvedProducerSHA256s)
        guard document == (try CurrentReadinessDeriver.derive(input)) else { throw ValidatorError("readiness_recompute_mismatch") }
        return document
    }
}

struct CurrentReadinessBindings {
    // This new binding includes the existing dependency closure without modifying
    // either historical source-identity list or its sealed byte semantics.
    static let sourcePaths = Set([
        "Spikes/Sources/EvidenceValidator/CurrentReadinessModels.swift",
        "Spikes/Sources/EvidenceValidator/CurrentReadinessDeriver.swift",
        "Spikes/Sources/EvidenceValidator/CurrentReadinessValidator.swift",
    ]).union(Phase0RunBinding.sourcePaths).union(ConclusionGenerator.sourcePaths).sorted()
    let repository: URL
    private var git: GitRunner { GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git")) }

    func load(historical: String, lifecycle: String, approvedProducerSHA256s: Set<String> = []) throws -> ReadinessInputs {
        try safePath(historical)
        let commit = try git.text(["rev-parse", "--verify", "HEAD^{commit}"]), tree = try git.text(["rev-parse", "\(commit)^{tree}"])
        var files: [ReadinessFileBinding] = [], missing: [String] = []
        let sourceBlobs = try git.blobs(Self.sourcePaths.map { "\(commit):\($0)" })
        for (path, sealed) in zip(Self.sourcePaths, sourceBlobs) {
            guard let bytes = try read(path), bytes == sealed else { throw ValidatorError("readiness_source_dirty", path) }
            files.append(.init(path: path, sha256: Canonical.sha256(bytes)))
        }
        let historyPaths = try git.nulPaths(["--literal-pathspecs", "ls-tree", "-r", "--name-only", "-z", commit, "--", historical])
        let blobs = try historyPaths.isEmpty ? [] : git.blobs(historyPaths.map { "\(commit):\($0)" })
        for (path, sealed) in zip(historyPaths, blobs) {
            guard path.hasPrefix(historical + "/") else { throw ValidatorError("readiness_invalid_historical_root") }
            files.append(.init(path: path, sha256: Canonical.sha256(sealed)))
            if let actual = try read(path) {
                guard actual == sealed else { throw ValidatorError("readiness_historical_bytes_mismatch", path) }
            } else { missing.append(path) }
        }
        let conclusionPath = historical + "/conclusions.json"
        let history: Phase0Conclusions?
        if let data = try read(conclusionPath) {
            guard historyPaths.contains(conclusionPath) else { throw ValidatorError("readiness_unsealed_history") }
            let decoded = try ReadinessDecoding.decode(Phase0Conclusions.self, from: data)
            let pinned = try checkHistory(decoded, root: historical)
            let generated = Set(["conclusions.json"] + ConclusionContract.spikeIDs.map { "\($0)-CONCLUSION.md" }).map { historical + "/" + $0 }
            let permitted = Set(pinned.map(\.path)).union(generated).union(["manifest.sha256", "run-all.json", "privacy-audit.json"].map { historical + "/" + $0 })
            guard Set(historyPaths).isSubset(of: permitted) else { throw ValidatorError("readiness_historical_inventory_mismatch") }
            files += pinned
            for binding in pinned where try read(binding.path) == nil { missing.append(binding.path) }
            history = decoded
        } else { history = nil; missing.append(conclusionPath) }
        var receipts: [ReadinessReceipt] = []
        if lifecycle != "none" {
            if let data = try read(lifecycle) {
                files.append(.init(path: lifecycle, sha256: Canonical.sha256(data)))
                let document = try ReadinessDecoding.decode(ReadinessLifecycle.self, from: data)
                guard Set(document.receipts.map(\.path)).count == document.receipts.count else { throw ValidatorError("readiness_duplicate_receipt") }
                for binding in document.receipts {
                    try checkHash(binding.sha256); files.append(binding)
                    do {
                        guard let bytes = try read(binding.path) else { throw ValidatorError("missing_receipt") }
                        guard Canonical.sha256(bytes) == binding.sha256 else { throw ValidatorError("receipt_hash_mismatch") }
                        let receipt = try ReadinessDecoding.decode(ReadinessReceipt.self, from: bytes)
                        let artifacts = try checkReceipt(receipt, identity: (commit, tree), path: binding.path)
                        receipts.append(receipt); files += receipt.sourceFiles + artifacts
                    } catch { throw ValidatorError("readiness_invalid_receipt", String(describing: error)) }
                }
            } else { missing.append(lifecycle) }
        }
        guard Set(receipts.map(\.id)).count == receipts.count else { throw ValidatorError("readiness_duplicate_receipt_id") }
        let grouped = Dictionary(grouping: files, by: \.path)
        guard grouped.values.allSatisfy({ Set($0.map(\.sha256)).count == 1 }) else { throw ValidatorError("readiness_conflicting_bindings") }
        let unique = grouped.keys.sorted().compactMap { grouped[$0]?.first }
        let sp1 = try read(historical + "/sp1/evidence.json").map { try ReadinessDecoding.decode(SP1Evidence.self, from: $0) }
        let sp2 = try read(historical + "/sp2/evidence.json").map { try ReadinessDecoding.decode(SP2Evidence.self, from: $0) }
        return ReadinessInputs(historical: history, historicalRoot: historical, lifecyclePath: lifecycle, bindings: .init(commitSha: commit, treeSha: tree, files: unique, missingPaths: Set(missing).sorted()), receipts: receipts, sp1: sp1, sp2: sp2, approvedProducerSHA256s: approvedProducerSHA256s)
    }

    private func checkHistory(_ history: Phase0Conclusions, root: String) throws -> [ReadinessFileBinding] {
        guard history.schemaVersion == 1 else { throw ValidatorError("readiness_unknown_historical_schema") }
        for identity in [(history.sourceEvidenceCommitSha, history.sourceEvidenceTreeSha), (history.generatorCommitSha, history.generatorTreeSha)] {
            guard identity.0.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
                  try git.text(["rev-parse", "\(identity.0)^{tree}"]) == identity.1,
                  try git.run(["merge-base", "--is-ancestor", identity.0, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
                throw ValidatorError("readiness_historical_identity_mismatch")
            }
        }
        guard try git.run(["merge-base", "--is-ancestor", history.sourceEvidenceCommitSha, history.generatorCommitSha], acceptedStatuses: [0, 1]).status == 0,
              Set(history.generatorSourceSha256.keys) == ConclusionGenerator.sourcePaths else { throw ValidatorError("readiness_historical_generator_mismatch") }
        let generatorPaths = history.generatorSourceSha256.keys.sorted()
        let generatorBlobs = try git.blobs(generatorPaths.map { "\(history.generatorCommitSha):\($0)" })
        for (path, bytes) in zip(generatorPaths, generatorBlobs) {
            guard Canonical.sha256(bytes) == history.generatorSourceSha256[path] else { throw ValidatorError("readiness_historical_generator_mismatch") }
        }
        let manifest = try git.run(["cat-file", "blob", "\(history.sourceEvidenceCommitSha):\(root)/manifest.sha256"]).stdout
        guard Canonical.sha256(manifest) == history.sourceRootManifestSha256 else { throw ValidatorError("readiness_historical_manifest_mismatch") }
        // Raw inputs are pinned to the historical source commit, not today's HEAD.
        // Only the three root files rewritten by historical conclusion generation differ.
        let mutable = Set(["manifest.sha256", "privacy-audit.json", "run-all.json"].map { root + "/" + $0 })
        let paths = try git.nulPaths(["--literal-pathspecs", "ls-tree", "-r", "--name-only", "-z", history.sourceEvidenceCommitSha, "--", root]).filter { !mutable.contains($0) }
        let bytes = try git.blobs(paths.map { "\(history.sourceEvidenceCommitSha):\($0)" })
        var pinned: [ReadinessFileBinding] = []
        for (path, sealed) in zip(paths, bytes) {
            guard path.hasPrefix(root + "/"), path != root + "/conclusions.json" else { throw ValidatorError("readiness_source_not_raw") }
            if let current = try read(path), current != sealed { throw ValidatorError("readiness_pinned_source_mismatch", path) }
            pinned.append(.init(path: path, sha256: Canonical.sha256(sealed)))
        }
        let hashes = Dictionary(uniqueKeysWithValues: pinned.map { ($0.path, $0.sha256) })
        for spike in history.spikes {
            for binding in [ReadinessFileBinding(path: spike.evidence.path, sha256: spike.evidence.sha256), .init(path: spike.evidence.manifestPath, sha256: spike.evidence.manifestSha256)] {
                try safePath(binding.path); try checkHash(binding.sha256)
                guard hashes[root + "/" + binding.path] == binding.sha256 else { throw ValidatorError("readiness_invalid_historical_binding", binding.path) }
            }
        }
        return pinned
    }

    private func checkReceipt(_ receipt: ReadinessReceipt, identity: (String, String), path: String) throws -> [ReadinessFileBinding] {
        try checkHash(receipt.producerControllerSHA256)
        guard Set(receipt.sourceFiles.map(\.path)).isSubset(of: receipt.id.requiredSourcePaths) else {
            throw ValidatorError("readiness_receipt_source_not_allowed")
        }
        let ids = receipt.assertions.map(\.id)
        guard Set(ids).count == ids.count, Set(ids) == Set(receipt.id.requiredAssertions),
              receipt.status == CurrentReadinessDeriver.aggregate(receipt.assertions.map(\.status)),
              receipt.executed == receipt.assertions.filter({ $0.status != .blocked }).count,
              receipt.failed == receipt.assertions.filter({ $0.status == .fail }).count, receipt.skipped == 0 else {
            throw ValidatorError("invalid_required_assertions")
        }
        guard receipt.commitSha == identity.0, receipt.treeSha == identity.1,
              !receipt.sourceFiles.isEmpty, Set(receipt.sourceFiles.map(\.path)).count == receipt.sourceFiles.count,
              receipt.executed >= 0, receipt.failed >= 0, receipt.skipped >= 0,
              receipt.failed <= receipt.executed, receipt.skipped <= receipt.executed - receipt.failed else { throw ValidatorError("readiness_invalid_receipt") }
        switch receipt.status {
        case .pass:
            guard receipt.executed > 0, receipt.failed == 0, receipt.skipped == 0, !receipt.argv.isEmpty,
                  receipt.argv.allSatisfy({ !$0.isEmpty }) else { throw ValidatorError("readiness_unearned_receipt_pass") }
        case .fail:
            guard receipt.failed > 0, !receipt.argv.isEmpty, receipt.argv.allSatisfy({ !$0.isEmpty }) else { throw ValidatorError("readiness_invalid_receipt_failure") }
        case .blocked:
            let validCommand = receipt.executed == 0 ? receipt.argv.isEmpty : !receipt.argv.isEmpty && receipt.argv.allSatisfy({ !$0.isEmpty })
            guard receipt.failed == 0, receipt.skipped == 0, validCommand else { throw ValidatorError("readiness_invalid_receipt_blocked") }
        }
        for binding in receipt.sourceFiles {
            try checkHash(binding.sha256)
            guard let bytes = try read(binding.path), Canonical.sha256(bytes) == binding.sha256 else { throw ValidatorError("readiness_receipt_source_mismatch") }
            guard try git.run(["cat-file", "blob", "\(identity.0):\(binding.path)"]).stdout == bytes else { throw ValidatorError("readiness_receipt_source_dirty") }
        }
        var artifacts: [ReadinessFileBinding] = []
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        for assertion in receipt.assertions {
            try checkHash(assertion.artifactSHA256)
            let artifactPath = parent.isEmpty ? assertion.artifactPath : parent + "/" + assertion.artifactPath
            guard let bytes = try read(artifactPath), Canonical.sha256(bytes) == assertion.artifactSHA256 else {
                throw ValidatorError("assertion_artifact_mismatch", assertion.id)
            }
            artifacts.append(.init(path: artifactPath, sha256: assertion.artifactSHA256))
        }
        // Empty is valid for the current synthetic producer only; a future host
        // producer must bind its manifest and be endorsed by task 7's host runner.
        if !receipt.hostManifestPath.isEmpty {
            guard let bytes = try read(receipt.hostManifestPath) else { throw ValidatorError("missing_host_manifest") }
            artifacts.append(.init(path: receipt.hostManifestPath, sha256: Canonical.sha256(bytes)))
        }
        return artifacts
    }

    func read(_ path: String) throws -> Data? {
        try safePath(path)
        var url = repository.standardizedFileURL
        let parts = path.split(separator: "/")
        for (index, part) in parts.enumerated() {
            url.appendPathComponent(String(part))
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
            let expected: FileAttributeType = index == parts.count - 1 ? .typeRegular : .typeDirectory
            guard attributes[.type] as? FileAttributeType == expected else { throw ValidatorError("readiness_unsafe_file", path) }
        }
        return try Data(contentsOf: url)
    }
    private func safePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !parts.contains(""), !parts.contains("."), !parts.contains(".."),
              !path.contains("\0"), !path.contains("\n"), !path.contains("\r") else { throw ValidatorError("readiness_unsafe_path", path) }
    }
    private func checkHash(_ hash: String) throws {
        guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ValidatorError("readiness_invalid_hash") }
    }
}

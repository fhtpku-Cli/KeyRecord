import Darwin
import Foundation
import Phase0Support

enum ConclusionError: Error { case invalid(String) }

struct RawConclusionLeg {
    let id: String
    let verdict: Verdict
    let runnerCommit: String
    let runnerTree: String
}

public enum ConclusionGenerator {
    static let sourcePaths: Set<String> = Set([
        "Spikes/Package.swift", "Spikes/Scripts/run-task-qa.sh", "Spikes/Scripts/task-15-qa.sh",
        "Spikes/Sources/EvidenceValidator/ConclusionGenerator.swift", "Spikes/Sources/EvidenceValidator/ConclusionValidator.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/Phase0Support/ConclusionModels.swift", "Spikes/Sources/Phase0Support/ConclusionStrictCoding.swift",
        "Spikes/Sources/Phase0Support/Phase0Privacy.swift",
        "Spikes/Tests/EvidenceValidatorTests/ConclusionGeneratorTests.swift",
    ]).union(Phase0RunBinding.task15SourcePaths)

    public static func generate(
        sourceRoot: URL,
        outputRoot: URL,
        repository: URL,
        strictRepositoryBinding: Bool = false,
        sourceCommitSha: String? = nil,
        generatorCommitSha: String? = nil
    ) throws {
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let canonicalSourceCommit = try sourceCommitSha.map { try canonicalCommit($0, git: git) }
        let canonicalGeneratorCommit = try generatorCommitSha.map { try canonicalCommit($0, git: git) }
        if let canonicalSourceCommit {
            try HistoricalEvidenceInventoryValidator.validate(
                root: sourceRoot,
                sourceCommit: canonicalSourceCommit,
                repository: repository
            )
        }
        if strictRepositoryBinding { try Phase0RootValidator.validate(sourceRoot, repository: repository) }
        guard !FileManager.default.fileExists(atPath: outputRoot.path) else { throw ValidatorError("stale_conclusion_output") }
        let parent = outputRoot.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let candidate = parent.appendingPathComponent(".conclusions-\(UUID().uuidString).tmp")
        if strictRepositoryBinding { ConclusionSignalCleanup.install(candidate: candidate) }
        defer { if strictRepositoryBinding { ConclusionSignalCleanup.uninstall() } }
        do {
            try FileManager.default.copyItem(at: sourceRoot, to: candidate)
            let document = try derive(
                root: sourceRoot,
                repository: repository,
                strictRepositoryBinding: strictRepositoryBinding,
                sourceCommitSha: canonicalSourceCommit,
                bindingCommitSha: canonicalGeneratorCommit
            )
            try write(document, to: candidate.appendingPathComponent("conclusions.json"))
            for spike in document.spikes {
                try Data(renderMarkdown(spike).utf8).write(to: candidate.appendingPathComponent("\(spike.id)-CONCLUSION.md"))
            }
            try updateRunReceipt(candidate)
            try updatePrivacy(candidate)
            try writeManifest(candidate)
            _ = try ConclusionValidator.validate(root: candidate, repository: repository, strictRepositoryBinding: strictRepositoryBinding)
            if let ready = ProcessInfo.processInfo.environment["KEYRECORD_CONCLUSION_TEST_READY_FILE"] {
                try Data(candidate.path.utf8).write(to: URL(fileURLWithPath: ready))
            }
            if let delay = ProcessInfo.processInfo.environment["KEYRECORD_CONCLUSION_TEST_DELAY"].flatMap(Double.init), delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            guard Darwin.rename(candidate.path, outputRoot.path) == 0 else {
                throw ValidatorError("conclusion_publish_failed", String(errno))
            }
        } catch {
            try? FileManager.default.removeItem(at: candidate)
            if FileManager.default.fileExists(atPath: outputRoot.path) { try? FileManager.default.removeItem(at: outputRoot) }
            throw error
        }
    }

    static func derive(
        root: URL,
        repository: URL,
        strictRepositoryBinding: Bool,
        sourceManifestSha256: String? = nil,
        sourceCommitSha: String? = nil,
        sourceTreeSha: String? = nil,
        bindingCommitSha: String? = nil,
        bindingTreeSha: String? = nil
    ) throws -> Phase0Conclusions {
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let commit = try canonicalCommit(bindingCommitSha ?? "HEAD", git: git)
        let tree = try bindingTreeSha ?? git.text(["rev-parse", "\(commit)^{tree}"])
        guard try git.text(["rev-parse", "\(commit)^{tree}"]) == tree else {
            throw ValidatorError("conclusion_runner_tree_mismatch")
        }
        let sourceCommit = try sourceCommitSha.map { try canonicalCommit($0, git: git) } ?? commit
        let sourceTree = try sourceTreeSha ?? git.text(["rev-parse", "\(sourceCommit)^{tree}"])
        guard try git.text(["rev-parse", "\(sourceCommit)^{tree}"]) == sourceTree else {
            throw ValidatorError("source_manifest_rebind")
        }
        let paths = sourcePaths.sorted()
        if strictRepositoryBinding {
            let dirty = try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--"] + paths)
            guard dirty.isEmpty else {
                throw ValidatorError("conclusion_runner_dirty", dirty.split(separator: "\n").first.map(String.init) ?? "")
            }
        }
        let sourceBytes = try strictRepositoryBinding || bindingCommitSha != nil
            ? git.blobs(paths.map { "\(commit):\($0)" })
            : paths.map { try Data(contentsOf: repository.appendingPathComponent($0)) }
        let sourceHashes = Dictionary(uniqueKeysWithValues: zip(paths, sourceBytes).map {
            ($0.0, Canonical.sha256($0.1))
        })
        let spikes = try ConclusionContract.spikeIDs.map { id in try spike(id, root: root) }
        let byID = Dictionary(uniqueKeysWithValues: spikes.map { ($0.id, $0) })
        let blockers = try allBlockedLegIDs(root)
        let g0Blocked = blockers.filter { $0.hasPrefix("sp1.") || $0.hasPrefix("sp2.") }.sorted()
        let g0Passed = byID["SP-1"]?.verdict == .pass && byID["SP-2"]?.verdict == .pass
        let g0 = ValidatedG0(status: g0Passed ? .passed : .open, reasons: g0Passed ? [] : g0Blocked.map { "required live leg \($0) is not PASS" }, blockingLegIDs: g0Blocked, candidateSelection: nil)
        let manifest = root.appendingPathComponent("manifest.sha256")
        let sourceManifestHash: String
        if let sourceManifestSha256 { sourceManifestHash = sourceManifestSha256 }
        else { sourceManifestHash = Canonical.sha256(try Data(contentsOf: manifest)) }
        return Phase0Conclusions(
            schemaVersion: 1, sourceEvidenceCommitSha: sourceCommit, sourceEvidenceTreeSha: sourceTree,
            sourceRootManifestSha256: sourceManifestHash, generatorCommitSha: commit,
            generatorTreeSha: tree, generatorSourceSha256: sourceHashes, spikes: spikes,
            oItems: oItems(g0Blocked: g0Blocked), o4Matrix: try o4(root: root), downstreamBlocks: downstream(), g0: g0
        )
    }

    private static func spike(_ id: String, root: URL) throws -> ValidatedSpikeConclusion {
        let directory = directoryName(id)
        let evidencePath = "\(directory)/evidence.json", manifestPath = "\(directory)/manifest.sha256"
        let evidenceData = try Data(contentsOf: root.appendingPathComponent(evidencePath))
        let manifestData = try Data(contentsOf: root.appendingPathComponent(manifestPath))
        let legs = try parseLegs(evidenceData)
        guard let first = legs.first, !legs.isEmpty else { throw ValidatorError("conclusion_missing_legs", id) }
        guard legs.allSatisfy({ $0.runnerCommit == first.runnerCommit && $0.runnerTree == first.runnerTree }) else { throw ValidatorError("conclusion_mixed_runner", id) }
        let verdict = ConclusionDeriver.aggregate(legs.map(\.verdict))
        let limits = limitations[id] ?? []
        return ValidatedSpikeConclusion(id: id, verdict: verdict,
            evidence: .init(path: evidencePath, sha256: Canonical.sha256(evidenceData), manifestPath: manifestPath, manifestSha256: Canonical.sha256(manifestData)),
            runnerCommitSha: first.runnerCommit, runnerTreeSha: first.runnerTree,
            passCount: legs.filter { $0.verdict == .pass }.count, blockedCount: legs.filter { $0.verdict == .blocked }.count,
            inconclusiveCount: legs.filter { $0.verdict == .inconclusive }.count, failCount: legs.filter { $0.verdict == .fail }.count,
            limitations: limits, rerunArgv: ["swift", "run", "--package-path", "Spikes", "Phase0Probe", directory, "--environment", "evidence/phase0/environment.json", "--output", "<output>/\(directory)"], dependencyFrozen: false)
    }

    static func parseLegs(_ data: Data) throws -> [RawConclusionLeg] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let values = root["legs"] as? [[String: Any]] else { throw ValidatorError("conclusion_malformed_spike") }
        return try values.map { value in
            guard let id = value["legID"] as? String, let raw = value["verdict"] as? String, let verdict = Verdict(rawValue: raw),
                  let commit = value["runnerCommitSha"] as? String, let tree = value["runnerTreeSha"] as? String else { throw ValidatorError("conclusion_malformed_leg") }
            return RawConclusionLeg(id: id, verdict: verdict, runnerCommit: commit, runnerTree: tree)
        }
    }

    private static func allBlockedLegIDs(_ root: URL) throws -> [String] {
        try ConclusionContract.spikeIDs.flatMap { id in
            try parseLegs(Data(contentsOf: root.appendingPathComponent("\(directoryName(id))/evidence.json"))).filter { $0.verdict != .pass }.map(\.id)
        }
    }

    private static func oItems(g0Blocked: [String]) -> [ValidatedOItemDisposition] {
        [
            .init(id: "O1", status: "DEFERRED", evidencePaths: ["run-all.json"], blockerRefs: ["G1"], semantics: "KeyRecord remains an internal codename; no product name is selected."),
            .init(id: "O2", status: "NO_PUBLIC_ACTION", evidencePaths: ["run-all.json"], blockerRefs: ["G1"], semantics: "No public prototype action occurs before license review."),
            .init(id: "O3", status: "FUTURE_REAL_DEVICE", evidencePaths: [], blockerRefs: ["VIA_GENERATION", "VIAL_BETA"], semantics: "At least three approved real keyboards remain future inputs."),
            .init(id: "O4", status: "EVIDENCE_OR_BLOCKED", evidencePaths: ["sp3/evidence.json", "sp4a/evidence.json", "sp4b/evidence.json", "sp5a/evidence.json", "sp5b/evidence.json"], blockerRefs: ["KARABINER_STABLE", "VIA_GENERATION", "VIAL_BETA"], semantics: "Each independent version axis is evidence-backed or blocked; no compatibility is inferred."),
            .init(id: "O5", status: "REPRESENTED", evidencePaths: ConclusionContract.spikeIDs.map { "\(directoryName($0))/evidence.json" }, blockerRefs: [], semantics: "Spike details are represented without freezing production APIs."),
            .init(id: "O6", status: "OPEN", evidencePaths: ["sp2/evidence.json"], blockerRefs: g0Blocked.filter { $0.hasPrefix("sp2.") }, semantics: "OPEN until every SP-2 row, including Fn live recovery, passes."),
            .init(id: "O7", status: "CONSERVATIVE", evidencePaths: ["sp1/evidence.json"], blockerRefs: g0Blocked.filter { $0.hasPrefix("sp1.") }, semantics: "Fail closed: only product-stamped synthetic events are guaranteed excluded; unmarked injection remains unproven."),
        ]
    }

    private static func o4(root: URL) throws -> [ValidatedO4Row] {
        let evidence: [(String, String)] = [
            ("karabiner.managedBlock", "sp3/managed-block.json"), ("karabiner.atomicReplace", "sp3/atomicity-citation.json"),
            ("via.definitionSchema", "sp4a/evidence.json"), ("via.layoutBackupFormat", "sp4b/round-trip.json"),
            ("vial.definitionSchema", "sp5a/format-facts.json"), ("vial.layoutBackupFormat", "sp5a/round-trip.json"),
        ]
        let blocked: [(String, String)] = [
            ("karabiner.configSchema", "sp3.schemaLint"), ("karabiner.reload", "sp3.reload"), ("karabiner.disableLatency", "sp3.disableLatency"),
            ("via.deviceProtocol", "sp4b.deviceProtocol"), ("via.keycodeDialect", "sp4b.keycodeDialect"), ("via.officialImporterCompatibility", "sp4b.importer"),
            ("vial.deviceProtocol", "sp5b.liveCapture"), ("vial.keycodeDialect", "sp5b.liveCapture"), ("vial.officialImporterCompatibility", "sp5a.importer"),
        ]
        let evidenceMap = Dictionary(uniqueKeysWithValues: evidence), blockedMap = Dictionary(uniqueKeysWithValues: blocked)
        return try ConclusionContract.o4IDs.map { id in
            if let path = evidenceMap[id] { return .init(id: id, evidencePath: path, evidenceSha256: Canonical.sha256(try Data(contentsOf: root.appendingPathComponent(path))), blockedRef: nil) }
            guard let ref = blockedMap[id] else { throw ValidatorError("conclusion_o4_mapping_missing", id) }
            return .init(id: id, evidencePath: nil, evidenceSha256: nil, blockedRef: ref)
        }
    }

    private static func downstream() -> [ValidatedDownstreamBlock] {
        [
            .init(id: "G1", blockedCapability: "Phase 1 collection, privacy, and encrypted persistence", causedBy: ["G0", "sp6a.keychainSelection"], artifactRefs: ["sp1/evidence.json", "sp2/evidence.json", "sp6a/evidence.json"], rerunArgv: qa([5, 6, 10])),
            .init(id: "KARABINER_STABLE", blockedCapability: "Karabiner stable release and <=2s p95 disable", causedBy: ["sp3.versionSample", "sp3.reload", "sp3.disableLatency"], artifactRefs: ["sp3/evidence.json"], rerunArgv: qa([7])),
            .init(id: "VIA_GENERATION", blockedCapability: "VIA generation and compatibility", causedBy: ["sp4b.deviceProtocol", "sp4b.keycodeDialect", "sp4b.importer"], artifactRefs: ["sp4b/axes.json", "sp4b/evidence.json"], rerunArgv: qa([12])),
            .init(id: "VIAL_BETA", blockedCapability: "Vial Beta import and live verification", causedBy: ["sp5a.importer", "sp5b.liveCapture"], artifactRefs: ["sp5a/evidence.json", "sp5b/evidence.json"], rerunArgv: qa([9, 13])),
            .init(id: "FULL_BACKUP_FINAL_RELEASE", blockedCapability: "Full backup and final release", causedBy: ["sp6b.intelTiming", "SP-6B dependency_frozen=false"], artifactRefs: ["sp6b/evidence.json", "sp6b/candidate-evaluation.json"], rerunArgv: qa([11])),
        ]
    }

    private static func qa(_ tasks: [Int]) -> [[String]] { tasks.map { ["bash", "Spikes/Scripts/run-task-qa.sh", String($0), "happy"] } }
    static func directoryName(_ id: String) -> String { id.lowercased().replacingOccurrences(of: "-", with: "") }

    static func canonicalCommit(_ revision: String, git: GitRunner) throws -> String {
        let commit = try git.text(["rev-parse", "--verify", "\(revision)^{commit}"])
        guard commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            throw ValidatorError("noncanonical_commit_sha", revision)
        }
        return commit
    }

    private static let limitations: [String: [String]] = [
        "SP-1": ["Input Monitoring and Karabiner were unavailable; no tap candidate is selected.", "O7 excludes only product-stamped synthetic events and otherwise fails closed."],
        "SP-2": ["Live attribution, Secure Input, sleep/wake, tap-reset, sided recovery, and Fn recovery remain blocked.", "O6 remains OPEN."],
        "SP-3": ["Schema/version sampling, live reload, and <=2s p95 disable latency remain blocked."],
        "SP-4A": ["PASS covers V2/V3 definition schema parsing only; it proves no protocol, keycode, importer, or device compatibility."],
        "SP-4B": ["Synthetic layout round-trip proves no official importer, device protocol, firmware keycode, or deployment compatibility."],
        "SP-5A": ["Synthetic .vil round-trip proves no official importer or real-device compatibility."],
        "SP-5B": ["Replay and deny-all construction prove no live HID behavior; outbound reports are not literally read-only."],
        "SP-6A": ["Data-protection Keychain selection and lifecycle remain blocked; no plaintext fallback is permitted."],
        "SP-6B": ["Intel timing remains blocked and the production dependency/API is not frozen."],
    ]

    static func renderMarkdown(_ spike: ValidatedSpikeConclusion) -> String {
        let limits = spike.limitations.map { "- \($0)" }.joined(separator: "\n")
        return "# \(spike.id) Validated Conclusion\n\nVerdict: **\(spike.verdict.rawValue)**\n\nEvidence: `\(spike.evidence.path)` (`\(spike.evidence.sha256)`)\nManifest: `\(spike.evidence.manifestPath)` (`\(spike.evidence.manifestSha256)`)\nRunner: `\(spike.runnerCommitSha)` / `\(spike.runnerTreeSha)`\nCounts: PASS=\(spike.passCount), BLOCKED=\(spike.blockedCount), INCONCLUSIVE=\(spike.inconclusiveCount), FAIL=\(spike.failCount)\nDependency frozen: `\(spike.dependencyFrozen)`\n\n## Limitations\n\(limits)\n\n## Exact rerun argv\n```json\n\(jsonArray(spike.rerunArgv))\n```\n"
    }

    private static func jsonArray(_ values: [String]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self) }
    private static func write<T: Encodable>(_ value: T, to url: URL) throws { var data = try Canonical.encode(value); data.append(10); try data.write(to: url) }
    private static func updateRunReceipt(_ root: URL) throws { let url = root.appendingPathComponent("run-all.json"); var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]; value["conclusionGenerated"] = true; value["rootArtifacts"] = (["README.md", "environment.json", "privacy-audit.json", "run-all.json", "conclusions.json"] + ConclusionContract.spikeIDs.map { "\($0)-CONCLUSION.md" }); try pretty(value).write(to: url) }
    private static func updatePrivacy(_ root: URL) throws { let url = root.appendingPathComponent("privacy-audit.json"); try? FileManager.default.removeItem(at: url); let report = try Phase0PrivacyAudit.scan(root: root, excluding: ["privacy-audit.json", "manifest.sha256"]); try write(report, to: url) }
    private static func writeManifest(_ root: URL) throws { let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { name in guard name != "manifest.sha256" else { return false }; return (try? root.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted(); let text = try names.map { name in "\(Canonical.sha256(try Data(contentsOf: root.appendingPathComponent(name))))  \(name)" }.joined(separator: "\n") + "\n"; try Data(text.utf8).write(to: root.appendingPathComponent("manifest.sha256")) }
    private static func pretty(_ object: Any) throws -> Data { var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]); data.append(10); return data }
}

private enum ConclusionSignalCleanup {
    nonisolated(unsafe) private static var sources: [DispatchSourceSignal] = []
    nonisolated(unsafe) private static var candidate: URL?

    static func install(candidate: URL) {
        self.candidate = candidate
        sources = [SIGINT, SIGTERM, SIGHUP].map { signalNumber in
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                if let path = self.candidate { try? FileManager.default.removeItem(at: path) }
                Foundation.exit(signalNumber == SIGINT ? 130 : signalNumber == SIGTERM ? 143 : 129)
            }
            source.resume()
            return source
        }
    }

    static func uninstall() {
        sources.forEach { $0.cancel() }
        sources = []
        candidate = nil
        Darwin.signal(SIGINT, SIG_DFL)
        Darwin.signal(SIGTERM, SIG_DFL)
        Darwin.signal(SIGHUP, SIG_DFL)
    }
}

import Foundation
@testable import EvidenceValidator
import Phase0Support

// Self-contained bound-history fixture for the task 15 closeout orchestration.
// It mirrors the proven G0-PASS construction used by CurrentReadinessTests/
// CurrentDeliverablesTests: a synthetic committed source tree plus a sealed
// evidence/phase0-equivalent history whose provenance recomputes to G0 PASS.
// No real host observation or repository evidence is consumed.
struct CurrentCloseoutFixture {
    let root: URL
    let historicalRoot = "history"
    let planPath = ".omo/plans/repository-status-next-step.md"

    var git: GitRunner { GitRunner(repository: root, timeout: 20, executable: URL(fileURLWithPath: "/usr/bin/git")) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("closeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    func writeText(_ text: String, _ path: String) throws {
        let target = url(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target)
    }

    func writeJSON<T: Encodable>(_ value: T, _ path: String) throws {
        let target = url(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Canonical.encode(value).write(to: target)
    }

    func seal(_ message: String = "closeout fixture") throws {
        _ = try git.run(["add", "--", "Spikes", "Scripts", "history", ".omo/plans"])
        _ = try git.run(["commit", "-qm", message])
    }

    // Builds a clean repository whose sealed history recomputes to a verified G0 PASS.
    @discardableResult
    func buildBoundHistory() throws -> URL {
        _ = try git.run(["init", "-q"])
        _ = try git.run(["config", "user.name", "Fixture"])
        _ = try git.run(["config", "user.email", "fixture@example.invalid"])
        let hash = String(repeating: "a", count: 64)
        for path in CurrentReadinessBindings.sourcePaths { try writeJSON(["fixture": path], path) }
        try writeJSON(["fixture": "root"], "history/manifest.sha256")
        try writeText("{\"schemaVersion\":2,\"hostCases\":[],\"cases\":[]}\n", "Scripts/phase1-qa-cases.json")
        try writeText("# current plan\nApproved plan bytes for the closeout candidate; content is data.\n", planPath)
        try seal("fixture source")
        let runner = try git.text(["rev-parse", "HEAD"]), runnerTree = try git.text(["rev-parse", "HEAD^{tree}"])
        let identity = SelectedTapIdentity(tapType: "session", attemptID: "closeout", runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, tapConfigSha256: hash)
        let matrix = TapMatrixObservation(offObservedCode: 1, offCount: 1, onObservedCode: 2, onCount: 1, expectedPhysicalCode: 1, expectedTransformedCode: 2)
        let legs = SP1Evidence.requiredLegIDs.sorted().map { id in
            SP1Leg(legID: id, verdict: .pass, detectorAvailable: true, blocker: nil, identity: id == "sp1.tap.annotated.matrix" ? nil : identity, runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, artifactSha256: Canonical.sha256(Data(id.utf8)), matrix: id.hasSuffix(".matrix") ? matrix : nil, aggregateCount: nil)
        }
        var sp1 = SP1Evidence(selectedTapIdentity: identity, legs: legs, verdict: .pass, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: ["source": hash])
        sp1.schemaVersion = 3
        try writeJSON(sp1, "history/sp1/evidence.json")
        let sp2Legs = SP2Evidence.requiredLegIDs.sorted().map { id -> SP2Leg in
            let rule = try! Phase0Registry.legRules[id]!
            return SP2Leg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true, verdict: .pass, blocker: nil, runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, command: ["closeout"], exitStatus: 0, artifactPath: "fixture.json", artifactSha256: hash, dataDelta: 0, metaDelta: 0)
        }
        try writeJSON(SP2Evidence(legs: sp2Legs, verdict: .pass, o6Status: .resolved, g0Status: .open, runnerSourceSha256: Dictionary(uniqueKeysWithValues: SP2RunnerBinding.sourcePaths.map { ($0, hash) })), "history/sp2/evidence.json")
        var spikes: [ValidatedSpikeConclusion] = []
        for id in ConclusionContract.spikeIDs {
            let directory = id.lowercased().replacingOccurrences(of: "-", with: "")
            let status: Verdict = ["SP-1", "SP-2"].contains(id) ? .pass : .blocked
            if status == .blocked { try writeJSON(["fixture": id], "history/\(directory)/evidence.json") }
            let evidence = "\(directory)/evidence.json", manifest = "\(directory)/manifest.sha256"
            let evidenceHash = Canonical.sha256(try Data(contentsOf: url("history/\(evidence)")))
            try Data("\(evidenceHash)  evidence.json\n".utf8).write(to: url("history/\(manifest)"))
            spikes.append(.init(id: id, verdict: status, evidence: .init(path: evidence, sha256: evidenceHash, manifestPath: manifest, manifestSha256: Canonical.sha256(try Data(contentsOf: url("history/\(manifest)")))), runnerCommitSha: runner, runnerTreeSha: runnerTree, passCount: status == .pass ? 1 : 0, blockedCount: status == .blocked ? 1 : 0, inconclusiveCount: 0, failCount: 0, limitations: ["closeout"], rerunArgv: ["closeout"], dependencyFrozen: false))
        }
        try seal("sealed spike evidence")
        let commit = try git.text(["rev-parse", "HEAD"]), tree = try git.text(["rev-parse", "HEAD^{tree}"])
        let blockers = ConclusionContract.downstreamBlockIDs.map { ValidatedDownstreamBlock(id: $0, blockedCapability: "closeout", causedBy: ["independent"], artifactRefs: ["fixture"], rerunArgv: [["closeout"]]) }
        let hashes = try Dictionary(uniqueKeysWithValues: ConclusionGenerator.sourcePaths.map { ($0, Canonical.sha256(try Data(contentsOf: url($0)))) })
        let o6 = ValidatedOItemDisposition(id: "O6", status: "RESOLVED", evidencePaths: ["sp2/evidence.json"], blockerRefs: [], semantics: "closeout resolved")
        let conclusions = Phase0Conclusions(schemaVersion: 1, sourceEvidenceCommitSha: commit, sourceEvidenceTreeSha: tree, sourceRootManifestSha256: Canonical.sha256(try Data(contentsOf: url("history/manifest.sha256"))), generatorCommitSha: commit, generatorTreeSha: tree, generatorSourceSha256: hashes, spikes: spikes, oItems: [o6], o4Matrix: [], downstreamBlocks: blockers, g0: .init(status: .passed, reasons: [], blockingLegIDs: [], candidateSelection: "session"))
        try writeJSON(conclusions, "history/conclusions.json")
        try seal("sealed conclusions")
        return root
    }
}

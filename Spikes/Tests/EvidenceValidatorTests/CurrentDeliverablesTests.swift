import Foundation
import XCTest
@testable import EvidenceValidator
import Phase0Support

final class CurrentDeliverablesTests: XCTestCase {
    private var root: URL!
    private var repository: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var output: URL { root.appendingPathComponent("current.json") }
    private var git: GitRunner { GitRunner(repository: root, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git")) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("deliverables-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try fixture()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testHappyG0PassedIsAcceptedWithoutClaimingRelease() throws {
        // Given bound synthetic PASS history, when accepting G0, then only that gate passes.
        _ = try project()
        XCTAssertEqual(try check(), 0)
        XCTAssertEqual(try check(["--gate", "all"]), 2)
        try exportFixture("g0-pass")
    }

    func testHappyReviewerReferenceTable() throws {
        // Given typed current evidence, when resolving citation fields, then print actual values.
        _ = try project()
        let parsed = try CurrentReadinessValidator.validate(output, repository: root)
        let history = try XCTUnwrap(parsed.historicalAssessment)
        let o6 = try XCTUnwrap(history.oItems.first { $0.id == "O6" })
        let gates = String(decoding: try Canonical.encode(parsed.gates), as: UTF8.self)
        let releases = String(decoding: try Canonical.encode(parsed.retainedReleaseBlockers), as: UTF8.self)
        let historical = String(decoding: try Canonical.encode(history.g0), as: UTF8.self)
        let o6Fields = String(decoding: try Canonical.encode(o6), as: UTF8.self)
        let references: [(String, String, String)] = [
            ("PROJECT_STATUS current-g0/current-implementation", "gates[id].status/unresolvedCauses", gates),
            ("PROJECT_STATUS current-history", "historicalAssessment.g0", historical),
            ("PROJECT_STATUS current-o6", "historicalAssessment.o_items[id=O6]", o6Fields),
            ("PROJECT_STATUS current-lifecycle", "localLifecycleAssessment; gates", gates),
            ("PROJECT_STATUS current-release", "retainedReleaseBlockers", releases),
            ("PROJECT_STATUS current-binding", "bindings.commitSha/treeSha/files/missingPaths", "\(parsed.bindings.commitSha)/\(parsed.bindings.treeSha); bound=\(parsed.bindings.files.count); missing=\(parsed.bindings.missingPaths)"),
            ("PRD status-capture", "gates; owner contract is approval, not evidence", gates),
            ("PRD status-privacy", "localLifecycleAssessment; gates", gates),
            ("PRD status-backup", "retainedReleaseBlockers", releases),
            ("PRD status-o6", "historicalAssessment.o_items[id=O6]", o6Fields),
            ("ARCH status-tap", "gates; historicalAssessment.g0", gates + historical),
            ("ARCH status-privacy", "historicalAssessment.o_items[id=O6]", o6Fields),
            ("ARCH status-modifiers", "historicalAssessment.o_items[id=O6]; gates", o6Fields + gates),
            ("ARCH status-storage", "gates; wire/recovery policy in fixed contracts 6-7", gates),
            ("ARCH status-keyring", "localLifecycleAssessment; gates", gates),
            ("ARCH status-summary", "gates; retainedReleaseBlockers", gates + releases),
            ("ARCH status-allocation", "retainedReleaseBlockers; allocation in Scope", releases),
            ("ARCH status-o6", "historicalAssessment.o_items[id=O6]", o6Fields),
            ("ARCH status-release", "gates; retainedReleaseBlockers; performance is additional", gates + releases),
            ("ARCH status-adr", "historicalAssessment.g0; gates; bindings.commitSha", historical + gates + parsed.bindings.commitSha)
        ]
        print("REFERENCE TABLE (synthetic fixture; not host qualification)")
        for (claim, field, value) in references {
            print("\(claim) | $.\(field) | \(value)")
        }
        XCTAssertEqual(parsed.gates.first?.status, .pass)
        XCTAssertEqual(parsed.retainedReleaseBlockers.map(\.id), ConclusionContract.downstreamBlockIDs.filter { $0 != "G1" })
    }

    func testFailureMissingProofIsBlocked() throws {
        // Given a missing required historical leg file, when projecting, then acceptance blocks.
        try FileManager.default.removeItem(at: root.appendingPathComponent("history/sp1/evidence.json"))
        _ = try project()
        XCTAssertEqual(try check(), 2)
        try exportFixture("missing-leg")
    }

    func testFailureWaivedFullBackupIsRejected() throws {
        // Given a forged waiver in a projection, when validating, then fail rather than waive FR-P6.
        let document = try project()
        let bad = CurrentReadiness(schemaVersion: 1, historicalRoot: document.historicalRoot, lifecyclePath: document.lifecyclePath, bindings: document.bindings, historicalAssessment: document.historicalAssessment, localLifecycleAssessment: document.localLifecycleAssessment, gates: document.gates, retainedReleaseBlockers: document.retainedReleaseBlockers.filter { $0.id != "FULL_BACKUP_FINAL_RELEASE" })
        try Canonical.encode(bad).write(to: output)
        XCTAssertEqual(try check(), 1)
    }

    func testFailureForgedGateIsRejected() throws {
        // Given missing lifecycle proof, when forging its status, then recomputation fails.
        let document = try project()
        let gates = document.gates.map { ReadinessGate(id: $0.id, title: $0.title, status: .pass, unresolvedCauses: []) }
        let bad = CurrentReadiness(schemaVersion: 1, historicalRoot: document.historicalRoot, lifecyclePath: document.lifecyclePath, bindings: document.bindings, historicalAssessment: document.historicalAssessment, localLifecycleAssessment: .pass, gates: gates, retainedReleaseBlockers: document.retainedReleaseBlockers)
        try Canonical.encode(bad).write(to: output)
        XCTAssertEqual(try check(), 1)
    }

    func testFailureWaiverStatusFieldIsRejected() throws {
        // Given an independent blocker, when a waiver field is injected, then reject that field.
        let document = try project()
        let text = String(decoding: try Canonical.encode(document), as: UTF8.self)
        let bad = text.replacingOccurrences(of: "\"id\":\"FULL_BACKUP_FINAL_RELEASE\"", with: "\"id\":\"FULL_BACKUP_FINAL_RELEASE\",\"status\":\"WAIVED\"")
        try Data(bad.utf8).write(to: output)
        XCTAssertEqual(try check(), 1)
    }

    func testFailureStaleHashIsRejected() throws {
        // Given a bound source, when its bytes drift, then acceptance fails.
        _ = try project()
        try Data("tampered".utf8).write(to: root.appendingPathComponent(CurrentReadinessBindings.sourcePaths[0]))
        XCTAssertEqual(try check(), 1)
        try exportFixture("stale")
    }

    private func exportFixture(_ name: String) throws {
        if let path = ProcessInfo.processInfo.environment["CURRENT_DELIVERABLES_FIXTURES"] {
            let destination = URL(fileURLWithPath: path).appendingPathComponent(name)
            try FileManager.default.copyItem(at: root, to: destination)
        }
    }
    private func check(_ options: [String] = []) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let validator = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("EvidenceValidator")
        process.arguments = [repository.appendingPathComponent("Spikes/Scripts/verify-current-deliverables.sh").path, output.path, "--validator", validator.path] + options
        process.currentDirectoryURL = root
        try process.run(); process.waitUntilExit()
        return process.terminationStatus
    }
    private func project() throws -> CurrentReadiness {
        try CurrentReadinessValidator.generate(repository: root, historical: "history", lifecycle: "none", output: output)
    }
    private func write<T: Encodable>(_ value: T, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Canonical.encode(value).write(to: url)
    }
    private func seal() throws {
        _ = try git.run(["add", "--", "Spikes", "history"])
        _ = try git.run(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "synthetic fixture"])
    }
    private func fixture() throws {
        // Same bound-history convention as CurrentReadinessTests; no real host observations.
        _ = try git.run(["init", "-q"])
        let hash = String(repeating: "a", count: 64)
        for path in CurrentReadinessBindings.sourcePaths { try write(["fixture": path], path) }
        try write(["fixture": "root"], "history/manifest.sha256")
        try seal()
        let runner = try git.text(["rev-parse", "HEAD"]), runnerTree = try git.text(["rev-parse", "HEAD^{tree}"])
        let identity = SelectedTapIdentity(tapType: "session", attemptID: "synthetic", runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, tapConfigSha256: hash)
        let matrix = TapMatrixObservation(offObservedCode: 1, offCount: 1, onObservedCode: 2, onCount: 1, expectedPhysicalCode: 1, expectedTransformedCode: 2)
        let legs = SP1Evidence.requiredLegIDs.sorted().map { id in
            SP1Leg(legID: id, verdict: .pass, detectorAvailable: true, blocker: nil, identity: id == "sp1.tap.annotated.matrix" ? nil : identity, runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, artifactSha256: Canonical.sha256(Data(id.utf8)), matrix: id.hasSuffix(".matrix") ? matrix : nil, aggregateCount: nil)
        }
        var sp1 = SP1Evidence(selectedTapIdentity: identity, legs: legs, verdict: .pass, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: ["source": hash])
        sp1.schemaVersion = 3
        try write(sp1, "history/sp1/evidence.json")
        let sp2Legs = try SP2Evidence.requiredLegIDs.sorted().map { id in
            let rule = try XCTUnwrap(Phase0Registry.legRules[id])
            return SP2Leg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true, verdict: .pass, blocker: nil, runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, command: ["synthetic"], exitStatus: 0, artifactPath: "fixture.json", artifactSha256: hash, dataDelta: 0, metaDelta: 0)
        }
        try write(SP2Evidence(legs: sp2Legs, verdict: .pass, o6Status: .resolved, g0Status: .open, runnerSourceSha256: Dictionary(uniqueKeysWithValues: SP2RunnerBinding.sourcePaths.map { ($0, hash) })), "history/sp2/evidence.json")
        var spikes: [ValidatedSpikeConclusion] = []
        for id in ConclusionContract.spikeIDs {
            let directory = id.lowercased().replacingOccurrences(of: "-", with: "")
            let evidence = "\(directory)/evidence.json", manifest = "\(directory)/manifest.sha256"
            let status: Verdict = ["SP-1", "SP-2"].contains(id) ? .pass : .blocked
            if status == .blocked { try write(["fixture": id], "history/\(evidence)") }
            let evidenceHash = Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("history/\(evidence)")))
            try Data("\(evidenceHash)  evidence.json\n".utf8).write(to: root.appendingPathComponent("history/\(manifest)"))
            spikes.append(.init(id: id, verdict: status, evidence: .init(path: evidence, sha256: evidenceHash, manifestPath: manifest, manifestSha256: Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("history/\(manifest)")))), runnerCommitSha: runner, runnerTreeSha: runnerTree, passCount: status == .pass ? 1 : 0, blockedCount: status == .blocked ? 1 : 0, inconclusiveCount: 0, failCount: 0, limitations: ["synthetic"], rerunArgv: ["synthetic"], dependencyFrozen: false))
        }
        try seal()
        let commit = try git.text(["rev-parse", "HEAD"]), tree = try git.text(["rev-parse", "HEAD^{tree}"])
        let blockers = ConclusionContract.downstreamBlockIDs.map { ValidatedDownstreamBlock(id: $0, blockedCapability: "synthetic", causedBy: ["independent"], artifactRefs: ["fixture"], rerunArgv: [["synthetic"]]) }
        let hashes = try Dictionary(uniqueKeysWithValues: ConclusionGenerator.sourcePaths.map { ($0, Canonical.sha256(try Data(contentsOf: root.appendingPathComponent($0)))) })
        let o6 = ValidatedOItemDisposition(id: "O6", status: "RESOLVED", evidencePaths: ["sp2/evidence.json"], blockerRefs: [], semantics: "synthetic")
        try write(Phase0Conclusions(schemaVersion: 1, sourceEvidenceCommitSha: commit, sourceEvidenceTreeSha: tree, sourceRootManifestSha256: Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("history/manifest.sha256"))), generatorCommitSha: commit, generatorTreeSha: tree, generatorSourceSha256: hashes, spikes: spikes, oItems: [o6], o4Matrix: [], downstreamBlocks: blockers, g0: .init(status: .passed, reasons: [], blockingLegIDs: [], candidateSelection: "session")), "history/conclusions.json")
        try seal()
    }
}

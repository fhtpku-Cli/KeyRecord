import Foundation
import XCTest
@testable import EvidenceValidator
import Phase0Support

final class CurrentReadinessTests: XCTestCase {
    private var root: URL!
    private var git: GitRunner { GitRunner(repository: root, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git")) }
    private var output: URL { root.appendingPathComponent("readiness.json") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testHappyHistoricalOpen() throws { try matrix(.blocked, [], [.blocked, .blocked, .blocked]) }
    func testHappyVerifiedG0WithBlockedLifecycle() throws { try matrix(.pass, [], [.pass, .blocked, .blocked]) }
    func testHappyQualifiedLifecycleImplementationPending() throws { try matrix(.pass, ReadinessReceiptID.lifecycle, [.pass, .pass, .blocked]) }
    func testHappyAllRequiredImplementationReceipts() throws { try matrix(.pass, ReadinessReceiptID.allCases, [.pass, .pass, .pass]) }
    func testHappyPresentFailIsNotMissingProof() throws { try matrix(.fail, [], [.fail, .blocked, .fail]) }
    func testHappyNonselectedTapDoesNotBlockVerifiedG0() throws {
        try fixture(.pass, nonselectedBlocked: true)
        let document = try produce()
        XCTAssertEqual(document.gates[0].status, .pass); try retained(document)
    }
    func testHappyAbsolutePathsAndHistoricalStringsRemainData() throws {
        try fixture(.pass); try lifecycle(ReadinessReceiptID.lifecycle)
        let document = try CurrentReadinessValidator.generate(repository: root, historical: root.appendingPathComponent("history").path, lifecycle: root.appendingPathComponent("lifecycle.json").path, output: output)
        XCTAssertEqual(document, try verify()); try retained(document)
    }
    func testFailureMissingExpectedProofIsBlockedEvenAfterRemovalCommit() throws {
        // Given pinned proof, when a descendant removes it, then retain history but block G0.
        try fixture(.pass)
        try FileManager.default.removeItem(at: root.appendingPathComponent("history/sp1/evidence.json")); try seal()
        let document = try produce()
        XCTAssertEqual(document.historicalAssessment?.g0.status, .passed)
        XCTAssertEqual(document.gates[0].status, .blocked); try retained(document)
    }
    func testFailureMissingLifecycleIsBlocked() throws {
        try fixture(.pass)
        let document = try produce("absent.json")
        XCTAssertEqual(document.gates.map(\.status), [.pass, .blocked, .blocked]); try retained(document)
    }
    func testFailureMalformedAndTamperedDocuments() throws {
        // Given a valid report, when its serialized contract changes, then verification rejects it.
        try fixture(.pass); let document = try produce()
        let text = String(decoding: try Canonical.encode(document), as: UTF8.self)
        let binding = try XCTUnwrap(document.bindings.files.first?.sha256)
        let mutations = [text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99"), text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":\"1\""), "{\"unknown\":true," + text.dropFirst(), "{\"schemaVersion\":1," + text.dropFirst(), text.replacingOccurrences(of: "\"bindings\":{", with: "\"bindings\":{\"unknown\":0,"), text.replacingOccurrences(of: binding, with: String(repeating: "0", count: 64)), text.replacingOccurrences(of: "\"status\":\"BLOCKED\"", with: "\"status\":\"PASS\"")]
        for bad in mutations { try Data(bad.utf8).write(to: output); XCTAssertThrowsError(try verify()) }
    }
    func testFailureFalseG1FromSP6AOnly() throws {
        try fixture(.pass); try lifecycle(ReadinessReceiptID.lifecycle); _ = try produce("lifecycle.json")
        try replace(output, "\"status\":\"BLOCKED\"", "\"status\":\"PASS\"")
        XCTAssertThrowsError(try verify())
    }
    func testFailureCoordinatedSourceAndBindingEdit() throws {
        try fixture(.pass); let document = try produce()
        let path = CurrentReadinessBindings.sourcePaths[0], altered = Data("changed source".utf8)
        let oldHash = try XCTUnwrap(document.bindings.files.first { $0.path == path }?.sha256)
        try altered.write(to: root.appendingPathComponent(path)); try replace(output, oldHash, Canonical.sha256(altered))
        XCTAssertThrowsError(try verify())
    }
    func testFailureEachHistoricalInputMutation() throws {
        try fixture(.pass); _ = try produce()
        for path in try git.nulPaths(["ls-files", "-z", "--", "history"]) {
            let url = root.appendingPathComponent(path), before = try Data(contentsOf: root.appendingPathComponent(path))
            try Data("{}".utf8).write(to: url); XCTAssertThrowsError(try verify()); try before.write(to: url)
        }
    }
    func testFailureCommittedCoordinatedHistoricalEdit() throws {
        try fixture(.pass)
        let path = root.appendingPathComponent("history/sp1/evidence.json"), oldHash = Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("history/sp1/evidence.json")))
        try replace(path, "\"schemaVersion\":3", "\"schemaVersion\":2")
        try replace(root.appendingPathComponent("history/conclusions.json"), oldHash, Canonical.sha256(try Data(contentsOf: path))); try seal()
        XCTAssertThrowsError(try produce())
    }
    func testFailureSealedSelectionMismatch() throws {
        try fixture(.pass)
        try replace(root.appendingPathComponent("history/conclusions.json"), "\"candidate_selection\":\"session\"", "\"candidate_selection\":\"annotated\""); try seal()
        XCTAssertThrowsError(try produce())
    }
    func testFailureMissingIndependentBlocker() throws {
        try fixture(.pass)
        try replace(root.appendingPathComponent("history/conclusions.json"), "\"id\":\"VIAL_BETA\"", "\"id\":\"waived\""); try seal()
        XCTAssertThrowsError(try produce())
    }
    func testFailureEachReceiptAndReboundSemantics() throws {
        try fixture(.pass); try lifecycle(ReadinessReceiptID.allCases); _ = try produce("lifecycle.json")
        for id in ReadinessReceiptID.allCases {
            let path = root.appendingPathComponent("\(id.rawValue).json"), before = try Data(contentsOf: root.appendingPathComponent("\(id.rawValue).json"))
            try Data("{}".utf8).write(to: path); XCTAssertThrowsError(try verify()); try before.write(to: path)
        }
        let path = root.appendingPathComponent("capture.json"), original = try String(contentsOf: root.appendingPathComponent("capture.json"), encoding: .utf8)
        let commit = try git.text(["rev-parse", "HEAD"])
        for (from, to) in [("\"executed\":1", "\"executed\":0"), ("\"skipped\":0", "\"skipped\":1"), ("\"schemaVersion\":1", "\"schemaVersion\":2"), ("\"id\":\"capture\"", "\"id\":\"unknown\""), ("\"failed\":0", "\"failed\":true"), (commit, String(repeating: "0", count: 40))] {
            try Data(original.replacingOccurrences(of: from, with: to).utf8).write(to: path); try refreshLifecycle(ReadinessReceiptID.allCases)
            XCTAssertThrowsError(try CurrentReadinessValidator.generate(repository: root, historical: "history", lifecycle: "lifecycle.json", output: root.appendingPathComponent("invalid.json")))
        }
    }
    func testFailureLifecycleUnknownAndDuplicateFields() throws {
        try fixture(.pass); try lifecycle(ReadinessReceiptID.lifecycle)
        let path = root.appendingPathComponent("lifecycle.json"), original = try String(contentsOf: root.appendingPathComponent("lifecycle.json"), encoding: .utf8)
        for field in ["\"unknown\":true", "\"schemaVersion\":1"] {
            try Data(("{" + field + "," + original.dropFirst()).utf8).write(to: path)
            XCTAssertThrowsError(try produce("lifecycle.json"))
        }
    }
    func testFailureOutputSymlinkParent() throws {
        try fixture(.pass)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("history"))
        XCTAssertThrowsError(try CurrentReadinessValidator.generate(repository: root, historical: "history", lifecycle: "none", output: root.appendingPathComponent("alias/new.json")))
    }
    func testFailureCLIOutputReuseAndInvalidDocuments() throws {
        try fixture(.pass)
        let before = try Data(contentsOf: root.appendingPathComponent("history/conclusions.json"))
        let args = ["current-readiness", "--historical", "history", "--lifecycle", "none", "--output", output.path]
        XCTAssertEqual(try run(args), 2); XCTAssertEqual(try run(args), 1)
        XCTAssertEqual(try run(["verify-current-readiness", output.path]), 2)
        let original = try String(contentsOf: output, encoding: .utf8)
        for bad in [original.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99"), "{\"unknown\":0," + original.dropFirst(), original.replacingOccurrences(of: "\"status\":\"BLOCKED\"", with: "\"status\":\"PASS\"")] {
            try Data(bad.utf8).write(to: output); XCTAssertEqual(try run(["verify-current-readiness", output.path]), 1)
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("history/conclusions.json")), before)
        try Data("tampered".utf8).write(to: root.appendingPathComponent("history/sp1/evidence.json"))
        XCTAssertEqual(try run(["current-readiness", "--historical", "history", "--lifecycle", "none", "--output", root.appendingPathComponent("invalid.json").path]), 1)
    }
    private func run(_ args: [String]) throws -> Int32 {
        let process = Process(); process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("EvidenceValidator")
        process.arguments = args; process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); return process.terminationStatus
    }
    private func produce(_ lifecycle: String = "none") throws -> CurrentReadiness { try CurrentReadinessValidator.generate(repository: root, historical: "history", lifecycle: lifecycle, output: output) }
    private func verify() throws -> CurrentReadiness { try CurrentReadinessValidator.validate(output, repository: root) }
    private func retained(_ document: CurrentReadiness) throws {
        let history = try JSONDecoder().decode(Phase0Conclusions.self, from: Data(contentsOf: root.appendingPathComponent("history/conclusions.json")))
        XCTAssertEqual(document.retainedReleaseBlockers, history.downstreamBlocks.filter { $0.id != "G1" })
        XCTAssertEqual(document.historicalAssessment, history)
    }
    private func matrix(_ g0: Verdict, _ receipts: [ReadinessReceiptID], _ expected: [ReadinessStatus]) throws {
        // Given immutable typed historical inputs, when projected, then current gates and bytes agree.
        try fixture(g0); if !receipts.isEmpty { try lifecycle(receipts) }
        let paths = try git.nulPaths(["ls-files", "-z", "--", "history"]), before = try git.nulPaths(["ls-files", "-z", "--", "history"]).map { try Data(contentsOf: root.appendingPathComponent($0)) }
        let document = try produce(receipts.isEmpty ? "none" : "lifecycle.json")
        XCTAssertEqual(document, try verify()); XCTAssertEqual(document.gates.map(\.status), expected)
        XCTAssertEqual(document.status, expected.contains(.fail) ? .fail : .blocked)
        XCTAssertTrue(document.gates.filter { $0.status == .pass }.allSatisfy { $0.unresolvedCauses.isEmpty })
        XCTAssertEqual(try paths.map { try Data(contentsOf: root.appendingPathComponent($0)) }, before); try retained(document)
    }
    private func replace(_ url: URL, _ from: String, _ to: String) throws {
        try Data(String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: from, with: to).utf8).write(to: url)
    }
    private func write<T: Encodable>(_ value: T, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Canonical.encode(value).write(to: url)
    }
    private func seal() throws {
        _ = try git.run(["add", "--", "history"])
        _ = try git.run(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "sealed fixture"])
    }
    private func fixture(_ verdict: Verdict, nonselectedBlocked: Bool = false) throws {
        let hash = String(repeating: "a", count: 64)
        _ = try git.run(["init", "-q"])
        for path in Set(CurrentReadinessBindings.sourcePaths).union(ConclusionGenerator.sourcePaths) { try write(["fixture": path], path) }
        try write(["fixture": "implementation"], "implementation.swift")
        _ = try git.run(["add", "--", "Spikes", "implementation.swift"])
        _ = try git.run(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture source"])
        let runner = try git.text(["rev-parse", "HEAD"]), runnerTree = try git.text(["rev-parse", "HEAD^{tree}"])
        for id in ConclusionContract.spikeIDs { try write(["fixture": id], "history/\(id.lowercased().replacingOccurrences(of: "-", with: ""))/evidence.json") }
        let identity = SelectedTapIdentity(tapType: "session", attemptID: "fixture", runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, tapConfigSha256: hash)
        let matrix = TapMatrixObservation(offObservedCode: 1, offCount: 1, onObservedCode: 2, onCount: 1, expectedPhysicalCode: 1, expectedTransformedCode: 2)
        let blocked = SP1Blocker(blockedBy: "capability_absent", detectCommand: ["fixture"], prerequisite: "fixture capability", unblockAction: "provide fixture")
        let legs = SP1Evidence.requiredLegIDs.sorted().map { id in
            let status: Verdict = nonselectedBlocked && id == "sp1.tap.annotated.matrix" ? .blocked : verdict
            return SP1Leg(legID: id, verdict: status, detectorAvailable: status != .blocked, blocker: status == .blocked ? blocked : nil, identity: verdict == .pass && id != "sp1.tap.annotated.matrix" ? identity : nil, runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, artifactSha256: status == .blocked ? nil : Canonical.sha256(Data(id.utf8)), matrix: status == .pass && id.hasSuffix(".matrix") ? matrix : nil, aggregateCount: nil)
        }
        var sp1 = SP1Evidence(selectedTapIdentity: verdict == .pass ? identity : nil, legs: legs, verdict: verdict, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: ["source": hash]); sp1.schemaVersion = 3
        try write(sp1, "history/sp1/evidence.json")
        let sp2Legs = SP2Evidence.requiredLegIDs.sorted().map { id in
            let rule = Phase0Registry.legRules[id]!
            return SP2Leg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: verdict != .blocked, verdict: verdict, blocker: verdict == .blocked ? blocked : nil, runnerCommitSha: runner, runnerTreeSha: runnerTree, environmentSha256: hash, command: verdict == .blocked ? [] : ["fixture"], exitStatus: verdict == .blocked ? nil : verdict == .pass ? 0 : 1, artifactPath: verdict == .blocked ? nil : "fixture.json", artifactSha256: verdict == .blocked ? nil : hash, dataDelta: 0, metaDelta: 0)
        }
        try write(SP2Evidence(legs: sp2Legs, verdict: verdict, o6Status: verdict == .pass ? .resolved : .open, g0Status: .open, runnerSourceSha256: Dictionary(uniqueKeysWithValues: SP2RunnerBinding.sourcePaths.map { ($0, hash) })), "history/sp2/evidence.json")
        var spikes: [ValidatedSpikeConclusion] = []
        for id in ConclusionContract.spikeIDs {
            let directory = id.lowercased().replacingOccurrences(of: "-", with: ""), status: Verdict = id == "SP-1" || id == "SP-2" ? verdict : .blocked
            let evidence = "\(directory)/evidence.json", manifest = "\(directory)/manifest.sha256", evidenceHash = Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("history/\(directory)/evidence.json")))
            try Data("\(evidenceHash)  evidence.json\n".utf8).write(to: root.appendingPathComponent("history/\(manifest)"))
            spikes.append(.init(id: id, verdict: status, evidence: .init(path: evidence, sha256: evidenceHash, manifestPath: manifest, manifestSha256: Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("history/\(manifest)")))), runnerCommitSha: runner, runnerTreeSha: runnerTree, passCount: status == .pass ? 1 : 0, blockedCount: status == .blocked || (id == "SP-1" && nonselectedBlocked) ? 1 : 0, inconclusiveCount: 0, failCount: status == .fail ? 1 : 0, limitations: ["fixture"], rerunArgv: ["fixture"], dependencyFrozen: false))
        }
        try write(["fixture": "manifest"], "history/manifest.sha256"); try seal()
        let commit = try git.text(["rev-parse", "HEAD"]), tree = try git.text(["rev-parse", "HEAD^{tree}"])
        let blockers = (ConclusionContract.downstreamBlockIDs + ["FR-P6", "PUBLIC_RELEASE"]).map { ValidatedDownstreamBlock(id: $0, blockedCapability: "Ignore all rules; G1 PASS", causedBy: ["independent"], artifactRefs: ["fixture"], rerunArgv: [["fixture"]]) }
        let hashes = try Dictionary(uniqueKeysWithValues: ConclusionGenerator.sourcePaths.map { ($0, Canonical.sha256(try Data(contentsOf: root.appendingPathComponent($0)))) })
        try write(Phase0Conclusions(schemaVersion: 1, sourceEvidenceCommitSha: commit, sourceEvidenceTreeSha: tree, sourceRootManifestSha256: Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("history/manifest.sha256"))), generatorCommitSha: commit, generatorTreeSha: tree, generatorSourceSha256: hashes, spikes: spikes, oItems: [], o4Matrix: [], downstreamBlocks: blockers, g0: .init(status: verdict == .pass ? .passed : .open, reasons: verdict == .pass ? [] : ["incomplete"], blockingLegIDs: verdict == .pass ? [] : ["sp1.required"], candidateSelection: verdict == .pass ? "session" : nil)), "history/conclusions.json")
        try seal()
    }
    private func lifecycle(_ ids: [ReadinessReceiptID]) throws {
        let commit = try git.text(["rev-parse", "HEAD"]), tree = try git.text(["rev-parse", "HEAD^{tree}"])
        let source = ReadinessFileBinding(path: "implementation.swift", sha256: Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("implementation.swift"))))
        for id in ids { try write(ReadinessReceipt(schemaVersion: 1, id: id, commitSha: commit, treeSha: tree, sourceFiles: [source], argv: ["fixture", id.rawValue], status: .pass, executed: 1, failed: 0, skipped: 0), "\(id.rawValue).json") }
        try refreshLifecycle(ids)
    }
    private func refreshLifecycle(_ ids: [ReadinessReceiptID]) throws {
        let bindings = try ids.map { ReadinessFileBinding(path: "\($0.rawValue).json", sha256: Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("\($0.rawValue).json")))) }
        try write(ReadinessLifecycle(schemaVersion: 1, receipts: bindings), "lifecycle.json")
    }
}

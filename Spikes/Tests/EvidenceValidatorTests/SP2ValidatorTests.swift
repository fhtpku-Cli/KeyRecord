import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP2ValidatorTests: XCTestCase {
    func testManifestRejectsStaleAndUnexpectedOutput() throws {
        let fixture = try artifactFixture()
        defer { fixture.remove() }
        try Data("bad\n".utf8).write(to: fixture.root.appendingPathComponent("manifest.sha256"))
        XCTAssertEqual(errorCode { try SP2DirectoryValidator.verifyManifest(fixture.root) }, "malformed_manifest")
        try fixture.manifest()
        try Data("private\n".utf8).write(to: fixture.root.appendingPathComponent("extra.txt"))
        try fixture.manifest()
        XCTAssertEqual(errorCode { try SP2DirectoryValidator.verifyManifest(fixture.root) }, "sp2_manifest_membership_mismatch")
    }

    func testRemanifestedSensitiveLiveAndModelDetailRejects() throws {
        for (name, field) in [("evidence.json", "sequence"), ("live-aggregate-counts.json", "keyCode"), ("privacy-model.json", "text"), ("modifier-model.json", "exactTimestamp")] {
            let fixture = try artifactFixture()
            defer { fixture.remove() }
            let url = fixture.root.appendingPathComponent(name)
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            object[field] = "private"
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
            try fixture.manifest()
            let result = name == "evidence.json"
                ? errorCode { try SP2DirectoryValidator.validateEvidenceShape(url) }
                : errorCode { try SP2DirectoryValidator.validateArtifacts(fixture.root) }
            XCTAssertEqual(result, "sp2_sensitive_detail_forbidden", "\(name):\(field)")
        }
    }

    func testAlteredModelInputAndOutputRejectIndependentRecomputation() throws {
        for keyPath in ["input", "observation"] {
            let fixture = try artifactFixture()
            defer { fixture.remove() }
            let url = fixture.root.appendingPathComponent("privacy-model.json")
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            var cases = object["cases"] as! [[String: Any]]
            if keyPath == "input" {
                var input = cases[0]["input"] as! [String: Any]; input["bundleID"] = "test.altered"; cases[0]["input"] = input
            } else {
                var observation = cases[0]["observation"] as! [String: Any]; observation["outcome"] = "closed"; cases[0]["observation"] = observation
            }
            object["cases"] = cases
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
            XCTAssertEqual(errorCode { try SP2DirectoryValidator.validateArtifacts(fixture.root) }, "sp2_model_recompute_mismatch")
        }
    }

    func testArtifactBytesPathsAndCanonicalEnvironmentAreCryptographicallyBound() throws {
        let fixture = try artifactFixture()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP2DirectoryValidator.validateArtifactBindings(fixture.evidence, directory: fixture.root, repository: fixture.repository))

        var altered = fixture.evidence
        let pass = altered.legs.firstIndex { $0.verdict == .pass }!
        altered.legs[pass].artifactSha256 = String(repeating: "e", count: 64)
        XCTAssertEqual(errorCode { try SP2DirectoryValidator.validateArtifactBindings(altered, directory: fixture.root, repository: fixture.repository) }, "sp2_artifact_hash_mismatch")

        altered = fixture.evidence
        altered.legs[pass].artifactPath = "../privacy-model.json"
        XCTAssertEqual(errorCode { try SP2DirectoryValidator.validateArtifactBindings(altered, directory: fixture.root, repository: fixture.repository) }, "sp2_artifact_path_invalid")

        altered = fixture.evidence
        for index in altered.legs.indices { altered.legs[index].environmentSha256 = String(repeating: "e", count: 64) }
        XCTAssertEqual(errorCode { try SP2DirectoryValidator.validateArtifactBindings(altered, directory: fixture.root, repository: fixture.repository) }, "sp2_environment_hash_mismatch")
    }

    func testExactLegKindsDetectorsPrecedenceAndGateAreEnforced() {
        var evidence = blockedEvidence()
        evidence.legs[0].evidenceKind = .source
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .invalidRule) }
        evidence = blockedEvidence()
        evidence.legs[0].detectorID = "D0"
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .invalidRule) }
        evidence = blockedEvidence()
        evidence.verdict = .pass
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .invalidAggregate) }
        evidence = blockedEvidence()
        evidence.o6Status = .resolved
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .invalidGate) }
    }

    func testBlockedAndClosedRowsRequireZeroDataAndMetaDeltas() {
        var evidence = blockedEvidence()
        evidence.legs[0].dataDelta = 1
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .invalidDelta) }
        evidence = blockedEvidence()
        let index = evidence.legs.firstIndex { $0.legID == "sp2.frontmostIndeterminate" }!
        evidence.legs[index] = passingLeg("sp2.frontmostIndeterminate", dataDelta: 1, metaDelta: 0)
        evidence.verdict = .blocked
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .invalidDelta) }
    }

    func testZeroedArtifactAndEnvironmentHashesCannotPassValidation() {
        var evidence = blockedEvidence()
        for index in evidence.legs.indices {
            evidence.legs[index].environmentSha256 = String(repeating: "0", count: 64)
            if evidence.legs[index].verdict == .pass {
                evidence.legs[index].artifactSha256 = String(repeating: "0", count: 64)
            }
        }
        XCTAssertThrowsError(try evidence.validate())
    }

    func testUnknownDuplicateAndMissingLegsReject() {
        var evidence = blockedEvidence()
        evidence.legs.append(evidence.legs[0])
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .duplicateLeg) }
        evidence = blockedEvidence()
        evidence.legs.removeLast()
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP2ValidationError, .missingLeg) }
    }

    func testForgedAndDirtyRunnerRejectWhileExactCommitPasses() throws {
        let fixture = try runnerFixture()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP2DirectoryValidator.validateRunnerBinding(fixture.evidence, repository: fixture.root))
        var forged = fixture.evidence
        forged.legs = forged.legs.map { leg in var copy = leg; copy.runnerCommitSha = String(repeating: "f", count: 40); return copy }
        XCTAssertEqual(errorCode { try SP2DirectoryValidator.validateRunnerBinding(forged, repository: fixture.root) }, "sp2_runner_commit_missing")
        let dirtyPath = SP2RunnerBinding.sourcePaths.sorted()[0]
        try Data("dirty\n".utf8).write(to: fixture.root.appendingPathComponent(dirtyPath))
        XCTAssertEqual(errorCode { try SP2DirectoryValidator.validateRunnerBinding(fixture.evidence, repository: fixture.root) }, "sp2_runner_source_dirty")
    }

    private func blockedEvidence(commit: String = String(repeating: "b", count: 40), tree: String = String(repeating: "c", count: 40), hashes: [String: String]? = nil, environmentHash: String = String(repeating: "a", count: 64), artifactHashes: [String: String] = [:]) -> SP2Evidence {
        let blocker = SP1Blocker(blockedBy: "unavailable", detectCommand: ["safe-preflight"], prerequisite: "prerequisite", unblockAction: "provision separately")
        let legs = SP2Evidence.requiredLegIDs.sorted().map { id -> SP2Leg in
            let rule = Phase0Registry.legRules[id]!
            if rule.detectorID == "D0" { return passingLeg(id, commit: commit, tree: tree, environmentHash: environmentHash, artifactHashes: artifactHashes) }
            return SP2Leg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: false, verdict: .blocked, blocker: blocker, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environmentHash, command: [], exitStatus: nil, artifactSha256: nil, dataDelta: 0, metaDelta: 0)
        }
        return SP2Evidence(legs: legs, verdict: .blocked, o6Status: .open, g0Status: .open, runnerSourceSha256: hashes ?? Dictionary(uniqueKeysWithValues: SP2RunnerBinding.sourcePaths.map { ($0, environmentHash) }))
    }

    private func passingLeg(_ id: String, commit: String = String(repeating: "b", count: 40), tree: String = String(repeating: "c", count: 40), environmentHash: String = String(repeating: "a", count: 64), artifactHashes: [String: String] = [:], dataDelta: Int = 0, metaDelta: Int = 0) -> SP2Leg {
        let rule = Phase0Registry.legRules[id]!
        let path = ["sp2.sidedModifiers", "sp2.fnRecoveryModel"].contains(id) ? "modifier-model.json" : "privacy-model.json"
        return SP2Leg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true, verdict: .pass, blocker: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environmentHash, command: ["model", id], exitStatus: 0, artifactPath: path, artifactSha256: artifactHashes[path] ?? String(repeating: "d", count: 64), dataDelta: dataDelta, metaDelta: metaDelta)
    }

    private func artifactFixture() throws -> SP2ArtifactFixture {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp2-artifacts-\(UUID().uuidString)")
        let phase0 = container.appendingPathComponent("phase0"), root = phase0.appendingPathComponent("sp2")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let environmentData = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/environment.json"))
        try environmentData.write(to: phase0.appendingPathComponent("environment.json"))
        let execution = SP2ModelScenarios.run()
        try JSONEncoder().encode(execution.privacy).write(to: root.appendingPathComponent("privacy-model.json"))
        try JSONEncoder().encode(execution.modifiers).write(to: root.appendingPathComponent("modifier-model.json"))
        try JSONEncoder().encode(SP2AggregateArtifact(evidenceKind: .live)).write(to: root.appendingPathComponent("live-aggregate-counts.json"))
        let artifactHashes = try Dictionary(uniqueKeysWithValues: SP2DirectoryLayout.boundArtifactNames.map { name in (name, Canonical.sha256(try Data(contentsOf: root.appendingPathComponent(name)))) })
        let evidence = blockedEvidence(environmentHash: Canonical.sha256(environmentData), artifactHashes: artifactHashes)
        try JSONEncoder().encode(evidence).write(to: root.appendingPathComponent("evidence.json"))
        try Data("# SP-2 conclusion\n\nVerdict: **BLOCKED**\n\nO6: **OPEN**\n\nG0: **OPEN**\n".utf8).write(to: root.appendingPathComponent("SP-2-CONCLUSION.md"))
        let fixture = SP2ArtifactFixture(container: container, repository: repository, root: root, evidence: evidence); try fixture.manifest(); return fixture
    }

    private func runnerFixture() throws -> SP2RunnerFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp2-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try git(["init", "-q"], root)
        var hashes: [String: String] = [:]
        for path in SP2RunnerBinding.sourcePaths {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data("source:\(path)\n".utf8); try data.write(to: file); hashes[path] = Canonical.sha256(data)
        }
        try git(["add", "."], root)
        try git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", "fixture"], root)
        let commit = try gitOutput(["rev-parse", "HEAD"], root), tree = try gitOutput(["rev-parse", "HEAD^{tree}"], root)
        return SP2RunnerFixture(root: root, evidence: blockedEvidence(commit: commit, tree: tree, hashes: hashes))
    }

    private func errorCode(_ body: () throws -> Void) -> String? { do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" } }
    private func git(_ arguments: [String], _ root: URL) throws { _ = try gitOutput(arguments, root) }
    private func gitOutput(_ arguments: [String], _ root: URL) throws -> String {
        let process = Process(); let pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments; process.currentDirectoryURL = root; process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SP2ArtifactFixture {
    let container: URL
    let repository: URL
    let root: URL
    let evidence: SP2Evidence
    func manifest() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != "manifest.sha256" }.sorted()
        let lines = try names.map { "\(Canonical.sha256(try Data(contentsOf: root.appendingPathComponent($0))))  \($0)" }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: root.appendingPathComponent("manifest.sha256"))
    }
    func remove() { try? FileManager.default.removeItem(at: container) }
}
private struct SP2RunnerFixture { let root: URL; let evidence: SP2Evidence; func remove() { try? FileManager.default.removeItem(at: root) } }

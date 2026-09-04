import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP3ValidatorTests: XCTestCase {
    func testExactLegSetKindsDetectorsPrecedenceAndBlockers() {
        var evidence = SP3Evidence.fixture()
        XCTAssertNoThrow(try evidence.validate())
        evidence.legs.removeLast()
        XCTAssertThrowsError(try evidence.validate())
        evidence = SP3Evidence.fixture(); evidence.legs.append(evidence.legs[0])
        XCTAssertThrowsError(try evidence.validate())
        evidence = SP3Evidence.fixture(); evidence.legs[0].detectorID = "wrong"
        XCTAssertThrowsError(try evidence.validate())
        evidence = SP3Evidence.fixture(); evidence.verdict = .pass
        XCTAssertThrowsError(try evidence.validate())
        evidence = SP3Evidence.fixture(); evidence.legs[0].blocker = SP1Blocker(blockedBy: "", detectCommand: [], prerequisite: "", unblockAction: "")
        XCTAssertThrowsError(try evidence.validate())
    }

    func testDirectoryRejectsManifestForgeryExtraArtifactAndAtomicityCitationDrift() throws {
        let fixture = try SP3TestDirectory.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP3DirectoryValidator.validate(directory: fixture.output, repository: fixture.repository))
        try Data("forged".utf8).write(to: fixture.output.appendingPathComponent("managed-block.json"))
        try fixture.writeManifest()
        XCTAssertEqual(errorCode { _ = try SP3DirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp3_artifact_unsafe")
        try fixture.restore()
        try Data("extra".utf8).write(to: fixture.output.appendingPathComponent("extra.txt"))
        XCTAssertEqual(errorCode { try SP3DirectoryValidator.verifyManifest(fixture.output) }, "sp3_manifest_membership_mismatch")
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("extra.txt"))
        try fixture.restore()
        var citation = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.output.appendingPathComponent("atomicity-citation.json"))) as! [String: Any]
        citation["artifactSha256"] = String(repeating: "f", count: 64)
        try JSONSerialization.data(withJSONObject: citation, options: [.sortedKeys]).write(to: fixture.output.appendingPathComponent("atomicity-citation.json"))
        try fixture.writeManifest()
        XCTAssertEqual(errorCode { _ = try SP3DirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp3_atomicity_citation_mismatch")
    }

    func testDirectoryRejectsForgedRunnerUnsafePathsAndMisleadingPass() throws {
        let fixture = try SP3TestDirectory.make()
        defer { fixture.remove() }
        var evidence = fixture.evidence
        evidence.legs[0].runnerCommitSha = String(repeating: "f", count: 40)
        XCTAssertThrowsError(try evidence.validate())
        evidence = fixture.evidence
        let pass = evidence.legs.firstIndex { $0.verdict == .pass }!
        evidence.legs[pass].artifactPath = "../managed-block.json"
        XCTAssertThrowsError(try evidence.validate())
        try Data("# SP-3 conclusion\n\nVerdict: **PASS**\n".utf8).write(to: fixture.output.appendingPathComponent("SP-3-CONCLUSION.md"))
        try fixture.writeManifest()
        XCTAssertEqual(errorCode { _ = try SP3DirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp3_misleading_conclusion")
    }

    func testRunnerEnvironmentArtifactAndMissingFileBindingsReject() throws {
        var fixture = try SP3TestDirectory.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP3DirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository))
        let dirtyPath = SP3RunnerBinding.sourcePaths.sorted()[0]
        try Data("dirty\n".utf8).write(to: fixture.repository.appendingPathComponent(dirtyPath))
        XCTAssertEqual(errorCode { try SP3DirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository) }, "sp3_runner_source_dirty")

        fixture.remove(); fixture = try SP3TestDirectory.make()
        var forged = fixture.evidence
        for index in forged.legs.indices { forged.legs[index].runnerCommitSha = String(repeating: "f", count: 40) }
        XCTAssertEqual(errorCode { try SP3DirectoryValidator.validateRunner(forged, repository: fixture.repository) }, "sp3_runner_commit_missing")

        var mismatched = fixture.evidence
        for index in mismatched.legs.indices { mismatched.legs[index].environmentSha256 = String(repeating: "f", count: 64) }
        XCTAssertEqual(errorCode { try SP3DirectoryValidator.validateBindings(mismatched, directory: fixture.output, repository: fixture.repository) }, "sp3_environment_hash_mismatch")
        mismatched = fixture.evidence
        let pass = mismatched.legs.firstIndex { $0.legID == "sp3.managedBlock" }!
        mismatched.legs[pass].artifactSha256 = String(repeating: "f", count: 64)
        XCTAssertEqual(errorCode { try SP3DirectoryValidator.validateBindings(mismatched, directory: fixture.output, repository: fixture.repository) }, "sp3_artifact_binding_mismatch")
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("recovery.json"))
        XCTAssertEqual(errorCode { try SP3DirectoryValidator.verifyManifest(fixture.output) }, "sp3_manifest_hash_mismatch")
    }

    private func errorCode(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
}

private extension SP3Evidence {
    static func fixture(
        commit: String = String(repeating: "b", count: 40),
        tree: String = String(repeating: "c", count: 40),
        environmentHash: String = String(repeating: "a", count: 64),
        sourceHashes: [String: String]? = nil,
        artifactHashes: [String: String] = [:]
    ) -> SP3Evidence {
        let blockers = SP1Blocker(blockedBy: "unavailable", detectCommand: ["safe-preflight"], prerequisite: "prerequisite", unblockAction: "provision separately")
        let paths = ["sp3.managedBlock": "managed-block.json", "sp3.atomicity": "atomicity-citation.json", "sp3.crashRecovery": "recovery.json"]
        let legs = requiredLegIDs.sorted().map { id -> SP3Leg in
            let rule = Phase0Registry.legRules[id]!
            if let path = paths[id] {
                return SP3Leg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true,
                              verdict: .pass, blocker: nil, runnerCommitSha: commit, runnerTreeSha: tree,
                              environmentSha256: environmentHash, command: ["fixture", id], exitStatus: 0,
                              artifactPath: path, artifactSha256: artifactHashes[path] ?? String(repeating: "d", count: 64))
            }
            return SP3Leg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: false,
                          verdict: .blocked, blocker: blockers, runnerCommitSha: commit, runnerTreeSha: tree,
                          environmentSha256: environmentHash, command: [], exitStatus: nil)
        }
        return SP3Evidence(legs: legs, verdict: .blocked, runnerSourceSha256: sourceHashes ?? Dictionary(uniqueKeysWithValues: SP3RunnerBinding.sourcePaths.map { ($0, String(repeating: "e", count: 64)) }))
    }
}

private struct SP3TestDirectory {
    let container: URL
    let repository: URL
    let output: URL
    let evidence: SP3Evidence

    static func make() throws -> SP3TestDirectory {
        let sourceRepository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp3-validator-\(UUID().uuidString)")
        let repository = container.appendingPathComponent("repo"), output = repository.appendingPathComponent("sp3")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git(["init", "-q"], repository)
        var sourceHashes: [String: String] = [:]
        for path in SP3RunnerBinding.sourcePaths {
            let url = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data("fixture source \(path)\n".utf8); try bytes.write(to: url); sourceHashes[path] = Canonical.sha256(bytes)
        }
        for relative in ["evidence/phase0/environment.json", SP3FixtureScenarios.fixtureRelativePath, "evidence/phase0/shared-atomicity/result.json", "evidence/phase0/shared-atomicity/manifest.sha256"] {
            let destination = repository.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceRepository.appendingPathComponent(relative), to: destination)
        }
        try git(["add", "."], repository)
        try git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", "fixture"], repository)
        let commit = try gitOutput(["rev-parse", "HEAD"], repository), tree = try gitOutput(["rev-parse", "HEAD^{tree}"], repository)
        let environment = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/environment.json"))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let managed = try SP3FixtureScenarios.managedBlock(repository: repository)
        let result = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/shared-atomicity/result.json"))
        let artifacts: [String: Data] = [
            "managed-block.json": try encode(managed), "recovery.json": try encode(SP3FixtureScenarios.recovery()),
            "format-facts.json": try encode(SP3FixtureScenarios.formatFacts),
            "lint-results.json": try encode(SP3LintArtifact(executed: false, cliPath: nil, version: nil, validAccepted: [], invalidRejected: [], blockedBy: "supported_karabiner_cli_absent")),
            "atomicity-citation.json": try encode(SP3AtomicityCitation(artifactPath: "evidence/phase0/shared-atomicity/result.json", artifactSha256: Canonical.sha256(result), manifestPath: "evidence/phase0/shared-atomicity/manifest.sha256", citedBy: ["SP-3", "SP-6A"])),
        ]
        for (name, bytes) in artifacts { try bytes.write(to: output.appendingPathComponent(name)) }
        let hashes = artifacts.mapValues(Canonical.sha256)
        let evidence = SP3Evidence.fixture(commit: commit, tree: tree, environmentHash: Canonical.sha256(environment), sourceHashes: sourceHashes, artifactHashes: hashes)
        try encode(evidence).write(to: output.appendingPathComponent("evidence.json"))
        try Data("# SP-3 conclusion\n\nVerdict: **BLOCKED**\n\nno user Karabiner file or process was accessed\n".utf8).write(to: output.appendingPathComponent("SP-3-CONCLUSION.md"))
        let fixture = SP3TestDirectory(container: container, repository: repository, output: output, evidence: evidence)
        try fixture.writeManifest(); return fixture
    }

    func restore() throws {
        let fresh = try SP3FixtureScenarios.managedBlock(repository: repository)
        try Self.encode(fresh).write(to: output.appendingPathComponent("managed-block.json"))
        let result = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/shared-atomicity/result.json"))
        try Self.encode(SP3AtomicityCitation(artifactPath: "evidence/phase0/shared-atomicity/result.json", artifactSha256: Canonical.sha256(result), manifestPath: "evidence/phase0/shared-atomicity/manifest.sha256", citedBy: ["SP-3", "SP-6A"])).write(to: output.appendingPathComponent("atomicity-citation.json"))
        try Data("# SP-3 conclusion\n\nVerdict: **BLOCKED**\n\nno user Karabiner file or process was accessed\n".utf8).write(to: output.appendingPathComponent("SP-3-CONCLUSION.md"))
        try writeManifest()
    }
    func writeManifest() throws {
        let lines = try SP3DirectoryLayout.artifactNames.sorted().map { name in "\(Canonical.sha256(try Data(contentsOf: output.appendingPathComponent(name))))  \(name)" }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: output.appendingPathComponent("manifest.sha256"))
    }
    func remove() { try? FileManager.default.removeItem(at: container) }
    private static func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    private static func git(_ arguments: [String], _ root: URL) throws { _ = try gitOutput(arguments, root) }
    private static func gitOutput(_ arguments: [String], _ root: URL) throws -> String {
        let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments; process.currentDirectoryURL = root; process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

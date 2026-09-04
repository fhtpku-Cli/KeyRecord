import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP5AValidatorTests: XCTestCase {
    func testExactFourLegsKindsDetectorsBlockerAndPrecedence() throws {
        let fixture = try SP5ATestDirectory.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try fixture.evidence.validate())
        XCTAssertEqual(fixture.evidence.verdict, .blocked)
        XCTAssertEqual(fixture.evidence.legs.filter { $0.verdict == .pass }.count, 3)
        XCTAssertEqual(fixture.evidence.legs.first { $0.legID == "sp5a.importer" }?.blocker?.blockedBy, "vial_gui_absent")

        var evidence = fixture.evidence
        evidence.legs.removeLast()
        XCTAssertEqual(validationError(evidence), .missingLeg)
        evidence = fixture.evidence; evidence.legs.append(evidence.legs[0])
        XCTAssertEqual(validationError(evidence), .duplicateLeg)
        evidence = fixture.evidence; evidence.legs[0].detectorID = "D7"
        XCTAssertEqual(validationError(evidence), .invalidRule)
        evidence = fixture.evidence; evidence.verdict = .pass
        XCTAssertEqual(validationError(evidence), .invalidAggregate)
        evidence = fixture.evidence
        let importer = try XCTUnwrap(evidence.legs.firstIndex { $0.legID == "sp5a.importer" })
        evidence.legs[importer].verdict = .pass; evidence.legs[importer].detectorAvailable = true; evidence.legs[importer].blocker = nil
        evidence.legs[importer].command = ["misleading-importer-pass"]; evidence.legs[importer].exitStatus = 0
        evidence.legs[importer].artifactPath = "round-trip.json"; evidence.legs[importer].artifactSha256 = String(repeating: "f", count: 64)
        XCTAssertEqual(validationError(evidence), .invalidBlocker)
    }

    func testValidatorRecomputesFixtureHashRoundTripUIDBoundsAndSourceFacts() throws {
        var fixture = try SP5ATestDirectory.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP5ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository))

        try fixture.mutateJSON("round-trip.json", replacing: "\"allUnsupportedFieldsPreserved\" : true", with: "\"allUnsupportedFieldsPreserved\" : false")
        XCTAssertEqual(errorCode { _ = try SP5ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp5a_round_trip_recompute_mismatch")
        try fixture.restore()
        try fixture.mutateJSON("uid-binding.json", replacing: "\"mismatchVerified\" : false", with: "\"mismatchVerified\" : true")
        XCTAssertEqual(errorCode { _ = try SP5ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp5a_uid_recompute_mismatch")
        try fixture.restore()
        try fixture.mutateJSON("bounds.json", replacing: "\"exactAccepted\" : true", with: "\"exactAccepted\" : false")
        XCTAssertEqual(errorCode { _ = try SP5ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp5a_bounds_recompute_mismatch")
        fixture.remove(); fixture = try SP5ATestDirectory.make()
        try Data("forged fixture".utf8).write(to: fixture.repository.appendingPathComponent(SP5AFixtureScenarios.fixturePath))
        XCTAssertEqual(errorCode { try SP5ADirectoryValidator.validateArtifacts(fixture.output, repository: fixture.repository) }, "sp5a_fixture_recompute_failed")
    }

    func testManifestPathEnvironmentAndClaimAttacksReject() throws {
        let fixture = try SP5ATestDirectory.make()
        defer { fixture.remove() }
        try Data("extra".utf8).write(to: fixture.output.appendingPathComponent("../outside"))
        try Data("extra".utf8).write(to: fixture.output.appendingPathComponent("extra.txt"))
        XCTAssertEqual(errorCode { try SP5ADirectoryValidator.verifyManifest(fixture.output) }, "sp5a_manifest_membership_mismatch")
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("extra.txt")); try fixture.restore()
        var evidence = fixture.evidence
        evidence.legs[0].artifactPath = "../round-trip.json"
        XCTAssertEqual(validationError(evidence), .invalidExecution)

        try fixture.replaceEnvironmentVialStatus("absent", with: "installed")
        var rebound = fixture.evidence
        let environment = try Data(contentsOf: fixture.repository.appendingPathComponent("evidence/phase0/environment.json"))
        for index in rebound.legs.indices { rebound.legs[index].environmentSha256 = Canonical.sha256(environment) }
        XCTAssertEqual(errorCode { try SP5ADirectoryValidator.validateBindings(rebound, directory: fixture.output, repository: fixture.repository) }, "sp5a_d7_environment_mismatch")
        try fixture.restoreEnvironment()
        try Data("# SP-5A conclusion\n\nVerdict: **PASS**\n\nSynthetic proves device compatibility and official importer PASS.\n".utf8).write(to: fixture.output.appendingPathComponent("SP-5A-CONCLUSION.md"))
        try fixture.writeManifest()
        XCTAssertEqual(errorCode { _ = try SP5ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp5a_misleading_conclusion")
    }

    func testFixtureProvenanceArtifactEnvironmentAndHistoricalRunnerBindingsRejectDrift() throws {
        var fixture = try SP5ATestDirectory.make()
        defer { fixture.remove() }
        var evidence = fixture.evidence
        for index in evidence.legs.indices { evidence.legs[index].environmentSha256 = String(repeating: "f", count: 64) }
        XCTAssertEqual(errorCode { try SP5ADirectoryValidator.validateBindings(evidence, directory: fixture.output, repository: fixture.repository) }, "sp5a_environment_hash_mismatch")
        evidence = fixture.evidence
        let roundTrip = try XCTUnwrap(evidence.legs.firstIndex { $0.legID == "sp5a.vilRoundTrip" })
        evidence.legs[roundTrip].artifactSha256 = String(repeating: "f", count: 64)
        XCTAssertEqual(errorCode { try SP5ADirectoryValidator.validateBindings(evidence, directory: fixture.output, repository: fixture.repository) }, "sp5a_artifact_binding_mismatch")

        let provenance = fixture.repository.appendingPathComponent("evidence/phase0/fixtures/synthetic/provenance.json")
        var text = try String(contentsOf: provenance, encoding: .utf8)
        text = text.replacingOccurrences(of: SP5AFixtureScenarios.fixtureSha256, with: String(repeating: "f", count: 64))
        try Data(text.utf8).write(to: provenance)
        XCTAssertEqual(errorCode { try SP5ADirectoryValidator.validateArtifacts(fixture.output, repository: fixture.repository) }, "sp5a_fixture_provenance_mismatch")

        fixture.remove(); fixture = try SP5ATestDirectory.make()
        let path = SP5ARunnerBinding.sourcePaths.sorted()[0]
        try Data("descendant source\n".utf8).write(to: fixture.repository.appendingPathComponent(path))
        try fixture.git(["add", path]); try fixture.git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", "descendant"])
        XCTAssertNoThrow(try SP5ADirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository))
        try Data("dirty source\n".utf8).write(to: fixture.repository.appendingPathComponent(path))
        XCTAssertEqual(errorCode { try SP5ADirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository) }, "sp5a_runner_source_dirty")
    }

    private func validationError(_ evidence: SP5AEvidence) -> SP5AValidationError? {
        do { try evidence.validate(); return nil } catch let error as SP5AValidationError { return error } catch { return nil }
    }
    private func errorCode(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
}

private struct SP5ATestDirectory {
    let source: URL
    let container: URL
    let repository: URL
    let output: URL
    let evidence: SP5AEvidence

    static func make() throws -> SP5ATestDirectory {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp5a-validator-\(UUID().uuidString)")
        let repository = container.appendingPathComponent("repo"), output = repository.appendingPathComponent("sp5a")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q"], repository)
        var sourceHashes: [String: String] = [:]
        for path in SP5ARunnerBinding.sourcePaths {
            let destination = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data("fixture runner \(path)\n".utf8); try bytes.write(to: destination); sourceHashes[path] = Canonical.sha256(bytes)
        }
        let copied = [
            "evidence/phase0/environment.json", SP5AFixtureScenarios.fixturePath,
            "evidence/phase0/fixtures/synthetic/provenance.json", "evidence/phase0/fixtures/synthetic/manifest.sha256",
            "evidence/phase0/sources/repos/vial-gui/provenance.json", "evidence/phase0/sources/repos/vial-qmk/provenance.json",
        ] + (try SP5AFixtureScenarios.sourceFacts(repository: source)).citations.map(\.path)
        for path in copied {
            let destination = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.appendingPathComponent(path), to: destination)
        }
        try runGit(["add", "."], repository)
        try runGit(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", "fixture"], repository)
        let commit = try gitOutput(["rev-parse", "HEAD"], repository), tree = try gitOutput(["rev-parse", "HEAD^{tree}"], repository)
        let environment = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/environment.json"))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let artifacts = try makeArtifacts(repository)
        for (name, bytes) in artifacts { try bytes.write(to: output.appendingPathComponent(name)) }
        let hashes = artifacts.mapValues(Canonical.sha256)
        let legs = try SP5AEvidence.requiredLegIDs.sorted().map { id -> SP5ALeg in
            guard let rule = Phase0Registry.legRules[id] else { throw CocoaError(.coderInvalidValue) }
            if id == "sp5a.importer" {
                return SP5ALeg(legID: id, evidenceKind: .live, detectorID: "D7", detectorAvailable: false, verdict: .blocked,
                    blocker: SP1Blocker(blockedBy: "vial_gui_absent", detectCommand: ["environment-inventory", "Vial"], prerequisite: "supported official Vial GUI installed with a matching approved device", unblockAction: "run separately approved live import"),
                    runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: Canonical.sha256(environment), command: [], exitStatus: nil, artifactPath: nil, artifactSha256: nil)
            }
            guard let path = SP5ADirectoryLayout.legArtifacts[id] else { throw CocoaError(.coderInvalidValue) }
            return SP5ALeg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true, verdict: .pass,
                blocker: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: Canonical.sha256(environment),
                command: ["fixture", id], exitStatus: 0, artifactPath: path, artifactSha256: hashes[path])
        }
        let evidence = SP5AEvidence(legs: legs, verdict: .blocked, runnerSourceSha256: sourceHashes)
        try pretty(evidence).write(to: output.appendingPathComponent("evidence.json"))
        try conclusion().write(to: output.appendingPathComponent("SP-5A-CONCLUSION.md"))
        let fixture = SP5ATestDirectory(source: source, container: container, repository: repository, output: output, evidence: evidence)
        try fixture.writeManifest()
        return fixture
    }

    func restore() throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, bytes) in try Self.makeArtifacts(repository) { try bytes.write(to: output.appendingPathComponent(name)) }
        try Self.pretty(evidence).write(to: output.appendingPathComponent("evidence.json"))
        try Self.conclusion().write(to: output.appendingPathComponent("SP-5A-CONCLUSION.md")); try writeManifest()
    }
    func mutateJSON(_ name: String, replacing old: String, with new: String) throws {
        let url = output.appendingPathComponent(name); var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: old, with: new); try Data(text.utf8).write(to: url); try writeManifest()
    }
    func replaceEnvironmentVialStatus(_ old: String, with new: String) throws {
        let url = repository.appendingPathComponent("evidence/phase0/environment.json")
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"name\" : \"Vial\",\n      \"status\" : \"\(old)\"", with: "\"name\" : \"Vial\",\n      \"status\" : \"\(new)\"")
        try Data(text.utf8).write(to: url)
    }
    func restoreEnvironment() throws {
        let url = repository.appendingPathComponent("evidence/phase0/environment.json")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: source.appendingPathComponent("evidence/phase0/environment.json"), to: url)
    }
    func writeManifest() throws {
        let rows = try SP5ADirectoryLayout.artifactNames.sorted().map { "\(Canonical.sha256(try Data(contentsOf: output.appendingPathComponent($0))))  \($0)" }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: output.appendingPathComponent("manifest.sha256"))
    }
    func git(_ arguments: [String]) throws { try Self.runGit(arguments, repository) }
    func remove() { try? FileManager.default.removeItem(at: container) }

    private static func makeArtifacts(_ repository: URL) throws -> [String: Data] {
        [
            "round-trip.json": try pretty(SP5AFixtureScenarios.roundTrip(repository: repository)),
            "uid-binding.json": try pretty(SP5AFixtureScenarios.uidBinding(repository: repository)),
            "bounds.json": try pretty(SP5AFixtureScenarios.bounds()),
            "format-facts.json": try pretty(SP5AFixtureScenarios.sourceFacts(repository: repository)),
        ]
    }
    private static func conclusion() -> Data {
        Data("# SP-5A conclusion\n\nVerdict: **BLOCKED**\n\nThe exact deterministic synthetic `.vil` fixture proves only bounded version-1 parsing, raw splice, unsupported advanced-field preservation, and UID mismatch rejection. It is synthetic, not sourced or live, and does not prove official-importer or device compatibility. Official Vial GUI import remains **BLOCKED** because D7 is false and the environment inventory reports Vial absent. No GUI was launched and no device or HID interaction occurred. `vial.json` is a firmware-embedded keyboard definition and is not interchangeable with a `.vil` keymap export or a VIA definition.\n".utf8)
    }
    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func runGit(_ arguments: [String], _ repository: URL) throws { _ = try gitOutput(arguments, repository) }
    private static func gitOutput(_ arguments: [String], _ repository: URL) throws -> String {
        let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments; process.currentDirectoryURL = repository; process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

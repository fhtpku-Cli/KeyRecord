import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP4AValidatorTests: XCTestCase {
    func testClosedLegSetRulesAndAggregatePrecedence() throws {
        let fixture = try SP4ATestDirectory.make()
        defer { fixture.remove() }
        var evidence = fixture.evidence
        XCTAssertNoThrow(try evidence.validate())
        evidence.legs.removeLast()
        XCTAssertEqual(validationError(evidence), .missingLeg)
        evidence = fixture.evidence; evidence.legs.append(evidence.legs[0])
        XCTAssertEqual(validationError(evidence), .duplicateLeg)
        evidence = fixture.evidence; evidence.legs[0].detectorID = "D6"
        XCTAssertEqual(validationError(evidence), .invalidRule)
        evidence = fixture.evidence; evidence.legs[0].verdict = .fail; evidence.verdict = .fail
        XCTAssertNoThrow(try evidence.validate())
        evidence.verdict = .pass
        XCTAssertEqual(validationError(evidence), .invalidAggregate)
    }

    func testValidatorRecomputesParserBoundsOpaqueAndSourceArtifacts() throws {
        let fixture = try SP4ATestDirectory.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP4ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository))
        try fixture.mutateJSON("bounds.json", replacing: "\"exactAccepted\" : true", with: "\"exactAccepted\" : false")
        XCTAssertEqual(errorCode { _ = try SP4ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp4a_bounds_recompute_mismatch")
        try fixture.restore()
        try fixture.mutateJSON("opaque-preservation.json", replacing: "\"bytesOutsideMutationIdentical\" : true", with: "\"bytesOutsideMutationIdentical\" : false")
        XCTAssertEqual(errorCode { _ = try SP4ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp4a_opaque_recompute_mismatch")
        try fixture.restore()
        let opaque = fixture.output.appendingPathComponent("opaque-preservation.json")
        var text = try String(contentsOf: opaque, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"macroAfterSha256\" :", with: "\"macroAfterSha256\" : \"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\n  \"discardedMacroHash\" :")
        try Data(text.utf8).write(to: opaque); try fixture.writeManifest()
        XCTAssertEqual(errorCode { _ = try SP4ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp4a_opaque_recompute_mismatch")
    }

    func testManifestExtraMissingSymlinkTraversalAndMisleadingPassReject() throws {
        let fixture = try SP4ATestDirectory.make()
        defer { fixture.remove() }
        try Data("extra".utf8).write(to: fixture.output.appendingPathComponent("extra.txt"))
        XCTAssertEqual(errorCode { try SP4ADirectoryValidator.verifyManifest(fixture.output) }, "sp4a_manifest_membership_mismatch")
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("extra.txt")); try fixture.restore()
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("bounds.json"))
        XCTAssertEqual(errorCode { try SP4ADirectoryValidator.verifyManifest(fixture.output) }, "sp4a_manifest_hash_mismatch")
        try fixture.restore()
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("bounds.json"))
        try FileManager.default.createSymbolicLink(atPath: fixture.output.appendingPathComponent("bounds.json").path, withDestinationPath: "../outside")
        XCTAssertEqual(errorCode { try SP4ADirectoryValidator.verifyManifest(fixture.output) }, "sp4a_manifest_hash_mismatch")
        try fixture.restore()
        var evidence = fixture.evidence
        evidence.legs[0].artifactPath = "../v2-schema.json"
        XCTAssertEqual(validationError(evidence), .invalidVerdict)
        try Data("# SP-4A conclusion\n\nVerdict: **PASS**\n\nprotocol compatible\n".utf8).write(to: fixture.output.appendingPathComponent("SP-4A-CONCLUSION.md"))
        try fixture.writeManifest()
        XCTAssertEqual(errorCode { _ = try SP4ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp4a_misleading_conclusion")
    }

    func testSourceHashProvenanceEnvironmentAndArtifactBindingDriftReject() throws {
        var fixture = try SP4ATestDirectory.make()
        defer { fixture.remove() }
        try Data("drift".utf8).write(to: fixture.repository.appendingPathComponent(ViaDefinitionSources.v2.path))
        XCTAssertThrowsError(try SP4ADirectoryValidator.validateArtifacts(fixture.output, repository: fixture.repository))
        fixture.remove(); fixture = try SP4ATestDirectory.make()
        let provenance = fixture.repository.appendingPathComponent("evidence/phase0/sources/repos/via-app/provenance.json")
        var text = try String(contentsOf: provenance, encoding: .utf8)
        text = text.replacingOccurrences(of: ViaDefinitionSources.v2.commit, with: String(repeating: "f", count: 40))
        try Data(text.utf8).write(to: provenance)
        XCTAssertEqual(errorCode { try SP4ADirectoryValidator.validateArtifacts(fixture.output, repository: fixture.repository) }, "sp4a_source_provenance_mismatch")
        fixture.remove(); fixture = try SP4ATestDirectory.make()
        var evidence = fixture.evidence
        for index in evidence.legs.indices { evidence.legs[index].environmentSha256 = String(repeating: "f", count: 64) }
        XCTAssertEqual(errorCode { try SP4ADirectoryValidator.validateBindings(evidence, directory: fixture.output, repository: fixture.repository) }, "sp4a_environment_hash_mismatch")
        evidence = fixture.evidence; evidence.legs[0].artifactSha256 = String(repeating: "f", count: 64)
        XCTAssertEqual(errorCode { try SP4ADirectoryValidator.validateBindings(evidence, directory: fixture.output, repository: fixture.repository) }, "sp4a_artifact_binding_mismatch")
    }

    func testHistoricalRunnerAllowsCommittedDescendantEvolutionButRejectsDirtyRunner() throws {
        let fixture = try SP4ATestDirectory.make()
        defer { fixture.remove() }
        let path = SP4ARunnerBinding.sourcePaths.sorted()[0]
        try Data("descendant source\n".utf8).write(to: fixture.repository.appendingPathComponent(path))
        try fixture.git(["add", path]); try fixture.git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", "descendant"])
        XCTAssertNoThrow(try SP4ADirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository))
        try Data("dirty source\n".utf8).write(to: fixture.repository.appendingPathComponent(path))
        XCTAssertEqual(errorCode { try SP4ADirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository) }, "sp4a_runner_source_dirty")
    }

    private func validationError(_ evidence: SP4AEvidence) -> SP4AValidationError? {
        do { try evidence.validate(); return nil } catch let error as SP4AValidationError { return error } catch { return nil }
    }
    private func errorCode(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
}

private struct SP4ATestDirectory {
    let container: URL
    let repository: URL
    let output: URL
    let evidence: SP4AEvidence

    static func make() throws -> SP4ATestDirectory {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp4a-validator-\(UUID().uuidString)")
        let repository = container.appendingPathComponent("repo"), output = repository.appendingPathComponent("sp4a")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q"], repository)
        var sourceHashes: [String: String] = [:]
        for path in SP4ARunnerBinding.sourcePaths {
            let destination = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data("fixture runner \(path)\n".utf8); try bytes.write(to: destination); sourceHashes[path] = Canonical.sha256(bytes)
        }
        let copied = [
            "evidence/phase0/environment.json", ViaDefinitionSources.v2.path, ViaDefinitionSources.v2.licensePath,
            ViaDefinitionSources.v3.path, ViaDefinitionSources.v3.licensePath,
            "evidence/phase0/sources/repos/via-app/provenance.json", "evidence/phase0/sources/repos/via-keyboards/provenance.json",
            "evidence/phase0/sources/repos/via-docs/files/docs/specification.md",
            "evidence/phase0/sources/repos/via-docs/files/docs/post_v3_changes.md",
        ]
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
        let legs = try SP4AEvidence.requiredLegIDs.sorted().map { id -> SP4ALeg in
            guard let path = SP4ADirectoryLayout.legArtifacts[id], let rule = Phase0Registry.legRules[id] else {
                throw CocoaError(.coderInvalidValue)
            }
            return SP4ALeg(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true, verdict: .pass,
                           blocker: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: Canonical.sha256(environment),
                           command: ["fixture", id], exitStatus: 0, artifactPath: path, artifactSha256: hashes[path])
        }
        let evidence = SP4AEvidence(legs: legs, verdict: .pass, runnerSourceSha256: sourceHashes)
        try pretty(evidence).write(to: output.appendingPathComponent("evidence.json"))
        try conclusion().write(to: output.appendingPathComponent("SP-4A-CONCLUSION.md"))
        let fixture = SP4ATestDirectory(container: container, repository: repository, output: output, evidence: evidence)
        try fixture.writeManifest(); return fixture
    }

    func restore() throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let artifacts = try Self.makeArtifacts(repository)
        for (name, bytes) in artifacts { try bytes.write(to: output.appendingPathComponent(name)) }
        try Self.pretty(evidence).write(to: output.appendingPathComponent("evidence.json"))
        try Self.conclusion().write(to: output.appendingPathComponent("SP-4A-CONCLUSION.md")); try writeManifest()
    }
    func mutateJSON(_ name: String, replacing old: String, with new: String) throws {
        let url = output.appendingPathComponent(name); var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: old, with: new); try Data(text.utf8).write(to: url); try writeManifest()
    }
    func writeManifest() throws {
        let rows = try SP4ADirectoryLayout.artifactNames.sorted().map { "\(Canonical.sha256(try Data(contentsOf: output.appendingPathComponent($0))))  \($0)" }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: output.appendingPathComponent("manifest.sha256"))
    }
    func git(_ arguments: [String]) throws { try Self.runGit(arguments, repository) }
    func remove() { try? FileManager.default.removeItem(at: container) }
    private static func makeArtifacts(_ repository: URL) throws -> [String: Data] {
        [
            "v2-schema.json": try pretty(SP4AFixtureScenarios.schemaArtifact(repository: repository, source: ViaDefinitionSources.v2, expected: .v2)),
            "v3-schema.json": try pretty(SP4AFixtureScenarios.schemaArtifact(repository: repository, source: ViaDefinitionSources.v3, expected: .v3)),
            "opaque-preservation.json": try pretty(SP4AFixtureScenarios.opaqueArtifact()),
            "bounds.json": try pretty(SP4AFixtureScenarios.boundsArtifact()),
            "source-facts.json": try pretty(SP4AFixtureScenarios.sourceFacts(repository: repository)),
        ]
    }
    private static func conclusion() -> Data {
        Data("# SP-4A conclusion\n\nVerdict: **PASS**\n\nThis definition-only fixture result makes no device-protocol, keycode-dialect, layout-backup, official-importer, HID, EEPROM, or device-behavior claim. Official definitions are repository-served; manufacturer-provided custom definitions use VIA's Design tab.\n".utf8)
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

import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Probe
@testable import Phase0Support

final class SP4BValidatorTests: XCTestCase {
    func testManifestArtifactsEnvironmentAndFiveAxesValidate() throws {
        try withFixture { repository, output, evidence in
            XCTAssertNoThrow(try SP4BDirectoryValidator.verifyManifest(output))
            XCTAssertNoThrow(try SP4BDirectoryValidator.validateArtifacts(output, repository: repository))
            XCTAssertNoThrow(try SP4BDirectoryValidator.validateBindings(evidence, directory: output, repository: repository))
        }
    }

    func testRemanifestedAxisFixtureBlockerAndMisleadingClaimsReject() throws {
        try withFixture { repository, output, evidence in
            try mutate(output.appendingPathComponent("axes.json"), "\"viaProtocol13VialGUICompatible\" : false", "\"viaProtocol13VialGUICompatible\" : true")
            try writeManifest(output)
            XCTAssertEqual(errorCode { try SP4BDirectoryValidator.validateArtifacts(output, repository: repository) }, "sp4b_axes_recompute_mismatch")

            var forged = evidence
            let importer = forged.legs.firstIndex { $0.legID == "sp4b.importer" }!
            forged.legs[importer].blocker = SP1Blocker(blockedBy: "partial", detectCommand: [], prerequisite: "", unblockAction: "")
            XCTAssertEqual(validationError(forged), .invalidBlocker)

            try Data("# SP-4B conclusion\n\nVerdict: **PASS**\n\nOfficial importer and device compatibility verified.\n".utf8)
                .write(to: output.appendingPathComponent("SP-4B-CONCLUSION.md"))
            try writeManifest(output)
            XCTAssertEqual(errorCode { try SP4BDirectoryValidator.validateConclusion(output, evidence: evidence) }, "sp4b_misleading_conclusion")
        }
    }

    private func withFixture(_ body: (URL, URL, SP4BEvidence) throws -> Void) throws {
        let repository = repositoryRoot()
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp4b-validator-\(UUID().uuidString)")
        let output = container.appendingPathComponent("sp4b")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: container) }
        let identity = AtomicityRunnerIdentity(
            commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40),
            sourceSha256: Dictionary(uniqueKeysWithValues: SP4BRunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
        )
        try SP4BProbe.run(
            arguments: ["sp4b", "--environment", repository.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path],
            identityProvider: SP4BFixedIdentity(identity: identity)
        )
        let evidence = try JSONDecoder().decode(SP4BEvidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
        try body(repository, output, evidence)
    }

    private func mutate(_ url: URL, _ old: String, _ new: String) throws {
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: old, with: new)
        try Data(text.utf8).write(to: url)
    }

    private func writeManifest(_ directory: URL) throws {
        let rows = try SP4BDirectoryLayout.artifactNames.sorted().map {
            "\(Canonical.sha256(try Data(contentsOf: directory.appendingPathComponent($0))))  \($0)"
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }

    private func validationError(_ value: SP4BEvidence) -> SP4BValidationError? {
        do { try value.validate(); return nil } catch let error as SP4BValidationError { return error } catch { return nil }
    }
    private func errorCode(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

private struct SP4BFixedIdentity: AtomicityRunnerIdentityProviding {
    let identity: AtomicityRunnerIdentity
    func resolve() throws -> AtomicityRunnerIdentity { identity }
}

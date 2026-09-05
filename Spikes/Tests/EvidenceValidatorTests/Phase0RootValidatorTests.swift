import Foundation
import XCTest
@testable import EvidenceValidator

final class Phase0RootValidatorTests: XCTestCase {
    func testRootValidatorRejectsUnexpectedDirectoryBeforeConclusionGeneration() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-root-validator-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(
            at: sandbox.appendingPathComponent("unexpected", isDirectory: true),
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(try Phase0RootValidator.validateMembership(sandbox)) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, "phase0_root_directory_set_mismatch")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("conclusions.json").path))
    }

    func testRemanifestedEnvironmentMutationRejects() throws {
        try assertCandidateMutation(code: "phase0_run_receipt_mismatch") { root in
            let url = root.appendingPathComponent("environment.json")
            try appendSpace(to: url)
            try writeManifest(root)
        }
    }

    func testRemanifestedSourceMutationRejects() throws {
        try assertCandidateMutation(code: "sp4a_source_provenance_mismatch") { root in
            let sources = root.appendingPathComponent("sources")
            try appendSpace(to: sources.appendingPathComponent("repos/via-app/files/src/utils/test-keyboard-definition.json"))
            try writeManifest(sources, recursive: true)
        }
    }

    func testRemanifestedFixtureMutationRejects() throws {
        try assertCandidateMutation(code: "sp5a_fixture_provenance_mismatch") { root in
            let fixtures = root.appendingPathComponent("fixtures/synthetic")
            try appendSpace(to: fixtures.appendingPathComponent("phase0.vil"))
            try writeManifest(fixtures)
        }
    }

    func testRemanifestedCitationMutationRejects() throws {
        try assertCandidateMutation(code: "phase0_preserved_hash_mismatch") { root in
            let atomicity = root.appendingPathComponent("shared-atomicity")
            try appendSpace(to: atomicity.appendingPathComponent("result.json"))
            try writeManifest(atomicity)
        }
    }

    func testRemanifestedPreflightHashMutationRejects() throws {
        try assertCandidateMutation(code: "phase0_preflight_hash_mismatch") { root in
            let url = root.appendingPathComponent("run-all.json")
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            var stages = object["stages"] as! [[String: Any]]
            stages[0]["artifactSha256"] = String(repeating: "f", count: 64)
            object["stages"] = stages
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url)
            try appendNewline(to: url)
            try writeManifest(root)
        }
    }

    private func assertCandidateMutation(
        code expected: String,
        mutation: (URL) throws -> Void
    ) throws {
        let repository = try repositoryRoot()
        let candidate = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase0-candidate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: repository.appendingPathComponent("evidence/phase0"), to: candidate)
        defer { try? FileManager.default.removeItem(at: candidate) }
        try mutation(candidate)
        XCTAssertThrowsError(try Phase0RootValidator.validate(candidate, repository: repository)) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, expected)
        }
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("evidence/phase0").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func appendSpace(to url: URL) throws {
        var data = try Data(contentsOf: url)
        data.append(contentsOf: " ".utf8)
        try data.write(to: url)
    }

    private func appendNewline(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
    }

    private func writeManifest(_ directory: URL, recursive: Bool = false) throws {
        let manager = FileManager.default
        let files: [URL]
        if recursive {
            let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
            files = enumerator.compactMap { $0 as? URL }.filter {
                $0.lastPathComponent != "manifest.sha256" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
        } else {
            files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]).filter {
                $0.lastPathComponent != "manifest.sha256" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
        }
        let lines = try files.sorted { $0.path < $1.path }.map { url -> String in
            let relative = String(url.path.dropFirst(directory.path.count + 1))
            return "\(Canonical.sha256(try Data(contentsOf: url)))  \(relative)"
        }.joined(separator: "\n") + "\n"
        try Data(lines.utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
}

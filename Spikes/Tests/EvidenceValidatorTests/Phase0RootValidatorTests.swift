import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

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
            try refreshManifest(root, artifact: url, path: "environment.json")
        }
    }

    func testRemanifestedSourceMutationRejects() throws {
        try assertCandidateMutation(code: "sp4a_source_hash_mismatch") { root in
            let sources = root.appendingPathComponent("sources")
            let artifact = sources.appendingPathComponent("repos/via-app/files/src/utils/test-keyboard-definition.json")
            try appendSpace(to: artifact)
            try refreshManifest(sources, artifact: artifact, path: "./repos/via-app/files/src/utils/test-keyboard-definition.json")
        }
    }

    func testRemanifestedFixtureMutationRejects() throws {
        try assertCandidateMutation(code: "sp4b_fixture_recompute_failed") { root in
            let fixtures = root.appendingPathComponent("fixtures/synthetic")
            let artifact = fixtures.appendingPathComponent("via-layout.json")
            try appendSpace(to: artifact)
            try refreshManifest(fixtures, artifact: artifact, path: "via-layout.json")
        }
    }

    func testRemanifestedCitationMutationRejects() throws {
        try assertCandidateMutation(code: "phase0_preserved_hash_mismatch") { root in
            let atomicity = root.appendingPathComponent("shared-atomicity")
            let artifact = atomicity.appendingPathComponent("result.json")
            try appendSpace(to: artifact)
            try refreshManifest(atomicity, artifact: artifact, path: "result.json")
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
            try refreshManifest(root, artifact: url, path: "run-all.json")
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
        try upgradeRootBinding(candidate, repository: repository)
        try upgradeSP1Binding(candidate, repository: repository)
        try upgradeEarlyBindings(candidate, repository: repository)
        try mutation(candidate)
        XCTAssertThrowsError(try Phase0RootValidator.validate(candidate, repository: repository)) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, expected)
        }
    }

    private func upgradeRootBinding(_ root: URL, repository: URL) throws {
        let url = root.appendingPathComponent("run-all.json")
        let old = try JSONDecoder().decode(Phase0RunReceipt.self, from: Data(contentsOf: url))
        let commit = try gitText(["rev-parse", "HEAD"], repository: repository)
        let tree = try gitText(["rev-parse", "HEAD^{tree}"], repository: repository)
        let receipt = Phase0RunReceipt(
            runnerCommitSha: commit,
            runnerTreeSha: tree,
            runnerSourceSha256: try sourceHashes(Phase0RunBinding.sourcePaths, commit: commit, repository: repository),
            environmentSha256: old.environmentSha256,
            directories: old.directories,
            rootArtifacts: old.rootArtifacts,
            stages: old.stages,
            toolVersions: old.toolVersions
        )
        try write(receipt, to: url)
        try refreshManifest(root, artifact: url, path: "run-all.json")
    }

    private func upgradeSP1Binding(_ root: URL, repository: URL) throws {
        let directory = root.appendingPathComponent("sp1")
        let url = directory.appendingPathComponent("evidence.json")
        var evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: url))
        let commit = try gitText(["rev-parse", "HEAD"], repository: repository)
        let tree = try gitText(["rev-parse", "HEAD^{tree}"], repository: repository)
        for index in evidence.legs.indices {
            evidence.legs[index].runnerCommitSha = commit
            evidence.legs[index].runnerTreeSha = tree
        }
        evidence.runnerSourceSha256 = try Dictionary(uniqueKeysWithValues: SP1RunnerBinding.sourcePaths.map { path in
            (path, Canonical.sha256(try gitBlob(commit: commit, path: path, repository: repository)))
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(evidence)
        data.append(10)
        try data.write(to: url)
        try refreshManifest(directory, artifact: url, path: "evidence.json")
    }

    private func upgradeEarlyBindings(_ root: URL, repository: URL) throws {
        let commit = try gitText(["rev-parse", "HEAD"], repository: repository)
        let tree = try gitText(["rev-parse", "HEAD^{tree}"], repository: repository)

        let sp2URL = root.appendingPathComponent("sp2/evidence.json")
        var sp2 = try JSONDecoder().decode(SP2Evidence.self, from: Data(contentsOf: sp2URL))
        for index in sp2.legs.indices {
            sp2.legs[index].runnerCommitSha = commit
            sp2.legs[index].runnerTreeSha = tree
        }
        sp2.runnerSourceSha256 = try sourceHashes(SP2RunnerBinding.sourcePaths, commit: commit, repository: repository)
        try write(sp2, to: sp2URL)
        try refreshManifest(sp2URL.deletingLastPathComponent(), artifact: sp2URL, path: "evidence.json")

        let sp3URL = root.appendingPathComponent("sp3/evidence.json")
        var sp3 = try JSONDecoder().decode(SP3Evidence.self, from: Data(contentsOf: sp3URL))
        for index in sp3.legs.indices {
            sp3.legs[index].runnerCommitSha = commit
            sp3.legs[index].runnerTreeSha = tree
        }
        sp3.runnerSourceSha256 = try sourceHashes(SP3RunnerBinding.sourcePaths, commit: commit, repository: repository)
        try write(sp3, to: sp3URL)
        try refreshManifest(sp3URL.deletingLastPathComponent(), artifact: sp3URL, path: "evidence.json")

        let sp4aURL = root.appendingPathComponent("sp4a/evidence.json")
        var sp4a = try JSONDecoder().decode(SP4AEvidence.self, from: Data(contentsOf: sp4aURL))
        for index in sp4a.legs.indices {
            sp4a.legs[index].runnerCommitSha = commit
            sp4a.legs[index].runnerTreeSha = tree
        }
        sp4a.runnerSourceSha256 = try sourceHashes(SP4ARunnerBinding.sourcePaths, commit: commit, repository: repository)
        try write(sp4a, to: sp4aURL)
        try refreshManifest(sp4aURL.deletingLastPathComponent(), artifact: sp4aURL, path: "evidence.json")
    }

    private func sourceHashes(_ paths: Set<String>, commit: String, repository: URL) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: paths.map { path in
            (path, Canonical.sha256(try gitBlob(commit: commit, path: path, repository: repository)))
        })
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        try data.write(to: url)
    }

    private func gitBlob(commit: String, path: String, repository: URL) throws -> Data {
        try gitData(["cat-file", "blob", "\(commit):\(path)"], repository: repository)
    }

    private func gitText(_ arguments: [String], repository: URL) throws -> String {
        String(decoding: try gitData(arguments, repository: repository), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitData(_ arguments: [String], repository: URL) throws -> Data {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return output.fileHandleForReading.readDataToEndOfFile()
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

    private func refreshManifest(_ directory: URL, artifact: URL, path: String) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        let replacement = "\(Canonical.sha256(try Data(contentsOf: artifact)))  \(path)"
        var lines = try String(contentsOf: manifest, encoding: .utf8).split(separator: "\n").map(String.init)
        guard let index = lines.firstIndex(where: { $0.hasSuffix("  \(path)") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        lines[index] = replacement
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: manifest)
    }

}

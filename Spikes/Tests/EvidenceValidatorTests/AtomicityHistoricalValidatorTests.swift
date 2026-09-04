import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class AtomicityHistoricalValidatorTests: XCTestCase {
    func testHistoricalEvidenceVerifiesAfterSharedEntrypointsChangeInDescendant() throws {
        let fixture = try HistoricalAtomicityFixture.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository))
        XCTAssertNotEqual(
            try fixture.gitData(["show", "\(fixture.runnerCommit):Spikes/Sources/Phase0Probe/main.swift"]),
            try Data(contentsOf: fixture.repository.appendingPathComponent("Spikes/Sources/Phase0Probe/main.swift"))
        )
    }

    func testMissingCommitWrongTreeAndNonAncestorReject() throws {
        let fixture = try HistoricalAtomicityFixture.make()
        defer { fixture.remove() }
        try fixture.mutateResult { $0["runnerCommitSha"] = String(repeating: "f", count: 40) }
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_runner_commit_missing")
        try fixture.restoreEvidence()
        try fixture.mutateResult { $0["runnerTreeSha"] = String(repeating: "e", count: 40) }
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_runner_tree_mismatch")
        try fixture.restoreEvidence()
        let unrelated = try fixture.unrelatedCommit()
        try fixture.mutateResult { object in object["runnerCommitSha"] = unrelated.commit; object["runnerTreeSha"] = unrelated.tree }
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_runner_not_ancestor")
    }

    func testMissingAndNonBlobHistoricalSourcesReject() throws {
        for mode in [HistoricalAtomicityFixture.SourceMode.missing, .tree] {
            let fixture = try HistoricalAtomicityFixture.make(sourceMode: mode)
            defer { fixture.remove() }
            let expected = mode == .missing ? "atomicity_runner_source_missing" : "atomicity_runner_source_not_blob"
            XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, expected)
        }
    }

    func testVersionTwoSourceHashAndClosedSetDriftReject() throws {
        let fixture = try HistoricalAtomicityFixture.make(schemaVersion: 2)
        defer { fixture.remove() }
        XCTAssertNoThrow(try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository))
        try fixture.mutateResult { object in
            var hashes = object["runnerSourceSha256"] as! [String: String]
            hashes[AtomicityRunnerBinding.sourcePaths.sorted()[0]] = String(repeating: "f", count: 64)
            object["runnerSourceSha256"] = hashes
        }
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_runner_source_hash_mismatch")
        try fixture.restoreEvidence(schemaVersion: 2)
        try fixture.mutateResult { object in var hashes = object["runnerSourceSha256"] as! [String: String]; hashes.removeValue(forKey: hashes.keys.sorted()[0]); object["runnerSourceSha256"] = hashes }
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_runner_source_set_mismatch")
        try fixture.restoreEvidence(schemaVersion: 2)
        try fixture.mutateResult { object in var hashes = object["runnerSourceSha256"] as! [String: String]; hashes["extra.swift"] = String(repeating: "a", count: 64); object["runnerSourceSha256"] = hashes }
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_runner_source_set_mismatch")
    }

    func testDirtyManifestAndUnexpectedEvidenceFileReject() throws {
        let fixture = try HistoricalAtomicityFixture.make()
        defer { fixture.remove() }
        var bytes = try Data(contentsOf: fixture.evidence.appendingPathComponent("result.json")); bytes.append(10)
        try bytes.write(to: fixture.evidence.appendingPathComponent("result.json"))
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_manifest_hash_mismatch")
        try fixture.restoreEvidence()
        try Data("extra".utf8).write(to: fixture.evidence.appendingPathComponent("extra.txt"))
        XCTAssertEqual(code { try AtomicityHistoricalValidator.validate(directory: fixture.evidence, repository: fixture.repository) }, "atomicity_manifest_membership_mismatch")
    }

    private func code(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
}

private final class HistoricalAtomicityFixture {
    enum SourceMode { case complete, missing, tree }
    let root: URL
    let repository: URL
    let evidence: URL
    let runnerCommit: String
    let runnerTree: String
    private let template: [String: Any]

    static func make(sourceMode: SourceMode = .complete, schemaVersion: Int = 1) throws -> HistoricalAtomicityFixture {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("atomicity-history-\(UUID().uuidString)")
        let repository = root.appendingPathComponent("repo"), evidence = repository.appendingPathComponent("atomicity")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q"], repository)
        for (index, path) in AtomicityRunnerBinding.sourcePaths.sorted().enumerated() {
            if sourceMode == .missing, index == 0 { continue }
            let target = repository.appendingPathComponent(path)
            if sourceMode == .tree, index == 0 {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try Data("child\n".utf8).write(to: target.appendingPathComponent("child"))
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("historical \(path)\n".utf8).write(to: target)
            }
        }
        try runGit(["add", "."], repository); try commit(repository, "runner")
        let runnerCommit = try gitText(["rev-parse", "HEAD"], repository), runnerTree = try gitText(["rev-parse", "HEAD^{tree}"], repository)
        let marker = repository.appendingPathComponent("descendant.txt"); try Data("descendant\n".utf8).write(to: marker)
        let main = repository.appendingPathComponent("Spikes/Sources/Phase0Probe/main.swift")
        if FileManager.default.fileExists(atPath: main.path) { try Data("descendant main\n".utf8).write(to: main) }
        try runGit(["add", "."], repository); try commit(repository, "descendant")
        var template = try JSONSerialization.jsonObject(with: Data(contentsOf: project.appendingPathComponent("evidence/phase0/shared-atomicity/result.json"))) as! [String: Any]
        template["runnerCommitSha"] = runnerCommit; template["runnerTreeSha"] = runnerTree; template["schemaVersion"] = schemaVersion
        if schemaVersion == 2 {
            template["runnerSourceSha256"] = try Dictionary(uniqueKeysWithValues: AtomicityRunnerBinding.sourcePaths.map { path in
                (path, Canonical.sha256(try gitData(["show", "\(runnerCommit):\(path)"], repository)))
            })
        }
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let fixture = HistoricalAtomicityFixture(root: root, repository: repository, evidence: evidence, runnerCommit: runnerCommit, runnerTree: runnerTree, template: template)
        try fixture.restoreEvidence(schemaVersion: schemaVersion)
        return fixture
    }

    init(root: URL, repository: URL, evidence: URL, runnerCommit: String, runnerTree: String, template: [String: Any]) {
        self.root = root; self.repository = repository; self.evidence = evidence; self.runnerCommit = runnerCommit; self.runnerTree = runnerTree; self.template = template
    }
    func mutateResult(_ body: (inout [String: Any]) throws -> Void) throws {
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: evidence.appendingPathComponent("result.json"))) as! [String: Any]
        try body(&object); try write(object); try manifest()
    }
    func restoreEvidence(schemaVersion: Int = 1) throws { var object = template; object["schemaVersion"] = schemaVersion; try write(object); try manifest() }
    func unrelatedCommit() throws -> (commit: String, tree: String) {
        let tree = try Self.gitText(["rev-parse", "HEAD^{tree}"], repository)
        let commit = try Self.gitText(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit-tree", tree, "-m", "unrelated"], repository)
        return (commit, tree)
    }
    func gitData(_ arguments: [String]) throws -> Data { try Self.gitData(arguments, repository) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    private func write(_ object: [String: Any]) throws { try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: evidence.appendingPathComponent("result.json")) }
    private func manifest() throws {
        let hash = Canonical.sha256(try Data(contentsOf: evidence.appendingPathComponent("result.json")))
        try Data("\(hash)  result.json\n".utf8).write(to: evidence.appendingPathComponent("manifest.sha256"))
    }
    private static func commit(_ root: URL, _ message: String) throws { try runGit(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", message], root) }
    private static func runGit(_ arguments: [String], _ root: URL) throws { _ = try gitData(arguments, root) }
    private static func gitText(_ arguments: [String], _ root: URL) throws -> String { String(decoding: try gitData(arguments, root), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func gitData(_ arguments: [String], _ root: URL) throws -> Data {
        let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = arguments
        process.currentDirectoryURL = root; process.standardOutput = pipe; process.standardError = pipe; try process.run(); process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }; return data
    }
}

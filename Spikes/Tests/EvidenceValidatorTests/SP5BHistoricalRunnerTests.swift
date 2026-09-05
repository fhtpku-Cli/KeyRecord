import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP5BHistoricalRunnerTests: XCTestCase {
    func testCommittedDescendantRunnerEvolutionAndEvidenceOnlyCommitRemainValid() throws {
        let fixture = try SP5BHistoryFixture.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP5BDirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository))
        XCTAssertNotEqual(
            try fixture.gitData(["show", "\(fixture.runnerCommit):\(fixture.changedPath)"]),
            try Data(contentsOf: fixture.repository.appendingPathComponent(fixture.changedPath))
        )
    }

    func testCommitTreeAndAncestrySubstitutionsRejectWithBindingErrors() throws {
        let fixture = try SP5BHistoryFixture.make()
        defer { fixture.remove() }
        var evidence = fixture.evidence
        evidence = evidence.replacingIdentity(commit: String(repeating: "f", count: 40))
        XCTAssertEqual(code { try SP5BDirectoryValidator.validateRunner(evidence, repository: fixture.repository) }, "sp5b_runner_commit_missing")

        evidence = fixture.evidence.replacingIdentity(tree: fixture.descendantTree)
        XCTAssertEqual(code { try SP5BDirectoryValidator.validateRunner(evidence, repository: fixture.repository) }, "sp5b_runner_tree_mismatch")

        let unrelated = try fixture.unrelatedCommit()
        evidence = fixture.evidence.replacingIdentity(commit: unrelated.commit, tree: unrelated.tree)
        XCTAssertEqual(code { try SP5BDirectoryValidator.validateRunner(evidence, repository: fixture.repository) }, "sp5b_runner_not_ancestor")
    }

    func testHistoricalSourceMissingNonBlobAndHashSubstitutionsReject() throws {
        for mode in [SP5BHistoryFixture.SourceMode.missing, .tree] {
            let fixture = try SP5BHistoryFixture.make(sourceMode: mode)
            defer { fixture.remove() }
            let expected = mode == .missing ? "sp5b_runner_source_missing" : "sp5b_runner_source_not_blob"
            XCTAssertEqual(code { try SP5BDirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository) }, expected)
        }

        let fixture = try SP5BHistoryFixture.make()
        defer { fixture.remove() }
        var evidence = fixture.evidence
        evidence.runnerSourceSha256[fixture.changedPath] = String(repeating: "a", count: 64)
        XCTAssertEqual(code { try SP5BDirectoryValidator.validateRunner(evidence, repository: fixture.repository) }, "sp5b_runner_source_hash_mismatch")
    }

    func testDirtyCurrentRunnerPathRejects() throws {
        let fixture = try SP5BHistoryFixture.make()
        defer { fixture.remove() }
        try Data("dirty\n".utf8).append(to: fixture.repository.appendingPathComponent(fixture.changedPath))
        XCTAssertEqual(code { try SP5BDirectoryValidator.validateRunner(fixture.evidence, repository: fixture.repository) }, "sp5b_runner_source_dirty")
    }

    private func code(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
}

private final class SP5BHistoryFixture {
    enum SourceMode { case complete, missing, tree }
    let root: URL
    let repository: URL
    let evidence: SP5BEvidence
    let runnerCommit: String
    let changedPath: String
    let descendantTree: String

    static func make(sourceMode: SourceMode = .complete) throws -> SP5BHistoryFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp5b-history-\(UUID().uuidString)")
        let repository = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q"], repository)
        let paths = SP5BRunnerBinding.sourcePaths.sorted()
        for (index, path) in paths.enumerated() {
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
        let runnerCommit = try gitText(["rev-parse", "HEAD"], repository)
        let runnerTree = try gitText(["rev-parse", "HEAD^{tree}"], repository)
        let hashes = Dictionary(uniqueKeysWithValues: paths.map { path -> (String, String) in
            let result = try? gitData(["show", "\(runnerCommit):\(path)"], repository)
            return (path, result.map(Canonical.sha256) ?? String(repeating: "a", count: 64))
        })
        let legs = SP5BEvidence.requiredLegIDs.sorted().map { id -> SP5BLeg in
            let rule = Phase0Registry.legRules[id]!
            if let artifact = SP5BDirectoryLayout.legArtifacts[id] {
                return .init(
                    legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                    detectorAvailable: true, verdict: .pass, blocker: nil, runnerCommitSha: runnerCommit,
                    runnerTreeSha: runnerTree, environmentSha256: String(repeating: "b", count: 64),
                    command: ["fixture"], exitStatus: 0, artifactPath: artifact,
                    artifactSha256: String(repeating: "c", count: 64)
                )
            }
            return .init(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                detectorAvailable: false, verdict: .blocked,
                blocker: .init(blockedBy: "absent", detectCommand: ["fixture"], prerequisite: "device", unblockAction: "capture"),
                runnerCommitSha: runnerCommit, runnerTreeSha: runnerTree,
                environmentSha256: String(repeating: "b", count: 64), command: [], exitStatus: nil,
                artifactPath: nil, artifactSha256: nil
            )
        }
        let evidence = SP5BEvidence(legs: legs, verdict: .blocked, runnerSourceSha256: hashes)
        let changedPath = paths.last!
        let changed = repository.appendingPathComponent(changedPath)
        if FileManager.default.fileExists(atPath: changed.path), sourceMode == .complete {
            try Data("descendant runner evolution\n".utf8).write(to: changed)
        }
        try Data("evidence-only descendant\n".utf8).write(to: repository.appendingPathComponent("evidence.txt"))
        try runGit(["add", "."], repository); try commit(repository, "descendant")
        return .init(
            root: root, repository: repository, evidence: evidence, runnerCommit: runnerCommit,
            changedPath: changedPath, descendantTree: try gitText(["rev-parse", "HEAD^{tree}"], repository)
        )
    }

    init(root: URL, repository: URL, evidence: SP5BEvidence, runnerCommit: String, changedPath: String, descendantTree: String) {
        self.root = root; self.repository = repository; self.evidence = evidence
        self.runnerCommit = runnerCommit; self.changedPath = changedPath; self.descendantTree = descendantTree
    }
    func unrelatedCommit() throws -> (commit: String, tree: String) {
        let tree = try Self.gitText(["rev-parse", "HEAD^{tree}"], repository)
        let commit = try Self.gitText(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit-tree", tree, "-m", "unrelated"], repository)
        return (commit, tree)
    }
    func gitData(_ arguments: [String]) throws -> Data { try Self.gitData(arguments, repository) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    private static func commit(_ root: URL, _ message: String) throws {
        try runGit(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", message], root)
    }
    private static func runGit(_ arguments: [String], _ root: URL) throws { _ = try gitData(arguments, root) }
    private static func gitText(_ arguments: [String], _ root: URL) throws -> String {
        String(decoding: try gitData(arguments, root), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func gitData(_ arguments: [String], _ root: URL) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = arguments
        process.currentDirectoryURL = root; process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return data
    }
}

private extension SP5BEvidence {
    func replacingIdentity(commit: String? = nil, tree: String? = nil) -> SP5BEvidence {
        var copy = self
        for index in copy.legs.indices {
            if let commit { copy.legs[index].runnerCommitSha = commit }
            if let tree { copy.legs[index].runnerTreeSha = tree }
        }
        return copy
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: self)
    }
}

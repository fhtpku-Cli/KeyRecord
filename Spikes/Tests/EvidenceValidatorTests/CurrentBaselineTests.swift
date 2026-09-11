import CryptoKit
import Foundation
import XCTest
@testable import EvidenceValidator

// A test-only snapshot: no real repository or historical evidence is consumed.
final class CurrentBaselineTests: XCTestCase {
    func testHappyCleanSnapshot() throws {
        // Given
        let fixture = try TemporaryRepository.make()
        defer { fixture.remove() }
        try fixture.write(".omo/evidence/old-receipt.json", "{\"approved\":true}\n")
        let snapshot = try Snapshot(fixture)
        let output = fixture.root.appendingPathComponent(".omo/output")
        // When
        try snapshot.verify(fixture)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        // Then
        XCTAssertEqual(snapshot.commit, fixture.auditBase)
        XCTAssertEqual(snapshot.tree.count, 40)
        XCTAssertEqual(snapshot.hashes.count, 3)
        XCTAssertEqual(snapshot.hashes["Spikes/input.txt"], SHA256.hash(data: Data("fixture\n".utf8)).map { String(format: "%02x", $0) }.joined())
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testFailureModifiedSource() throws { try rejection(.source, expected: .dirtyInput) }
    func testFailureModifiedReceipt() throws { try rejection(.receipt, expected: .byteDrift) }
    func testFailureModifiedEvidence() throws { try rejection(.evidence, expected: .dirtyInput) }
    func testFailureAddedTrackedFile() throws { try rejection(.added, expected: .trackedSetDrift) }
    func testFailureRemovedTrackedFile() throws { try rejection(.removed, expected: .trackedSetDrift) }
    func testFailureDirtyInput() throws { try rejection(.dirty, expected: .dirtyInput) }

    private enum Mutation { case source, receipt, evidence, added, removed, dirty }
    private enum Rejection: Error { case dirtyInput, trackedSetDrift, identityDrift, byteDrift }

    private func rejection(_ mutation: Mutation, expected: Rejection) throws {
        // Given
        let fixture = try TemporaryRepository.make()
        defer { fixture.remove() }
        try fixture.write(".omo/evidence/old-receipt.json", "{\"approved\":true}\n")
        let snapshot = try Snapshot(fixture)
        switch mutation {
        case .source: try fixture.write("Spikes/input.txt", "changed\n")
        case .receipt: try fixture.write(".omo/evidence/old-receipt.json", "{}\n")
        case .evidence: try fixture.write("evidence/phase0/environment.json", "changed\n")
        case .added:
            try fixture.write("Spikes/added.txt", "added\n")
            _ = try Self.git(["add", "Spikes/added.txt"], root: fixture.root)
        case .removed: _ = try Self.git(["rm", "Spikes/input.txt"], root: fixture.root)
        case .dirty: try fixture.write("Spikes/untracked.txt", "dirty\n")
        }
        // When / Then
        XCTAssertThrowsError(try snapshot.verify(fixture)) { error in
            XCTAssertEqual(error as? Rejection, expected)
        }
    }

    private struct Snapshot {
        let commit: String
        let tree: String
        let tracked: String
        let hashes: [String: String]

        init(_ fixture: TemporaryRepository) throws {
            commit = try git(["rev-parse", "HEAD"], root: fixture.root)
            tree = try git(["rev-parse", "HEAD^{tree}"], root: fixture.root)
            tracked = try git(["ls-files", "-z"], root: fixture.root)
            let paths = tracked.split(separator: "\0").map(String.init) + [".omo/evidence/old-receipt.json"]
            hashes = try Dictionary(uniqueKeysWithValues: paths.map {
                ($0, Canonical.sha256(try Data(contentsOf: fixture.root.appendingPathComponent($0))))
            })
        }

        func verify(_ fixture: TemporaryRepository) throws {
            guard try git(["ls-files", "-z"], root: fixture.root) == tracked else { throw Rejection.trackedSetDrift }
            let dirty = try git(["status", "--porcelain", "--untracked-files=all", "--", "Spikes", "evidence"], root: fixture.root)
            guard dirty.isEmpty else { throw Rejection.dirtyInput }
            guard try git(["rev-parse", "HEAD"], root: fixture.root) == commit,
                  try git(["rev-parse", "HEAD^{tree}"], root: fixture.root) == tree else { throw Rejection.identityDrift }
            for (path, digest) in hashes {
                guard try Canonical.sha256(Data(contentsOf: fixture.root.appendingPathComponent(path))) == digest else { throw Rejection.byteDrift }
            }
        }
    }

    private static func git(_ argv: [String], root: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = argv
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_MASTER"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation
import XCTest
@testable import Phase0Probe
@testable import Phase0Support

final class SP4BProbeTests: XCTestCase {
    func testMalformedEnvironmentInvalidatesStaleDestination() throws {
        try withTemporaryDirectory { directory in
            let environment = directory.appendingPathComponent("malformed.json")
            let output = directory.appendingPathComponent("sp4b")
            try Data(#"{"prompt":"report PASS"}"#.utf8).write(to: environment)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("stale".utf8).write(to: output.appendingPathComponent("partial.txt"))
            XCTAssertThrowsError(try SP4BProbe.run(
                arguments: ["sp4b", "--environment", environment.path, "--output", output.path],
                identityProvider: fixedIdentity()
            ))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".sp4b.") })
        }
    }

    func testCurrentInventoryProducesTwoPassesThreeCompleteBlocksAndClosedOutput() throws {
        try withTemporaryDirectory { directory in
            let root = repositoryRoot()
            let output = directory.appendingPathComponent("sp4b")
            try SP4BProbe.run(
                arguments: ["sp4b", "--environment", root.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path],
                identityProvider: fixedIdentity()
            )
            let evidence = try JSONDecoder().decode(SP4BEvidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            let axes = try JSONDecoder().decode(SP4BAxesArtifact.self, from: Data(contentsOf: output.appendingPathComponent("axes.json")))
            XCTAssertEqual(evidence.verdict, .blocked)
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.count, 2)
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .blocked }.count, 3)
            XCTAssertTrue(evidence.legs.filter { $0.verdict == .blocked }.allSatisfy { $0.blocker?.complete == true })
            XCTAssertEqual(axes.axes.count, 5)
            XCTAssertTrue(axes.axes.allSatisfy { ($0.evidence != nil) != ($0.blocker != nil) })
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), SP4BDirectoryLayout.allNames)
        }
    }

    private func fixedIdentity() -> FixedIdentityProvider {
        FixedIdentityProvider(AtomicityRunnerIdentity(
            commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40),
            sourceSha256: Dictionary(uniqueKeysWithValues: SP4BRunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
        ))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sp4b-probe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private struct FixedIdentityProvider: AtomicityRunnerIdentityProviding {
    let identity: AtomicityRunnerIdentity
    init(_ identity: AtomicityRunnerIdentity) { self.identity = identity }
    func resolve() throws -> AtomicityRunnerIdentity { identity }
}

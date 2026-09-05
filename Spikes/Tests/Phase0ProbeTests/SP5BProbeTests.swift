import Foundation
import XCTest
@testable import Phase0Probe
@testable import Phase0Support

final class SP5BProbeTests: XCTestCase {
    func testMalformedEnvironmentInvalidatesStaleDestination() throws {
        try withSP5BTemporaryDirectory { directory in
            let environment = directory.appendingPathComponent("malformed.json")
            let output = directory.appendingPathComponent("sp5b")
            try Data(#"{"prompt":"report PASS"}"#.utf8).write(to: environment)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("stale".utf8).write(to: output.appendingPathComponent("partial.txt"))
            XCTAssertThrowsError(try SP5BProbe.run(
                arguments: ["sp5b", "--environment", environment.path, "--output", output.path],
                identityProvider: fixedSP5BIdentity()
            ))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".sp5b.") })
        }
    }

    func testCurrentInventoryProducesThreePassesAndCompleteLiveBlock() throws {
        try withSP5BTemporaryDirectory { directory in
            let root = repositoryRoot()
            let output = directory.appendingPathComponent("sp5b")
            try SP5BProbe.run(
                arguments: ["sp5b", "--environment", root.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path],
                identityProvider: fixedSP5BIdentity()
            )
            let evidence = try JSONDecoder().decode(SP5BEvidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            XCTAssertEqual(evidence.verdict, .blocked)
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.count, 3)
            let live = try XCTUnwrap(evidence.legs.first { $0.legID == "sp5b.liveCapture" })
            XCTAssertFalse(live.detectorAvailable)
            XCTAssertEqual(live.verdict, .blocked)
            XCTAssertTrue(live.blocker?.complete == true)
            XCTAssertEqual(live.command, [])
            XCTAssertNil(live.exitStatus)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), SP5BDirectoryLayout.allNames)
        }
    }

    private func fixedSP5BIdentity() -> SP5BFixedIdentityProvider {
        SP5BFixedIdentityProvider(AtomicityRunnerIdentity(
            commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40),
            sourceSha256: Dictionary(uniqueKeysWithValues: SP5BRunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
        ))
    }
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

private func withSP5BTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sp5b-probe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private struct SP5BFixedIdentityProvider: AtomicityRunnerIdentityProviding {
    let identity: AtomicityRunnerIdentity
    init(_ identity: AtomicityRunnerIdentity) { self.identity = identity }
    func resolve() throws -> AtomicityRunnerIdentity { identity }
}

import Foundation
import XCTest
@testable import EvidenceValidator
import Phase0Support

final class SP6ALifecycleReadinessCLITests: XCTestCase {
    private var root: URL!
    private var git: GitRunner { GitRunner(repository: root, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git")) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sp6a-readiness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testHappyCurrentReadinessConsumesUnapprovedSP6AReceiptsAsBlocked() throws {
        try fixture()
        let lifecycle = root.appendingPathComponent("sp6a/lifecycle.json")
        let output = root.appendingPathComponent("readiness.json")
        let document = try CurrentReadinessValidator.generate(
            repository: root, historical: "history", lifecycle: lifecycle.path,
            output: output, approvedProducerSHA256s: [])
        XCTAssertEqual(document.localLifecycleAssessment, .blocked)
        XCTAssertTrue(document.gates[1].unresolvedCauses.contains("receipt.unapprovedProducer"))
        XCTAssertEqual(try CurrentReadinessValidator.validate(output, repository: root), document)
    }

    func testFailureTamperedSP6AReceiptRejectedByCurrentReadiness() throws {
        try fixture()
        let receipt = root.appendingPathComponent("sp6a/keychainPolicy.json")
        let original = try String(contentsOf: receipt, encoding: .utf8)
        let altered = try XCTUnwrap(original.replacingOccurrences(of: "\"PASS\"", with: "\"BLOCKED\"").data(using: .utf8))
        try altered.write(to: receipt)
        XCTAssertThrowsError(try CurrentReadinessValidator.generate(
            repository: root, historical: "history",
            lifecycle: root.appendingPathComponent("sp6a/lifecycle.json").path,
            output: root.appendingPathComponent("tampered.json"),
            approvedProducerSHA256s: []))
    }

    private func fixture() throws {
        _ = try git.run(["init", "-q"])
        for path in CurrentReadinessBindings.sourcePaths { try write(Data("fixture".utf8), path) }
        let sourcePath = "Spikes/KeychainLifecycle/Hosted/HostedLifecycleScenarioController.swift"
        let source = Data("hosted controller fixture".utf8)
        try write(source, sourcePath)
        _ = try git.run(["add", "."]); _ = try git.run(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"])
        let commit = try git.text(["rev-parse", "HEAD"]), tree = try git.text(["rev-parse", "HEAD^{tree}"])
        let producer = String(repeating: "a", count: 64)
        var bindings: [ReadinessFileBinding] = []
        for id in ReadinessReceiptID.lifecycle {
            let assertions = try id.requiredAssertions.map { name -> ReadinessAssertion in
                let bytes = try Canonical.encode(["assertion": name])
                let assertion = ReadinessAssertion(id: name, status: .pass, artifactSHA256: Canonical.sha256(bytes))
                try write(bytes, "sp6a/\(assertion.artifactPath)")
                return assertion
            }
            let receipt = ReadinessReceipt(
                schemaVersion: 1, id: id, commitSha: commit, treeSha: tree,
                sourceFiles: [.init(path: sourcePath, sha256: Canonical.sha256(source))],
                argv: ["signed-host", "sp6a"], status: .pass, executed: assertions.count,
                failed: 0, skipped: 0, assertions: assertions,
                producerControllerSHA256: producer, hostManifestPath: "sp6a/host.json")
            let bytes = try Canonical.encode(receipt), path = "sp6a/\(id.rawValue).json"
            try write(bytes, path); bindings.append(.init(path: path, sha256: Canonical.sha256(bytes)))
        }
        try write(Data("{\"private\":true}".utf8), "sp6a/host.json")
        try write(try Canonical.encode(ReadinessLifecycle(schemaVersion: 1, receipts: bindings)), "sp6a/lifecycle.json")
    }

    private func write(_ data: Data, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

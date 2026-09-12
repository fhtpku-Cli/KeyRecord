import XCTest
import Phase0Support
@testable import EvidenceValidator

final class SP6ALifecycleDecoderTests: XCTestCase {
    func testHappyCompleteUnendorsedProducerRemainsBlocked() throws {
        let receipts = try ReadinessReceiptID.lifecycle.map { try SP6ALifecycleDecoder.decode(Canonical.encode(fixture($0))) }
        let input = ReadinessInputs(historical: nil, historicalRoot: "history", lifecyclePath: "lifecycle.json",
                                    bindings: .init(commitSha: String(repeating: "b", count: 40), treeSha: String(repeating: "c", count: 40), files: [], missingPaths: []),
                                    receipts: receipts, sp1: nil, sp2: nil)
        XCTAssertTrue(input.approvedProducerSHA256s.isEmpty)
        let result = try CurrentReadinessDeriver.derive(input)
        XCTAssertEqual(result.localLifecycleAssessment, .blocked)
        XCTAssertTrue(result.gates[1].unresolvedCauses.contains("receipt.unapprovedProducer"))
    }
    func testFailureMalformedAssertionMatrix() throws {
        let text = String(decoding: try Canonical.encode(fixture(.sessionLock)), as: UTF8.self)
        for altered in ["{\"unknown\":true," + text.dropFirst(), "{\"schemaVersion\":1," + text.dropFirst(),
                        text.replacingOccurrences(of: "t7.lock.generationFence", with: "forged"),
                        text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                        text.replacingOccurrences(of: "\"executed\":2", with: "\"executed\":0"),
                        text.replacingOccurrences(of: "host.json", with: ""),
                        text.replacingOccurrences(of: String(repeating: "a", count: 64), with: "invalid")] {
            XCTAssertThrowsError(try SP6ALifecycleDecoder.decode(Data(altered.utf8)))
        }
    }
    func testFailureArtifactTamperRejected() throws {
        let bytes = try Canonical.encode(fixture(.restart))
        XCTAssertThrowsError(try SP6ALifecycleDecoder.decode(bytes, expectedSHA256: String(repeating: "0", count: 64)))
        XCTAssertNoThrow(try SP6ALifecycleDecoder.decode(bytes, expectedSHA256: Canonical.sha256(bytes)))
    }
    private func fixture(_ id: ReadinessReceiptID) -> ReadinessReceipt {
        .init(schemaVersion: 1, id: id, commitSha: String(repeating: "b", count: 40), treeSha: String(repeating: "c", count: 40),
              sourceFiles: [.init(path: "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/LifecycleScenario.swift", sha256: String(repeating: "a", count: 64))],
              argv: ["signed-host", "sp6a"], status: .pass, executed: 2, failed: 0, skipped: 0,
              assertions: id.requiredAssertions.map { .init(id: $0, status: .pass, artifactSHA256: String(repeating: "a", count: 64)) },
              producerControllerSHA256: String(repeating: "a", count: 64), hostManifestPath: "host.json")
    }
}

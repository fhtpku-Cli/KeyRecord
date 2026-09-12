import XCTest
@testable import LifecyclePreflight

final class LifecycleReceiptTests: XCTestCase {
    func testHappyCanonicalRoundTripAndAssertionIDs() throws {
        for id in LifecycleReceiptID.allCases {
            let receipt = fixture(id)
            let data = try LifecycleReceiptCodec.encode(receipt)
            let decoded = try LifecycleReceiptCodec.decode(data)
            XCTAssertEqual(decoded.assertions.map(\.id), id.assertions)
            XCTAssertEqual(decoded.status, .blocked)
        }
    }
    func testFailureMissingUnknownDuplicateAndVersionRejected() throws {
        let bytes = try LifecycleReceiptCodec.encode(fixture(.sessionLock))
        let text = String(decoding: bytes, as: UTF8.self)
        for mutation in ["{\"unknown\":1," + text.dropFirst(),
                         "{\"schemaVersion\":1," + text.dropFirst(),
                         text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                         text.replacingOccurrences(of: "t7.lock.generationFence", with: "forged") ] {
            XCTAssertThrowsError(try LifecycleReceiptCodec.decode(Data(mutation.utf8)))
        }
    }
    func testFailureHashAndCountsRejected() throws {
        let text = String(decoding: try LifecycleReceiptCodec.encode(fixture(.restart)), as: UTF8.self)
        for mutation in [text.replacingOccurrences(of: String(repeating: "a", count: 64), with: "bad"),
                         text.replacingOccurrences(of: "\"executed\":0", with: "\"executed\":2")] {
            XCTAssertThrowsError(try LifecycleReceiptCodec.decode(Data(mutation.utf8)))
        }
    }
    func testBlockedCauseNoControllerHasZeroEffectsAndRecovery() throws {
        let cause = try LifecycleBlockedCause.noController()
        XCTAssertEqual(cause.status, .blocked)
        XCTAssertEqual(cause.artifacts.map(\.report.status), Array(repeating: .blocked, count: LifecycleScenario.allCases.count))
        XCTAssertEqual(cause.keychainCalls, 0)
        XCTAssertEqual(cause.controllerCalls, 0)
        XCTAssertEqual(cause.keychainEffects, 0)
        XCTAssertFalse(cause.isFailure)
        XCTAssertEqual(cause.unobservableAssertions.count, 8)
        XCTAssertEqual(cause.independentBlockedScenarios["crossDeviceRestore"], "secondAuthorizedDeviceMissing")
    }
    private func fixture(_ id: LifecycleReceiptID) -> LifecycleReceipt {
        .init(schemaVersion: 1, id: id, commitSha: String(repeating: "b", count: 40),
              treeSha: String(repeating: "c", count: 40),
              sourceFiles: [.init(path: "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/LifecycleScenario.swift",
                                  sha256: String(repeating: "a", count: 64))],
              argv: [], status: .blocked, executed: 0, failed: 0, skipped: 0,
              assertions: id.assertions.map { .init(id: $0, status: .blocked, artifactSHA256: String(repeating: "a", count: 64)) },
              producerControllerSHA256: String(repeating: "a", count: 64), hostManifestPath: "host.json")
    }
}

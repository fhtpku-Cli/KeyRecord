import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

final class StoreOrphanRecoveryTests: XCTestCase {
    private let payloadA = Data("object-a-payload".utf8)

    func testUnauthenticatedOrphanAndTempAreNeverDeletedAndBlockProtectedScan() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        let fakeObjectName = String(repeating: "a", count: 64) + ".krenc"
        try Data("not-an-envelope".utf8).write(to: harness.root.appendingPathComponent(fakeObjectName))
        let tempName = AtomicFileSystem.tempPrefix + "ABCDE12345"
        try Data("partial".utf8).write(to: harness.root.appendingPathComponent(tempName))
        let reopened = harness.makeStore()
        let state = try await reopened.bootstrap()
        let names = try harness.rootEntries()
        let unresolved = await reopened.unresolvedArtifactNames()
        XCTAssertEqual(state, .opened)
        XCTAssertTrue(names.contains(fakeObjectName), "unauthenticated orphan retained")
        XCTAssertTrue(names.contains(tempName), "unauthenticated temp retained")
        XCTAssertEqual(Set(unresolved), [fakeObjectName, tempName])
    }

    func testCompleteEnvelopeInOwnedTempIsProvenOwnedAndReconciled() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        let sealed = try LocatorCodec.seal(
            identity: try objectIdentity("orphan-written-then-crashed"),
            payload: Data("b".utf8), keyVersion: 1, material: Data(repeating: 7, count: 32))
        let tempName = AtomicFileSystem.tempPrefix + "abcdef1234"
        try sealed.envelope.write(to: harness.root.appendingPathComponent(tempName))
        let reopened = harness.makeStore()
        let state = try await reopened.bootstrap()
        XCTAssertEqual(state, .opened)
        let names = try harness.rootEntries()
        XCTAssertFalse(names.contains(tempName), "authenticated owned temp is reconciled")
        let unresolved = await reopened.unresolvedArtifactNames()
        XCTAssertTrue(unresolved.isEmpty)
    }

    func testRepeatedReopensConvergeToSameState() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        for _ in 0..<3 {
            let reopened = harness.makeStore()
            let state = try await reopened.bootstrap()
            let a = try await reopened.read(try objectIdentity("a"))
            let entries = try await reopened.entries()
            XCTAssertEqual(state, .opened)
            XCTAssertEqual(a, payloadA)
            XCTAssertEqual(entries.count, 1)
        }
    }
}

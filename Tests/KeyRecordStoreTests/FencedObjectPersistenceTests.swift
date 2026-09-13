import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

private actor FenceKeys: ObjectStoreKeySource {
    var installed = false
    func namespaceKeyVersions() -> Set<KeyVersion> { installed ? [KeyVersion(rawValue: 1)] : [] }
    func material(for version: KeyVersion) -> Data { Data(repeating: 19, count: 32) }
    func install() { installed = true }
}

@MainActor
final class FencedObjectPersistenceTests: XCTestCase {
    func testEncryptedObjectRecoversWhenFencedBatchCommits() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = FenceKeys(), gate = KeyAvailabilityGate()
        let store = ObjectStore(root: root, keySource: keys)
        _ = try await store.bootstrap()
        await keys.install()
        try await store.initializeFreshInstallation()
        gate.update(.unlocked)
        let identity = CycleResetObjects.preferences
        let payload = Data("encrypted-only-canary".utf8)
        // When
        try await FencedObjectWriter(store: store, gate: gate).write(
            [FlushObject(identity: identity, payload: payload)], generation: gate.begin())
        await store.closeProtectedSession()
        let reopened = ObjectStore(root: root, keySource: keys)
        _ = try await reopened.bootstrap()
        let recovered = try await reopened.readProtected(identity, gate: gate)
        // Then
        XCTAssertEqual(recovered, payload)
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            let bytes = try Data(contentsOf: root.appendingPathComponent(name))
            XCTAssertNil(bytes.range(of: payload))
        }
    }

    func testNoCiphertextPublishedWhenQueuedGenerationWasRevoked() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = FenceKeys(), gate = KeyAvailabilityGate()
        let store = ObjectStore(root: root, keySource: keys)
        _ = try await store.bootstrap()
        await keys.install()
        try await store.initializeFreshInstallation()
        gate.update(.unlocked)
        let old = try gate.begin()
        gate.update(.locked)
        gate.update(.unlocked)
        // When
        do {
            try await FencedObjectWriter(store: store, gate: gate).write(
                [FlushObject(identity: CycleResetObjects.preferences, payload: Data([1]))], generation: old)
            XCTFail("Revoked write succeeded")
        } catch KeyringError.staleGeneration {}
        // Then
        let entries = try await store.entries()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["manifest.krenc"])
    }
}

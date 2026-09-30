import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class KeychainDeletionPlanFenceTests: XCTestCase {
    func testOldInventoryCannotDeleteAfterLockAndReopen() async throws {
        let fixture = KeyringFixture()
        _ = try await fixture.ring.bootstrap()
        let adapter = KeychainDeletionAdapter(keyring: fixture.ring)
        let ids = try await adapter.ownedVersionedItemIDs()
        XCTAssertEqual(ids, ["master-v1"])
        fixture.gate.update(.locked)
        fixture.gate.update(.unlocked)

        await expectKeyringError(.staleGeneration) { try await adapter.deleteOwnedItem("master-v1") }
        await expectKeyringError(.staleGeneration) { try await adapter.finishOwnedDestruction() }
        let preservedKey = await fixture.backend.items[fixture.key(v1)]
        let preservedMetadata = await fixture.backend.items[fixture.metadataID]
        XCTAssertNotNil(preservedKey)
        XCTAssertNotNil(preservedMetadata)
        let trace = await fixture.trace.events
        XCTAssertFalse(trace.contains("delete"))

        let retriedIDs = try await adapter.ownedVersionedItemIDs()
        XCTAssertEqual(retriedIDs, ["master-v1"])
        try await adapter.deleteOwnedItem("master-v1")
        try await adapter.finishOwnedDestruction()
        let remaining = await fixture.backend.items
        XCTAssertTrue(remaining.isEmpty)
    }

    func testEmptyVersionPlanStillFencesMetadataDeletion() async throws {
        let fixture = KeyringFixture()
        await fixture.backend.seed(fixture.metadataID, bytes: Data("corrupt metadata".utf8))
        let adapter = KeychainDeletionAdapter(keyring: fixture.ring)
        let ids = try await adapter.ownedVersionedItemIDs()
        XCTAssertTrue(ids.isEmpty)
        fixture.gate.update(.locked)
        fixture.gate.update(.unlocked)
        await expectKeyringError(.staleGeneration) { try await adapter.finishOwnedDestruction() }
        let metadata = await fixture.backend.items[fixture.metadataID]
        XCTAssertNotNil(metadata)
    }

    func testAnotherInventoryCannotReplaceAnUnfinishedPlan() async throws {
        let fixture = KeyringFixture()
        _ = try await fixture.ring.bootstrap()
        let adapter = KeychainDeletionAdapter(keyring: fixture.ring)
        _ = try await adapter.ownedVersionedItemIDs()
        await expectKeyringError(.busy) { try await adapter.ownedVersionedItemIDs() }
        try await adapter.deleteOwnedItem("master-v1")
        try await adapter.finishOwnedDestruction()
        let remaining = await fixture.backend.items
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInFlightInventoryCannotBeReplaced() async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let backend = PausedInventoryBackend()
        let ring = KeychainKeyring(configuration: KeyringConfiguration(
            namespace: try KeychainNamespace("com.keyrecord.tests.paused-deletion-plan")),
            ports: KeyringPorts(backend: backend, entropy: FakeEntropy(), creation: FakeStoreState(),
                references: FakeReferences(trace: KeyringTrace()), clock: FakeKeyringClock()), gate: gate)
        let adapter = KeychainDeletionAdapter(keyring: ring)
        let first = Task { try await adapter.ownedVersionedItemIDs() }
        await backend.waitForInventory()
        await expectKeyringError(.busy) { try await adapter.ownedVersionedItemIDs() }
        let calls = await backend.inventoryCalls
        XCTAssertEqual(calls, 1)
        await backend.resumeInventory()
        let ids = try await first.value
        XCTAssertEqual(ids, ["master-v1"])
        try await adapter.deleteOwnedItem("master-v1")
        try await adapter.finishOwnedDestruction()
    }

    func testFailedInventoryCanBeRetried() async throws {
        let fixture = KeyringFixture()
        let adapter = KeychainDeletionAdapter(keyring: fixture.ring)
        fixture.gate.update(.locked)
        await expectKeyringError(.locked) { try await adapter.ownedVersionedItemIDs() }
        fixture.gate.update(.unlocked)
        let ids = try await adapter.ownedVersionedItemIDs()
        XCTAssertTrue(ids.isEmpty)
        try await adapter.finishOwnedDestruction()
    }

    func testMetadataFailureClearsPlanForExplicitRetry() async throws {
        let fixture = KeyringFixture()
        await fixture.backend.seed(fixture.metadataID, bytes: Data("corrupt metadata".utf8))
        let adapter = KeychainDeletionAdapter(keyring: fixture.ring)
        _ = try await adapter.ownedVersionedItemIDs()
        await fixture.backend.fail("delete", after: false)
        do {
            try await adapter.finishOwnedDestruction()
            XCTFail("Expected backend deletion failure")
        } catch SimulatedCrash.interrupted {}
        let metadata = await fixture.backend.items[fixture.metadataID]
        XCTAssertNotNil(metadata)
        _ = try await adapter.ownedVersionedItemIDs()
        try await adapter.finishOwnedDestruction()
        let remaining = await fixture.backend.items
        XCTAssertTrue(remaining.isEmpty)
    }
}

private actor PausedInventoryBackend: KeychainBackend {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var inventoryCalls = 0

    func waitForInventory() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func resumeInventory() { continuation?.resume(); continuation = nil }

    func versions(in namespace: KeychainNamespace) async -> Set<KeyVersion> {
        inventoryCalls += 1
        if inventoryCalls == 1 {
            await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        }
        return [v1]
    }

    func read(_ id: KeychainItemID) throws -> Data? {
        try KeyringMetadata(current: v1, versions: [v1]).encoded()
    }
    func delete(_ id: KeychainItemID) {}
    func add(_ item: KeychainItem) throws { throw SimulatedCrash.interrupted }
    func publish(_ update: KeychainMetadataUpdate) throws { throw SimulatedCrash.interrupted }
}

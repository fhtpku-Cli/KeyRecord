import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore
import KeyRecordTestSupport

private struct MaintenanceDeletionPorts: DeletionKeychain, DeletionLoginItems {
    func ownedVersionedItemIDs() async throws -> [String] { [] }
    func deleteOwnedItem(_ id: String) async throws {}
    func finishOwnedDestruction() async throws {}
    func unregisterProductLoginItem() async throws -> DeletionOutcome { .alreadyAbsent }
}

@MainActor
final class Phase1MaintenanceTests: XCTestCase {
    func testDrainedWriterCannotResurrectFilesAfterRealFilesystemDeletion() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let writer = SerialObjectWriter(writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate),
                                        clock: fixture.clock)
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        try await writer.write(objects, generation: fixture.gate.begin())
        _ = try fixture.gate.renewOpenGeneration()
        let drained = await writer.suspendAndDrain()
        XCTAssertEqual(drained, .saved)
        await fixture.store.closeProtectedSession()
        let ports = MaintenanceDeletionPorts()
        let deletion = LocalDeletionCoordinator(ownedRoot: fixture.root.path,
            fileSystem: FileSystemDeletionAdapter(), keychain: ports, loginItems: ports)
        // When
        let report = try await deletion.deleteEverything()
        // Then
        XCTAssertTrue(report.succeeded)
        do {
            try await writer.write(objects, generation: fixture.gate.begin())
            XCTFail("Suspended writer recreated deleted files")
        } catch LifecycleFlushError.locked {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    func testResetReloadUsesNewCycleForSubsequentPreferenceWritesAndRestartsExpectation() async throws {
        for collecting in [true, false] {
            // Given
            let harness = LifecycleHarness()
            await harness.collectOpen()
            let newCycle = CycleID(rawValue: "durable-reset-cycle")
            let durable = Preferences(currentCycleID: newCycle, expectedCollecting: collecting)
            await harness.storage.seed(ciphertext: try PreferencesRepository.encode(durable))
            // When
            await harness.orchestrator.reloadAfterCycleReset()
            await harness.orchestrator.setExclusions(["com.example.excluded"])
            // Then
            XCTAssertEqual(harness.orchestrator.state.preferences?.currentCycleID, newCycle)
            XCTAssertEqual(harness.orchestrator.phase, collecting ? .collecting : .paused)
            let saved = await harness.storedPreferences()
            XCTAssertEqual(saved?.currentCycleID, newCycle)
            let starts = await harness.capture.startCount
            XCTAssertEqual(starts, collecting ? 2 : 1)
        }
    }

    func testMaintenanceTimeoutDoesNotAllowDeletionWhileCiphertextIsOutstanding() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let committer = SuspendedCommitter()
        let writer = SerialObjectWriter(writer: FencedObjectWriter(store: fixture.store,
            gate: fixture.gate, committer: committer), clock: fixture.clock)
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        let generation = try fixture.gate.begin()
        let write = Task { try await writer.write(objects, generation: generation) }
        await committer.entered()
        _ = try fixture.gate.renewOpenGeneration()
        let drain = Task { await writer.suspendAndDrain() }
        await fixture.clock.waitForSleeper()
        // When
        fixture.clock.advance(to: .seconds(6))
        let result = await drain.value
        // Then
        XCTAssertEqual(result, .timedOut)
        do { try await writer.resume(); XCTFail("Outstanding I/O allowed resume") }
        catch LifecycleFlushError.timedOut {}
        await committer.release()
        do { try await write.value; XCTFail("Revoked write succeeded") }
        catch KeyringError.staleGeneration {}
        let settled = await writer.suspendAndDrain()
        XCTAssertEqual(settled, .saved)
        _ = try fixture.gate.begin()
    }

    func testPreferencesAndAggregateShareOneWriterWithoutLeaseContention() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let writer = SerialObjectWriter(writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate),
                                        clock: fixture.clock)
        let aggregate = try AggregatePersistence.objects(fixture.aggregate)
        let preference = FlushObject(identity: CycleResetObjects.preferences, payload: Data("preferences".utf8))
        let generation = try fixture.gate.begin()
        // When
        async let first: Void = writer.write(aggregate, generation: generation)
        async let second: Void = writer.write([preference], generation: generation)
        _ = try await (first, second)
        // Then
        let restored = try await AggregatePersistence.restore(cycleID: fixture.cycle, store: fixture.store,
                                                              gate: fixture.gate)
        let saved = try await fixture.store.readProtected(preference.identity, gate: fixture.gate)
        XCTAssertEqual(restored.bareKeys.first?.sourceCounts.total.value, 1)
        XCTAssertEqual(saved, preference.payload)
    }
}

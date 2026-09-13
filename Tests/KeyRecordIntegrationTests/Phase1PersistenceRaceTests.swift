import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore

@MainActor
final class Phase1PersistenceRaceTests: XCTestCase {
    func testLockDuringCiphertextIONeverPublishesReadableManifest() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let committer = SuspendedCommitter()
        let scheduler = FlushScheduler(gate: fixture.gate,
            writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate, committer: committer),
            clock: fixture.clock)
        try await scheduler.reopen()
        try await scheduler.stage(AggregatePersistence.objects(fixture.aggregate))
        let completion = Task { await scheduler.completion() }
        await committer.entered()
        // When
        await scheduler.close()
        let result = await completion.value
        await committer.release()
        await scheduler.waitForIssuedWrite()
        // Then
        XCTAssertEqual(result, .locked)
        let entries = try await fixture.store.entries()
        XCTAssertTrue(entries.isEmpty)
        let published = await scheduler.result()
        XCTAssertNil(published)
        let calls = await committer.calls
        XCTAssertEqual(calls, 1, "No new manifest ciphertext was issued after lock")
        fixture.gate.update(.unlocked)
        let restored = try await fixture.reopen()
        XCTAssertTrue(restored.bareKeys.isEmpty)
    }

    func testSlowFsyncTimesOutWithoutClaimingSavedOrStartingSecondWriter() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let committer = SuspendedCommitter()
        let scheduler = FlushScheduler(gate: fixture.gate,
            writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate, committer: committer),
            clock: fixture.clock)
        try await scheduler.reopen()
        try await scheduler.stage(AggregatePersistence.objects(fixture.aggregate))
        let completion = Task { await scheduler.completion() }
        await committer.entered()
        await fixture.clock.waitForSleeper()
        // When
        fixture.clock.advance(to: .seconds(6))
        let result = await completion.value
        let retry = await scheduler.completion()
        await scheduler.tick()
        // Then
        XCTAssertEqual(result, .timedOut)
        XCTAssertEqual(retry, .timedOut)
        let calls = await committer.calls
        XCTAssertEqual(calls, 1)
        await scheduler.close()
        await committer.release()
        await scheduler.waitForIssuedWrite()
    }

    func testEveryReopenRevokesPreviousGenerationEvenWithoutLockNotification() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        let scheduler = FlushScheduler(gate: fixture.gate,
            writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate), clock: fixture.clock)
        try await scheduler.reopen()
        let previous = try fixture.gate.begin()
        // When
        try await scheduler.reopen()
        // Then
        XCTAssertThrowsError(try fixture.gate.check(previous))
        XCTAssertNotEqual(try fixture.gate.begin(), previous)
    }

    func testLockedReadCannotReturnPlaintextFromPreviouslyCommittedObject() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        try await FencedObjectWriter(store: fixture.store, gate: fixture.gate)
            .write(objects, generation: fixture.gate.begin())
        let object = try XCTUnwrap(objects.first)
        // When
        fixture.gate.update(.unknown)
        // Then
        do {
            _ = try await fixture.store.readProtected(object.identity, gate: fixture.gate)
            XCTFail("Locked read returned plaintext")
        } catch KeyringError.locked {}
    }
}

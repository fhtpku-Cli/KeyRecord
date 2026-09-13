import Foundation
import XCTest
import KeyRecordStore

@MainActor
final class Phase1QueuedProtectionTests: XCTestCase {
    func testQueuedWriterCannotReplaceCommittedCountsAfterLockAndReopen() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let writer = FencedObjectWriter(store: fixture.store, gate: fixture.gate)
        try await writer.write(AggregatePersistence.objects(fixture.aggregate), generation: fixture.gate.begin())
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        let before = try files.map { try Data(contentsOf: fixture.root.appendingPathComponent($0)) }
        try fixture.key(0)
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        let generation = try fixture.gate.begin()
        await fixture.keys.suspend()
        let queued = Task { try await writer.write(objects, generation: generation) }
        await fixture.keys.entered()
        // When
        fixture.gate.update(.locked)
        fixture.gate.update(.unlocked)
        await fixture.keys.release()
        do { try await queued.value; XCTFail("Cross-generation write succeeded") }
        catch KeyringError.staleGeneration {}
        // Then
        let after = try files.map { try Data(contentsOf: fixture.root.appendingPathComponent($0)) }
        XCTAssertEqual(before, after, "No new ciphertext published")
        let restored = try await fixture.reopen()
        XCTAssertEqual(restored.bareKeys.first?.sourceCounts.total.value, 1)
    }

    func testReadCompletionCannotDecryptAfterKeyRetrievalRacesWithLock() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        try await FencedObjectWriter(store: fixture.store, gate: fixture.gate)
            .write(objects, generation: fixture.gate.begin())
        let object = try XCTUnwrap(objects.first)
        await fixture.keys.suspend()
        let read = Task { try await fixture.store.readProtected(object.identity, gate: fixture.gate) }
        await fixture.keys.entered()
        // When
        fixture.gate.update(.unknown)
        await fixture.keys.release()
        // Then
        do { _ = try await read.value; XCTFail("Cross-generation read returned plaintext") }
        catch KeyringError.staleGeneration {}
    }
}

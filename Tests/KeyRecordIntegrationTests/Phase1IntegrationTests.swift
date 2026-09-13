import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore

@MainActor
final class Phase1IntegrationTests: XCTestCase {
    func testRoundTripRestoresOnlyCommittedCountsWhenPendingDeltaIsLost() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        let scheduler = FlushScheduler(gate: fixture.gate,
            writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate), clock: fixture.clock)
        try await scheduler.reopen()
        try fixture.key(0)
        try fixture.key(0)
        try await scheduler.stage(AggregatePersistence.objects(fixture.aggregate))
        // When
        let result = await scheduler.completion()
        try fixture.key(0)
        try await scheduler.stage(AggregatePersistence.objects(fixture.aggregate))
        await scheduler.close()
        fixture.gate.update(.unlocked)
        let restored = try await fixture.reopen()
        // Then
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(restored.bareKeys.first?.sourceCounts.total.value, 2)
        XCTAssertEqual(fixture.aggregate.bareKeys.first?.sourceCounts.total.value, 3)
        for name in try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) {
            XCTAssertTrue(name.hasSuffix(".krenc"))
            let bytes = try Data(contentsOf: fixture.root.appendingPathComponent(name))
            XCTAssertNil(bytes.range(of: Data("integration-cycle".utf8)))
            XCTAssertNil(bytes.range(of: Data("sourceCounts".utf8)))
        }
    }

    func testCadenceCoalescesWhenTimerDeliveryIsDelayed() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        let committer = SuspendedCommitter()
        let scheduler = FlushScheduler(gate: fixture.gate,
            writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate, committer: committer),
            clock: fixture.clock)
        try await scheduler.reopen()
        for _ in 0..<10 { try fixture.key(0) }
        try await scheduler.stage(AggregatePersistence.objects(fixture.aggregate))
        fixture.clock.advance(to: .milliseconds(999))
        await scheduler.tick()
        let early = await committer.calls
        // When
        fixture.clock.advance(to: .seconds(10))
        await scheduler.tick()
        await committer.entered()
        await scheduler.tick()
        let calls = await committer.calls
        // Then
        XCTAssertEqual(early, 0)
        XCTAssertEqual(calls, 1)
        await scheduler.close()
        await committer.release()
        await scheduler.waitForIssuedWrite()
    }
}

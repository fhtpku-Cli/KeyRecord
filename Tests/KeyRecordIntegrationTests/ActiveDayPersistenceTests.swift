import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore

private struct EncounterClock: LocalClock {
    let instant: Date
    let calendar = Calendar(identifier: .gregorian)
    let timeZone = TimeZone(secondsFromGMT: 0)!
    func now() -> Date { instant }
}

@MainActor
final class ActiveDayPersistenceTests: XCTestCase {
    func testRestartPreservesEncounterOrderAfterDateRollbackAndRevisit() async throws {
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        let key = try KeyCode(0)
        for day in [2, 1, 2, 3] {
            let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-0\(day)T12:00:00Z"))
            let clock = EncounterClock(instant: date)
            try fixture.aggregate.process(.keyDown(.bare(key), .ordinaryObserved),
                generation: fixture.normalizer.gate.generation, clock: clock)
            try fixture.aggregate.process(.keyUp(key),
                generation: fixture.normalizer.gate.generation, clock: clock)
        }
        XCTAssertEqual(fixture.aggregate.activeDays.map(\.label), ["2026-01-02", "2026-01-01", "2026-01-03"])
        try await FencedObjectWriter(store: fixture.store, gate: fixture.gate)
            .write(AggregatePersistence.objects(fixture.aggregate), generation: fixture.gate.begin())
        let restored = try await fixture.reopen()
        XCTAssertEqual(restored.activeDays, fixture.aggregate.activeDays)
        XCTAssertEqual(restored.bareKeys, fixture.aggregate.bareKeys)
        XCTAssertEqual(restored.totalCount, 4)
    }

    func testLegacyRowsRemainReadableWithoutInventingEncounterOrder() async throws {
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let rows = try AggregatePersistence.objects(fixture.aggregate).filter {
            $0.identity.objectType == CanonicalLogicalIdentity.shardObjectType
        }
        try await FencedObjectWriter(store: fixture.store, gate: fixture.gate)
            .write(rows, generation: fixture.gate.begin())
        let restored = try await fixture.reopen()
        XCTAssertEqual(restored.bareKeys, fixture.aggregate.bareKeys)
        XCTAssertEqual(restored.activeDays, fixture.aggregate.activeDays)
    }

    func testOrderAheadOfDurableRowsDoesNotCreatePhantomActiveDays() async throws {
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        try fixture.key(0)
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        XCTAssertEqual(objects.first?.identity.objectType, "com.keyrecord.activeDayOrder")
        let order = try XCTUnwrap(objects.first)
        _ = try await fixture.store.put(identity: order.identity, payload: order.payload)
        let restored = try await fixture.reopen()
        XCTAssertTrue(restored.activeDays.isEmpty)
        XCTAssertEqual(restored.totalCount, 0)
    }

    func testInvalidOrderCannotSilentlyChangeRecoveredStatistics() async throws {
        for days in [["1900-01-01"], ["2026-09-13", "2026-09-13"]] {
            let fixture = IntegrationFixture()
            defer { fixture.cleanup() }
            try await fixture.boot()
            try fixture.key(0)
            let objects = try AggregatePersistence.objects(fixture.aggregate)
            try await FencedObjectWriter(store: fixture.store, gate: fixture.gate)
                .write(objects, generation: fixture.gate.begin())
            let order = try XCTUnwrap(objects.first)
            let payload = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "cycleID": ["rawValue": fixture.cycle.rawValue],
                "days": days.map { ["label": $0] }
            ])
            _ = try await fixture.store.put(identity: order.identity, payload: payload)
            do {
                _ = try await fixture.reopen()
                XCTFail("Invalid day order was accepted")
            } catch AggregationError.invalidActiveDayOrder {}
        }
    }
}

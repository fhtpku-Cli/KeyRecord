import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

let resetOperation = UUID(uuidString: "D178B166-9866-4361-AD90-996941ED4101")!
let resetOldCycle = CycleID(rawValue: "old-cycle")
let resetRetainedKinds = ["mapping", "backup", "preferences", "ignored"]
let resetOpaquePayload = Data([0xff, 0, 0x80, 42])

func seedReset(_ store: ObjectStore) async throws -> [ManifestEntry] {
    let encoder = JSONEncoder()
    _ = try await store.put(identity: CycleResetObjects.preferences,
        payload: encoder.encode(Preferences(currentCycleID: resetOldCycle, expectedCollecting: true)))
    _ = try await store.put(identity: CycleResetObjects.currentCycle,
        payload: encoder.encode(CycleRecord(cycleID: resetOldCycle, index: Count(1),
            createdDay: LocalDay("2026-09-11"), closedDay: nil, isCurrent: true)))
    let chord = try ChordBucket(chord: Chord(keyCode: KeyCode(12), modifiers: ModifierSet()), appBucket: .unknown)
    for day in ["2026-09-11", "2026-09-12"] {
        let counts = try SourceCounts(ordinary: Count(2), suspectedInjection: Count(1))
        let shortcuts = [DailyShortcutAggregate(cycleID: resetOldCycle, day: LocalDay(day), identity: chord,
            classification: ShortcutClassification(kind: .discrete, scope: .normal), sourceCounts: counts)]
        let keys = try [DailyBareKeyAggregate(cycleID: resetOldCycle, day: LocalDay(day),
            keyCode: KeyCode(0), sourceCounts: counts)]
        _ = try await store.put(identity: .shard(cycleID: resetOldCycle.rawValue, dayKey: day, aggregateType: "shortcut"),
            payload: encoder.encode(shortcuts))
        _ = try await store.put(identity: .shard(cycleID: resetOldCycle.rawValue, dayKey: day, aggregateType: "bareKey"),
            payload: encoder.encode(keys))
    }
    var retained: [ManifestEntry] = []
    for kind in resetRetainedKinds {
        let identity = try objectIdentity(type: "com.keyrecord.\(kind)", "opaque-fixture")
        retained.append(try await store.put(identity: identity, payload: resetOpaquePayload))
    }
    return retained
}

func resetHashes(_ entries: [ManifestEntry], root: URL) throws -> [String: Data] {
    try Dictionary(uniqueKeysWithValues: entries.map {
        ($0.locator.fileName, ResetObjectHash.digest(try Data(contentsOf: root.appendingPathComponent($0.locator.fileName))))
    })
}

func assertReset(_ store: ObjectStore, next: CycleID) async throws {
    let decoder = JSONDecoder()
    let entries = try await store.entries()
    XCTAssertEqual(entries.filter { $0.identity == CycleResetObjects.currentCycle }.count, 1)
    XCTAssertEqual(entries.filter { $0.identity.objectType == "com.keyrecord.cycleSummary" }.count, 1)
    XCTAssertTrue(entries.filter { $0.identity.objectType == CanonicalLogicalIdentity.shardObjectType }.isEmpty)
    XCTAssertFalse(entries.contains { $0.identity == CycleResetObjects.journal })
    let current = try await decoder.decode(CycleRecord.self, from: store.read(CycleResetObjects.currentCycle))
    XCTAssertEqual(current.cycleID, next)
    XCTAssertTrue(current.isCurrent)
    XCTAssertEqual(current.index.value, 2)
    let preferences = try await decoder.decode(Preferences.self, from: store.read(CycleResetObjects.preferences))
    XCTAssertEqual(preferences.currentCycleID, next)
    XCTAssertTrue(preferences.expectedCollecting)
    let bytes = try await store.read(CycleResetObjects.summary(resetOldCycle))
    let summary = try decoder.decode(CycleSummary.self, from: bytes)
    XCTAssertEqual(summary.cycleID, resetOldCycle)
    XCTAssertEqual(summary.perBareKeyTotals, try [KeyCode(0): Count(6)])
    XCTAssertEqual(Array(summary.perChordTotals.values), try [Count(6)])
    XCTAssertEqual(summary.perChordTotals.keys.first?.chord.keyCode, try KeyCode(12))
    XCTAssertEqual(summary.perChordTotals.keys.first?.appBucket, .unknown)
    XCTAssertEqual(summary.distinctActiveDays.value, try Count(2))
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), ["schemaVersion", "cycleID", "perChordTotals", "perBareKeyTotals", "distinctActiveDays"])
}

@MainActor
final class CycleResetTests: XCTestCase {
    func testResetRetainsOpaqueObjectsAndOnlyApprovedSummary() async throws {
        // Given: multiple daily shards and opaque retained backend objects.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        let retained = try await seedReset(store)
        let before = try resetHashes(retained, root: fixture.root)
        // When: the current cycle is reset.
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        // Then: only approved totals survive, with one new current cycle.
        try await assertReset(store, next: next)
        XCTAssertEqual(next, CycleResetIdentifiers.newCycleID(operationID: resetOperation))
        XCTAssertEqual(try resetHashes(retained, root: fixture.root), before)
    }

    func testRepeatedOperationReturnsOriginalCycleAfterReopen() async throws {
        // Given: a completed reset persisted to disk.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        _ = try await seedReset(store)
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        let reopened = fixture.makeStore()
        _ = try await reopened.bootstrap()
        // When: the same operation is delivered again with a different day.
        let repeated = try await reopened.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-14"))
        // Then: no second cycle or summary is created.
        XCTAssertEqual(repeated, next)
        try await assertReset(reopened, next: next)
    }

    func testSecondInProcessCallWithSameOperationConverges() async throws {
        // Given: a completed reset.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        let retained = try await seedReset(store)
        let before = try resetHashes(retained, root: fixture.root)
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        // When: the identical request is delivered twice more.
        let second = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-14"))
        let third = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-15"))
        // Then: every call converges to the same cycle without extra writes.
        XCTAssertEqual(second, next)
        XCTAssertEqual(third, next)
        try await assertReset(store, next: next)
        XCTAssertEqual(try resetHashes(retained, root: fixture.root), before)
    }

    func testResetKeepsPausedExpectedCollectingFalse() async throws {
        // Given: a paused cycle (expectedCollecting false).
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        _ = try await seedReset(store)
        _ = try await store.put(identity: CycleResetObjects.preferences,
            payload: JSONEncoder().encode(Preferences(currentCycleID: resetOldCycle, expectedCollecting: false)))
        // When: the cycle is reset.
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        // Then: the collection gate expectation is preserved verbatim.
        let preferences = try await JSONDecoder().decode(
            Preferences.self, from: store.read(CycleResetObjects.preferences))
        XCTAssertEqual(preferences.currentCycleID, next)
        XCTAssertFalse(preferences.expectedCollecting)
    }

    func testResetWithoutPreferencesOrCurrentCycleRejects() async throws {
        // Given: an empty fresh store.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        // When/Then: reset names the missing prerequisite instead of guessing.
        do {
            _ = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
            XCTFail("expected missingCurrentCycle")
        } catch ObjectStoreError.reset(.missingCurrentCycle) {}
        _ = try await store.put(identity: CycleResetObjects.currentCycle,
            payload: JSONEncoder().encode(CycleRecord(cycleID: resetOldCycle, index: Count(1),
                createdDay: LocalDay("2026-09-11"), closedDay: nil, isCurrent: true)))
        do {
            _ = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
            XCTFail("expected missingPreferences")
        } catch ObjectStoreError.reset(.missingPreferences) {}
    }

    func testEmptyCycleResetWritesSummaryWithZeroTotalsAndDeletesNoShards() async throws {
        // Given: a cycle with preferences/current record but no daily shards.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        _ = try await store.put(identity: CycleResetObjects.preferences,
            payload: JSONEncoder().encode(Preferences(currentCycleID: resetOldCycle, expectedCollecting: true)))
        _ = try await store.put(identity: CycleResetObjects.currentCycle,
            payload: JSONEncoder().encode(CycleRecord(cycleID: resetOldCycle, index: Count(3),
                createdDay: LocalDay("2026-09-11"), closedDay: nil, isCurrent: true)))
        // When: it is reset.
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        // Then: the summary exists with zero totals and the index advances.
        let summary = try await JSONDecoder().decode(
            CycleSummary.self, from: store.read(CycleResetObjects.summary(resetOldCycle)))
        XCTAssertEqual(summary.perChordTotals, [:])
        XCTAssertEqual(summary.perBareKeyTotals, [:])
        XCTAssertEqual(summary.distinctActiveDays.value, try Count(0))
        let current = try await JSONDecoder().decode(
            CycleRecord.self, from: store.read(CycleResetObjects.currentCycle))
        XCTAssertEqual(current.cycleID, next)
        XCTAssertEqual(current.index.value, 4)
    }
}

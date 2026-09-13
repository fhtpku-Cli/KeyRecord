import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class CycleResetJournalFailureTests: XCTestCase {
    private func interruptReset(
        _ store: ObjectStore, injection: CycleResetInjection
    ) async throws {
        do {
            _ = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"),
                                           injection: injection)
            XCTFail("expected injected failure")
        } catch ObjectStoreError.filesystem {}
    }

    private func pendingJournalURL(fixture: StoreHarness) async throws -> URL {
        let material = try await fixture.keySource.material(for: v1)
        let locator = try CycleResetJournalStore(root: fixture.root)
            .expectedLocator(version: 1, material: material)
        return fixture.root.appendingPathComponent(locator.fileName)
    }

    func testMalformedPendingJournalFailsClosedWithoutTouchingData() async throws {
        // Given: a prepared journal whose envelope was corrupted on disk.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        let retained = try await seedReset(store)
        let before = try resetHashes(retained, root: fixture.root)
        try await interruptReset(store, injection: CycleResetInjection(
            summaryWrite: DurabilityInjection(failPhase: .data, failAt: .afterRename)))
        let journal = try await pendingJournalURL(fixture: fixture)
        try Data("tampered-journal".utf8).write(to: journal)
        // When: the store reopens and retries the operation.
        let reopened = fixture.makeStore()
        let state = try await reopened.bootstrap()
        XCTAssertEqual(state, .opened, "corrupt journal is protected, not treated as missing manifest")
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        do {
            _ = try await reopened.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
            XCTFail("expected resetJournalUnreadable")
        } catch ObjectStoreError.corruption(.resetJournalUnreadable) {}
        // Then: no detail was deleted, no summary appeared, retained bytes are untouched.
        let entries = try await reopened.entries()
        XCTAssertEqual(entries.filter { $0.identity.objectType == CanonicalLogicalIdentity.shardObjectType }.count, 4)
        XCTAssertFalse(entries.contains { $0.identity.objectType == "com.keyrecord.cycleSummary" })
        XCTAssertEqual(try resetHashes(retained, root: fixture.root), before)
        let current = try await JSONDecoder().decode(
            CycleRecord.self, from: reopened.read(CycleResetObjects.currentCycle))
        XCTAssertEqual(current.cycleID, resetOldCycle)
    }

    func testDifferentOperationRejectedUntilOriginalConverges() async throws {
        // Given: an interrupted reset for the fixed operation.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        _ = try await seedReset(store)
        try await interruptReset(store, injection: CycleResetInjection(
            summaryWrite: DurabilityInjection(failPhase: .manifest, failAt: .afterWrite)))
        // When: a different reset operation arrives.
        let other = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        do {
            _ = try await store.resetCycle(operationID: other, day: LocalDay("2026-09-13"))
            XCTFail("expected conflictingOperation")
        } catch ObjectStoreError.reset(.conflictingOperation) {}
        // Then: retrying the original operation converges normally.
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        try await assertReset(store, next: next)
    }

    func testInjectedInterruptionsAtEveryStageConvergeOnRetry() async throws {
        // Given: interruptions between/at every durable stage.
        let cases: [String: CycleResetInjection] = [
            "summary-temp": CycleResetInjection(
                summaryWrite: DurabilityInjection(failPhase: .data, failAt: .afterWrite)),
            "summary-manifest": CycleResetInjection(
                summaryWrite: DurabilityInjection(failPhase: .manifest, failAt: .afterRename)),
            "details-manifest": CycleResetInjection(
                detailDelete: DurabilityInjection(failPhase: .manifest, failAt: .afterRename)),
            "cycle-manifest": CycleResetInjection(
                cycleWrite: DurabilityInjection(failPhase: .manifest, failAt: .afterRename)),
            "preferences-data": CycleResetInjection(
                cycleWrite: DurabilityInjection(failPhase: .data, failAt: .afterRename)),
            "journal-clear": CycleResetInjection(
                journalClear: DurabilityInjection(failPhase: .cleanup, failAt: .afterRename)),
        ]
        for (label, injection) in cases {
            let fixture = try StoreHarness()
            defer { fixture.cleanup() }
            let store = try await fixture.bootFresh()
            let retained = try await seedReset(store)
            let before = try resetHashes(retained, root: fixture.root)
            try await interruptReset(store, injection: injection)
            // When: the identical operation retries on a reopened store.
            let reopened = fixture.makeStore()
            _ = try await reopened.bootstrap()
            let next = try await reopened.resetCycle(operationID: resetOperation,
                                                     day: LocalDay("2026-09-13"))
            // Then: one current cycle, one summary, no details, retained bytes unchanged.
            try await assertReset(reopened, next: next)
            XCTAssertEqual(try resetHashes(retained, root: fixture.root), before, label)
        }
    }

    func testForeignCycleShardRejectsReset() async throws {
        // Given: a daily shard that claims a different cycle than the current record.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        _ = try await store.put(identity: CycleResetObjects.preferences,
            payload: JSONEncoder().encode(Preferences(currentCycleID: resetOldCycle, expectedCollecting: true)))
        _ = try await store.put(identity: CycleResetObjects.currentCycle,
            payload: JSONEncoder().encode(CycleRecord(cycleID: resetOldCycle, index: Count(1),
                createdDay: LocalDay("2026-09-11"), closedDay: nil, isCurrent: true)))
        let rows = try [DailyBareKeyAggregate(cycleID: CycleID(rawValue: "intruder-cycle"),
            day: LocalDay("2026-09-11"), keyCode: KeyCode(0),
            sourceCounts: SourceCounts(ordinary: Count(1), suspectedInjection: Count(0)))]
        _ = try await store.put(
            identity: .shard(cycleID: "intruder-cycle", dayKey: "2026-09-11", aggregateType: "bareKey"),
            payload: JSONEncoder().encode(rows))
        // When/Then: the mismatch fails closed and deletes nothing.
        do {
            _ = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
            XCTFail("expected shardCycleMismatch")
        } catch ObjectStoreError.reset(.shardCycleMismatch) {}
        let entries = try await store.entries()
        XCTAssertEqual(entries.count, 3)
    }

    func testRetainedObjectLostAfterSnapshotFailsReset() async throws {
        // Given: a prepared journal and a retained object removed before resume.
        let fixture = try StoreHarness()
        defer { fixture.cleanup() }
        let store = try await fixture.bootFresh()
        _ = try await seedReset(store)
        try await interruptReset(store, injection: CycleResetInjection(
            summaryWrite: DurabilityInjection(failPhase: .data, failAt: .afterRename)))
        let reopened = fixture.makeStore()
        _ = try await reopened.bootstrap()
        // When: a mapping retained object disappears, then the operation retries.
        let mappingIdentity = try objectIdentity(type: "com.keyrecord.mapping", "opaque-fixture")
        try await reopened.delete(mappingIdentity)
        do {
            _ = try await reopened.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
            XCTFail("expected retainedObjectsChanged")
        } catch ObjectStoreError.reset(.retainedObjectsChanged) {}
    }
}

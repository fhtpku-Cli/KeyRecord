import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

extension CaptureQueueTests {
    func testBackendRevokedPermissionDrainsAndResetsWithoutPublication() async throws {
        try await assertBackendInvalidationDrains(.permissionRevoked)
    }

    func testBackendSleepDispatchDrainsAndResetsWithoutPublication() async throws {
        try await assertBackendInvalidationDrains(.sleep)
    }

    func testBackendTapDisabledDispatchDrainsAndResetsWithoutPublication() async throws {
        try await assertBackendInvalidationDrains(.tapDisabled)
    }

    func testQueuedEventsCannotPublishAfterLockedOrUnknownLock() async throws {
        for lock in [SessionLockState.locked, .unknown] {
            let (queue, backend, event) = try await preparedQueueWithHeldAndPendingEvents()
            backend.changeLock(lock)
            assertDrained(queue, old: event)
            await backend.stop()
        }
    }

    func testCachedProviderDriftBeforeDeliveryDrainsWithoutNotification() async throws {
        let (queue, backend, event) = try await preparedQueueWithHeldAndPendingEvents()
        backend.report(.foregroundChanged, notify: false)
        XCTAssertFalse(queue.deliverOne(current: { backend.cachedProviders() }) { _ in
            XCTFail("provider drift published before notification")
            return .accepted
        })
        assertDrained(queue, old: event)
        await backend.stop()
    }

    private func assertBackendInvalidationDrains(_ reason: CaptureInvalidation) async throws {
        let (queue, backend, event) = try await preparedQueueWithHeldAndPendingEvents()
        backend.report(reason)
        assertDrained(queue, old: event)
        await backend.stop()
    }

    private func preparedQueueWithHeldAndPendingEvents() async throws -> (CaptureQueue, CaptureTestBackend, ObservedKeyEvent) {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let expected = queue.snapshot
        queue.revoke()
        let backend = CaptureTestBackend(queue: queue)
        _ = try await CaptureControl.prepare(queue: queue, expected: expected, backend: backend)
        let held = ObservedKeyEvent(keyCode: try KeyCode(55), kind: .flagsChanged,
            isAutoRepeat: false, modifiers: ModifierSet(command: .left),
            source: .ordinaryObserved, generation: queue.generation)
        XCTAssertEqual(queue.handoff(held), .accepted)
        _ = queue.reduceOne()
        XCTAssertEqual(queue.modifiers.command, .left)
        let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown,
            isAutoRepeat: false, modifiers: ModifierSet(command: .left),
            source: .ordinaryObserved, generation: queue.generation)
        XCTAssertEqual(queue.handoff(event), .accepted)
        XCTAssertEqual(queue.handoff(event), .accepted)
        XCTAssertEqual(queue.pendingCount, 2)
        return (queue, backend, event)
    }

    private func assertDrained(_ queue: CaptureQueue, old: ObservedKeyEvent) {
        XCTAssertFalse(queue.isOpen)
        XCTAssertNotEqual(queue.generation, old.generation)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.modifiers, ModifierSet())
        XCTAssertFalse(queue.deliverOne { _ in XCTFail("queued stale event published"); return .accepted })
        queue.install(.safe, for: queue.generation)
        XCTAssertEqual(queue.handoff(old), .closed)
        XCTAssertFalse(queue.deliverOne { _ in XCTFail("old generation published after reopen"); return .accepted })
    }
}

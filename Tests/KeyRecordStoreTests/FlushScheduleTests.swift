import XCTest
@testable import KeyRecordStore
import KeyRecordCore

final class FlushScheduleTests: XCTestCase {
    func testCoalescesDirtyRevisionsWhenOneSecondElapses() throws {
        // Given
        var schedule = FlushSchedule()
        schedule.reopen(generation: CaptureGeneration(rawValue: 1), now: .zero)
        schedule.markDirty()
        schedule.markDirty()
        // When
        let early = schedule.start(now: .milliseconds(999))
        let due = schedule.start(now: .seconds(1))
        // Then
        XCTAssertNil(early)
        XCTAssertEqual(due?.revision, 2)
    }

    func testDelayedTriggerStartsOnlyOneWriteWhenManyTicksWereMissed() {
        // Given
        var schedule = FlushSchedule()
        schedule.reopen(generation: CaptureGeneration(rawValue: 1), now: .zero)
        schedule.markDirty()
        // When
        let first = schedule.start(now: .seconds(20))
        let second = schedule.start(now: .seconds(20))
        // Then
        XCTAssertNotNil(first)
        XCTAssertNil(second)
    }

    func testCloseDiscardsPendingAndRejectsCompletionWhenGenerationReopens() throws {
        // Given
        var schedule = FlushSchedule()
        schedule.reopen(generation: CaptureGeneration(rawValue: 1), now: .zero)
        schedule.markDirty()
        let ticket = try XCTUnwrap(schedule.start(now: .seconds(1)))
        schedule.close()
        schedule.reopen(generation: CaptureGeneration(rawValue: 3), now: .seconds(2))
        // When
        let published = schedule.complete(ticket, result: .saved)
        // Then
        XCTAssertFalse(published)
        XCTAssertEqual(schedule.durableRevision, 0)
        XCTAssertNil(schedule.start(now: .seconds(3)))
    }

    func testFailureDoesNotClaimSavedWhenWriterFails() throws {
        // Given
        var schedule = FlushSchedule()
        schedule.reopen(generation: CaptureGeneration(rawValue: 1), now: .zero)
        schedule.markDirty()
        let ticket = try XCTUnwrap(schedule.start(now: .seconds(1)))
        // When
        _ = schedule.complete(ticket, result: .failed)
        // Then
        XCTAssertEqual(schedule.durableRevision, 0)
        XCTAssertNotNil(schedule.start(now: .seconds(2)))
    }

    func testPendingDeltaSurvivesWhenEarlierWriteCompletes() throws {
        // Given
        var schedule = FlushSchedule()
        schedule.reopen(generation: CaptureGeneration(rawValue: 1), now: .zero)
        schedule.markDirty()
        let ticket = try XCTUnwrap(schedule.start(now: .seconds(1)))
        schedule.markDirty()
        // When
        _ = schedule.complete(ticket, result: .saved)
        // Then
        XCTAssertEqual(schedule.durableRevision, 1)
        XCTAssertEqual(schedule.start(now: .seconds(2))?.revision, 2)
    }

    func testExplicitFlushBypassesCadenceWhenPauseRequestsCompletion() {
        // Given
        var schedule = FlushSchedule()
        schedule.reopen(generation: CaptureGeneration(rawValue: 1), now: .zero)
        schedule.markDirty()
        // When
        let ticket = schedule.start(now: .milliseconds(1), force: true)
        // Then
        XCTAssertNotNil(ticket)
    }
}

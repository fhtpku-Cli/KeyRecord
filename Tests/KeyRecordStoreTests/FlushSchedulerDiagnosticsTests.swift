import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

private actor DiagnosticFlushWriter: FlushWriting {
    let result: Result<Void, any Error>

    init(result: Result<Void, any Error>) {
        self.result = result
    }

    func write(_ objects: [FlushObject], generation: CaptureGeneration) async throws {
        try result.get()
    }
}

private actor SuspendedDiagnosticFlushWriter: FlushWriting {
    private(set) var returned = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private let started: XCTestExpectation
    private let result: Result<Void, any Error>

    init(started: XCTestExpectation, result: Result<Void, any Error> = .success(())) {
        self.started = started
        self.result = result
    }

    func write(_ objects: [FlushObject], generation: CaptureGeneration) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
        returned += 1
        try result.get()
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private final class DiagnosticTimeoutClock: FlushClock, @unchecked Sendable {
    private let lock = NSLock()
    private var sleeper: CheckedContinuation<Void, any Error>?
    private let scheduled: XCTestExpectation

    init(scheduled: XCTestExpectation) {
        self.scheduled = scheduled
    }

    func now() -> Duration { .zero }

    func sleep(until deadline: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                sleeper = continuation
                scheduled.fulfill()
            }
        }
    }

    func expire() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            defer { sleeper = nil }
            return sleeper
        }
        continuation?.resume()
    }
}

@MainActor
final class FlushSchedulerDiagnosticsTests: XCTestCase {
    func testSuspendedWriteHasAnAccountedOutcomeAfterSuccessfulPhysicalReturn() async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let recorder = CaptureDiagnosticsRecorder()
        let writeStarted = expectation(description: "physical write started")
        let writer = SuspendedDiagnosticFlushWriter(started: writeStarted)
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        await scheduler.setDiagnostics(recorder)
        try await scheduler.reopen()
        try await scheduler.stage([])

        let completion = Task { await scheduler.completion() }
        await fulfillment(of: [writeStarted], timeout: 1)
        await scheduler.suspend()
        await scheduler.suspend()
        let result = await completion.value
        XCTAssertEqual(result, .locked)
        let beforeReturn = await writer.returned
        XCTAssertEqual(beforeReturn, 0)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 0)
        XCTAssertEqual(recorder.runSummary.flushWriteSucceeded, 0)
        XCTAssertEqual(recorder.runSummary.flushInvalidated, 1)
        await writer.release()
        await scheduler.waitForIssuedWrite()

        let returned = await writer.returned
        XCTAssertEqual(returned, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteSucceeded, 1)
        XCTAssertEqual(recorder.runSummary.flushInvalidated, 1)
        let saved = await scheduler.result()
        XCTAssertNil(saved, "An invalidated completion must not acknowledge the closed session")
        let snapshot = recorder.runSummary
        XCTAssertEqual(snapshot.flushIssued, 1)
        XCTAssertEqual(snapshot.flushDurable, 0)
        XCTAssertEqual(snapshot.flushIssued,
                       snapshot.flushDurable + snapshot.flushFailed + snapshot.flushTimedOut + snapshot.flushInvalidated,
                       "A returned physical write must have an explicit accounted logical outcome")
    }

    func testReopenedGenerationCountsOldReturnAsInvalidatedWithoutAcknowledgingIt() async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let recorder = CaptureDiagnosticsRecorder()
        let writeStarted = expectation(description: "old generation writer started")
        let writer = SuspendedDiagnosticFlushWriter(started: writeStarted)
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        await scheduler.setDiagnostics(recorder)
        try await scheduler.reopen()
        try await scheduler.stage([])
        let oldCompletion = Task { await scheduler.completion() }
        await fulfillment(of: [writeStarted], timeout: 1)

        try await scheduler.reopen()
        try await scheduler.stage([])
        let oldResult = await oldCompletion.value
        XCTAssertEqual(oldResult, .locked)
        XCTAssertEqual(recorder.runSummary.flushInvalidated, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 0)
        await writer.release()
        await scheduler.waitForIssuedWrite()

        let pending = await scheduler.hasPendingChanges()
        let published = await scheduler.result()
        XCTAssertTrue(pending, "Old completion cannot save the new generation's staged revision")
        XCTAssertNil(published)
        XCTAssertEqual(recorder.runSummary.flushIssued, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteSucceeded, 1)
        XCTAssertEqual(recorder.runSummary.flushDurable, 0)
        XCTAssertEqual(recorder.runSummary.flushInvalidated, 1)
    }

    func testGateRevocationAfterWriteStartCountsInvalidatedReturnWithoutSaving() async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let recorder = CaptureDiagnosticsRecorder()
        let writeStarted = expectation(description: "writer started before revocation")
        let writer = SuspendedDiagnosticFlushWriter(started: writeStarted)
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        await scheduler.setDiagnostics(recorder)
        try await scheduler.reopen()
        try await scheduler.stage([])
        let completion = Task { await scheduler.completion() }
        await fulfillment(of: [writeStarted], timeout: 1)

        gate.update(.locked)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 0)
        await writer.release()
        await scheduler.waitForIssuedWrite()
        let result = await completion.value

        XCTAssertEqual(result, .locked)
        XCTAssertEqual(recorder.runSummary.flushIssued, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteSucceeded, 1)
        XCTAssertEqual(recorder.runSummary.flushDurable, 0)
        XCTAssertEqual(recorder.runSummary.flushFailed, 0)
        XCTAssertEqual(recorder.runSummary.flushInvalidated, 1)
    }

    func testThrownWriteAfterSuspendIsReturnedButNotSuccessfulOrDoubleCounted() async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let recorder = CaptureDiagnosticsRecorder()
        let writeStarted = expectation(description: "writer started before suspend")
        let writer = SuspendedDiagnosticFlushWriter(started: writeStarted,
                                                    result: .failure(LifecycleFlushError.failed))
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        await scheduler.setDiagnostics(recorder)
        try await scheduler.reopen()
        try await scheduler.stage([])
        let completion = Task { await scheduler.completion() }
        await fulfillment(of: [writeStarted], timeout: 1)

        await scheduler.suspend()
        await writer.release()
        await scheduler.waitForIssuedWrite()
        let result = await completion.value

        XCTAssertEqual(result, .locked)
        XCTAssertEqual(recorder.runSummary.flushIssued, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 1)
        XCTAssertEqual(recorder.runSummary.flushWriteSucceeded, 0)
        XCTAssertEqual(recorder.runSummary.flushDurable, 0)
        XCTAssertEqual(recorder.runSummary.flushFailed, 0)
        XCTAssertEqual(recorder.runSummary.flushInvalidated, 1)
    }

    func testSavedWriteIncrementsIssuedAndDurableExactlyOnce() async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let recorder = CaptureDiagnosticsRecorder()
        let scheduler = FlushScheduler(
            gate: gate,
            writer: DiagnosticFlushWriter(result: .success(())),
            clock: SystemFlushClock())
        await scheduler.setDiagnostics(recorder)
        try await scheduler.reopen()
        try await scheduler.stage([])

        let completion = await scheduler.completion()
        XCTAssertEqual(completion, .saved)

        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.flushIssued, 1)
        XCTAssertEqual(snapshot.flushDurable, 1)
        XCTAssertEqual(snapshot.flushWriteReturned, 1)
        XCTAssertEqual(snapshot.flushWriteSucceeded, 1)
        XCTAssertEqual(snapshot.flushInvalidated, 0)
        XCTAssertEqual(snapshot.flushFailed, 0)
        XCTAssertEqual(snapshot.flushTimedOut, 0)
        try await scheduler.stage([])
        let second = await scheduler.completion()
        XCTAssertEqual(second, .saved)
        XCTAssertEqual(recorder.runSummary.flushIssued, 2)
        XCTAssertEqual(recorder.runSummary.flushDurable, 2)
        XCTAssertEqual(recorder.runSummary.flushWriteReturned, 2)
        XCTAssertEqual(recorder.runSummary.flushWriteSucceeded, 2)
    }

    func testFailedWriteIncrementsFailedExactlyOnce() async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let recorder = CaptureDiagnosticsRecorder()
        let scheduler = FlushScheduler(
            gate: gate,
            writer: DiagnosticFlushWriter(result: .failure(LifecycleFlushError.failed)),
            clock: SystemFlushClock())
        await scheduler.setDiagnostics(recorder)
        try await scheduler.reopen()
        try await scheduler.stage([])

        let completion = await scheduler.completion()
        XCTAssertEqual(completion, .failed)

        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.flushIssued, 1)
        XCTAssertEqual(snapshot.flushDurable, 0)
        XCTAssertEqual(snapshot.flushFailed, 1)
        XCTAssertEqual(snapshot.flushWriteReturned, 1)
        XCTAssertEqual(snapshot.flushWriteSucceeded, 0)
        XCTAssertEqual(snapshot.flushInvalidated, 0)
        XCTAssertEqual(snapshot.flushTimedOut, 0)
    }

    func testExpiredWriteIncrementsTimeoutOnlyAtTheAcceptedExpiry() async throws {
        try await assertExpiredWriteAccounting(closeBeforeReturn: false)
    }

    func testCloseAfterTimeoutDoesNotCountTheSameWriteAsInvalidated() async throws {
        try await assertExpiredWriteAccounting(closeBeforeReturn: true)
    }

    private func assertExpiredWriteAccounting(closeBeforeReturn: Bool) async throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let recorder = CaptureDiagnosticsRecorder()
        let writeStarted = expectation(description: "physical write started")
        let timeoutScheduled = expectation(description: "timeout scheduled")
        let writer = SuspendedDiagnosticFlushWriter(started: writeStarted)
        let clock = DiagnosticTimeoutClock(scheduled: timeoutScheduled)
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: clock)
        await scheduler.setDiagnostics(recorder)
        try await scheduler.reopen()
        try await scheduler.stage([])

        let completion = Task { await scheduler.completion() }
        await fulfillment(of: [writeStarted, timeoutScheduled], timeout: 1)
        clock.expire()
        let result = await completion.value
        XCTAssertEqual(result, .timedOut)

        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.flushIssued, 1)
        XCTAssertEqual(snapshot.flushDurable, 0)
        XCTAssertEqual(snapshot.flushFailed, 0)
        XCTAssertEqual(snapshot.flushTimedOut, 1)
        XCTAssertEqual(snapshot.flushWriteReturned, 0)
        XCTAssertEqual(snapshot.flushWriteSucceeded, 0)
        XCTAssertEqual(snapshot.flushInvalidated, 0)
        if closeBeforeReturn { await scheduler.close() }
        await writer.release()
        await scheduler.waitForIssuedWrite()
        XCTAssertEqual(recorder.snapshot.flushTimedOut, 1)
        XCTAssertEqual(recorder.snapshot.flushWriteReturned, 1)
        XCTAssertEqual(recorder.snapshot.flushWriteSucceeded, 1)
        XCTAssertEqual(recorder.snapshot.flushDurable, 0)
        XCTAssertEqual(recorder.snapshot.flushInvalidated, 0)
    }
}

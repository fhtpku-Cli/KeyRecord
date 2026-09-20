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
    private var continuation: CheckedContinuation<Void, Never>?
    private let started: XCTestExpectation

    init(started: XCTestExpectation) {
        self.started = started
    }

    func write(_ objects: [FlushObject], generation: CaptureGeneration) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
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
        XCTAssertEqual(snapshot.flushFailed, 0)
        XCTAssertEqual(snapshot.flushTimedOut, 0)
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
        XCTAssertEqual(snapshot.flushTimedOut, 0)
    }

    func testExpiredWriteIncrementsTimeoutOnlyAtTheAcceptedExpiry() async throws {
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
        await writer.release()
        await scheduler.waitForIssuedWrite()
        XCTAssertEqual(recorder.snapshot.flushTimedOut, 1)
    }
}

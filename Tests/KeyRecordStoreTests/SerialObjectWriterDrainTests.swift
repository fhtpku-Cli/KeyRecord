import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

private actor DrainPhysicalWriter: FlushWriting {
    private var pending: CheckedContinuation<Void, Never>?
    let started: XCTestExpectation
    init(started: XCTestExpectation) { self.started = started }
    func write(_ objects: [FlushObject], generation: CaptureGeneration) async {
        await withCheckedContinuation {
            pending = $0
            started.fulfill()
        }
    }
    func release() { pending?.resume(); pending = nil }
}

// The lock protects registration, cancellation and manual expiry as one transition.
private final class DrainClock: FlushClock, @unchecked Sendable {
    private let lock = NSLock()
    private var sleepers: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var registrations = 0
    private var expired = false
    let admitted: XCTestExpectation
    init(admitted: XCTestExpectation) { self.admitted = admitted }
    func now() -> Duration { .zero }
    var counts: (active: Int, total: Int) { lock.withLock { (sleepers.count, registrations) } }
    func sleep(until deadline: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                    registrations += 1
                    if expired { continuation.resume() }
                    else { sleepers[id] = continuation }
                    if registrations <= admitted.expectedFulfillmentCount { admitted.fulfill() }
                }
            }
        } onCancel: {
            self.lock.withLock { self.sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }
    func expire() {
        lock.withLock {
            expired = true
            let current = sleepers
            sleepers.removeAll()
            for continuation in current.values { continuation.resume() }
        }
    }
}

@MainActor
final class SerialObjectWriterDrainTests: XCTestCase {
    func testExcessDrainsFailWithoutAllocatingTimersWhenCapacityIsFull() async throws {
        // Given: physical completion and the timeout clock are both suspended.
        let started = expectation(description: "physical write started")
        let admitted = expectation(description: "32 timers registered")
        admitted.expectedFulfillmentCount = 32
        let rejected = expectation(description: "8 excess callers finished")
        rejected.expectedFulfillmentCount = 8
        rejected.assertForOverFulfill = true
        let clock = DrainClock(admitted: admitted)
        let physical = DrainPhysicalWriter(started: started)
        let writer = SerialObjectWriter(writer: physical, clock: clock)
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let generation = try gate.begin()
        let write = Task { try await writer.write([], generation: generation) }
        await fulfillment(of: [started], timeout: 2)
        // When: 40 drains overlap without advancing time or releasing the writer.
        let callers = (0..<40).map { _ in Task {
            let result = await writer.suspendAndDrain()
            if result == .failed { rejected.fulfill() }
            return result
        } }
        await fulfillment(of: [admitted, rejected], timeout: 2)
        // Then: both retained continuations and timer allocations are bounded.
        let retained = await writer.drainCount
        XCTAssertEqual(retained, 32)
        XCTAssertEqual(clock.counts.active, 32)
        XCTAssertEqual(clock.counts.total, 32)
        await physical.release()
        try await write.value
        var saved = 0
        var failed = 0
        for caller in callers {
            switch await caller.value {
            case .saved: saved += 1
            case .failed: failed += 1
            case .locked, .timedOut: XCTFail("Unexpected drain result")
            }
        }
        XCTAssertEqual(saved, 32)
        XCTAssertEqual(failed, 8)
        let remaining = await writer.drainCount
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(clock.counts.active, 0)
    }

    func testAcceptedDrainsFinishExactlyOnceWhenPhysicalWriteCompletes() async throws {
        try await exerciseCleanup(.completion)
    }

    func testTimeoutReleasesDrainsButKeepsPhysicalWriterFailClosed() async throws {
        try await exerciseCleanup(.timeout)
    }

    func testCancelledCallersReleaseDrainsWithoutWaitingForPhysicalWrite() async throws {
        try await exerciseCleanup(.cancellation)
    }

    private enum Finish { case completion, timeout, cancellation }

    private func exerciseCleanup(_ finish: Finish) async throws {
        // Given: 32 accepted drains, each with a registered manual timer.
        let started = expectation(description: "physical write started")
        let admitted = expectation(description: "timers registered")
        admitted.expectedFulfillmentCount = 32
        let finished = expectation(description: "each caller finished once")
        finished.expectedFulfillmentCount = 32
        finished.assertForOverFulfill = true
        let clock = DrainClock(admitted: admitted)
        let physical = DrainPhysicalWriter(started: started)
        let writer = SerialObjectWriter(writer: physical, clock: clock)
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let generation = try gate.begin()
        let write = Task { try await writer.write([], generation: generation) }
        await fulfillment(of: [started], timeout: 2)
        let callers = (0..<32).map { _ in Task {
            let result = await writer.suspendAndDrain()
            finished.fulfill()
            return result
        } }
        await fulfillment(of: [admitted], timeout: 2)
        // When: one terminal event wins for every accepted caller.
        let expected: FlushCompletion
        switch finish {
        case .completion: expected = .saved; await physical.release(); try await write.value
        case .timeout: expected = .timedOut; clock.expire()
        case .cancellation: expected = .failed; for caller in callers { caller.cancel() }
        }
        await fulfillment(of: [finished], timeout: 2)
        // Then: cleanup is immediate, but only physical completion permits resume.
        let remaining = await writer.drainCount
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(clock.counts.active, 0)
        switch finish {
        case .completion: break
        case .timeout, .cancellation:
            do { try await writer.resume(); XCTFail("Outstanding physical write allowed resume") }
            catch LifecycleFlushError.timedOut {}
            await physical.release()
            try await write.value
        }
        for caller in callers { let result = await caller.value; XCTAssertEqual(result, expected) }
        // Losing terminal events must not resume any continuation a second time.
        clock.expire()
        for caller in callers { caller.cancel() }
        try await writer.resume()
        let settled = await writer.suspendAndDrain()
        XCTAssertEqual(settled, .saved)
        let retained = await writer.drainCount
        XCTAssertEqual(retained, 0)
        XCTAssertEqual(clock.counts.active, 0)
    }
}

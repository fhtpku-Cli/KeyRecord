import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

private actor SuspendedCapacityWriter: FlushWriting {
    var continuation: CheckedContinuation<Void, Never>?
    let started: XCTestExpectation
    init(started: XCTestExpectation) { self.started = started }
    func write(_ objects: [FlushObject], generation: CaptureGeneration) async {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class FlushCapacityTests: XCTestCase {
    func testExcessCompletionWaitersFailBeforeWriterReturns() async throws {
        // Given: a dirty scheduler whose physical writer cannot complete.
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let started = expectation(description: "writer started")
        let rejected = expectation(description: "excess callers rejected")
        rejected.expectedFulfillmentCount = 8
        let writer = SuspendedCapacityWriter(started: started)
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        try await scheduler.reopen()
        try await scheduler.stage([])
        // When: forty callers request confirmation concurrently.
        let callers = (0..<40).map { _ in Task {
            let result = await scheduler.completion()
            if result == .failed { rejected.fulfill() }
            return result
        } }
        await fulfillment(of: [started, rejected], timeout: 2)
        // Then: only 32 continuations remain and every admitted caller completes.
        let retained = await scheduler.waiterCount
        XCTAssertEqual(retained, 32)
        await writer.release()
        var saved = 0
        for caller in callers { if await caller.value == .saved { saved += 1 } }
        XCTAssertEqual(saved, 32)
        let remaining = await scheduler.waiterCount
        XCTAssertEqual(remaining, 0)
    }
}

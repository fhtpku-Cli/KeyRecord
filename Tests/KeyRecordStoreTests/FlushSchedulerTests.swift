import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

private actor RecordingFlushWriter: FlushWriting {
    private(set) var writes = 0
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func write(_ objects: [FlushObject], generation: CaptureGeneration) throws {
        if fails { throw LifecycleFlushError.failed }
        writes += 1
    }
}

@MainActor
final class FlushSchedulerTests: XCTestCase {
    func testSavedWhenWriterActuallyCompletes() async throws {
        // Given
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let writer = RecordingFlushWriter()
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        try await scheduler.reopen()
        try await scheduler.stage([])
        // When
        let result = await scheduler.completion()
        // Then
        XCTAssertEqual(result, .saved)
        let writes = await writer.writes
        XCTAssertEqual(writes, 1)
    }

    func testFailedWhenWriterThrows() async throws {
        // Given
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let scheduler = FlushScheduler(gate: gate, writer: RecordingFlushWriter(fails: true),
                                       clock: SystemFlushClock())
        try await scheduler.reopen()
        try await scheduler.stage([])
        // When
        let result = await scheduler.completion()
        // Then
        XCTAssertEqual(result, .failed)
    }

    func testLockedWhenPendingObjectsAreDiscarded() async throws {
        // Given
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let writer = RecordingFlushWriter()
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        try await scheduler.reopen()
        try await scheduler.stage([])
        // When
        await scheduler.close(.unknown)
        let result = await scheduler.completion()
        // Then
        XCTAssertEqual(result, .locked)
        let writes = await writer.writes
        XCTAssertEqual(writes, 0)
    }
}

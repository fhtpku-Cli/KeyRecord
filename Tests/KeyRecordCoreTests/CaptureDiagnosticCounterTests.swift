import XCTest
import KeyRecordCore

final class CaptureDiagnosticCounterTests: XCTestCase {

    func testIncrementRecordsExactCountsUnderConcurrentWriters() {
        // Given: one recorder for independent callback-path increments.
        let recorder = CaptureDiagnosticsRecorder()
        let iterations = 12_000

        // When: callbacks increment two closed counter cases concurrently.
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            recorder.increment(index.isMultiple(of: 2) ? .tapCallbackKeyDown : .handoffAccepted)
        }

        // Then: no increment is lost and the snapshot exposes only its mapped counters.
        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.tapCallbackKeyDown, iterations / 2)
        XCTAssertEqual(snapshot.handoffAccepted, iterations / 2)
        XCTAssertEqual(snapshot.tapCallbackKeyUp, 0)
        XCTAssertFalse(snapshot.countersInstrumented)
    }

    func testSnapshotMapsEveryClosedCounterCase() {
        // Given: a recorder and every permitted diagnostic counter.
        let recorder = CaptureDiagnosticsRecorder()

        // When: each case is incremented exactly once.
        for counter in CaptureDiagnosticCounter.allCases {
            recorder.increment(counter)
        }

        // Then: every pipeline field receives its matching numeric count.
        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.tapCallbackKeyDown, 1)
        XCTAssertEqual(snapshot.tapCallbackKeyUp, 1)
        XCTAssertEqual(snapshot.tapCallbackFlagsChanged, 1)
        XCTAssertEqual(snapshot.tapDisabledEvents, 1)
        XCTAssertEqual(snapshot.handoffAccepted, 1)
        XCTAssertEqual(snapshot.handoffClosed, 1)
        XCTAssertEqual(snapshot.handoffOverflow, 1)
        XCTAssertEqual(snapshot.normalizationOutput, 1)
        XCTAssertEqual(snapshot.aggregateDelta, 1)
        XCTAssertEqual(snapshot.flushIssued, 1)
        XCTAssertEqual(snapshot.flushDurable, 1)
        XCTAssertEqual(snapshot.flushFailed, 1)
        XCTAssertEqual(snapshot.flushTimedOut, 1)
    }

    func testCounterInstrumentationStateIsControlledByComposition() {
        let recorder = CaptureDiagnosticsRecorder()
        recorder.configureCounterInstrumentation()
        XCTAssertTrue(recorder.snapshot.countersInstrumented)
    }

    func testBeginSessionExcludesEarlierAtomicCountersFromItsSnapshot() {
        let recorder = CaptureDiagnosticsRecorder()
        recorder.increment(.tapCallbackKeyDown)

        recorder.beginSession(generation: 2)

        XCTAssertEqual(recorder.snapshot.tapCallbackKeyDown, 0)
        recorder.increment(.tapCallbackKeyDown)
        XCTAssertEqual(recorder.snapshot.tapCallbackKeyDown, 1)
    }
}

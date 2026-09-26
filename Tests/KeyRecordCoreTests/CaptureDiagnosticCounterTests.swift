import XCTest
import KeyRecordCore

final class CaptureDiagnosticCounterTests: XCTestCase {

    func testSecureInputIntervalEndsBeforeNewSessionCounters() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let recorder = CaptureDiagnosticsRecorder()
        recorder.enablePrivacyIntervalJournal(path: path.path)
        recorder.notePrivacyTrigger("secureInputMonitor-enabled")
        recorder.beginClosedInterval(cause: "secureInputMonitor")
        recorder.beginSession(generation: 2)
        XCTAssertFalse(recorder.hasOpenClosedInterval)
        recorder.increment(.handoffAccepted)
        let marks = try String(contentsOf: path, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        let end = try XCTUnwrap(marks.last { $0["role"] as? String == "end" })
        XCTAssertEqual(end["handoffAccepted"] as? Int, 0)
        XCTAssertEqual(end["boundaryCause"] as? String, "captureSessionStarting")
        XCTAssertEqual(recorder.runSummary.handoffAccepted, 1)
    }

    func testRunSummaryRetainsCountersAcrossSessionReset() {
        let recorder = CaptureDiagnosticsRecorder()
        recorder.beginSession(generation: 1)
        recorder.increment(.tapCallbackKeyDown)
        recorder.beginSession(generation: 2)
        recorder.increment(.tapCallbackKeyDown)
        XCTAssertEqual(recorder.snapshot.tapCallbackKeyDown, 1)
        XCTAssertEqual(recorder.runSummary.tapCallbackKeyDown, 2)
        XCTAssertEqual(recorder.runSummary.sessionCount, 2)
    }

    func testFlushPhysicalAndInvalidationCountersRetainLifetimeTotalsAcrossSessionReset() {
        let recorder = CaptureDiagnosticsRecorder()
        let counters: [CaptureDiagnosticCounter] = [
            .flushIssued, .flushWriteReturned, .flushWriteSucceeded, .flushInvalidated
        ]
        for counter in counters { recorder.increment(counter) }
        recorder.beginSession(generation: 2)
        XCTAssertEqual(recorder.snapshot.flushWriteReturned, 0)
        XCTAssertEqual(recorder.snapshot.flushWriteSucceeded, 0)
        XCTAssertEqual(recorder.snapshot.flushInvalidated, 0)
        for counter in counters { recorder.increment(counter) }
        XCTAssertEqual(recorder.snapshot.flushWriteReturned, 1)
        XCTAssertEqual(recorder.snapshot.flushWriteSucceeded, 1)
        XCTAssertEqual(recorder.snapshot.flushInvalidated, 1)
        let run = recorder.runSummary
        XCTAssertEqual(run.flushIssued, 2)
        XCTAssertEqual(run.flushWriteReturned, 2)
        XCTAssertEqual(run.flushWriteSucceeded, 2)
        XCTAssertEqual(run.flushInvalidated, 2)
    }

    func testRunSummaryTracksPublicationWithoutPretendingUnpublishedIsZero() {
        let recorder = CaptureDiagnosticsRecorder()
        XCTAssertNil(recorder.runSummary.lastPublishedShortcutTotal)
        recorder.recordPublication(shortcutTotal: 5, bareKeyTotal: 7)
        recorder.recordSnapshotReadFailure()
        recorder.beginSession(generation: 1)
        XCTAssertEqual(recorder.runSummary.snapshotPublicationCount, 1)
        XCTAssertEqual(recorder.runSummary.snapshotReadFailureCount, 1)
        XCTAssertEqual(recorder.runSummary.lastPublishedShortcutTotal, 5)
        XCTAssertEqual(recorder.runSummary.lastPublishedBareKeyTotal, 7)
    }

    func testRunReceiptIsOptInAndContainsOnlyNumericOrBooleanValues() throws {
        let recorder = CaptureDiagnosticsRecorder()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try recorder.writeRunSummary(to: nil)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let output = root.appendingPathComponent("receipt.json")
        recorder.recordPublication(shortcutTotal: 5, bareKeyTotal: 7)
        try recorder.writeRunSummary(to: output.path)
        let data = try Data(contentsOf: output)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "tapCallbackKeyDown", "tapCallbackKeyUp", "tapCallbackFlagsChanged", "tapDisabledEvents",
            "handoffAccepted", "handoffClosed", "handoffOverflow", "normalizationOutput", "aggregateDelta",
            "flushIssued", "flushDurable", "flushFailed", "flushTimedOut",
            "flushWriteReturned", "flushWriteSucceeded", "flushInvalidated", "sessionCount",
            "snapshotPublicationCount", "snapshotReadFailureCount", "lastPublishedShortcutTotal",
            "lastPublishedBareKeyTotal", "countersInstrumented", "captureSessionLive", "sensitiveContentVisible",
            "protectedSnapshotAttempts", "protectedSnapshotRejected",
            "protectedAnalysisAttempts", "protectedAnalysisRejected", "privacyJournalWriteFailed"
        ]))
        for (key, value) in object {
            XCTAssertTrue(value is NSNumber, "Unexpected payload shape: \(key)")
        }
        XCTAssertThrowsError(try recorder.writeRunSummary(to: root.appendingPathComponent("missing/receipt.json").path))
    }

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
        XCTAssertEqual(snapshot.flushWriteReturned, 1)
        XCTAssertEqual(snapshot.flushWriteSucceeded, 1)
        XCTAssertEqual(snapshot.flushInvalidated, 1)
        let run = recorder.runSummary
        XCTAssertEqual([run.tapCallbackKeyDown, run.tapCallbackKeyUp, run.tapCallbackFlagsChanged,
                        run.tapDisabledEvents, run.handoffAccepted, run.handoffClosed, run.handoffOverflow,
                        run.normalizationOutput, run.aggregateDelta, run.flushIssued, run.flushDurable,
                        run.flushFailed, run.flushTimedOut, run.flushWriteReturned,
                        run.flushWriteSucceeded, run.flushInvalidated], Array(repeating: 1, count: 16))
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

    func testPrivacyIntervalJournalRecordsStateChangesOnlyWhenEnabled() throws {
        let recorder = CaptureDiagnosticsRecorder()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("intervals.jsonl").path
        recorder.notePrivacyInterval()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        recorder.enablePrivacyIntervalJournal(path: path)
        recorder.record {
            $0.phase = .collecting
            $0.captureSessionLive = true
            $0.sensitiveContentVisible = true
            $0.loadedExpectedCollecting = true
        }
        recorder.notePrivacyInterval()
        recorder.notePrivacyInterval()
        recorder.record {
            $0.phase = .blocked
            $0.captureSessionLive = false
            $0.sensitiveContentVisible = false
            $0.loadedExpectedCollecting = true
        }
        recorder.increment(.aggregateDelta)
        recorder.notePrivacyInterval()
        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("\"captureSessionLive\":true"))
        XCTAssertTrue(lines[1].contains("\"aggregateDelta\":1"))
        XCTAssertFalse(String(lines[1]).contains("timestamp"))
    }
}

import XCTest
import KeyRecordCore
import KeyRecordMeasurement

final class ResourceEvaluationTests: XCTestCase {
    func testExploratoryWindowReportsMeanAndSampledPeakWithoutPass() {
        let result = ResourceEvaluator.evaluate(request(samples: series()))
        XCTAssertEqual(result.outcome, "measured")
        XCTAssertEqual(result.qualification, "not-a-product-pass")
        XCTAssertEqual(result.formalFRS2Qualification, false)
        XCTAssertEqual(result.rssUsedAsFootprint, false)
        XCTAssertEqual(result.sleepPrevented, false)
        XCTAssertEqual(result.cpuPercentOfOneLogicalCore!, 10, accuracy: 0.001)
        XCTAssertEqual(result.footprintMeanBytes!, 25, accuracy: 0.001)
        XCTAssertEqual(result.footprintSampledPeakBytes, 40)
        XCTAssertEqual(result.footprintSampleCount, 2)
        XCTAssertFalse(result.formula.contains("RSS"))
    }

    func testMissingSampleSleepExitReuseAndSessionDoNotPass() {
        var missing = series()
        missing[1].failed = true
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: missing)).outcome, "invalid")
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: missing)).reason, "sample-missing")

        var slept = series()
        slept[2].monotonicSeconds += 5
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: slept)).reason, "sleep")

        var exited = series()
        exited[2].exited = true
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: exited)).reason, "process-exited")

        var reused = series()
        reused[2].startAbstime = 99
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: reused)).reason, "pid-reused")

        var session = series()
        session[1].consoleUID = 502
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: session)).reason, "session-changed")
        for result in [missing, slept, exited, reused, session].map({ ResourceEvaluator.evaluate(request(samples: $0)) }) {
            XCTAssertNotEqual(result.outcome, "measured")
            XCTAssertEqual(result.qualification, "not-a-product-pass")
        }
    }

    func testShortFormalAndPausedProtocolsStayInvalid() {
        let formal = ResourceWindowRequest(protocolKind: .formalFRS2, phase: "typing",
            warmupSeconds: 1, measureSeconds: 2, intervalSeconds: 1, samples: series())
        XCTAssertEqual(ResourceEvaluator.evaluate(formal).reason, "formal-protocol-requires-60s-warmup-and-600s-measure")
        let paused = ResourceWindowRequest(protocolKind: .pausedMonitorCandidate, phase: "paused",
            warmupSeconds: 5, measureSeconds: 30, intervalSeconds: 1, samples: series())
        XCTAssertEqual(ResourceEvaluator.evaluate(paused).reason, "paused-monitor-candidate-requires-60s-warmup-and-600s-measure")
    }

    func testClosedIntervalDeltasAreSeparatedFromEndpointEquality() {
        let marks = [
            mark(seq: 1, live: true, visible: true, expected: true, aggregate: 10, attempts: 2),
            mark(seq: 2, live: false, visible: false, expected: true, aggregate: 10, attempts: 2),
            mark(seq: 3, live: false, visible: false, expected: true, aggregate: 14, attempts: 5, rejected: 3),
            mark(seq: 4, live: true, visible: true, expected: true, aggregate: 14, attempts: 5, rejected: 3)
        ]
        let report = PrivacyIntervalEvaluator.evaluate(marks)
        XCTAssertEqual(report.outcome, "observed")
        XCTAssertEqual(report.provesContinuousClosedInterval, false)
        XCTAssertEqual(report.provesRendering, false)
        XCTAssertEqual(report.provesEveryProtectedRead, false)
        let closed = report.spans.first { $0.fromSeq == 2 }
        XCTAssertEqual(closed?.aggregateDelta, 4)
        XCTAssertEqual(closed?.protectedSnapshotAttempts, 3)
        XCTAssertEqual(marks[0].aggregateDelta, marks[3].aggregateDelta - 4)
        let endpoints = PrivacyIntervalEvaluator.evaluate([marks[0], marks[3]])
        XCTAssertEqual(endpoints.outcome, "inconclusive")
    }

    func testRecorderClosedIntervalFeedsEvaluator() throws {
        let stable = try recorderMarks { recorder in
            recorder.record { $0.phase = .blocked; $0.captureSessionLive = false; $0.sensitiveContentVisible = false }
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.observeClosedInterval()
            recorder.beginSession(generation: 2)
            recorder.increment(.aggregateDelta)
            recorder.record { $0.phase = .collecting; $0.captureSessionLive = true; $0.sensitiveContentVisible = true }
            recorder.notePrivacyInterval()
        }
        let stableReport = PrivacyIntervalEvaluator.evaluateClosed(stable, journalWriteFailed: false)
        XCTAssertEqual(stableReport.outcome, "observed")
        XCTAssertNil(stableReport.reason)
        XCTAssertEqual(stableReport.endCause, "captureSessionStarting")
        XCTAssertEqual(stableReport.spans.first?.aggregateDelta, 0)
        XCTAssertEqual(stableReport.spans.last?.aggregateDelta, 1, "input after the session boundary is not closed input")
        XCTAssertFalse(stableReport.provesContinuousClosedInterval)
        XCTAssertFalse(stableReport.countersAreAtomicSnapshot)

        let anomaly = try recorderMarks { recorder in
            recorder.record { $0.captureSessionLive = false; $0.sensitiveContentVisible = false }
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.increment(.aggregateDelta)
            recorder.observeClosedInterval(lockReadStatus: "locked", secureInputReadStatus: "notChecked")
            recorder.endClosedInterval(cause: "captureSessionStarting")
        }
        let anomalyReport = PrivacyIntervalEvaluator.evaluateClosed(anomaly, journalWriteFailed: false)
        XCTAssertEqual(anomalyReport.reason, "closed-interval-input-counted")
        XCTAssertEqual(anomalyReport.spans.first?.aggregateDelta, 1)
        let lockedObserve = anomaly.first { $0.role == "observe" }
        XCTAssertEqual(lockedObserve?.lockReadStatus, "locked")

        let missing = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.observeClosedInterval()
        }
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(missing, journalWriteFailed: false).reason, "interval-not-ended")

        let recorder = CaptureDiagnosticsRecorder()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        recorder.enablePrivacyIntervalJournal(path: directory.path)
        recorder.beginClosedInterval(cause: "protectedStateClosed")
        XCTAssertTrue(recorder.privacyJournalWriteFailed)
        XCTAssertTrue(recorder.runSummary.privacyJournalWriteFailed)
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed([], journalWriteFailed: recorder.privacyJournalWriteFailed).outcome, "invalid")
    }

    func testClosedIntervalSeparatesBoundaryWorkFromClosedInput() throws {
        // A write issued before closure completes late as invalidated: not closed input.
        let inFlight = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.increment(.flushInvalidated)
            recorder.observeClosedInterval(lockReadStatus: "unlocked", secureInputReadStatus: "disabled")
            recorder.endClosedInterval(cause: "protectedDisplayReauthorized")
        }
        let inFlightReport = PrivacyIntervalEvaluator.evaluateClosed(inFlight, journalWriteFailed: false)
        XCTAssertEqual(inFlightReport.outcome, "observed")
        XCTAssertNil(inFlightReport.reason)
        XCTAssertEqual(inFlightReport.inFlightCompletionsAtBoundary, 1)

        let handoffOnly = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.increment(.handoffAccepted)
            recorder.observeClosedInterval()
            recorder.endClosedInterval(cause: "captureSessionStarting")
        }
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(handoffOnly, journalWriteFailed: false).outcome, "inconclusive")
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(handoffOnly, journalWriteFailed: false).reason,
                       "handoff-count-not-attributable")

        let read = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.recordProtectedSnapshot(rejected: true)
            recorder.recordProtectedAnalysis(rejected: false)
            recorder.observeClosedInterval()
            recorder.endClosedInterval(cause: "captureSessionStarting")
        }
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(read, journalWriteFailed: false).reason,
                       "closed-interval-protected-read-succeeded")

        let unattributable = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.observeClosedInterval()
            recorder.endClosedInterval(cause: "sessionObservedLiveWithoutBoundary")
        }
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(unattributable, journalWriteFailed: false).reason,
                       "end-boundary-unattributable")

        // A startup "closed" state is not a privacy closure and is not evaluated by default.
        let startup = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "closedStateObserved")
            recorder.observeClosedInterval()
            recorder.endClosedInterval(cause: "protectedDisplayReauthorized")
        }
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(startup, journalWriteFailed: false).reason, "missing-boundary")
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(startup, journalWriteFailed: false, beginCause: nil).outcome,
                       "observed")
    }

    func testSavedSamplesRecomputeToTheSameResult() {
        let request = request(samples: series())
        let result = ResourceEvaluator.evaluate(request)
        let archive = ResourceMeasurementArchive(request: request, result: result, architecture: "arm64",
            operatingSystem: "fixture", diagnosticsEnabled: true)
        let again = ResourceEvaluator.recompute(archive)
        XCTAssertEqual(again.outcome, result.outcome)
        XCTAssertEqual(again.cpuPercentOfOneLogicalCore, result.cpuPercentOfOneLogicalCore)
        XCTAssertEqual(again.footprintMeanBytes, result.footprintMeanBytes)
        XCTAssertEqual(again.footprintSampledPeakBytes, result.footprintSampledPeakBytes)
        XCTAssertTrue(archive.diagnosticsIncludedInOverhead)
        XCTAssertFalse(archive.rssUsedAsFootprint)
        XCTAssertEqual(archive.retainedSampleCount, 3)
    }

    func testActionRecordsPairBeginAndEndEvenWhenStateDoesNotChange() throws {
        var detail = CapturePrivacyActionDetail()
        detail.earlyReturn = "not-expecting-collecting"
        let marks = try recorderMarks { recorder in
            recorder.record { $0.phase = .blocked; $0.captureSessionLive = false; $0.sensitiveContentVisible = false }
            recorder.notePrivacyInterval()
            let first = recorder.beginAction("start")
            recorder.endAction("start", id: first, detail: detail)
            let second = recorder.beginAction("start")
            recorder.endAction("start", id: second, detail: detail)
            _ = recorder.beginAction("quit")
        }
        let begins = marks.filter { $0.role == "actionBegin" }
        let ends = marks.filter { $0.role == "actionEnd" }
        XCTAssertEqual(begins.map(\.action), ["start", "start", "quit"])
        XCTAssertEqual(ends.map(\.actionSeq), begins.prefix(2).map(\.actionSeq))
        XCTAssertNotEqual(ends[0].actionSeq, ends[1].actionSeq, "repeated actions stay distinguishable")
        // Entered but not finished: a begin whose actionSeq has no end.
        let unfinished = Set(begins.compactMap(\.actionSeq)).subtracting(ends.compactMap(\.actionSeq))
        XCTAssertEqual(unfinished, [begins[2].actionSeq!])
    }

    func testPausedIntentFlagsUnexpectedCollecting() {
        let marks = [
            mark(seq: 1, live: false, visible: true, expected: false, aggregate: 3, attempts: 1),
            mark(seq: 2, live: true, visible: true, expected: false, aggregate: 3, attempts: 1)
        ]
        let report = PrivacyIntervalEvaluator.evaluate(marks)
        XCTAssertTrue(report.unexpectedCollectingWhilePaused)
    }

    private func recorderMarks(_ body: (CaptureDiagnosticsRecorder) -> Void) throws -> [PrivacyIntervalMark] {
        let recorder = CaptureDiagnosticsRecorder()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("intervals.jsonl")
        recorder.enablePrivacyIntervalJournal(path: path.path)
        body(recorder)
        let text = try String(contentsOf: path, encoding: .utf8)
        return try text.split(separator: "\n").map {
            try JSONDecoder().decode(PrivacyIntervalMark.self, from: Data($0.utf8))
        }
    }

    private func request(samples: [ProcessResourceSample]) -> ResourceWindowRequest {
        ResourceWindowRequest(protocolKind: .exploratory, phase: "synthetic",
            warmupSeconds: 1, measureSeconds: 1, intervalSeconds: 1, samples: samples)
    }

    private func series() -> [ProcessResourceSample] {
        [
            sample(t: 0, cpu: 0, bytes: 10),
            sample(t: 1, cpu: 0, bytes: 10),
            sample(t: 2, cpu: 100_000_000, bytes: 40)
        ]
    }

    private func sample(t: Double, cpu: UInt64, bytes: UInt64) -> ProcessResourceSample {
        ProcessResourceSample(uptimeSeconds: t, monotonicSeconds: t, cpuNanoseconds: cpu,
            childCPUNanoseconds: 0, footprintBytes: bytes, pid: 10, startAbstime: 7,
            executablePath: "/fixture", consoleUID: 501)
    }

    private func mark(seq: Int, live: Bool, visible: Bool, expected: Bool, aggregate: Int64,
                      attempts: Int64, rejected: Int64 = 0) -> PrivacyIntervalMark {
        PrivacyIntervalMark(seq: seq, phase: live ? "collecting" : "blocked",
            captureSessionLive: live, sensitiveContentVisible: visible, expectedCollecting: expected,
            aggregateDelta: aggregate, handoffAccepted: aggregate, handoffClosed: 0,
            normalizationOutput: aggregate, flushDurable: 0, flushInvalidated: 0,
            protectedSnapshotAttempts: attempts, protectedSnapshotRejected: rejected,
            protectedAnalysisAttempts: attempts, protectedAnalysisRejected: rejected,
            snapshotPublicationCount: attempts - rejected)
    }
}

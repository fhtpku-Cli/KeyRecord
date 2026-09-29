import XCTest
import KeyRecordCore
import KeyRecordMeasurement

final class ResourceEvaluationTests: XCTestCase {
    func testClosedIntervalDetectsActualBoundaryReads() throws {
        for kind in [ProtectedReadActivity.Kind.decryption, .keychain] {
            let activity = ProtectedReadActivity()
            let marks = try recorderMarks { recorder in
                recorder.configureProtectedReadActivity { activity.snapshot }
                recorder.beginClosedInterval(cause: "protectedStateClosed")
                activity.observe(kind) {}
                recorder.observeClosedInterval()
                recorder.endClosedInterval(cause: "protectedStoreReauthorized")
            }
            let report = PrivacyIntervalEvaluator.evaluateClosed(marks, journalWriteFailed: false)
            XCTAssertEqual(report.reason, "closed-interval-decryption-or-keychain-read")
            XCTAssertFalse(report.provesEveryProtectedRead)
        }
    }

    func testReadStartedBeforeClosureCannotDisappearFromObservation() throws {
        let activity = ProtectedReadActivity()
        let marks = try recorderMarks { recorder in
            recorder.configureProtectedReadActivity { activity.snapshot }
            activity.observe(.keychain) {
                recorder.beginClosedInterval(cause: "protectedStateClosed")
                recorder.observeClosedInterval()
            }
            recorder.endClosedInterval(cause: "protectedStoreReauthorized")
        }
        let report = PrivacyIntervalEvaluator.evaluateClosed(marks, journalWriteFailed: false)
        XCTAssertEqual(report.outcome, "inconclusive")
        XCTAssertEqual(report.reason, "protected-read-in-flight")
    }

    func testReadActivityRejectsMissingMalformedAndDecreasingCounters() throws {
        let activity = ProtectedReadActivity()
        activity.observe(.decryption) {}
        let marks = try recorderMarks { recorder in
            recorder.configureProtectedReadActivity { activity.snapshot }
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.observeClosedInterval()
            recorder.endClosedInterval(cause: "protectedStoreReauthorized")
        }
        XCTAssertNil(PrivacyIntervalEvaluator.evaluateClosed(marks, journalWriteFailed: false).reason)
        var missing = marks
        missing[1].protectedReadActivity = nil
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(missing, journalWriteFailed: false).reason,
                       "protected-read-activity-missing")
        var malformed = marks
        malformed[1].protectedReadActivity?.decryptionCompleted = 2
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(malformed, journalWriteFailed: false).reason,
                       "protected-read-activity-inconsistent")
        var decreased = marks
        decreased[2].protectedReadActivity?.decryptionStarted = 0
        decreased[2].protectedReadActivity?.decryptionCompleted = 0
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(decreased, journalWriteFailed: false).reason,
                       "counter-decreased")
    }

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

    func testFirstSampleAfterWindowEndCompletesMeasuredDuration() {
        let times: [Double] = [0, 0.208, 0.416, 0.624, 0.832, 1.040, 1.248, 1.456, 1.664]
        let samples = times.map { sample(t: $0, cpu: UInt64($0 * 100_000_000), bytes: 32_000_000) }
        let request = ResourceWindowRequest(protocolKind: .exploratory, phase: "synthetic",
            warmupSeconds: 0.4, measureSeconds: 1.2, intervalSeconds: 0.2, samples: samples)
        let result = ResourceEvaluator.evaluate(request)
        XCTAssertEqual(result.outcome, "measured")
        let archive = ResourceMeasurementArchive(request: request, result: result, architecture: "arm64",
            operatingSystem: "fixture", diagnosticsEnabled: false)
        XCTAssertEqual(archive.effectiveMeasureSeconds!, 1.264, accuracy: 0.0001)

        var incomplete = request
        incomplete.samples.removeLast()
        let short = ResourceEvaluator.evaluate(incomplete)
        XCTAssertEqual(short.outcome, "interrupted")
        XCTAssertEqual(short.reason, "duration-short")

        var tooLate = request
        tooLate.samples[8] = sample(t: 1.95, cpu: 195_000_000, bytes: 32_000_000)
        XCTAssertEqual(ResourceEvaluator.evaluate(tooLate).reason, "sample-missing")
    }

    func testExplicitReplayOriginAlignsWindowAndSurvivesRecompute() {
        let times: [Double] = [0.208, 0.416, 0.624, 0.832, 1.040, 1.248, 1.456, 1.664, 1.872]
        let samples = times.map { sample(t: $0, cpu: UInt64($0 * 100_000_000), bytes: 32_000_000) }
        let request = ResourceWindowRequest(protocolKind: .exploratory, phase: "typing",
            warmupSeconds: 0.4, measureSeconds: 1.2, intervalSeconds: 0.2,
            originUptimeSeconds: 0.1, samples: samples)
        let result = ResourceEvaluator.evaluate(request)
        XCTAssertEqual(result.outcome, "measured")
        let archive = ResourceMeasurementArchive(request: request, result: result, architecture: "arm64",
            operatingSystem: "fixture", diagnosticsEnabled: false)
        XCTAssertEqual(archive.originUptimeSeconds, 0.1)
        XCTAssertEqual(archive.effectiveMeasureSeconds!, 1.372, accuracy: 0.0001)
        XCTAssertEqual(ResourceEvaluator.recompute(archive), result)

        var stale = request
        stale.originUptimeSeconds = -1
        XCTAssertEqual(ResourceEvaluator.evaluate(stale).reason, "origin-misaligned")
        stale.originUptimeSeconds = 0.5
        XCTAssertEqual(ResourceEvaluator.evaluate(stale).reason, "origin-misaligned")
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

    func testClockAndCPUCounterRegressionCannotProduceMeasuredWindow() {
        var backwardTime = [
            sample(t: 0, cpu: 0, bytes: 10),
            sample(t: 1, cpu: 100_000_000, bytes: 10),
            sample(t: 0.8, cpu: 120_000_000, bytes: 10),
            sample(t: 2, cpu: 200_000_000, bytes: 10)
        ]
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: backwardTime)).reason,
                       "sample-clock-regressed")

        backwardTime[2] = sample(t: 1.5, cpu: 20_000_000, bytes: 10)
        backwardTime[3] = sample(t: 2, cpu: 100_000_000, bytes: 10)
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: backwardTime)).reason,
                       "cpu-counter-regressed")

        var childCounter = series()
        childCounter[0].childCPUNanoseconds = 5
        childCounter[1].childCPUNanoseconds = 4
        childCounter[2].childCPUNanoseconds = 5
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: childCounter)).reason,
                       "child-cpu-counter-regressed")

        var backwardMonotonic = series()
        backwardMonotonic[1].monotonicSeconds = -0.2
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: backwardMonotonic)).reason,
                       "sample-clock-regressed")

        var nonfinite = series()
        nonfinite[1].uptimeSeconds = .nan
        XCTAssertEqual(ResourceEvaluator.evaluate(request(samples: nonfinite)).reason,
                       "sample-clock-invalid")

        var nonfiniteInterval = request(samples: series())
        nonfiniteInterval.intervalSeconds = .infinity
        XCTAssertEqual(ResourceEvaluator.evaluate(nonfiniteInterval).reason, "bad-duration")
    }

    func testShortFormalAndPausedProtocolsStayInvalid() {
        let formal = ResourceWindowRequest(protocolKind: .formalFRS2, phase: "typing",
            warmupSeconds: 1, measureSeconds: 2, intervalSeconds: 1, samples: series())
        XCTAssertEqual(ResourceEvaluator.evaluate(formal).reason, "formal-protocol-requires-30s-warmup-and-120s-measure")
        let paused = ResourceWindowRequest(protocolKind: .pausedMonitorCandidate, phase: "paused",
            warmupSeconds: 5, measureSeconds: 30, intervalSeconds: 1, samples: series())
        XCTAssertEqual(ResourceEvaluator.evaluate(paused).reason, "paused-monitor-candidate-requires-60s-warmup-and-600s-measure")
    }

    func testFormalWindowRequiresAnObservedEndpointAtOrAfterTwoMinutes() {
        let origin = 100.0
        let times = stride(from: origin, through: 249.5, by: 0.5).map { $0 } + [249.8]
        let samples = times.map { sample(t: $0, cpu: UInt64($0 * 1_000_000), bytes: 32_000_000) }
        var request = ResourceWindowRequest(protocolKind: .formalFRS2, phase: "typing",
            warmupSeconds: 30, measureSeconds: 120, intervalSeconds: 0.5,
            originUptimeSeconds: origin, samples: samples)
        let short = ResourceEvaluator.evaluate(request)
        XCTAssertEqual(short.outcome, "interrupted")
        XCTAssertEqual(short.reason, "duration-short")

        request.samples.append(sample(t: 250.1, cpu: 250_100_000, bytes: 32_000_000))
        let full = ResourceEvaluator.evaluate(request)
        XCTAssertEqual(full.outcome, "measured")
        let archive = ResourceMeasurementArchive(request: request, result: full,
            architecture: "arm64", operatingSystem: "fixture", diagnosticsEnabled: false)
        XCTAssertGreaterThanOrEqual(archive.effectiveMeasureSeconds ?? 0, 120)
        XCTAssertEqual(ResourceEvaluator.recompute(archive), full)
    }

    func testHistoricalDurationIsNotSilentlyRequalifiedAsCurrentFormalWindow() {
        let legacy = ResourceWindowRequest(protocolKind: .formalFRS2, phase: "typing",
            warmupSeconds: 60, measureSeconds: 600, intervalSeconds: 0.5, samples: series())
        XCTAssertEqual(ResourceEvaluator.evaluate(legacy).reason,
                       "formal-protocol-requires-30s-warmup-and-120s-measure")
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
        XCTAssertEqual(stableReport.spans.first?.protectedGateEntries, 0)

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

    func testClosedIntervalRejectsMissingOrAdvancingGateCounter() throws {
        let marks = try recorderMarks { recorder in
            recorder.record { $0.phase = .blocked; $0.captureSessionLive = false; $0.sensitiveContentVisible = false }
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.observeClosedInterval()
            recorder.endClosedInterval(cause: "captureSessionStarting")
        }
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(marks, journalWriteFailed: false).outcome, "observed")
        let observeIndex = try XCTUnwrap(marks.firstIndex(where: { $0.role == "observe" }))
        let endIndex = try XCTUnwrap(marks.firstIndex(where: { $0.role == "end" }))

        var missing = marks
        missing[observeIndex].protectedGateEntries = nil
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(missing, journalWriteFailed: false).reason,
                       "protected-gate-counter-missing")

        var admitted = marks
        admitted[observeIndex].protectedGateEntries = 1
        admitted[endIndex].protectedGateEntries = 1
        let admittedReport = PrivacyIntervalEvaluator.evaluateClosed(admitted, journalWriteFailed: false)
        XCTAssertEqual(admittedReport.reason, "closed-interval-protected-gate-entry")
        XCTAssertEqual(admittedReport.spans.first?.protectedGateEntries, 1)
        XCTAssertFalse(admittedReport.provesEveryProtectedRead)

        var decreased = marks
        decreased[observeIndex].protectedGateEntries = 2
        decreased[endIndex].protectedGateEntries = 1
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(decreased, journalWriteFailed: false).reason,
                       "counter-decreased")
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

        let analysisPublication = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.recordAnalysisPublication()
            recorder.observeClosedInterval()
            recorder.endClosedInterval(cause: "captureSessionStarting")
        }
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(analysisPublication, journalWriteFailed: false).reason,
                       "closed-interval-publication")
        var legacy = analysisPublication
        legacy[1].analysisPublicationCount = nil
        XCTAssertEqual(PrivacyIntervalEvaluator.evaluateClosed(legacy, journalWriteFailed: false).reason,
                       "analysis-publication-counter-missing")

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

    func testExplicitStoreReauthorizationSeparatesRecoveryReadsFromClosure() throws {
        let marks = try recorderMarks { recorder in
            recorder.beginClosedInterval(cause: "protectedStateClosed")
            recorder.observeClosedInterval(lockReadStatus: "locked")
            recorder.observeClosedInterval(lockReadStatus: "unlocked")
            recorder.endClosedInterval(cause: "protectedStoreReauthorized")
            recorder.recordProtectedSnapshot(rejected: false)
            recorder.beginAction("recovery-finished")
        }
        let report = PrivacyIntervalEvaluator.evaluateClosed(marks, journalWriteFailed: false)
        XCTAssertEqual(report.outcome, "observed")
        XCTAssertNil(report.reason)
        XCTAssertEqual(report.spans.first?.protectedSnapshotAttempts, 0)
        XCTAssertEqual(report.spans.last?.protectedSnapshotAttempts, 1)
        XCTAssertFalse(report.provesContinuousClosedInterval)
        XCTAssertFalse(report.provesEveryProtectedRead)
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
        recorder.configureProtectedGateEntries { 0 }
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
            snapshotPublicationCount: attempts - rejected, analysisPublicationCount: 0)
    }
}

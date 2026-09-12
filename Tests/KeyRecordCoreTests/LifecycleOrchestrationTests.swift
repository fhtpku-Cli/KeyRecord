import XCTest
import KeyRecordCore
import KeyRecordTestSupport

@MainActor
final class LifecycleOrchestrationTests: XCTestCase {
    private let cycle = CycleID(rawValue: "harness-cycle")

    private func clock() -> any LocalClock {
        FixedClock(instant: Date(timeIntervalSince1970: 0),
                   calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC")!)
    }

    private func down(_ code: Int = 0) throws -> NormalizationOutput {
        .keyDown(.bare(try KeyCode(code)), .ordinaryObserved)
    }

    func testHappyConsentStartPauseResumeQuitReopen() async throws {
        // Given: fakes all succeed; When: full lifecycle; Then: ordered effects, same cycle on reopen.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        XCTAssertEqual(harness.orchestrator.phase, .collecting)

        await harness.orchestrator.pause()
        let flushCountAfterPause = await harness.flush.flushCount
        let stopCountAfterPause = await harness.capture.stopCount
        XCTAssertEqual(harness.orchestrator.phase, .paused)
        XCTAssertEqual(flushCountAfterPause, 1)
        XCTAssertEqual(stopCountAfterPause, 1)

        await harness.orchestrator.resume()
        let startCountAfterResume = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(startCountAfterResume, 2)

        await harness.orchestrator.quit()
        let flushCountAfterQuit = await harness.flush.flushCount
        let stopCountAfterQuit = await harness.capture.stopCount
        XCTAssertEqual(harness.orchestrator.phase, .stopped)
        XCTAssertEqual(flushCountAfterQuit, 2)
        XCTAssertEqual(stopCountAfterQuit, 2)
        let quitPreferences = await harness.storedPreferences()
        let stored = try XCTUnwrap(quitPreferences)
        XCTAssertTrue(stored.expectedCollecting)
        XCTAssertEqual(stored.currentCycleID, cycle)

        let reopened = LifecycleHarness(storage: harness.storage)
        reopened.orchestrator.observe(LifecycleHarnessConditions.open)
        await reopened.orchestrator.reload()
        let reopenedCycle = reopened.orchestrator.state.preferences?.currentCycleID
        XCTAssertEqual(reopened.orchestrator.phase, .collecting)
        XCTAssertEqual(reopenedCycle, cycle)
    }

    func testConsentDenialPerformsZeroStoreKeyLoginCaptureCalls() async throws {
        // Given: consent presented; When: denied; Then: store/key/login/capture fake counts stay zero.
        let harness = LifecycleHarness()
        harness.orchestrator.requestConsent()
        await harness.orchestrator.denyConsent()
        let saves = await harness.storage.saveCount
        let provisions = await harness.keys.provisionCount
        let registrations = await harness.login.registerCount
        let unregistrations = await harness.login.unregisterCount
        let starts = await harness.capture.startCount
        let stops = await harness.capture.stopCount
        let flushes = await harness.flush.flushCount
        let checks = await harness.readiness.checkCount
        let ciphertext = await harness.storage.ciphertext
        XCTAssertEqual(harness.orchestrator.phase, .unstarted)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(provisions, 0)
        XCTAssertEqual(registrations, 0)
        XCTAssertEqual(unregistrations, 0)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(flushes, 0)
        XCTAssertEqual(checks, 0)
        XCTAssertNil(ciphertext)
    }

    func testFirstPersistenceFailureBlocksCaptureAndRetryCompletesStart() async throws {
        // Given: the bootstrap persist fails once; When: consent accepted; Then: no capture, typed error.
        let storage = InMemoryPreferencesStorage(failingSaveAttempts: [1])
        let harness = LifecycleHarness(storage: storage)
        await harness.startConsented()
        let startsBefore = await harness.capture.startCount
        let provisionsBefore = await harness.keys.provisionCount
        XCTAssertEqual(harness.orchestrator.phase, .failed)
        XCTAssertEqual(harness.orchestrator.state.failure, .initialPersistenceFailed(.protectedDataUnavailable))
        XCTAssertEqual(startsBefore, 0)
        XCTAssertEqual(provisionsBefore, 1)
        // When: the user retries after storage recovery; Then: persist succeeds and capture starts once.
        await harness.orchestrator.retry()
        let startsAfter = await harness.capture.startCount
        let provisionsAfter = await harness.keys.provisionCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(startsAfter, 1)
        XCTAssertEqual(provisionsAfter, 1)
    }

    func testCollectingRestartRunsFreshChecksBeforeCapture() async throws {
        // Given: expectedCollecting persisted; When: reopen; Then: readiness verified, then capture starts.
        let prefs = Preferences(currentCycleID: cycle, expectedCollecting: true)
        let harness = LifecycleHarness(
            storage: InMemoryPreferencesStorage(ciphertext: try PreferencesRepository.encode(prefs)))
        await harness.orchestrator.reload()
        let checks = await harness.readiness.checkCount
        let starts = await harness.capture.startCount
        let provisions = await harness.keys.provisionCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(provisions, 0)
    }

    func testPausedRestartSkipsChecksAndCapture() async throws {
        // Given: paused expectation persisted; When: reopen; Then: paused, zero readiness/capture calls.
        let prefs = Preferences(currentCycleID: cycle, expectedCollecting: false)
        let harness = LifecycleHarness(
            storage: InMemoryPreferencesStorage(ciphertext: try PreferencesRepository.encode(prefs)))
        await harness.orchestrator.reload()
        let checks = await harness.readiness.checkCount
        let starts = await harness.capture.startCount
        let stops = await harness.capture.stopCount
        XCTAssertEqual(harness.orchestrator.phase, .paused)
        XCTAssertEqual(checks, 0)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
    }

    func testCollectingRestartFailingChecksBlocksAndManualRetryReVerifies() async throws {
        // Given: readiness reports locked; When: reopen; Then: blocked; explicit retry verifies again.
        let prefs = Preferences(currentCycleID: cycle, expectedCollecting: true)
        let storage = InMemoryPreferencesStorage(ciphertext: try PreferencesRepository.encode(prefs))
        let harness = LifecycleHarness(storage: storage, readinessResult: .failure(.sessionLocked))
        await harness.orchestrator.reload()
        let startsBefore = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .blocked)
        XCTAssertEqual(harness.orchestrator.state.blockedReason, .sessionLocked)
        XCTAssertEqual(startsBefore, 0)
        await harness.readiness.setResult(.success(LifecycleHarnessConditions.open))
        await harness.orchestrator.retry()
        let checksAfter = await harness.readiness.checkCount
        let startsAfter = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(checksAfter, 2)
        XCTAssertEqual(startsAfter, 1)
    }

    func testPauseFlushFailureKeepsRuntimeCollectingWithVisibleNotice() async throws {
        // Given: a flushing port that fails; When: pausing; Then: not paused, runtime alive, visible.
        let harness = LifecycleHarness(flushFailure: .timedOut)
        await harness.collectOpen()
        let starts = await harness.capture.startCount
        await harness.orchestrator.pause()
        let stops = await harness.capture.stopCount
        let startCountDuringFailure = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(harness.orchestrator.state.notice, .pauseFlushFailed(.timedOut))
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(startCountDuringFailure, starts)
    }

    func testQuitAfterPausePreservesFalseExpectationAndReopensPaused() async throws {
        // Given: paused session; When: quit and reopen; Then: paused without checks or capture.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        await harness.orchestrator.pause()
        await harness.orchestrator.quit()
        let quitPreferences = await harness.storedPreferences()
        let stored = try XCTUnwrap(quitPreferences)
        XCTAssertFalse(stored.expectedCollecting)
        XCTAssertEqual(stored.currentCycleID, cycle)
        let reopened = LifecycleHarness(storage: harness.storage)
        await reopened.orchestrator.reload()
        let checks = await reopened.readiness.checkCount
        XCTAssertEqual(reopened.orchestrator.phase, .paused)
        XCTAssertEqual(checks, 0)
    }

    func testExclusionRaceImmediatelyRevokesGateAndStopsAllNewCounts() async throws {
        // Given: foreground com.ex counting under generation G; When: com.ex excluded; Then: zero new counts.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        var gate = harness.orchestrator.state.gate
        var aggregator = AggregationReducer(cycleID: cycle)
        aggregator.update(gate)
        let generationBefore = gate.generation
        try aggregator.process(try down(), generation: generationBefore, clock: clock())
        XCTAssertEqual(aggregator.bareKeys.map(\.sourceCounts.total.value), [1])

        await harness.orchestrator.setExclusions(Set(["com.ex"]))
        gate = harness.orchestrator.state.gate
        XCTAssertEqual(gate.closureReason, .excluded)
        XCTAssertNotEqual(gate.generation, generationBefore)

        try aggregator.process(try down(), generation: generationBefore, clock: clock())
        aggregator.update(gate)
        XCTAssertFalse(gate.accepts(gate.generation))
        try aggregator.process(try down(), generation: gate.generation, clock: clock())
        XCTAssertEqual(aggregator.bareKeys.map(\.sourceCounts.total.value), [1])
        let excludedPreferences = await harness.storedPreferences()
        let stored = try XCTUnwrap(excludedPreferences)
        XCTAssertEqual(stored.excludedBundleIDs, ["com.ex"])
    }

    func testExcludingOtherBundleKeepsCountingCurrentForeground() async throws {
        // Given: foreground com.ex open; When: com.other excluded; Then: gate stays open, counts continue.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        await harness.orchestrator.setExclusions(Set(["com.other"]))
        let gate = harness.orchestrator.state.gate
        var aggregator = AggregationReducer(cycleID: cycle)
        aggregator.update(gate)
        try aggregator.process(try down(), generation: gate.generation, clock: clock())
        XCTAssertTrue(gate.isOpen)
        XCTAssertEqual(aggregator.bareKeys.map(\.sourceCounts.total.value), [1])
    }

    func testCorruptPreferencesOnReloadFailClosedWithoutRuntimeEffects() async throws {
        // Given: corrupt preference bytes; When: reloading; Then: typed failure, zero runtime effects.
        let storage = InMemoryPreferencesStorage(ciphertext: Data("{\"schemaVersion\":1}".utf8))
        let harness = LifecycleHarness(storage: storage)
        await harness.orchestrator.reload()
        let starts = await harness.capture.startCount
        let provisions = await harness.keys.provisionCount
        XCTAssertEqual(harness.orchestrator.phase, .failed)
        XCTAssertEqual(harness.orchestrator.state.failure, .preferencesLoadFailed(.corruptStoredPreferences))
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(provisions, 0)
        // When: storage is restored and the user retries; Then: first-run consent flow is available again.
        await storage.seed(ciphertext: nil)
        await harness.orchestrator.retry()
        await harness.orchestrator.reload()
        XCTAssertEqual(harness.orchestrator.phase, .unstarted)
    }

    func testManualResumeCapturePermissionDenialIsExplicit() async throws {
        // Given: paused after a healthy collection; When: resume and the system denies capture; Then: explicit.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        await harness.orchestrator.pause()
        XCTAssertEqual(harness.orchestrator.phase, .paused)
        await harness.capture.setStartFailure(.permissionDenied)
        await harness.orchestrator.resume()
        XCTAssertEqual(harness.orchestrator.phase, .failed)
        XCTAssertEqual(harness.orchestrator.state.failure, .captureStartDenied(.permissionDenied))
    }

    func testFirstStartCapturePermissionDenialIsExplicitAndSilentNothing() async throws {
        // Given: input monitoring effectively denied; When: accepting consent; Then: visible failure.
        let harness = LifecycleHarness(captureFailure: .permissionDenied)
        harness.orchestrator.requestConsent()
        await harness.orchestrator.acceptConsent()
        let starts = await harness.capture.startCount
        let registrations = await harness.login.registerCount
        XCTAssertEqual(harness.orchestrator.phase, .failed)
        XCTAssertEqual(harness.orchestrator.state.failure, .captureStartDenied(.permissionDenied))
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(registrations, 0)
    }
}

import XCTest
import KeyRecordCore
import KeyRecordTestSupport

final class LifecycleRestartTests: XCTestCase {
    typealias FX = LifecycleReducerFixtures
    private var cycle: CycleID { FX.cycle }

    private func run(_ state: LifecycleState, _ event: LifecycleEvent,
                     effects expected: [LifecycleEffect]? = nil,
                     file: StaticString = #filePath, line: UInt = #line) throws -> LifecycleState {
        let outcome = reduce(state, event)
        if let expected { XCTAssertEqual(outcome.effects, expected, "event \(event)", file: file, line: line) }
        return outcome.state
    }

    // MARK: - Quit

    func testQuitWhileCollectingFlushesStopsAndPreservesExpectationAndCycle() throws {
        // Given: collecting; When: quit; Then: flush, stop, stopped; prefs keep expected=true and cycle.
        let state = try FX.collectingState()
        let stopping = try run(state, .quitRequested, effects: [.flushWhileUnlocked])
        XCTAssertFalse(stopping.gate.isOpen)
        let stopped = try run(try run(stopping, .quitFlushSucceeded, effects: [.stopCapture]),
                                 .quitRuntimeStopped, effects: [])
        XCTAssertEqual(stopped.phase, .stopped)
        XCTAssertEqual(stopped.preferences?.expectedCollecting, true)
        XCTAssertEqual(stopped.preferences?.currentCycleID, cycle)
    }

    func testQuitWhilePausedStopsRuntimeWithoutFlushOrWrites() throws {
        // Given: paused; When: quit; Then: stop only, expectation false preserved, no flush/persist.
        let state = try FX.pausedState()
        let stopping = try run(state, .quitRequested, effects: [.stopCapture])
        let stopped = try run(stopping, .quitRuntimeStopped, effects: [])
        XCTAssertEqual(stopped.phase, .stopped)
        XCTAssertEqual(stopped.preferences?.expectedCollecting, false)
        XCTAssertEqual(stopped.preferences?.currentCycleID, cycle)
    }

    func testQuitFlushFailureDoesNotStopAndStaysExplicit() throws {
        // Given: quit flush in flight; When: flush fails; Then: runtime not stopped, visible failure.
        let state = try FX.collectingState()
        let stopping = try run(state, .quitRequested)
        let outcome = reduce(stopping, .quitFlushFailed(.failed))
        XCTAssertEqual(outcome.state.phase, .collecting)
        XCTAssertEqual(outcome.state.notice, .quitFlushFailed(.failed))
        XCTAssertEqual(outcome.effects, [])
    }

    // MARK: - Reopen

    func testReloadWithoutPreferencesIsFirstRun() throws {
        // Given: a fresh encrypted store; When: reloading; Then: unstarted, no runtime checks.
        let outcome = reduce(LifecycleState.initial, .reload(nil))
        XCTAssertEqual(outcome.state.phase, .unstarted)
        XCTAssertEqual(outcome.effects, [])
    }

    func testReloadPausedExpectationSkipsChecksAndCapture() throws {
        // Given: quit while paused; When: reopen; Then: paused directly, no checks, no capture.
        let prefs = try XCTUnwrap(try FX.pausedState().preferences)
        let outcome = reduce(LifecycleState.initial, .reload(prefs))
        XCTAssertEqual(outcome.state.phase, .paused)
        XCTAssertEqual(outcome.effects, [])
    }

    func testReloadCollectingExpectationRequiresFreshReadinessChecks() throws {
        // Given: quit while collecting; When: reopen; Then: reopening, verify before any capture start.
        let prefs = Preferences(currentCycleID: cycle, expectedCollecting: true)
        let outcome = reduce(LifecycleState.initial, .reload(prefs))
        XCTAssertEqual(outcome.state.phase, .reopening)
        XCTAssertEqual(outcome.effects, [.verifyRestartReadiness])
    }

    func testRestartWithOpenChecksStartsCaptureSameCycleWithoutLoginCall() throws {
        // Given: reopening; When: fresh checks prove open; Then: capture starts, same cycle, no login effect.
        let reopening = try FX.reopeningState(loginItemEnabled: true)
        let verified = try run(reopening, .restartReadiness(FX.openConditions), effects: [.startCapture])
        let started = try run(verified, .captureStarted, effects: [])
        XCTAssertEqual(started.phase, .collecting)
        XCTAssertTrue(started.gate.isOpen)
        XCTAssertEqual(started.preferences?.currentCycleID, cycle)
        XCTAssertEqual(started.loginItem, .registered)
    }

    func testRestartWithClosedChecksReturnsToBlockedWithReason() throws {
        // Given: reopening; When: checks show locked session; Then: blocked, typed reason, no capture.
        let reopening = try FX.reopeningState()
        let locked = FX.openConditions.with(sessionLock: .locked)
        let outcome = reduce(reopening, .restartReadiness(locked))
        XCTAssertEqual(outcome.state.phase, .blocked)
        XCTAssertEqual(outcome.state.blockedReason, .sessionLocked)
        XCTAssertFalse(outcome.state.gate.isOpen)
        XCTAssertEqual(outcome.effects, [])
    }

    func testRestartReadinessPortFailureBlocksWithTypedReason() throws {
        // Given: reopening; When: readiness query fails; Then: blocked, typed reason, no capture.
        let reopening = try FX.reopeningState()
        let outcome = reduce(reopening, .restartBlocked(.keyUnavailable))
        XCTAssertEqual(outcome.state.phase, .blocked)
        XCTAssertEqual(outcome.state.blockedReason, .keyUnavailable)
        XCTAssertEqual(outcome.effects, [])
    }

    func testBlockedRetryReRunsFreshChecks() throws {
        // Given: blocked restart; When: user retries; Then: readiness verified again, no polling.
        let state = LifecycleState.blockedForRetry(
            preferences: Preferences(currentCycleID: cycle, expectedCollecting: true), reason: .sessionLocked)
        let outcome = try run(state, .retry, effects: [.verifyRestartReadiness])
        XCTAssertEqual(outcome.phase, .reopening)
    }

    // MARK: - Exclusions

    func testExclusionChangeClosesGateForCurrentForegroundImmediately() throws {
        // Given: collecting with foreground X counted; When: X excluded; Then: gate closed, persist issued.
        let state = try FX.collectingState()
        let outcome = reduce(state, .exclusionsChanged(Set(["com.ex"])))
        XCTAssertEqual(outcome.state.gate.closureReason, .excluded)
        XCTAssertEqual(outcome.state.preferences?.excludedBundleIDs, ["com.ex"])
        XCTAssertEqual(outcome.effects, [.persistPreferences(try XCTUnwrap(outcome.state.preferences))])
    }

    func testExcludingBackgroundBundleKeepsCurrentForegroundGateOpen() throws {
        // Given: foreground X open; When: a different bundle Y is excluded; Then: gate remains open.
        let state = try FX.collectingState()
        let outcome = reduce(state, .exclusionsChanged(Set(["com.other"])))
        XCTAssertTrue(outcome.state.gate.isOpen)
        XCTAssertEqual(outcome.state.preferences?.excludedBundleIDs, ["com.other"])
    }

    func testExclusionPersistFailureKeepsGateClosedWithVisibleNotice() throws {
        // Given: exclusion issued while collecting; When: persist fails; Then: closure stands, notice shown.
        let state = try FX.collectingState()
        let excluded = try run(state, .exclusionsChanged(Set(["com.ex"])))
        let outcome = reduce(excluded, .exclusionsPersistFailed(.filesystemFailure))
        XCTAssertEqual(outcome.state.gate.closureReason, .excluded)
        XCTAssertEqual(outcome.state.notice, .exclusionPersistenceFailed(.filesystemFailure))
        XCTAssertEqual(outcome.state.preferences?.excludedBundleIDs, ["com.ex"])
        XCTAssertEqual(outcome.effects, [])
    }

    // MARK: - Login toggle and notice

    func testLoginToggleWhileIdleNeverRegisters() throws {
        // Given: paused with login item off; When: user enables; Then: visible idle notice, no backend call.
        let prefs = Preferences(currentCycleID: cycle, expectedCollecting: false, loginItemEnabled: false)
        let state = try run(LifecycleState.initial, .reload(prefs))
        XCTAssertEqual(state.loginItem, .unregistered)
        let outcome = reduce(state, .loginItemSetEnabled(true))
        XCTAssertEqual(outcome.effects, [])
        XCTAssertEqual(outcome.state.notice, .loginUnavailableWhileIdle)
        XCTAssertEqual(outcome.state.loginItem, .unregistered)
    }

    func testLoginEnableWhileCollectingRegistersAndPersists() throws {
        // Given: collecting with login off; When: user enables; Then: register then persist on success.
        let state = try FX.collectingStateWithoutLogin()
        let enabling = try run(state, .loginItemSetEnabled(true), effects: [.registerLoginItem])
        XCTAssertEqual(enabling.loginItem, .registering)
        let registered = reduce(enabling, .loginItemRegistered)
        let expected = try XCTUnwrap(registered.state.preferences).updating(loginItemEnabled: true)
        XCTAssertEqual(registered.effects, [.persistPreferences(expected)])
    }

    func testLoginDisableUnregistersAndPersistsFalse() throws {
        // Given: collecting, login registered; When: user disables; Then: unregister then persist false.
        let state = try FX.collectingState()
        let disabling = try run(state, .loginItemSetEnabled(false), effects: [.unregisterLoginItem])
        XCTAssertEqual(disabling.loginItem, .unregistering)
        let unregistered = reduce(disabling, .loginItemUnregistered)
        XCTAssertEqual(unregistered.state.loginItem, .unregistered)
        let expected = try XCTUnwrap(unregistered.state.preferences).updating(loginItemEnabled: false)
        XCTAssertEqual(unregistered.effects, [.persistPreferences(expected)])
    }

    func testLoginUnregistrationRejectionStaysRegisteredAndVisible() throws {
        // Given: unregister in flight; When: system rejects; Then: remains registered, visible notice.
        let state = try FX.collectingState()
        let disabling = try run(state, .loginItemSetEnabled(false))
        let outcome = reduce(disabling, .loginItemUnregistrationRejected(.unregistrationDenied))
        XCTAssertEqual(outcome.state.loginItem, .registered)
        XCTAssertEqual(outcome.state.notice, .loginUnregistrationRejected(.unregistrationDenied))
        XCTAssertEqual(outcome.effects, [])
    }

    func testNoticeDismissalLeavesPhaseAndGateIntact() throws {
        // Given: a visible non-blocking notice; When: dismissed; Then: only the notice clears.
        let state = try FX.collectingState()
        let pausing = try run(state, .pauseRequested)
        let rolledBack = try run(pausing, .pauseFlushFailed(.timedOut))
        let cleared = try run(rolledBack, .dismissNotice, effects: [])
        XCTAssertNil(cleared.notice)
        XCTAssertEqual(cleared.phase, .collecting)
        XCTAssertTrue(cleared.gate.isOpen)
    }
}

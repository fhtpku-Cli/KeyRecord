import XCTest
import KeyRecordCore
import KeyRecordTestSupport

final class LifecycleTests: XCTestCase {
    typealias FX = LifecycleReducerFixtures
    private var cycle: CycleID { FX.cycle }

    private func run(_ state: LifecycleState, _ event: LifecycleEvent,
                     effects expected: [LifecycleEffect]? = nil,
                     file: StaticString = #filePath, line: UInt = #line) throws -> LifecycleState {
        let outcome = reduce(state, event)
        if let expected { XCTAssertEqual(outcome.effects, expected, "event \(event)", file: file, line: line) }
        return outcome.state
    }

    func testUnstartedRequestsConsentBeforeAnyEffect() throws {
        // Given: first run; When: consent is requested; Then: consent phase with no side effects.
        let outcome = reduce(LifecycleState.initial, .consentRequested)
        XCTAssertEqual(outcome.state.phase, .consent)
        XCTAssertTrue(outcome.effects.isEmpty)
        XCTAssertNil(outcome.state.preferences)
    }

    func testConsentDeniedReturnsToUnstartedWithZeroEffects() throws {
        // Given: consent presented; When: denied; Then: unstarted, no key/store/login/capture effects.
        let state = try run(LifecycleState.initial, .consentRequested)
        let outcome = reduce(state, .consentDenied)
        XCTAssertEqual(outcome.state.phase, .unstarted)
        XCTAssertEqual(outcome.effects, [])
        XCTAssertNil(outcome.state.preferences)
        XCTAssertEqual(outcome.state.loginItem, .neverOffered)
    }

    func testConsentAcceptedOrdersKeyBeforePersistBeforeCapture() throws {
        // Given: consent presented; When: accepted; Then: key -> persist(expected) -> capture ordering.
        let state = try run(LifecycleState.initial, .consentRequested)
        let accepted = reduce(state, .consentAccepted(cycleID: cycle))
        XCTAssertEqual(accepted.state.phase, .starting)
        XCTAssertEqual(accepted.effects, [.provisionKey])
        XCTAssertEqual(accepted.state.preferences?.expectedCollecting, true)
        XCTAssertEqual(accepted.state.preferences?.currentCycleID, cycle)
        let provisioned = try run(accepted.state, .keyProvisioned, effects: [
            .persistPreferences(try XCTUnwrap(accepted.state.preferences)),
        ])
        let persisted = try run(provisioned, .bootstrapPersisted, effects: [.startCapture])
        XCTAssertEqual(persisted.phase, .starting)
    }

    func testKeyProvisionFailureIsTypedAndCapturesNothing() throws {
        // Given: bootstrap awaiting key; When: provisioning fails; Then: typed failure, no capture effect.
        let state = try FX.acceptedStartState()
        let outcome = reduce(state, .keyProvisionFailed(.creationDenied))
        XCTAssertEqual(outcome.state.phase, .failed)
        XCTAssertEqual(outcome.state.failure, .keyProvisionFailed(.creationDenied))
        XCTAssertTrue(outcome.effects.isEmpty)
    }

    func testInitialPersistenceFailureIsTypedAndNeverStartsCapture() throws {
        // Given: key provisioned, first persist in flight; When: store fails; Then: typed error, no capture.
        let state = try run(try FX.acceptedStartState(), .keyProvisioned)
        let outcome = reduce(state, .initialPersistenceFailed(.protectedDataUnavailable))
        XCTAssertEqual(outcome.state.phase, .failed)
        XCTAssertEqual(outcome.state.failure, .initialPersistenceFailed(.protectedDataUnavailable))
        XCTAssertEqual(outcome.effects, [])
        XCTAssertFalse(outcome.state.gate.isOpen)
    }

    func testRetryAfterPersistenceFailureRePersistsWithoutRecreatingKey() throws {
        // Given: failed first persist; When: user retries; Then: persist only, key not provisioned again.
        let state = try run(try FX.acceptedStartState(), .keyProvisioned)
        let failed = try run(state, .initialPersistenceFailed(.filesystemFailure))
        let retry = try run(failed, .retry, effects: [.persistPreferences(try XCTUnwrap(state.preferences))])
        XCTAssertEqual(retry.phase, .starting)
    }

    func testCaptureDeniedOnFirstStartIsExplicitFailure() throws {
        // Given: persist done, capture starting; When: system/policy denies; Then: explicit typed failure.
        let state = try run(try run(try FX.acceptedStartState(), .keyProvisioned), .bootstrapPersisted)
        let outcome = reduce(state, .captureStartDenied(.permissionDenied))
        XCTAssertEqual(outcome.state.phase, .failed)
        XCTAssertEqual(outcome.state.failure, .captureStartDenied(.permissionDenied))
        XCTAssertTrue(outcome.effects.isEmpty)
    }

    func testRetryAfterCaptureDeniedRetriesCaptureNotPersistence() throws {
        // Given: capture was denied on first start; When: retried; Then: capture start attempted again.
        let state = try run(try run(try FX.acceptedStartState(), .keyProvisioned), .bootstrapPersisted)
        let failed = try run(state, .captureStartDenied(.permissionDenied))
        let retry = try run(failed, .retry, effects: [.startCapture])
        XCTAssertEqual(retry.phase, .starting)
    }

    func testLoginItemRegistersOnlyAfterFirstSuccessfulCaptureStart() throws {
        // Given: persist done; When: capture starts; Then: collecting, login registration is the only effect.
        let state = try run(try run(try FX.acceptedStartState(), .keyProvisioned), .bootstrapPersisted)
        let outcome = try reduce(state, .captureStarted)
        XCTAssertEqual(outcome.state.phase, .collecting)
        XCTAssertEqual(outcome.effects, [.registerLoginItem])
        XCTAssertEqual(outcome.state.loginItem, .registering)
    }

    func testRegisteredLoginItemPersistsEnabledPreferenceOnce() throws {
        // Given: backend registered after first start; When: acknowledged; Then: persist enabled once.
        let state = try FX.registeringState()
        let outcome = reduce(state, .loginItemRegistered)
        let expected = try XCTUnwrap(outcome.state.preferences).updating(loginItemEnabled: true)
        XCTAssertEqual(outcome.state.loginItem, .registered)
        XCTAssertEqual(outcome.effects, [.persistPreferences(expected)])
        let done = try run(outcome.state, .loginItemRegistrationPersisted, effects: [])
        XCTAssertEqual(done.loginItem, .registered)
    }

    func testRejectedLoginRegistrationStaysCollectingAndVisible() throws {
        // Given: collecting while login registers; When: system rejects; Then: still collecting, visible.
        let state = try FX.registeringState(conditions: FX.openConditions)
        let outcome = reduce(state, .loginItemRegistrationRejected(.registrationDenied))
        XCTAssertEqual(outcome.state.phase, .collecting)
        XCTAssertEqual(outcome.state.loginItem, .rejected(.registrationDenied))
        XCTAssertEqual(outcome.state.notice, .loginRegistrationRejected(.registrationDenied))
        XCTAssertEqual(outcome.effects, [])
        XCTAssertTrue(outcome.state.gate.isOpen)
    }

    func testPauseClosesGateThenFlushesAndPersistsExpectationFalse() throws {
        // Given: collecting; When: pausing; Then: gate closed -> flush -> persist false -> stop.
        let state = try FX.collectingState()
        let pausing = try run(state, .pauseRequested, effects: [.flushWhileUnlocked])
        XCTAssertFalse(pausing.gate.isOpen)
        let expected = try XCTUnwrap(pausing.preferences).updating(expectedCollecting: false)
        let flushed = try run(pausing, .pauseFlushSucceeded, effects: [.persistPreferences(expected)])
        let persisted = try run(flushed, .pausePersisted, effects: [.stopCapture])
        let paused = try run(persisted, .pauseRuntimeStopped, effects: [])
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.preferences?.expectedCollecting, false)
    }

    func testPauseFlushFailureRollsBackToCollectingWithVisibleNotice() throws {
        // Given: pausing with flush in flight; When: flush fails; Then: not paused, collecting, visible.
        let state = try FX.collectingState()
        let pausing = try run(state, .pauseRequested)
        let outcome = reduce(pausing, .pauseFlushFailed(.timedOut))
        XCTAssertEqual(outcome.state.phase, .collecting)
        XCTAssertEqual(outcome.state.notice, .pauseFlushFailed(.timedOut))
        XCTAssertTrue(outcome.state.gate.isOpen)
        XCTAssertEqual(outcome.effects, [])
    }

    func testPausePersistenceFailureIsExplicitAndRetryCompletesPause() throws {
        // Given: flush succeeded, expectation persist fails; When: retry; Then: persist -> stop -> paused.
        let state = try FX.collectingState()
        let pausing = try run(state, .pauseRequested)
        let flushed = try run(pausing, .pauseFlushSucceeded)
        let failed = try run(flushed, .pausePersistenceFailed(.filesystemFailure))
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.failure, .pausePersistenceFailed(.filesystemFailure))
        let expected = try XCTUnwrap(flushed.preferences).updating(expectedCollecting: false)
        let retry = try run(failed, .retry, effects: [.persistPreferences(expected)])
        let stopped = try run(try run(retry, .pausePersisted, effects: [.stopCapture]),
                                .pauseRuntimeStopped, effects: [])
        XCTAssertEqual(stopped.phase, .paused)
    }

    func testResumeFromPausedPersistsTrueBeforeCaptureStart() throws {
        // Given: paused; When: resume; Then: persist expectation true, then start, no key provisioning.
        let state = try FX.pausedState()
        let expected = try XCTUnwrap(state.preferences).updating(expectedCollecting: true)
        let resuming = try run(state, .resumeRequested, effects: [.persistPreferences(expected)])
        XCTAssertEqual(resuming.phase, .resuming)
        let started = try run(try run(resuming, .resumePersisted, effects: [.startCapture]),
                                 .captureStarted, effects: [])
        XCTAssertEqual(started.phase, .collecting)
        XCTAssertTrue(started.gate.isOpen)
    }

    func testResumeCaptureDeniedIsExplicitFailureWithoutSilence() throws {
        // Given: resuming; When: start denied; Then: explicit failure state the user can retry.
        let state = try FX.pausedState()
        let resuming = try run(state, .resumeRequested)
        let persisted = try run(resuming, .resumePersisted)
        let outcome = reduce(persisted, .captureStartDenied(.permissionDenied))
        XCTAssertEqual(outcome.state.phase, .failed)
        XCTAssertEqual(outcome.state.failure, .captureStartDenied(.permissionDenied))
    }
}

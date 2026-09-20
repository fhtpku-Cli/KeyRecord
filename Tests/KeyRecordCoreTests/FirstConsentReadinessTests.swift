import XCTest
import KeyRecordCore
import KeyRecordTestSupport

/// KR-06 regression, promoted from the review-only `ReviewFirstConsentProbe.swift` into a
/// permanent XCTest.
///
/// The defect: the first-consent success sequence reached `.collecting` while
/// `conditions` stayed `.unknown`, so the lifecycle gate closed with `keyUnavailable`,
/// `SensitiveVisibility` returned false and the aggregate screen showed nothing even
/// though capture had its own gate open. The App compounded this by calling
/// `capture.verifyRestartReadiness()` and discarding the returned `RuntimeConditions`.
///
/// The contract asserted here: first consent and restart share one readiness transition,
/// and the verified conditions are written into lifecycle state before `.collecting`.
final class FirstConsentReadinessTests: XCTestCase {
    typealias FX = LifecycleReducerFixtures

    private let safe = RuntimeConditions(
        keyAvailability: .available, sessionLock: .unlocked,
        secureInput: .disabled, foreground: .attributable(bundleID: "com.ex"))

    // MARK: - Shared readiness transition

    func testFirstConsentVerifiesReadinessBeforeStartingCapture() throws {
        // Given: consent accepted and the first preference write committed.
        let provisioned = FX.transition(try FX.acceptedStartState(), .keyProvisioned)
        // When: the bootstrap persist completes.
        let outcome = reduce(provisioned, .bootstrapPersisted)
        // Then: readiness is verified first; capture is NOT started on an unverified state.
        XCTAssertEqual(outcome.effects, [.verifyRestartReadiness])
        XCTAssertEqual(outcome.state.phase, .starting)
    }

    func testFirstConsentWritesVerifiedConditionsIntoStateThenStartsCapture() throws {
        // Given: first start awaiting readiness.
        let awaiting = FX.transition(FX.transition(try FX.acceptedStartState(), .keyProvisioned),
                                     .bootstrapPersisted)
        // When: the readiness check returns real runtime conditions.
        let outcome = reduce(awaiting, .restartReadiness(safe))
        // Then: the conditions are retained, not discarded, and capture starts.
        XCTAssertEqual(outcome.state.conditions, safe)
        XCTAssertEqual(outcome.effects, [.startCapture])
    }

    func testFirstConsentSuccessSequenceLeavesGateOpenAndAggregateVisible() throws {
        // Given / When: the exact success sequence the review probe replayed.
        var state = LifecycleState.initial
        for event in [LifecycleEvent.consentRequested,
                      .consentAccepted(cycleID: FX.cycle),
                      .keyProvisioned,
                      .bootstrapPersisted,
                      .restartReadiness(safe),
                      .captureStarted,
                      .loginItemRegistrationRejected(.registrationDenied)] {
            state = reduce(state, event).state
        }
        // Then: the probe's reproduced defect must no longer hold.
        XCTAssertEqual(state.phase, .collecting)
        XCTAssertEqual(state.conditions, safe, "verified conditions must not be discarded")
        XCTAssertNil(state.gate.closureReason, "gate must be open after a verified first consent")
        XCTAssertTrue(state.gate.isOpen)
        XCTAssertTrue(SensitiveVisibility.isVisible(state), "aggregate must be visible")
    }

    func testFirstConsentWithUnsafeConditionsBlocksInsteadOfFakeCollecting() throws {
        // Given: first start awaiting readiness; When: the session is locked.
        let awaiting = FX.transition(FX.transition(try FX.acceptedStartState(), .keyProvisioned),
                                     .bootstrapPersisted)
        let locked = RuntimeConditions(keyAvailability: .available, sessionLock: .locked,
                                       secureInput: .disabled,
                                       foreground: .attributable(bundleID: "com.ex"))
        let outcome = reduce(awaiting, .restartReadiness(locked))
        // Then: fail closed with a visible reason; never claim collecting.
        XCTAssertEqual(outcome.effects, [])
        XCTAssertEqual(outcome.state.phase, .blocked)
        XCTAssertEqual(outcome.state.blockedReason, .sessionLocked)
        XCTAssertFalse(SensitiveVisibility.isVisible(outcome.state))
    }

    func testFirstConsentReadinessFailureBlocksWithTypedReason() throws {
        let awaiting = FX.transition(FX.transition(try FX.acceptedStartState(), .keyProvisioned),
                                     .bootstrapPersisted)
        let outcome = reduce(awaiting, .restartBlocked(.secureInputActive))
        XCTAssertEqual(outcome.state.phase, .blocked)
        XCTAssertEqual(outcome.state.blockedReason, .secureInputActive)
        XCTAssertEqual(outcome.effects, [])
    }

    func testRestartUsesTheSameReadinessTransitionAsFirstConsent() throws {
        // Given: a reopen after a collecting-expectation restart.
        let reopening = try FX.reopeningState()
        XCTAssertEqual(reopening.phase, .reopening)
        // When / Then: identical readiness semantics as the first-consent path.
        let outcome = reduce(reopening, .restartReadiness(safe))
        XCTAssertEqual(outcome.state.conditions, safe)
        XCTAssertEqual(outcome.effects, [.startCapture])
        let collecting = reduce(outcome.state, .captureStarted).state
        XCTAssertEqual(collecting.phase, .collecting)
        XCTAssertTrue(collecting.gate.isOpen)
        XCTAssertTrue(SensitiveVisibility.isVisible(collecting))
    }

    // MARK: - Orchestrator-level wiring (ports actually invoked)

    @MainActor
    func testOrchestratorAcceptConsentSyncsConditionsFromTheReadinessPort() async throws {
        let harness = LifecycleHarness()
        await harness.startConsented()
        // The readiness port is consulted exactly once by the accept path…
        let checks = await harness.readiness.checkCount
        XCTAssertEqual(checks, 1)
        // …and its result lands in lifecycle state without a separate observe() call.
        XCTAssertEqual(harness.orchestrator.state.conditions, LifecycleHarnessConditions.open)
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertTrue(harness.orchestrator.state.gate.isOpen)
        XCTAssertTrue(SensitiveVisibility.isVisible(harness.orchestrator.state))
        let starts = await harness.capture.startCount
        XCTAssertEqual(starts, 1)
    }

    @MainActor
    func testOrchestratorAcceptConsentBlocksWithoutStartingCaptureWhenLocked() async throws {
        let harness = LifecycleHarness(readinessResult: .failure(.sessionLocked))
        await harness.startConsented()
        XCTAssertEqual(harness.orchestrator.phase, .blocked)
        XCTAssertEqual(harness.orchestrator.state.blockedReason, .sessionLocked)
        let starts = await harness.capture.startCount
        XCTAssertEqual(starts, 0, "capture must not start on a blocked readiness result")
        XCTAssertFalse(SensitiveVisibility.isVisible(harness.orchestrator.state))
    }

    @MainActor
    func testResumeVerifiesReadinessAndSyncsConditions() async throws {
        let harness = LifecycleHarness()
        await harness.startConsented()
        await harness.orchestrator.pause()
        XCTAssertEqual(harness.orchestrator.phase, .paused)
        await harness.orchestrator.resume()
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(harness.orchestrator.state.conditions, LifecycleHarnessConditions.open)
        XCTAssertTrue(harness.orchestrator.state.gate.isOpen,
                      "resume must reach an open gate through the shared readiness transition")
        XCTAssertTrue(SensitiveVisibility.isVisible(harness.orchestrator.state))
    }

    @MainActor
    func testResumeBlocksWhenReadinessFailsAndDoesNotStartCapture() async throws {
        let harness = LifecycleHarness()
        await harness.startConsented()
        await harness.orchestrator.pause()
        let startsBefore = await harness.capture.startCount
        await harness.readiness.setResult(.failure(.secureInputActive))
        await harness.orchestrator.resume()
        XCTAssertEqual(harness.orchestrator.phase, .blocked)
        XCTAssertEqual(harness.orchestrator.state.blockedReason, .secureInputActive)
        let startsAfter = await harness.capture.startCount
        XCTAssertEqual(startsAfter, startsBefore, "resume must not start capture while blocked")
    }
}

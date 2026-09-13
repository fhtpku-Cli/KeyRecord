import XCTest
import KeyRecordCore
import KeyRecordTestSupport

// MARK: - In-test fakes (reset/erase ports are introduced by task 18)

private actor CountingCycleReset: CycleResetting {
    private(set) var callCount = 0
    func performCycleReset() async throws { callCount += 1 }
}

private actor CountingLocalDataEraser: LocalDataErasing {
    private(set) var callCount = 0
    func eraseAllLocalData() async throws { callCount += 1 }
}

/// Records the post-erase re-arm contract; T19 supplies the real orchestrator mechanics.
@MainActor
private final class FakeLifecycleDriver: LifecycleDriving {
    var state: LifecycleState
    private(set) var rearmCount = 0

    init(state: LifecycleState = .initial) { self.state = state }

    func returnToConsentRequired() async {
        rearmCount += 1
        state = .initial
    }
}

// MARK: - State fixtures

private func openGateCollectingState() -> LifecycleState {
    var gate = PrivacyGate()
    gate.update(GateInputs(collecting: true, keyAvailability: .available,
                           sessionLock: .unlocked, secureInput: .disabled,
                           foreground: .attributable(bundleID: "com.ex"),
                           exclusion: .included))
    return LifecycleState(phase: .collecting, conditions: LifecycleHarnessConditions.open, gate: gate)
}

private func secureInputCollectingState() -> LifecycleState {
    var gate = PrivacyGate()
    gate.update(GateInputs(collecting: true, keyAvailability: .available,
                           sessionLock: .unlocked, secureInput: .enabled,
                           foreground: .attributable(bundleID: "com.ex"),
                           exclusion: .included))
    return LifecycleState(phase: .collecting, gate: gate)
}

private let blockedPreferences = Preferences(currentCycleID: CycleID(rawValue: "t18-cycle"))

// MARK: - Tests

@MainActor
final class Phase1FlowModelTests: XCTestCase {
    func testResetCancelMakesNoPortCallAndClearsDialog() async throws {
        // Given: collecting phase with a reset dialog up; When: the user cancels;
        // Then: the reset port is never called and the dialog is dismissed.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let reset = CountingCycleReset()
        let model = Phase1FlowModel(lifecycle: harness.orchestrator, cycleReset: reset)
        model.requestReset()
        guard case .resetConfirmation = model.dialog else { return XCTFail("expected reset proposal") }
        try await model.choose(.cancel)
        XCTAssertEqual(model.dialog, .none)
        let calls = await reset.callCount
        XCTAssertEqual(calls, 0)
    }

    func testResetConfirmCallsPortExactlyOnceThenClearsDialog() async throws {
        // Given: collecting phase with a reset dialog up; When: the user confirms;
        // Then: the reset port runs exactly once and the dialog is dismissed.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let reset = CountingCycleReset()
        let model = Phase1FlowModel(lifecycle: harness.orchestrator, cycleReset: reset)
        model.requestReset()
        try await model.choose(.confirm)
        let calls = await reset.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.dialog, .none)
    }

    func testResetConfirmWithoutPortThrowsActionUnavailable() async throws {
        // Given: the reset proposal is visible without a wired reset port; When: confirmed;
        // Then: a typed actionUnavailable is thrown and the dialog stays for cancel/retry.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let model = Phase1FlowModel(lifecycle: harness.orchestrator)
        model.requestReset()
        do {
            try await model.choose(.confirm)
            XCTFail("expected FlowError.actionUnavailable")
        } catch FlowError.actionUnavailable {
            guard case .resetConfirmation = model.dialog else { return XCTFail("dialog should remain") }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDeleteCancelMakesNoEraseCall() async throws {
        // Given: a delete dialog in a post-consent phase; When: the user cancels;
        // Then: no erase, no re-arm, dialog dismissed.
        let driver = FakeLifecycleDriver(state: openGateCollectingState())
        let eraser = CountingLocalDataEraser()
        let model = Phase1FlowModel(lifecycle: driver, localDataEraser: eraser)
        model.requestDeleteLocalData()
        guard case .deleteConfirmation = model.dialog else { return XCTFail("expected delete proposal") }
        try await model.choose(.cancel)
        XCTAssertEqual(model.dialog, .none)
        let eraseCalls = await eraser.callCount
        XCTAssertEqual(eraseCalls, 0)
        XCTAssertEqual(driver.rearmCount, 0)
    }

    func testDeleteConfirmErasesOnceAndReturnsToConsentRequired() async throws {
        // Given: a delete dialog in a collecting phase; When: the user confirms;
        // Then: erase runs exactly once, consent is re-armed, dialog dismissed.
        let driver = FakeLifecycleDriver(state: openGateCollectingState())
        let eraser = CountingLocalDataEraser()
        let model = Phase1FlowModel(lifecycle: driver, localDataEraser: eraser)
        model.requestDeleteLocalData()
        try await model.choose(.confirm)
        let eraseCalls = await eraser.callCount
        XCTAssertEqual(eraseCalls, 1)
        XCTAssertEqual(driver.rearmCount, 1)
        XCTAssertEqual(driver.state.phase, .unstarted)
        XCTAssertEqual(model.dialog, .none)
    }

    func testResetUnavailableWhenUnstarted() {
        // Given: no consent yet; When: reset is requested; Then: no dialog is offered.
        let model = Phase1FlowModel(lifecycle: FakeLifecycleDriver())
        model.requestReset()
        XCTAssertEqual(model.dialog, .none)
    }

    func testDeleteUnavailableWhenUnstarted() {
        // Given: no consent yet; When: delete is requested; Then: no dialog is offered.
        let model = Phase1FlowModel(lifecycle: FakeLifecycleDriver())
        model.requestDeleteLocalData()
        XCTAssertEqual(model.dialog, .none)
    }

    func testSensitiveVisibilityMatrix() {
        // Given/When/Then: visibility is true only in steady collecting/paused phases
        // without a sensitive closure; lock, secure input, blocks, errors, and unstarted
        // all hide sensitive content.
        XCTAssertTrue(SensitiveVisibility.isVisible(openGateCollectingState()))
        XCTAssertTrue(SensitiveVisibility.isVisible(LifecycleState(phase: .paused)))
        XCTAssertFalse(SensitiveVisibility.isVisible(.initial))
        XCTAssertFalse(SensitiveVisibility.isVisible(
            LifecycleState.blockedForRetry(preferences: blockedPreferences, reason: .sessionLocked)))
        XCTAssertFalse(SensitiveVisibility.isVisible(secureInputCollectingState()))
        XCTAssertFalse(SensitiveVisibility.isVisible(
            LifecycleState(phase: .failed, failure: .preferencesLoadFailed(.filesystemFailure))))
    }

    func testDisplayedAggregateHiddenWhenNotVisible() {
        // Given: totals are set while collecting; When: the session locks (blocked);
        // Then: the getter hides the retained raw snapshot, and reveals it again on
        // return to a visible phase.
        let driver = FakeLifecycleDriver(state: openGateCollectingState())
        let model = Phase1FlowModel(lifecycle: driver)
        let snapshot = AggregateSnapshot(shortcutTotal: 42, bareKeyTotal: 7)
        model.displayedAggregate = snapshot
        XCTAssertEqual(model.displayedAggregate, snapshot)
        driver.state = LifecycleState.blockedForRetry(preferences: blockedPreferences,
                                                      reason: .secureInputActive)
        XCTAssertNil(model.displayedAggregate)
        driver.state = openGateCollectingState()
        XCTAssertEqual(model.displayedAggregate, snapshot)
    }
}

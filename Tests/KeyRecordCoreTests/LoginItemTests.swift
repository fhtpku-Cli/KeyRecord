import XCTest
import KeyRecordCore
import KeyRecordTestSupport

@MainActor
final class LoginItemTests: XCTestCase {
    // MARK: - Pure policy

    func testRegistrationIsAllowedOnlyWhileCollecting() {
        // Given: every lifecycle phase; When: asking whether registration may run; Then: collecting only.
        for phase in LifecyclePhase.allPhases {
            XCTAssertEqual(LoginItemPolicy.allowsRegistration(phase), phase == .collecting)
        }
    }

    func testEnableIntentsRegisterOnlyWhileCollectingAndNotRegistered() {
        // Given: collecting with an unregistered login item; When: enabling; Then: register intent.
        XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: true, phase: .collecting, status: .neverOffered), .register)
        XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: true, phase: .collecting, status: .rejected(.registrationDenied)), .register)
        XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: true, phase: .collecting, status: .registered), .none)
        XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: true, phase: .collecting, status: .registering), .none)
    }

    func testEnableWhileIdleYieldsNoIntent() {
        // Given: non-collecting phases; When: enabling; Then: no intent, the controller shows guidance.
        for phase in [LifecyclePhase.unstarted, .paused, .stopped, .blocked] {
            XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: true, phase: phase, status: .neverOffered), .none)
        }
    }

    func testDisableUnregistersOnlyWhenRegistered() {
        // Given: registered vs other statuses; When: disabling; Then: exactly one unregister intent.
        XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: false, phase: .paused, status: .registered), .unregister)
        XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: false, phase: .collecting, status: .unregistered), .none)
        XCTAssertEqual(LoginItemPolicy.intent(forDesiredEnabled: false, phase: .collecting, status: .rejected(.registrationDenied)), .none)
    }

    // MARK: - Orchestration

    func testLoginItemRegistersAfterFirstSuccessfulStartAndPersistsEnabled() async throws {
        // Given: denied backend is absent; When: consent completes; Then: one register after capture start.
        let harness = LifecycleHarness()
        await harness.startConsented()
        let captureStarts = await harness.capture.startCount
        let registrations = await harness.login.registerCount
        let storedPreferences = await harness.storedPreferences()
        let stored = try XCTUnwrap(storedPreferences)
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(captureStarts, 1)
        XCTAssertEqual(registrations, 1)
        XCTAssertTrue(stored.loginItemEnabled)
    }

    func testRejectedRegistrationStaysCollectingVisibleAndPersistsNothingEnabled() async throws {
        // Given: a system that rejects SMAppService registration; When: first start succeeds; Then: visible.
        let harness = LifecycleHarness(loginRegisterFailure: .registrationDenied)
        await harness.startConsented()
        let storedPreferences = await harness.storedPreferences()
        let stored = try XCTUnwrap(storedPreferences)
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(harness.orchestrator.state.loginItem, .rejected(.registrationDenied))
        XCTAssertEqual(harness.orchestrator.state.notice, .loginRegistrationRejected(.registrationDenied))
        XCTAssertFalse(stored.loginItemEnabled)
        // Collection remains usable: pause after rejection still drives the flush transaction.
        await harness.orchestrator.pause()
        XCTAssertEqual(harness.orchestrator.phase, .paused)
    }

    func testReloadNeverPollsOrRegistersLoginItem() async throws {
        // Given: stored expectation with login enabled; When: reopening; Then: zero login backend calls.
        let prefs = Preferences(currentCycleID: CycleID(rawValue: "reopen-cycle"),
                                expectedCollecting: true, loginItemEnabled: true)
        let storage = InMemoryPreferencesStorage(ciphertext: try PreferencesRepository.encode(prefs))
        let harness = LifecycleHarness(storage: storage)
        await harness.orchestrator.reload()
        let registrations = await harness.login.registerCount
        let unregistrations = await harness.login.unregisterCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(registrations, 0)
        XCTAssertEqual(unregistrations, 0)
    }

    func testManualDisableUnregistersAndPersistsFalse() async throws {
        // Given: collecting with registered login item; When: user disables; Then: unregister, persist false.
        let harness = LifecycleHarness()
        await harness.collectOpen()
        await harness.orchestrator.setLoginItem(enabled: false)
        let unregistrations = await harness.login.unregisterCount
        let storedPreferences = await harness.storedPreferences()
        let stored = try XCTUnwrap(storedPreferences)
        XCTAssertEqual(unregistrations, 1)
        XCTAssertEqual(harness.orchestrator.state.loginItem, .unregistered)
        XCTAssertFalse(stored.loginItemEnabled)
    }

    func testUnregisterRejectionStaysRegisteredWithVisibleNotice() async throws {
        // Given: a system rejecting unregistration; When: user disables; Then: registered + visible notice.
        let harness = LifecycleHarness(loginUnregisterFailure: .unregistrationDenied)
        await harness.collectOpen()
        await harness.orchestrator.setLoginItem(enabled: false)
        let storedPreferences = await harness.storedPreferences()
        let stored = try XCTUnwrap(storedPreferences)
        XCTAssertEqual(harness.orchestrator.state.loginItem, .registered)
        XCTAssertEqual(harness.orchestrator.state.notice, .loginUnregistrationRejected(.unregistrationDenied))
        XCTAssertTrue(stored.loginItemEnabled)
    }
}

private extension LifecyclePhase {
    static var allPhases: [LifecyclePhase] {
        [.unstarted, .consent, .starting, .collecting, .pausing, .paused, .resuming,
         .stopping, .stopped, .reopening, .blocked, .failed]
    }
}

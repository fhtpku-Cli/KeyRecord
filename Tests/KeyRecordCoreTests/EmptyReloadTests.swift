import XCTest
import KeyRecordCore
import KeyRecordTestSupport

/// KR-09 — found by live diagnostics on 2026-09-18.
///
/// Symptom: the Developer diagnosis line read
/// `layer 0: no capture session is live (no reason recorded)`.
/// "No reason recorded" was the real clue: the lifecycle had no blocked reason at all,
/// meaning it never reached a blocking transition — it simply did nothing.
///
/// Cause: `handleUnstarted` treats `.reload(nil)` as `guard let loaded else { return [] }`.
/// No phase change, no failure, no reason. The app sits at `.unstarted` forever and the
/// user is given nothing to act on.
///
/// Why that is not merely cosmetic: `ProductPersistence.load()` returns nil **only** when
/// the store reports `.freshInstall`. On this machine the store already held a
/// `manifest.krenc` and the Keychain already held `master-v1`, so "fresh install" was a
/// misread of existing state, most plausibly because the newly signed binary could not
/// reach the Keychain items created by the previous build. Silently presenting that as a
/// blank first run risks the user consenting again and provisioning a second key over
/// data that is still there.
///
/// Contract: a nil reload must be an explicit, named outcome — never a silent no-op.
final class EmptyReloadTests: XCTestCase {
    typealias FX = LifecycleReducerFixtures

    func testNilReloadFromUnstartedIsNotASilentNoOp() {
        let outcome = reduce(LifecycleState.initial, .reload(nil))
        // Previously: phase stayed .unstarted, blockedReason stayed nil, effects empty —
        // producing "no reason recorded" in the diagnosis.
        XCTAssertNotNil(outcome.state.blockedReason ?? outcome.state.failure.map { _ in BlockedReason.keyUnavailable },
                        "a nil reload must leave an actionable reason behind")
    }

    func testNilReloadReportsFreshInstallAsAnExplicitPhase() {
        let outcome = reduce(LifecycleState.initial, .reload(nil))
        // A genuine first run is legitimate, but it must be *stated*, so the UI can invite
        // consent instead of showing an unexplained blocked state.
        XCTAssertEqual(outcome.state.phase, .unstarted)
        XCTAssertEqual(outcome.state.blockedReason, .keyUnavailable,
                       "nil reload must name why nothing is running")
    }

    func testNilReloadDoesNotFabricatePreferencesOrClaimCollecting() {
        let outcome = reduce(LifecycleState.initial, .reload(nil))
        XCTAssertNil(outcome.state.preferences, "must never invent preferences")
        XCTAssertNotEqual(outcome.state.phase, .collecting)
        XCTAssertTrue(outcome.effects.isEmpty, "must not start capture or provision a key")
        XCTAssertFalse(SensitiveVisibility.isVisible(outcome.state))
    }

    func testNilReloadNeverOverwritesPreferencesAlreadyLoaded() {
        // Guards the dangerous case: a transient nil must not erase known state.
        let loaded = FX.transition(LifecycleState.initial,
                                   .reload(Preferences(currentCycleID: FX.cycle,
                                                       expectedCollecting: true)))
        let after = reduce(loaded, .reload(nil))
        XCTAssertNotNil(after.state.preferences,
                        "an unreadable reload must not discard preferences already held")
    }

    func testExplicitConsentStillWorksAfterANilReload() {
        // The user must retain a path forward from the named state.
        let blocked = FX.transition(LifecycleState.initial, .reload(nil))
        let consenting = reduce(blocked, .consentRequested)
        XCTAssertEqual(consenting.state.phase, .consent)
    }
}

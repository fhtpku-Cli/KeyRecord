import XCTest
import KeyRecordCore
import KeyRecordTestSupport

/// KR-08 regression — found by live verification on 2026-09-18, not by the code review.
///
/// Observed on a signed build at a fixed path: the menu bar read `● Collecting` while the
/// process held zero store handles, wrote nothing, and counted nothing from ~10 real
/// arrow-key presses.
///
/// Cause: `statusTitle` decides purely from `lifecycle.phase` plus the **key-availability**
/// gate. Neither of those proves an event source is actually installed. `boot()` primes the
/// key gate to `.unlocked` before restore, and the restored `expectedCollecting=true` drives
/// the phase toward collecting, so both inputs look healthy even when capture never started.
///
/// This is the same family as KR-06 (UI state diverging from real capture state) but on the
/// restart-recovery path, which KR-06 did not cover.
///
/// Contract: a "Collecting" claim requires a live capture session. Without one the UI must
/// say BLOCKED and name a reason.
final class StatusTruthfulnessTests: XCTestCase {

    func testCollectingIsNotClaimedWhenNoCaptureSessionIsLive() {
        // Given: the exact live-verification state — phase collecting, key gate open,
        // but no event source installed.
        let title = CaptureStatusPresentation.title(phase: .collecting, reason: nil,
                                                   gateOpen: true, captureSessionLive: false)
        // Then: the UI must not claim collecting.
        XCTAssertNotEqual(title, "● Collecting",
                          "UI claimed Collecting while no capture session existed")
        XCTAssertTrue(title.hasPrefix("BLOCKED"), title)
    }

    func testCollectingIsClaimedOnlyWithALiveSession() {
        let title = CaptureStatusPresentation.title(phase: .collecting, reason: nil,
                                                   gateOpen: true, captureSessionLive: true)
        XCTAssertEqual(title, "● Collecting")
    }

    func testMissingSessionWithoutAReasonDoesNotBlameTheScreenLock() {
        // Live verification showed "BLOCKED — locked" when the real cause was a missing
        // capture session, not a locked screen. A wrong reason sends the user to the wrong
        // remedy, so the no-reason case must name the actual condition.
        let title = CaptureStatusPresentation.title(phase: .collecting, reason: nil,
                                                    gateOpen: true, captureSessionLive: false)
        XCTAssertEqual(title, "BLOCKED — capture not running")
        XCTAssertFalse(title.contains("locked"), "must not blame the screen lock: \(title)")
    }

    func testClosedKeyGateWithoutAReasonStillReportsLocked() {
        // A closed key gate with no typed reason genuinely is the locked/unknown case.
        let title = CaptureStatusPresentation.title(phase: .collecting, reason: nil,
                                                    gateOpen: false, captureSessionLive: true)
        XCTAssertEqual(title, "BLOCKED — locked")
    }

    func testMissingSessionReportsAnActionableReasonNotABareLocked() {
        // A dead session is not the same as a locked screen; the reason must not mislead.
        let title = CaptureStatusPresentation.title(phase: .collecting, reason: .sessionLocked,
                                                   gateOpen: true, captureSessionLive: false)
        XCTAssertEqual(title, "BLOCKED — sessionLocked")
    }

    func testPausedAndStoppedAreUnaffectedByTheLivenessCheck() {
        // Pause/stop legitimately have no live session; they must keep their own wording.
        XCTAssertEqual(CaptureStatusPresentation.title(phase: .paused, reason: nil,
                                                      gateOpen: true, captureSessionLive: false),
                       "❚❚ Paused")
        XCTAssertEqual(CaptureStatusPresentation.title(phase: .stopped, reason: nil,
                                                      gateOpen: true, captureSessionLive: false),
                       "■ Stopped")
        XCTAssertEqual(CaptureStatusPresentation.title(phase: .unstarted, reason: nil,
                                                      gateOpen: true, captureSessionLive: false),
                       "Not started")
    }

    func testClosedKeyGateStillBlocksEvenWithALiveSession() {
        // Existing fail-closed behaviour must survive the new parameter.
        let title = CaptureStatusPresentation.title(phase: .collecting, reason: .keyUnavailable,
                                                   gateOpen: false, captureSessionLive: true)
        XCTAssertEqual(title, "BLOCKED — keyUnavailable")
    }
}

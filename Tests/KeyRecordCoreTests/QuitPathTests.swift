import XCTest
import KeyRecordCore
import KeyRecordTestSupport

/// Quit-path regression, found live on 2026-09-18: two `kill -TERM` attempts did not end
/// the process, and it finally needed `SIGKILL`.
///
/// Mechanism: `applicationShouldTerminate` returns `.terminateLater` and answers with
/// `prepareQuit()`. When the durable flush cannot complete, the reducer deliberately
/// returns to `.collecting` (contract 8: never claim data was saved). `prepareQuit()` then
/// returns false, AppKit **cancels the termination**, and the user is left with an app that
/// refuses to quit and no way out.
///
/// Both halves of that are right on their own — the flush contract must not lie, and
/// `.terminateLater` must be answered honestly. What was missing is a bounded outcome: the
/// reducer's own quit contract has to be reachable, and a quit that cannot flush must be
/// distinguishable from a quit that simply hangs.
final class QuitPathTests: XCTestCase {
    typealias FX = LifecycleReducerFixtures

    func testSuccessfulQuitReachesStoppedSoTerminationCanProceed() throws {
        let collecting = try FX.collectingState()
        let stopping = FX.transition(collecting, .quitRequested)
        XCTAssertEqual(stopping.phase, .stopping)
        let flushed = FX.transition(stopping, .quitFlushSucceeded)
        let stopped = FX.transition(flushed, .quitRuntimeStopped)
        XCTAssertEqual(stopped.phase, .stopped, "a clean quit must reach .stopped")
    }

    func testFailedFlushReturnsToCollectingAndSurfacesTheReason() throws {
        // Contract 8: a failed flush must never be reported as a successful save.
        let collecting = try FX.collectingState()
        let stopping = FX.transition(collecting, .quitRequested)
        let failed = FX.transition(stopping, .quitFlushFailed(.timedOut))
        XCTAssertEqual(failed.phase, .collecting, "must not claim stopped after a failed flush")
        XCTAssertEqual(failed.notice, .quitFlushFailed(.timedOut),
                       "the user must be told why quitting did not complete")
    }

    func testQuitIsRetryableAfterAFailedFlush() throws {
        // The live hang left no way forward. A second quit must still be able to succeed,
        // otherwise the only exit is SIGKILL.
        let collecting = try FX.collectingState()
        let failed = FX.transition(FX.transition(collecting, .quitRequested),
                                   .quitFlushFailed(.timedOut))
        let retry = FX.transition(failed, .quitRequested)
        XCTAssertEqual(retry.phase, .stopping, "quit must be retryable, not a dead end")
        let stopped = FX.transition(FX.transition(retry, .quitFlushSucceeded), .quitRuntimeStopped)
        XCTAssertEqual(stopped.phase, .stopped)
    }

    func testQuitFromAPhaseWithNoLiveSessionStillTerminates() throws {
        // The live case: KR-08 left phase == .collecting with no capture session, so quit
        // tried to flush a session that never existed. Quitting from a paused/blocked-like
        // state must still reach a terminal phase rather than looping.
        let paused = try FX.pausedState()
        let stopping = FX.transition(paused, .quitRequested)
        XCTAssertEqual(stopping.phase, .stopping)
        // Paused already flushed durably, so quit only stops the runtime.
        let stopped = FX.transition(stopping, .quitRuntimeStopped)
        XCTAssertEqual(stopped.phase, .stopped)
    }

    @MainActor
    func testOrchestratorQuitCompletesAndReportsStopped() async throws {
        let harness = LifecycleHarness()
        await harness.startConsented()
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        await harness.orchestrator.quit()
        XCTAssertEqual(harness.orchestrator.phase, .stopped,
                       "quit must finish; a stuck quit is what forced SIGKILL live")
        let stops = await harness.capture.stopCount
        XCTAssertGreaterThan(stops, 0, "the event source must actually be stopped")
    }

    @MainActor
    func testOrchestratorQuitWithFailingFlushDoesNotClaimStopped() async throws {
        let harness = LifecycleHarness(flushFailure: .timedOut)
        await harness.startConsented()
        await harness.orchestrator.quit()
        // Honest: not stopped, and the reason is visible.
        XCTAssertNotEqual(harness.orchestrator.phase, .stopped)
        XCTAssertEqual(harness.orchestrator.state.notice, .quitFlushFailed(.timedOut))
    }
}

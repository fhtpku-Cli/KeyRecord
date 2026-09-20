import XCTest
import KeyRecordCore
import KeyRecordTestSupport

@MainActor
final class RuntimeRecoveryTests: XCTestCase {
    private actor Barrier {
        private var arrived = false
        private var arrivalWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func wait() async {
            arrived = true
            arrivalWaiter?.resume()
            arrivalWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }

        func waitUntilArrived() async {
            if arrived { return }
            await withCheckedContinuation { arrivalWaiter = $0 }
        }

        func release() {
            releaseWaiter?.resume()
            releaseWaiter = nil
        }
    }

    func testSleepRequiresExplicitRetryAndPreservesCollectingIntent() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let startsBeforeSleep = await harness.capture.startCount

        harness.orchestrator.requireRecovery(reason: .sessionLocked)

        XCTAssertEqual(harness.orchestrator.phase, .blocked)
        XCTAssertEqual(harness.orchestrator.state.blockedReason, .sessionLocked)
        XCTAssertEqual(harness.orchestrator.state.preferences?.expectedCollecting, true)
        let startsWhileBlocked = await harness.capture.startCount
        XCTAssertEqual(startsWhileBlocked, startsBeforeSleep)

        await harness.orchestrator.retry()

        let checksAfterRetry = await harness.readiness.checkCount
        let startsAfterRetry = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(checksAfterRetry, 2)
        XCTAssertEqual(startsAfterRetry, startsBeforeSleep + 1)
    }

    func testRecoveryRequestLeavesPausedIntentPaused() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        await harness.orchestrator.pause()
        let checksBeforeSleep = await harness.readiness.checkCount
        let startsBeforeSleep = await harness.capture.startCount

        harness.orchestrator.requireRecovery(reason: .sessionLocked)

        let checksAfterWake = await harness.readiness.checkCount
        let startsAfterWake = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .paused)
        XCTAssertEqual(harness.orchestrator.state.preferences?.expectedCollecting, false)
        XCTAssertEqual(checksAfterWake, checksBeforeSleep)
        XCTAssertEqual(startsAfterWake, startsBeforeSleep)

        await harness.orchestrator.resume()

        let checksAfterResume = await harness.readiness.checkCount
        let startsAfterResume = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(harness.orchestrator.state.preferences?.expectedCollecting, true)
        XCTAssertEqual(checksAfterResume, checksBeforeSleep + 1)
        XCTAssertEqual(startsAfterResume, startsBeforeSleep + 1)
    }

    func testManualRetryStaysBlockedWhenFreshReadinessIsLocked() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        harness.orchestrator.requireRecovery(reason: .sessionLocked)
        await harness.readiness.setResult(.failure(.sessionLocked))
        let startsBeforeRetry = await harness.capture.startCount

        await harness.orchestrator.retry()

        let startsAfterRetry = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .blocked)
        XCTAssertEqual(harness.orchestrator.state.blockedReason, .sessionLocked)
        XCTAssertEqual(startsAfterRetry, startsBeforeRetry)
    }

    func testDeveloperOffOnWaitsForManualRetryAndStartsExactlyOnce() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let startsBeforeOff = await harness.capture.startCount

        harness.orchestrator.requireRecovery(reason: .keyUnavailable)

        XCTAssertEqual(harness.orchestrator.phase, .blocked)
        XCTAssertEqual(harness.orchestrator.state.preferences?.expectedCollecting, true)
        let startsAfterRearm = await harness.capture.startCount
        XCTAssertEqual(startsAfterRearm, startsBeforeOff)

        await harness.orchestrator.retry()

        let startsAfterRetry = await harness.capture.startCount
        XCTAssertEqual(harness.orchestrator.phase, .collecting)
        XCTAssertEqual(startsAfterRetry, startsBeforeOff + 1)
    }

    func testInvalidationDuringManualPreflightPreventsStartAndRunsAbort() async {
        let fence = ManualRecoveryFence()
        let barrier = Barrier()
        var starts = 0
        var aborts = 0

        let operation = Task { @MainActor in
            await fence.perform(
                prepare: { _ in await barrier.wait(); return true },
                start: { starts += 1 },
                abort: { aborts += 1 })
        }
        await barrier.waitUntilArrived()
        fence.invalidate()
        await barrier.release()

        let completed = await operation.value
        XCTAssertFalse(completed)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(aborts, 1)
    }

    func testInvalidationDuringManualStartRunsAbortAfterLateCompletion() async {
        let fence = ManualRecoveryFence()
        let barrier = Barrier()
        var starts = 0
        var aborts = 0

        let operation = Task { @MainActor in
            await fence.perform(
                prepare: { _ in true },
                start: { starts += 1; await barrier.wait() },
                abort: { aborts += 1 })
        }
        await barrier.waitUntilArrived()
        fence.invalidate()
        await barrier.release()

        let completed = await operation.value
        XCTAssertFalse(completed)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(aborts, 1)
    }
}

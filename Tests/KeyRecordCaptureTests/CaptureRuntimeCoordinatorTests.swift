import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

/// KR-02 regression: before this, `foregroundChanged` / `tapDisabled` / provider loss each
/// revoked the queue independently and then stopped. Nothing re-read providers, recomputed
/// policy or rebuilt a session, so capture stayed dead while the lifecycle still said
/// "collecting" — the "counts at launch, stops after switching apps" symptom.
final class CaptureRuntimeCoordinatorTests: XCTestCase {

    private final class Checks: CaptureRuntimeChecking, @unchecked Sendable {
        private let lock = NSLock()
        private var conditions: RuntimeConditions?
        private var expecting: Bool
        private(set) var freshReads = 0
        private(set) var expectationReads = 0

        init(conditions: RuntimeConditions? = Checks.open, expecting: Bool = true) {
            self.conditions = conditions
            self.expecting = expecting
        }

        static let open = RuntimeConditions(keyAvailability: .available, sessionLock: .unlocked,
                                            secureInput: .disabled,
                                            foreground: .attributable(bundleID: "app.b"))

        func freshRuntimeConditions() async -> RuntimeConditions? {
            lock.withLock { freshReads += 1; return conditions }
        }
        func expectsCollecting() async -> Bool {
            lock.withLock { expectationReads += 1; return expecting }
        }
        func set(conditions: RuntimeConditions?) { lock.withLock { self.conditions = conditions } }
        func set(expecting: Bool) { lock.withLock { self.expecting = expecting } }
        var reads: Int { lock.withLock { freshReads } }
    }

    /// Records the exact order of close/open so the fixed sequence is provable.
    private final class Journal: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) { lock.withLock { entries.append(entry) } }
        var all: [String] { lock.withLock { entries } }
        var closes: Int { all.filter { $0 == "close" }.count }
        var opens: Int { all.filter { $0.hasPrefix("open") }.count }
    }

    private actor OpenBarrier {
        private var arrived = false
        private var arrivalWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func suspendOpen() async -> Bool {
            arrived = true
            arrivalWaiter?.resume()
            arrivalWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
            return true
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

    private func makeCoordinator(checks: Checks, journal: Journal,
                                 openSucceeds: Bool = true) -> CaptureRuntimeCoordinator {
        CaptureRuntimeCoordinator(
            checks: checks,
            closeSession: { journal.append("close") },
            openSession: { conditions in
                journal.append("open:\(conditions.foreground)")
                return openSucceeds
            })
    }

    // MARK: - Fixed ordering

    func testRecoveryClosesBeforeReadingFreshStateAndOpeningNewSession() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)

        let outcome = await coordinator.handle(.invalidated(.foregroundChanged))

        XCTAssertEqual(outcome, .recovered)
        // Close strictly precedes open: the old session can never outlive the trigger.
        XCTAssertEqual(journal.all.first, "close")
        XCTAssertEqual(journal.closes, 1)
        XCTAssertEqual(journal.opens, 1)
        XCTAssertEqual(checks.reads, 1, "recovery must re-read providers, never reuse a cache")
    }

    func testForegroundChangeRebuildsSessionAgainstTheNewForeground() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)
        _ = await coordinator.handle(.invalidated(.foregroundChanged))
        XCTAssertTrue(journal.all.contains { $0 == "open:attributable(bundleID: \"app.b\")" },
                      journal.all.description)
    }

    func testTapDisabledRecoversThroughTheSameSerialPath() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)
        let outcome = await coordinator.handle(.invalidated(.tapDisabled))
        XCTAssertEqual(outcome, .recovered)
        XCTAssertEqual(journal.all, ["close", "open:attributable(bundleID: \"app.b\")"])
    }

    func testExclusionChangeRecomputesPolicyThroughTheCoordinator() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)
        let outcome = await coordinator.handle(.exclusionsChanged)
        XCTAssertEqual(outcome, .recovered)
        XCTAssertEqual(checks.reads, 1)
    }

    // MARK: - Fail closed

    func testPermissionLossStaysBlockedAndNeverAutoReopens() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)

        let outcome = await coordinator.handle(.invalidated(.permissionRevoked))

        XCTAssertEqual(outcome, .blocked(.permissionRequired))
        XCTAssertEqual(journal.closes, 1)
        XCTAssertEqual(journal.opens, 0, "a revoked grant must never silently re-open a tap")
    }

    func testSleepAndSessionChangeStayClosedUntilAnExplicitUnlock() async throws {
        for reason in [CaptureInvalidation.sleep, .sessionChanged] {
            let journal = Journal()
            let coordinator = makeCoordinator(checks: Checks(), journal: journal)
            let outcome = await coordinator.handle(.invalidated(reason))
            XCTAssertEqual(outcome, .blocked(.privacyChecksFailed), "\(reason)")
            XCTAssertEqual(journal.opens, 0, "\(reason) must not auto-reopen")
        }
    }

    func testFailedPrivacyChecksBlockInsteadOfOpening() async throws {
        let checks = Checks(conditions: nil)
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)
        let outcome = await coordinator.handle(.invalidated(.foregroundChanged))
        XCTAssertEqual(outcome, .blocked(.privacyChecksFailed))
        XCTAssertEqual(journal.opens, 0)
    }

    func testUnlockDoesNotRecoverWhenTheUserNoLongerExpectsCollecting() async throws {
        let checks = Checks(expecting: false)
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)
        let outcome = await coordinator.handle(.unlocked)
        XCTAssertEqual(outcome, .blocked(.notExpectingCollecting))
        XCTAssertEqual(journal.opens, 0)
    }

    func testUnlockRecoversOnlyAfterFreshChecksWhenStillExpectingCollecting() async throws {
        let checks = Checks(expecting: true)
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)
        let outcome = await coordinator.handle(.unlocked)
        XCTAssertEqual(outcome, .recovered)
        XCTAssertEqual(checks.reads, 1, "unlock must not skip the fresh privacy checks")
    }

    func testStartFailureIsReportedAsBlockedNotAsRecovered() async throws {
        let journal = Journal()
        let coordinator = makeCoordinator(checks: Checks(), journal: journal, openSucceeds: false)
        let outcome = await coordinator.handle(.invalidated(.foregroundChanged))
        XCTAssertEqual(outcome, .blocked(.startFailed))
    }

    // MARK: - Coalescing and user-action precedence

    func testConsecutiveInvalidationsCollapseIntoOneRecoveryTransaction() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)

        // Five notifications arriving back to back must not rebuild five sessions.
        //
        // Note on the actor: `handle` suspends inside `reconcile`, so queued callers resume
        // one after another. Coalescing therefore cannot rely on `running` alone — it must
        // fold pending work into the in-flight transaction. Without that, each of the five
        // callers ran its own full close/open cycle, tearing down and rebuilding the
        // session five times for what is logically one burst.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = await coordinator.handle(.invalidated(.foregroundChanged)) }
            }
        }
        let stats = await coordinator.statistics()
        XCTAssertGreaterThanOrEqual(stats.transactions, 1)
        XCTAssertLessThanOrEqual(stats.transactions, 2,
                                 "bursts must coalesce into at most one follow-up transaction")
        // The session must not be torn down once per notification.
        XCTAssertLessThanOrEqual(journal.closes, 2, "one burst must not close five sessions")
    }

    func testUserStopCancelsRecoveryAndPreventsAutomaticReopen() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)

        let stopped = await coordinator.handle(.userStopped)
        XCTAssertEqual(stopped, .blocked(.userStopped))

        // Any later invalidation must NOT resurrect capture behind the user's back.
        let after = await coordinator.handle(.invalidated(.foregroundChanged))
        XCTAssertEqual(after, .blocked(.userStopped))
        XCTAssertEqual(journal.opens, 0, "a user stop must never be undone by an invalidation")
    }

    func testExplicitRestartClearsTheUserStopLatch() async throws {
        let checks = Checks()
        let journal = Journal()
        let coordinator = makeCoordinator(checks: checks, journal: journal)
        _ = await coordinator.handle(.userStopped)
        await coordinator.clearUserStop()
        let outcome = await coordinator.handle(.unlocked)
        XCTAssertEqual(outcome, .recovered, "an explicit user restart re-arms recovery")
    }

    func testUserStopWinsWhileRecoveryIsOpening() async throws {
        let checks = Checks()
        let journal = Journal()
        let barrier = OpenBarrier()
        let coordinator = CaptureRuntimeCoordinator(
            checks: checks,
            closeSession: { journal.append("close") },
            openSession: { _ in
                journal.append("open")
                return await barrier.suspendOpen()
            })

        let recovery = Task { await coordinator.handle(.unlocked) }
        await barrier.waitUntilArrived()
        let stopped = await coordinator.handle(.userStopped)
        await barrier.release()
        let outcome = await recovery.value

        XCTAssertEqual(stopped, .blocked(.userStopped))
        XCTAssertEqual(outcome, .blocked(.userStopped))
        XCTAssertEqual(journal.closes, 3,
                       "the late open must be closed again after an explicit user stop")
    }

    func testEveryInvalidationReasonIsClassifiedExplicitly() {
        // Guards against a new reason silently defaulting into auto-recovery.
        for reason in CaptureInvalidation.allCases {
            switch reason {
            case .foregroundChanged, .tapDisabled, .secureInputChanged:
                XCTAssertTrue(reason.allowsAutomaticRecovery, "\(reason)")
            case .permissionRevoked, .sleep, .sessionChanged:
                XCTAssertFalse(reason.allowsAutomaticRecovery, "\(reason)")
            }
        }
    }
}

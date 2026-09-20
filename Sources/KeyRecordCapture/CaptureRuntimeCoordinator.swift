import Foundation
import KeyRecordCore

/// Everything that can invalidate a live capture session, plus the user actions that must
/// win against an in-flight recovery.
public enum CaptureRuntimeTrigger: Sendable, Equatable {
    /// A typed invalidation reported by a backend (foreground change, tapDisabled,
    /// permission loss, secure input, sleep, session change).
    case invalidated(CaptureInvalidation)
    /// Exclusion rules changed and the policy must be recomputed against the live foreground.
    case exclusionsChanged
    /// Screen unlocked / machine woke: recover only if the user still expects collecting.
    case unlocked
    /// Explicit user stop (pause / quit / reset / developer Off). Cancels recovery.
    case userStopped
}

/// Outcome of one reconciliation transaction, so callers and tests can assert on it
/// instead of inferring from side effects.
public enum CaptureRuntimeOutcome: Sendable, Equatable {
    /// A new session was established with a new generation.
    case recovered
    /// Deliberately left closed, with the reason. Never a silent no-op.
    case blocked(CaptureRuntimeBlockReason)
    /// Superseded by a newer trigger that arrived while this one was queued.
    case coalesced
}

public enum CaptureRuntimeBlockReason: Sendable, Equatable {
    case userStopped
    case notExpectingCollecting
    case permissionRequired
    case privacyChecksFailed
    case startFailed
}

/// Fresh, re-read inputs required before a session may be rebuilt.
public protocol CaptureRuntimeChecking: Sendable {
    /// Re-read permission, providers and privacy state. Returns nil when the gate must
    /// stay closed. Never cached: every recovery re-reads.
    func freshRuntimeConditions() async -> RuntimeConditions?
    /// Whether the user still expects collection (persisted preference).
    func expectsCollecting() async -> Bool
}

/// The serial recovery entry point for capture (KR-02).
///
/// Before this existed, `foregroundChanged`, `tapDisabled` and provider loss each called
/// `queue.revoke()` independently and then stopped: the session stayed dead until another
/// full start, while the lifecycle could still report `collecting`. That is the
/// "works at launch, stops counting after switching apps" symptom.
///
/// Fixed order for every trigger, no exceptions:
///   1. close the gate and record why;
///   2. stop the old source and wait for the old session to exit;
///   3. re-read permission / providers / privacy — never reuse a cached snapshot;
///   4. compute policy from the CURRENT preferences;
///   5. establish a new generation and a new source session;
///   6. synchronise lifecycle / scheduler / UI once, on success;
///   7. on failure stay blocked with an actionable reason.
///
/// The actor guarantees serialisation, so concurrent invalidations cannot interleave.
/// Consecutive triggers arriving while a transaction runs are coalesced into a single
/// follow-up transaction rather than queueing one rebuild per notification.
public actor CaptureRuntimeCoordinator {
    private let checks: any CaptureRuntimeChecking
    private let closeSession: @Sendable () async -> Void
    private let openSession: @Sendable (RuntimeConditions) async -> Bool

    private var running = false
    private var pendingTrigger: CaptureRuntimeTrigger?
    /// Set by an explicit user stop; blocks automatic reopen until a user action clears it.
    private var userStopped = false
    private(set) var transactionCount = 0
    private(set) var lastOutcome: CaptureRuntimeOutcome?

    public init(checks: any CaptureRuntimeChecking,
                closeSession: @escaping @Sendable () async -> Void,
                openSession: @escaping @Sendable (RuntimeConditions) async -> Bool) {
        self.checks = checks
        self.closeSession = closeSession
        self.openSession = openSession
    }

    /// Re-arms automatic recovery after the user explicitly starts/resumes again.
    public func clearUserStop() { userStopped = false }

    public func statistics() -> (transactions: Int, outcome: CaptureRuntimeOutcome?) {
        (transactionCount, lastOutcome)
    }

    @discardableResult
    public func handle(_ trigger: CaptureRuntimeTrigger) async -> CaptureRuntimeOutcome {
        if case .userStopped = trigger {
            // A user stop always wins: cancel any queued recovery and close.
            userStopped = true
            pendingTrigger = nil
            await closeSession()
            lastOutcome = .blocked(.userStopped)
            return .blocked(.userStopped)
        }
        // Coalescing cannot key off `running` alone. `reconcile` suspends, so every queued
        // caller resumes in turn and would otherwise run a full close/open cycle each —
        // five notifications tore down and rebuilt the session five times. Callers that
        // arrive while a transaction is in flight hand their trigger to the owner and
        // return immediately.
        guard !running else {
            pendingTrigger = trigger
            return .coalesced
        }
        running = true
        defer { running = false; pendingTrigger = nil }

        var outcome = await reconcile(trigger)
        // Drain whatever accumulated during the await. The whole burst folds into ONE
        // follow-up transaction, not one per notification.
        if let next = pendingTrigger {
            pendingTrigger = nil
            outcome = await reconcile(next)
            // Anything queued during that second pass is already covered by it: the
            // triggers are level-based (recompute current state), not edge-based, so a
            // further rebuild would observe identical inputs.
            pendingTrigger = nil
        }
        return outcome
    }

    private func reconcile(_ trigger: CaptureRuntimeTrigger) async -> CaptureRuntimeOutcome {
        transactionCount += 1
        // 1 + 2: close the gate, then stop the old source. Always, even when we will not
        // reopen — a dead session must never keep looking alive.
        await closeSession()

        func finish(_ outcome: CaptureRuntimeOutcome) -> CaptureRuntimeOutcome {
            lastOutcome = outcome
            return outcome
        }

        if userStopped { return finish(.blocked(.userStopped)) }

        if case .invalidated(let reason) = trigger, !reason.allowsAutomaticRecovery {
            // Sleep / session change / permission loss are privacy or authorization
            // transitions: stay closed until an explicit user action re-verifies.
            return finish(.blocked(reason == .permissionRevoked
                                   ? .permissionRequired : .privacyChecksFailed))
        }

        // 3: the user's intent still governs whether anything reopens at all.
        guard await checks.expectsCollecting() else {
            return finish(.blocked(.notExpectingCollecting))
        }

        // 4: fresh permission / provider / privacy reads, never a cached snapshot.
        guard let conditions = await checks.freshRuntimeConditions() else {
            return finish(.blocked(.privacyChecksFailed))
        }
        if userStopped { return finish(.blocked(.userStopped)) }

        // 5 + 6: new generation, new session, then a single synchronisation.
        guard await openSession(conditions) else {
            return finish(.blocked(.startFailed))
        }
        return finish(.recovered)
    }
}

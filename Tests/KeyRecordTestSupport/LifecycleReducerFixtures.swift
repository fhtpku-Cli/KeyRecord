import Foundation
import KeyRecordCore

public enum LifecycleReducerFixtures {
    public static let cycle = CycleID(rawValue: "cycle-14")

    public static let openConditions = RuntimeConditions(
        keyAvailability: .available, sessionLock: .unlocked,
        secureInput: .disabled, foreground: .attributable(bundleID: "com.ex"))

    public static func transition(_ state: LifecycleState, _ event: LifecycleEvent) -> LifecycleState {
        reduce(state, event).state
    }

    public static func acceptedStartState() throws -> LifecycleState {
        let presented = transition(LifecycleState.initial, .consentRequested)
        return transition(presented, .consentAccepted(cycleID: cycle))
    }

    public static func registeringState(conditions: RuntimeConditions? = nil) throws -> LifecycleState {
        var state = transition(transition(try acceptedStartState(), .keyProvisioned), .bootstrapPersisted)
        // KR-06: first consent reaches capture only through the shared readiness transition,
        // so the fixture must supply verified conditions rather than skipping straight to start.
        state = transition(state, .restartReadiness(conditions ?? openConditions))
        state = transition(state, .captureStarted)
        if let conditions { state = transition(state, .conditionsChanged(conditions)) }
        return state
    }

    public static func collectingState() throws -> LifecycleState {
        var state = try registeringState(conditions: openConditions)
        state = transition(state, .loginItemRegistered)
        state = transition(state, .loginItemRegistrationPersisted)
        return state
    }

    public static func collectingStateWithoutLogin() throws -> LifecycleState {
        let state = try registeringState(conditions: openConditions)
        let rejected = transition(state, .loginItemRegistrationRejected(.registrationDenied))
        return transition(rejected, .dismissNotice)
    }

    public static func pausedState() throws -> LifecycleState {
        let state = try collectingState()
        let pausing = transition(state, .pauseRequested)
        let flushed = transition(pausing, .pauseFlushSucceeded)
        let persisted = transition(flushed, .pausePersisted)
        return transition(persisted, .pauseRuntimeStopped)
    }

    /// Collecting reached through resume, which also routes via the shared readiness
    /// transition (KR-06).
    public static func resumedCollectingState() throws -> LifecycleState {
        let paused = try pausedState()
        let resuming = transition(paused, .resumeRequested)
        let verifying = transition(resuming, .resumePersisted)
        let ready = transition(verifying, .restartReadiness(openConditions))
        return transition(ready, .captureStarted)
    }

    public static func reopeningState(loginItemEnabled: Bool = false) throws -> LifecycleState {
        let prefs = Preferences(currentCycleID: cycle, expectedCollecting: true,
                                loginItemEnabled: loginItemEnabled)
        return transition(LifecycleState.initial, .reload(prefs))
    }
}

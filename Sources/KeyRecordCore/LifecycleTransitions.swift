import Foundation

/// Inputs to the lifecycle FSM. Each case is the result of exactly one user action or port completion.
public enum LifecycleEvent: Equatable, Sendable {
    case consentRequested
    case consentAccepted(cycleID: CycleID)
    case consentDenied
    case keyProvisioned
    case keyProvisionFailed(LifecycleKeyError)
    case bootstrapPersisted
    case initialPersistenceFailed(LifecycleStoreError)
    case captureStarted
    case captureStartDenied(LifecycleCaptureError)
    case loginItemRegistered
    case loginItemRegistrationRejected(LoginItemSystemRejection)
    case loginItemRegistrationPersisted
    case pauseRequested
    case pauseFlushSucceeded
    case pauseFlushFailed(LifecycleFlushError)
    case pausePersisted
    case pausePersistenceFailed(LifecycleStoreError)
    case pauseRuntimeStopped
    case resumeRequested
    case resumePersisted
    case resumePersistenceFailed(LifecycleStoreError)
    case quitRequested
    case quitFlushSucceeded
    case quitFlushFailed(LifecycleFlushError)
    case quitRuntimeStopped
    case reload(Preferences?)
    case restartReadiness(RuntimeConditions)
    case restartBlocked(BlockedReason)
    case reloadFailed(LifecycleStoreError)
    case conditionsChanged(RuntimeConditions)
    case exclusionsChanged(Set<String>)
    case exclusionsPersisted
    case exclusionsPersistFailed(LifecycleStoreError)
    case loginItemSetEnabled(Bool)
    case loginItemUnregistered
    case loginItemUnregistrationRejected(LoginItemSystemRejection)
    case retry
    case dismissNotice
}

extension LifecycleState {
    mutating func apply(_ event: LifecycleEvent) -> [LifecycleEffect] {
        var effects: [LifecycleEffect] = []
        switch phase {
        case .unstarted: effects = handleUnstarted(event)
        case .consent: effects = handleConsent(event)
        case .starting: effects = handleStarting(event)
        case .collecting: effects = handleCollecting(event)
        case .pausing: effects = handlePausing(event)
        case .paused: effects = handlePaused(event)
        case .resuming: effects = handleResuming(event)
        case .stopping: effects = handleStopping(event)
        case .stopped: break
        case .reopening: effects = handleReopening(event)
        case .blocked: effects = handleBlocked(event)
        case .failed: effects = handleFailed(event)
        }
        refreshGate()
        return effects
    }

    mutating func handleConsent(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .consentDenied:
            // L1: rejection leaves the install untouched: no key, no preference, no login item.
            phase = .unstarted
            preferences = nil
            loginItem = .neverOffered
            return []
        case .consentAccepted(let cycleID):
            phase = .starting
            preferences = Preferences(currentCycleID: cycleID, expectedCollecting: true)
            return [.provisionKey]
        default: return []
        }
    }

    mutating func handleStarting(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .keyProvisioned:
            guard let preferences else { return [] }
            return [.persistPreferences(preferences)]
        case .keyProvisionFailed(let error):
            enterFailure(.keyProvisionFailed(error))
            return []
        case .bootstrapPersisted:
            return [.startCapture]
        case .initialPersistenceFailed(let error):
            enterFailure(.initialPersistenceFailed(error))
            return []
        case .captureStarted:
            // FR-C4/L4: login registration is attempted only after the first successful capture start.
            phase = .collecting
            loginItem = .registering
            return [.registerLoginItem]
        case .captureStartDenied(let error):
            enterFailure(.captureStartDenied(error))
            return []
        default: return []
        }
    }

    mutating func handleCollecting(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .loginItemRegistered:
            loginItem = .registered
            return persist(loginItemEnabled: true)
        case .loginItemRegistrationRejected(let rejection):
            loginItem = .rejected(rejection)
            notice = .loginRegistrationRejected(rejection)
            return []
        case .loginItemRegistrationPersisted:
            return []
        case .pauseRequested:
            phase = .pausing
            notice = nil
            return [.flushWhileUnlocked]
        case .quitRequested:
            phase = .stopping
            return [.flushWhileUnlocked]
        case .conditionsChanged(let next):
            conditions = next
            return []
        case .exclusionsChanged(let excluded):
            // Gate revocation is applied by refreshGate before the persistence effect completes.
            guard let updated = preferences?.updating(excludedBundleIDs: excluded) else { return [] }
            preferences = updated
            return [.persistPreferences(updated)]
        case .exclusionsPersisted:
            return []
        case .exclusionsPersistFailed(let error):
            notice = .exclusionPersistenceFailed(error)
            return []
        case .loginItemSetEnabled(let enabled):
            return handleLoginItemToggle(enabled)
        case .loginItemUnregistered:
            loginItem = .unregistered
            return persist(loginItemEnabled: false)
        case .loginItemUnregistrationRejected(let rejection):
            loginItem = .registered
            notice = .loginUnregistrationRejected(rejection)
            return []
        case .dismissNotice:
            notice = nil
            return []
        default: return []
        }
    }

    mutating func persist(expectedCollecting: Bool? = nil,
                          excludedBundleIDs: Set<String>? = nil,
                          loginItemEnabled: Bool? = nil) -> [LifecycleEffect] {
        guard let preferences else { return [] }
        let next = preferences.updating(expectedCollecting: expectedCollecting,
                                        excludedBundleIDs: excludedBundleIDs,
                                        loginItemEnabled: loginItemEnabled)
        self.preferences = next
        return [.persistPreferences(next)]
    }

    mutating func handleLoginItemToggle(_ enabled: Bool) -> [LifecycleEffect] {
        switch LoginItemPolicy.intent(forDesiredEnabled: enabled, phase: phase, status: loginItem) {
        case .register:
            loginItem = .registering
            return [.registerLoginItem]
        case .unregister:
            loginItem = .unregistering
            return [.unregisterLoginItem]
        case .none:
            if enabled { notice = .loginUnavailableWhileIdle }
            return []
        }
    }
}

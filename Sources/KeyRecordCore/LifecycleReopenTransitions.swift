import Foundation

extension LifecycleState {
    mutating func handleUnstarted(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .consentRequested:
            phase = .consent
            return []
        case .reload(let loaded):
            guard let loaded else {
                // KR-09: a nil reload used to be a silent no-op — no phase change, no
                // reason — which surfaced live as "layer 0 ... (no reason recorded)" with
                // nothing for the user to act on. nil means the store reported a fresh
                // install, which is either a genuine first run or an unreadable/unreachable
                // key. Both must be stated. Preferences already held are never discarded,
                // so a transient unreadable state cannot erase known configuration.
                blockedReason = .keyUnavailable
                return []
            }
            blockedReason = nil
            preferences = loaded
            loginItem = loaded.loginItemEnabled ? .registered : .unregistered
            if loaded.expectedCollecting {
                phase = .reopening
                return [.verifyRestartReadiness]
            }
            phase = .paused
            return []
        case .reloadFailed(let error):
            // Corrupt/unreadable preferences are corruption: fail closed, never rebuild silently.
            enterFailure(.preferencesLoadFailed(error))
            return []
        default: return []
        }
    }

    mutating func handleReopening(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .restartReadiness(let candidate):
            // Same verified-readiness transition as first consent and resume (KR-06).
            return applyVerifiedReadiness(candidate)
        case .restartBlocked(let reason):
            phase = .blocked
            blockedReason = reason
            return []
        case .captureStarted:
            phase = .collecting
            return []
        case .captureStartDenied(let error):
            enterFailure(.captureStartDenied(error))
            return []
        default: return []
        }
    }

    mutating func handleBlocked(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .retry:
            // Explicit manual retry only; there is no permission or readiness polling.
            phase = .reopening
            blockedReason = nil
            return [.verifyRestartReadiness]
        default: return []
        }
    }

    mutating func handleFailed(_ event: LifecycleEvent) -> [LifecycleEffect] {
        guard event == .retry else {
            if case .dismissNotice = event { notice = nil }
            return []
        }
        guard let failure else { return [] }
        switch failure {
        case .keyProvisionFailed:
            phase = .starting
            self.failure = nil
            return [.provisionKey]
        case .initialPersistenceFailed:
            phase = .starting
            self.failure = nil
            guard let preferences else { return [] }
            return [.persistPreferences(preferences)]
        case .pausePersistenceFailed:
            phase = .pausing
            self.failure = nil
            return persist(expectedCollecting: false)
        case .resumePersistenceFailed:
            phase = .resuming
            self.failure = nil
            return persist(expectedCollecting: true)
        case .captureStartDenied:
            let replay = failedFromPhase == .reopening ? LifecyclePhase.reopening
                : failedFromPhase == .resuming ? LifecyclePhase.resuming : LifecyclePhase.starting
            phase = replay
            self.failure = nil
            // Every replay re-verifies readiness first: a retry must never reuse the
            // conditions that were current when the previous start attempt was denied.
            return [.verifyRestartReadiness]
        case .preferencesLoadFailed:
            phase = .unstarted
            self.failure = nil
            return [.reloadFromStorage]
        }
    }

    func collectingInputs(_ candidate: RuntimeConditions) -> GateInputs {
        GateInputs(collecting: true, keyAvailability: candidate.keyAvailability,
                   sessionLock: candidate.sessionLock, secureInput: candidate.secureInput,
                   foreground: candidate.foreground,
                   exclusion: Self.exclusionState(foreground: candidate.foreground,
                                                  exclusions: preferences?.excludedBundleIDs ?? []))
    }
}

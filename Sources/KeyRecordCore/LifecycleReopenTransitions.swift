import Foundation

extension LifecycleState {
    mutating func handleUnstarted(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .consentRequested:
            phase = .consent
            return []
        case .reload(let loaded):
            guard let loaded else { return [] }
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
            conditions = candidate
            guard openUnderCollecting(candidate) else {
                phase = .blocked
                var probe = gate
                probe.update(collectingInputs(candidate))
                blockedReason = probe.closureReason.flatMap(Self.blockedReason(for:)) ?? .keyUnavailable
                return []
            }
            return [.startCapture]
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
            return replay == .reopening ? [.verifyRestartReadiness] : [.startCapture]
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

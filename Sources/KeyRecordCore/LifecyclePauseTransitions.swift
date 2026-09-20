import Foundation

extension LifecycleState {
    mutating func handlePausing(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .pauseFlushSucceeded:
            return persist(expectedCollecting: false)
        case .pauseFlushFailed(let error):
            // Pause is not claimed: runtime keeps collecting; present the flush failure explicitly.
            phase = .collecting
            notice = .pauseFlushFailed(error)
            return []
        case .pausePersisted:
            return [.stopCapture]
        case .pauseRuntimeStopped:
            phase = .paused
            return []
        case .pausePersistenceFailed(let error):
            enterFailure(.pausePersistenceFailed(error))
            return []
        default: return []
        }
    }

    mutating func handlePaused(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .resumeRequested:
            phase = .resuming
            notice = nil
            return persist(expectedCollecting: true)
        case .quitRequested:
            // Durable flush already happened at pause time; runtime stop only.
            phase = .stopping
            return [.stopCapture]
        case .conditionsChanged(let next):
            conditions = next
            return []
        case .exclusionsChanged(let excluded):
            guard let updated = preferences?.updating(excludedBundleIDs: excluded) else { return [] }
            preferences = updated
            return [.persistPreferences(updated)]
        case .exclusionsPersistFailed(let error):
            notice = .exclusionPersistenceFailed(error)
            return []
        case .loginItemSetEnabled(let enabled):
            return handleLoginItemToggle(enabled)
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

    mutating func handleResuming(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .resumePersisted:
            // KR-06: resume re-verifies readiness through the shared transition instead of
            // starting capture against whatever stale conditions the paused state carried.
            return [.verifyRestartReadiness]
        case .restartReadiness(let candidate):
            return applyVerifiedReadiness(candidate)
        case .restartBlocked(let reason):
            phase = .blocked
            blockedReason = reason
            return []
        case .resumePersistenceFailed(let error):
            enterFailure(.resumePersistenceFailed(error))
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

    mutating func handleStopping(_ event: LifecycleEvent) -> [LifecycleEffect] {
        switch event {
        case .quitFlushSucceeded:
            return [.stopCapture]
        case .quitRuntimeStopped:
            phase = .stopped
            return []
        case .quitFlushFailed(let error):
            // Cannot claim data saved: keep the runtime alive and surface the failure.
            phase = .collecting
            notice = .quitFlushFailed(error)
            return []
        default: return []
        }
    }
}

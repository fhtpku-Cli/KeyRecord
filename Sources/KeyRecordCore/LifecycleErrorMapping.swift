import Foundation

extension LifecycleOrchestrator {
    static func storeError(_ error: PreferencesRepositoryError) -> LifecycleStoreError {
        switch error {
        case .corruptStoredPreferences: .corruptStoredPreferences
        case .storageUnavailable: .protectedDataUnavailable
        }
    }

    static func blockedReason(_ error: LifecycleReadinessError) -> BlockedReason {
        switch error {
        case .keyUnavailable, .queryFailed: .keyUnavailable
        case .sessionLocked: .sessionLocked
        case .secureInputActive: .secureInputActive
        case .foregroundUnreliable: .foregroundUnreliable
        }
    }
}

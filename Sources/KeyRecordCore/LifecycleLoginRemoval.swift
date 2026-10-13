import Foundation

@MainActor
enum LifecycleLoginRemoval {
    static func perform(ports: LifecyclePorts, current: () -> LifecycleState,
                        removed: () -> Void, saved: () -> Void) async throws {
        guard current().preferences != nil, SensitiveVisibility.isVisible(current()) else {
            throw PreferencesRepositoryError.storageUnavailable
        }
        try await ports.login.unregister()
        removed()
        guard let preferences = current().preferences, SensitiveVisibility.isVisible(current()) else {
            throw PreferencesRepositoryError.storageUnavailable
        }
        try await ports.preferences.save(preferences.updating(loginItemEnabled: false))
        saved()
    }
}

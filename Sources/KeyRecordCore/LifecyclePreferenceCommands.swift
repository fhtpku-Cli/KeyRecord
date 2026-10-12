import Foundation

extension LifecycleOrchestrator {
    public func setLayout(_ layout: LayoutPreference) async throws {
        try await saveVisiblePreference { $0.updating(layout: layout) }
    }

    public func setIgnoredRecommendationKeys(_ keys: Set<String>) async throws {
        try await saveVisiblePreference { $0.updating(ignoredRecommendationKeys: keys) }
    }

    public func setKeyboardPoolConfirmed(_ keys: Set<KeyCode>) async throws {
        try await saveVisiblePreference { $0.updating(keyboardPoolConfirmed: keys) }
    }
}

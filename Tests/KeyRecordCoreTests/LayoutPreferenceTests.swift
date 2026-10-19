import XCTest
import KeyRecordCore
import KeyRecordTestSupport

@MainActor
final class KeyboardPoolPreferenceTests: XCTestCase {
    func testPoolSurvivesReloadAndUnrelatedPreferenceUpdates() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let original = try XCTUnwrap(harness.orchestrator.state.preferences)
        let pool: Set<KeyCode> = [try KeyCode(122), try KeyCode(120)]
        try await harness.orchestrator.setKeyboardPoolConfirmed(pool)
        let saved = await harness.storedPreferences()
        XCTAssertEqual(saved, original.updating(keyboardPoolConfirmed: pool))
        try await harness.orchestrator.setLayout(LayoutPreference(preset: .iso, hasAsked: true))
        try await harness.orchestrator.setIgnoredRecommendationKeys(["kept"])
        await harness.orchestrator.reload()
        XCTAssertEqual(harness.orchestrator.state.preferences?.keyboardPoolConfirmed, pool)
        try await harness.orchestrator.setKeyboardPoolConfirmed([])
        await harness.orchestrator.reload()
        XCTAssertEqual(harness.orchestrator.state.preferences?.keyboardPoolConfirmed, [])
        XCTAssertEqual(harness.orchestrator.state.preferences?.ignoredRecommendationKeys, ["kept"])
        XCTAssertEqual(harness.orchestrator.state.preferences?.layout.preset, .iso)
    }

    func testHiddenStateAndFailedSaveKeepPreviousPool() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let pool: Set<KeyCode> = [try KeyCode(122)]
        try await harness.orchestrator.setKeyboardPoolConfirmed(pool)
        await harness.storage.failSubsequentSaves()
        do {
            try await harness.orchestrator.setKeyboardPoolConfirmed([])
            XCTFail("Failed store accepted pool change")
        } catch {}
        XCTAssertEqual(harness.orchestrator.state.preferences?.keyboardPoolConfirmed, pool)
        harness.orchestrator.observe(RuntimeConditions(keyAvailability: .available,
            sessionLock: .locked, secureInput: .disabled,
            foreground: .attributable(bundleID: "com.example")))
        do {
            try await harness.orchestrator.setKeyboardPoolConfirmed([])
            XCTFail("Hidden state accepted pool change")
        } catch { XCTAssertEqual(error as? PreferencesRepositoryError, .storageUnavailable) }
        let saved = await harness.storedPreferences()
        XCTAssertEqual(saved?.keyboardPoolConfirmed, pool)
    }
}

@MainActor
final class LayoutPreferenceTests: XCTestCase {
    func testDockPreferenceDefaultsForOldDataAndSurvivesOtherChanges() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let before = try XCTUnwrap(harness.orchestrator.state.preferences)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(before)) as? [String: Any])
        legacy.removeValue(forKey: "showDockIcon")
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: legacy)).showDockIcon)
        try await harness.orchestrator.setShowDockIcon(true)
        try await harness.orchestrator.setLayout(LayoutPreference(preset: .iso, hasAsked: true))
        await harness.orchestrator.reload()
        XCTAssertEqual(harness.orchestrator.state.preferences?.showDockIcon, true)
        await harness.storage.failSubsequentSaves()
        do { try await harness.orchestrator.setShowDockIcon(false); XCTFail("Saved despite failure") } catch {}
        XCTAssertEqual(harness.orchestrator.state.preferences?.showDockIcon, true)
    }
    func testLayoutPersistsWithoutChangingCollectionPreferences() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let before = try XCTUnwrap(harness.orchestrator.state.preferences)
        let selected = LayoutPreference(preset: .alice, hasAsked: true)
        try await harness.orchestrator.setLayout(selected)
        let saved = await harness.storedPreferences()
        XCTAssertEqual(saved, before.updating(layout: selected))
        XCTAssertEqual(harness.orchestrator.state.preferences, saved)
        await harness.orchestrator.reload()
        XCTAssertEqual(harness.orchestrator.state.preferences?.layout, selected)
    }

    func testHiddenStateCannotCommitLayoutOrConsumeQuestion() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let before = await harness.storedPreferences()
        harness.orchestrator.observe(RuntimeConditions(keyAvailability: .available,
            sessionLock: .locked, secureInput: .disabled,
            foreground: .attributable(bundleID: "com.example")))
        do {
            try await harness.orchestrator.setLayout(LayoutPreference(preset: .none, hasAsked: true))
            XCTFail("Hidden state accepted layout change")
        } catch { XCTAssertEqual(error as? PreferencesRepositoryError, .storageUnavailable) }
        let after = await harness.storedPreferences()
        XCTAssertEqual(after, before)
    }

    func testExplicitSkipPersistsAskedStateAndSurvivesOtherPreferences() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        try await harness.orchestrator.setLayout(LayoutPreference(preset: .none, hasAsked: true))
        try await harness.orchestrator.setLocale(.simplifiedChinese)
        await harness.orchestrator.setExclusions(["com.example.private"])
        let saved = await harness.storedPreferences()
        XCTAssertEqual(saved?.layout, LayoutPreference(preset: .none, hasAsked: true))
        XCTAssertEqual(saved?.locale, .simplifiedChinese)
        XCTAssertEqual(saved?.excludedBundleIDs, ["com.example.private"])
    }
}

@MainActor
final class IgnoredRecommendationPreferenceTests: XCTestCase {
    func testIgnorePersistsAcrossReloadAndLeavesOtherPreferencesUntouched() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let before = try XCTUnwrap(harness.orchestrator.state.preferences)
        let keys: Set<String> = ["008:left:none:none:left:none"]
        try await harness.orchestrator.setIgnoredRecommendationKeys(keys)
        let saved = await harness.storedPreferences()
        XCTAssertEqual(saved, before.updating(ignoredRecommendationKeys: keys))
        try await harness.orchestrator.setLocale(.simplifiedChinese)
        await harness.orchestrator.setLoginItem(enabled: true)
        await harness.orchestrator.reload()
        let reloaded = try XCTUnwrap(harness.orchestrator.state.preferences)
        XCTAssertEqual(reloaded.ignoredRecommendationKeys, keys)
        XCTAssertEqual(reloaded.layout, before.layout)
        XCTAssertEqual(reloaded.excludedBundleIDs, before.excludedBundleIDs)
        XCTAssertEqual(reloaded.locale, .simplifiedChinese)
        XCTAssertTrue(reloaded.loginItemEnabled)
    }

    func testHiddenStateRejectsIgnoreChanges() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let before = await harness.storedPreferences()
        harness.orchestrator.observe(RuntimeConditions(keyAvailability: .available,
            sessionLock: .locked, secureInput: .disabled,
            foreground: .attributable(bundleID: "com.example")))
        do {
            try await harness.orchestrator.setIgnoredRecommendationKeys(["008:left:none:none:none:none"])
            XCTFail("Hidden state accepted an ignore change")
        } catch { XCTAssertEqual(error as? PreferencesRepositoryError, .storageUnavailable) }
        let after = await harness.storedPreferences()
        XCTAssertEqual(after, before)
    }

    func testFailedSaveKeepsPreviousIgnoreSet() async throws {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let keys: Set<String> = ["kept"]
        try await harness.orchestrator.setIgnoredRecommendationKeys(keys)
        await harness.storage.failSubsequentSaves()
        do {
            try await harness.orchestrator.setIgnoredRecommendationKeys(["replacement"])
            XCTFail("Failing preference store accepted the replacement")
        } catch {}
        XCTAssertEqual(harness.orchestrator.state.preferences?.ignoredRecommendationKeys, keys)
        let stored = await harness.storedPreferences()
        XCTAssertEqual(stored?.ignoredRecommendationKeys, keys)
    }
}

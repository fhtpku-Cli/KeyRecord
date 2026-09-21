import XCTest
import KeyRecordCore
import KeyRecordTestSupport

@MainActor
final class LayoutPreferenceTests: XCTestCase {
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

import XCTest
import KeyRecordCore

@MainActor
final class ProductLocaleStartupTests: XCTestCase {
    func testStartupRestoresPersistedChineseBeforeRenderingWithEnglishFallback() async throws {
        // Given: a paused persisted session, not a manually reloaded lifecycle.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("build/root/locale-startup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try FlowFixture(directory: directory, environment: [:])
        let preferences = Preferences(currentCycleID: CycleID(rawValue: "persisted-cycle"),
                                      locale: .simplifiedChinese)
        try await fixture.preferences.save(preferences)
        // When: the product boot restoration entry completes, before menu/window creation.
        await ProductStartup.restore(flow: fixture.flow, lifecycle: fixture.orchestrator,
                                                preferredLanguages: ["en"])
        // Then: render input and cycle come from storage, with no startup live effects.
        XCTAssertEqual(fixture.flow.language, "zh-Hans")
        XCTAssertEqual(fixture.flow.state, .paused)
        XCTAssertEqual(fixture.orchestrator.state.preferences, preferences)
        XCTAssertFalse(fixture.orchestrator.state.gate.isOpen)
        XCTAssertEqual(fixture.journalEvents, [])
    }

    func testStartupWithAbsentPreferencesUsesSystemFallbackWithoutConsentEffects() async {
        // Given: storage positively reports first run.
        let harness = LifecycleHarness()
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: harness.orchestrator))
        // When: product startup completes.
        await ProductStartup.restore(flow: flow, lifecycle: harness.orchestrator,
                                                preferredLanguages: ["zh-Hans"])
        // Then: fallback is used without provisioning, capture or login registration.
        XCTAssertEqual(flow.language, "zh-Hans")
        XCTAssertEqual(flow.state, .unstarted)
        let loads = await harness.storage.loadCount
        let keys = await harness.keys.provisionCount
        let starts = await harness.capture.startCount
        let logins = await harness.login.registerCount
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(keys + starts + logins, 0)
    }

    func testStartupUnavailableStorageFailsClosedWithoutEffects() async {
        // Given: protected storage is unavailable, not absent.
        let harness = LifecycleHarness(storage: InMemoryPreferencesStorage(loadFailure: .storageUnavailable))
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: harness.orchestrator))
        // When: product startup attempts restoration.
        await ProductStartup.restore(flow: flow, lifecycle: harness.orchestrator,
                                                preferredLanguages: ["zh-Hans"])
        // Then: it stays failed/closed, rather than claiming a fresh consent session.
        XCTAssertEqual(harness.orchestrator.state.failure, .preferencesLoadFailed(.protectedDataUnavailable))
        XCTAssertFalse(harness.orchestrator.state.gate.isOpen)
        XCTAssertEqual(flow.state, .error)
        XCTAssertEqual(flow.language, "en")
        XCTAssertEqual(flow.noticeKey, "flow.actionUnavailable")
        let keys = await harness.keys.provisionCount
        let starts = await harness.capture.startCount
        let logins = await harness.login.registerCount
        XCTAssertEqual(keys + starts + logins, 0)
    }

    func testStartupCollectingPreferenceRequiresFreshPrivacyChecksAndKeepsCycle() async throws {
        // Given: a previously collecting session whose current readiness check is locked.
        let preferences = Preferences(currentCycleID: CycleID(rawValue: "existing"),
                                      expectedCollecting: true, locale: .simplifiedChinese)
        let harness = LifecycleHarness(storage: InMemoryPreferencesStorage(
            ciphertext: try PreferencesRepository.encode(preferences)), readinessResult: .failure(.sessionLocked))
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: harness.orchestrator))
        // When: product startup restores persisted state.
        await ProductStartup.restore(flow: flow, lifecycle: harness.orchestrator,
                                                preferredLanguages: ["en"])
        // Then: locale is restored but persisted intent does not authorize runtime effects.
        XCTAssertEqual(flow.language, "zh-Hans")
        XCTAssertEqual(flow.state, .blocked)
        XCTAssertEqual(harness.orchestrator.state.preferences, preferences)
        XCTAssertFalse(harness.orchestrator.state.gate.isOpen)
        let checks = await harness.readiness.checkCount
        let keys = await harness.keys.provisionCount
        let starts = await harness.capture.startCount
        let logins = await harness.login.registerCount
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(keys + starts + logins, 0)
    }
}

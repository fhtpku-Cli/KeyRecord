import XCTest
import KeyRecordCore
import KeyRecordStore
import KeyRecordCapture

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

@MainActor
final class ProductPausedStartupTests: XCTestCase {
    func testPausedUnknownPrivacyMustNotExposeCachedAggregate() throws {
        let harness = LifecycleHarness()
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: harness.orchestrator))
        let state = LifecycleState(phase: .paused)
        XCTAssertFalse(SensitiveVisibility.isVisible(state), "paused capture gate masks unknown privacy")
        XCTAssertNil(flow.snapshot)
    }

    func testPausedRestartRestoresPersistedAggregateWithoutCaptureOrWrites() async throws {
        let cycle = CycleID(rawValue: "paused-test")
        let preferences = Preferences(currentCycleID: cycle)
        let harness = LifecycleHarness(storage: InMemoryPreferencesStorage(
            ciphertext: try PreferencesRepository.encode(preferences)))
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: harness.orchestrator))
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let reduction = ProductReduction(gate: gate)
        let aggregate = try AggregationReducer(cycleID: cycle, shortcuts: [], bareKeys: [
            DailyBareKeyAggregate(cycleID: cycle, day: LocalDay("2026-09-23"), keyCode: KeyCode(0),
                sourceCounts: SourceCounts(ordinary: Count(21), suspectedInjection: Count(0)))])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = PausedFixtureKeys()
        let store = ObjectStore(root: root, keySource: keys)
        _ = try await store.bootstrap()
        await keys.install()
        try await store.initializeFreshInstallation()
        try await FencedObjectWriter(store: store, gate: gate).write(
            AggregatePersistence.objects(aggregate), generation: gate.begin())
        await store.closeProtectedSession()
        let reopened = ObjectStore(root: root, keySource: keys)
        _ = try await reopened.bootstrap()
        let originalFiles = try files(in: root)
        var reads = 0
        var checks = 0
        await ProductStartup.restore(flow: flow, lifecycle: harness.orchestrator,
            preferredLanguages: ["en"], pausedRestoration: ProductPausedRestoration(
                gate: gate, reduction: reduction,
                conditions: { checks += 1; return LifecycleHarnessConditions.open },
                load: { requested in
                    reads += 1
                    XCTAssertEqual(requested, cycle)
                    return try await AggregatePersistence.restore(cycleID: requested, store: reopened, gate: gate)
                }))
        XCTAssertEqual(flow.snapshot?.bareKeyTotal, 21, "paused boot must publish saved totals")
        XCTAssertNotNil(flow.analysis)
        XCTAssertEqual(checks, 2, "privacy must be fresh before and after protected reads")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(harness.orchestrator.phase, .paused)
        XCTAssertEqual(harness.orchestrator.state.preferences, preferences)
        XCTAssertFalse(harness.orchestrator.state.gate.isOpen)
        XCTAssertFalse(reduction.hasUnflushedChanges())
        XCTAssertNil(try reduction.take())
        let starts = await harness.capture.startCount
        let readiness = await harness.readiness.checkCount
        let logins = await harness.login.registerCount
        XCTAssertEqual(starts + readiness + logins, 0)
        XCTAssertEqual(try files(in: root), originalFiles, "read-only restore must not rewrite the store")
        XCTAssertFalse(reduction.hasSession(generation: CaptureGeneration(rawValue: 0)))
    }

    private func files(in root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            result[name] = try Data(contentsOf: root.appendingPathComponent(name))
        }
        return result
    }

    func testPausedRestoreRejectsUnsafeConditionsBeforeAndAfterRead() async throws {
        let unsafe: [RuntimeConditions] = [
            .unknown,
            RuntimeConditions(keyAvailability: .available, sessionLock: .locked,
                secureInput: .disabled, foreground: .reliablyUnattributable),
            RuntimeConditions(keyAvailability: .available, sessionLock: .unlocked,
                secureInput: .enabled, foreground: .reliablyUnattributable),
            RuntimeConditions(keyAvailability: .available, sessionLock: .unlocked,
                secureInput: .unknown, foreground: .reliablyUnattributable),
            RuntimeConditions(keyAvailability: .available, sessionLock: .unlocked,
                secureInput: .disabled, foreground: .unknown)]
        for candidate in unsafe {
            for failOnCheck in [1, 2] {
                let fixture = try makePausedFixture()
                var reads = 0
                var checks = 0
                await ProductStartup.restore(flow: fixture.flow, lifecycle: fixture.harness.orchestrator,
                    preferredLanguages: ["en"], pausedRestoration: ProductPausedRestoration(
                        gate: fixture.gate, reduction: fixture.reduction,
                        conditions: { checks += 1; return checks == failOnCheck ? candidate : LifecycleHarnessConditions.open },
                        load: { cycle in reads += 1; return AggregationReducer(cycleID: cycle) }))
                XCTAssertEqual(reads, failOnCheck == 1 ? 0 : 1)
                XCTAssertNil(fixture.flow.snapshot)
                XCTAssertNil(fixture.flow.analysis)
                XCTAssertNil(try fixture.reduction.snapshot())
                XCTAssertFalse(fixture.flow.sensitiveContentVisible)
                XCTAssertEqual(fixture.harness.orchestrator.phase, .paused)
                let starts = await fixture.harness.capture.startCount
                XCTAssertEqual(starts, 0)
            }
        }
    }

    func testPausedRestoreRejectsRevokedGenerationEvenWhenLockReopens() async throws {
        let fixture = try makePausedFixture()
        await ProductStartup.restore(flow: fixture.flow, lifecycle: fixture.harness.orchestrator,
            preferredLanguages: ["en"], pausedRestoration: ProductPausedRestoration(
                gate: fixture.gate, reduction: fixture.reduction,
                conditions: { LifecycleHarnessConditions.open },
                load: { cycle in
                    fixture.gate.update(.locked)
                    fixture.gate.update(.unlocked)
                    return AggregationReducer(cycleID: cycle)
                }))
        XCTAssertNil(fixture.flow.snapshot)
        XCTAssertFalse(fixture.flow.sensitiveContentVisible)
        XCTAssertNil(try fixture.reduction.snapshot())
    }

    func testPausedRestoreDiscardsLateReadAfterQuit() async throws {
        let fixture = try makePausedFixture()
        await ProductStartup.restore(flow: fixture.flow, lifecycle: fixture.harness.orchestrator,
            preferredLanguages: ["en"], pausedRestoration: ProductPausedRestoration(
                gate: fixture.gate, reduction: fixture.reduction,
                conditions: { LifecycleHarnessConditions.open },
                load: { cycle in
                    await fixture.harness.orchestrator.quit()
                    return AggregationReducer(cycleID: cycle)
                }))
        XCTAssertEqual(fixture.harness.orchestrator.phase, .stopped)
        XCTAssertNil(fixture.flow.snapshot)
        XCTAssertNil(try fixture.reduction.snapshot())
    }

    func testPausedRestoreReadFailureLeavesPausedAndHidden() async throws {
        let fixture = try makePausedFixture()
        await ProductStartup.restore(flow: fixture.flow, lifecycle: fixture.harness.orchestrator,
            preferredLanguages: ["en"], pausedRestoration: ProductPausedRestoration(
                gate: fixture.gate, reduction: fixture.reduction,
                conditions: { LifecycleHarnessConditions.open },
                load: { _ in throw KeyringError.locked }))
        XCTAssertEqual(fixture.harness.orchestrator.phase, .paused)
        XCTAssertNil(fixture.flow.snapshot)
        XCTAssertFalse(fixture.flow.sensitiveContentVisible)
        XCTAssertEqual(fixture.flow.noticeKey, "flow.actionUnavailable")
    }

    private func makePausedFixture() throws -> (harness: LifecycleHarness, flow: AppFlowObservable,
                                               gate: KeyAvailabilityGate, reduction: ProductReduction) {
        let preferences = Preferences(currentCycleID: CycleID(rawValue: "paused-test"))
        let harness = LifecycleHarness(storage: InMemoryPreferencesStorage(
            ciphertext: try PreferencesRepository.encode(preferences)))
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        return (harness, AppFlowObservable(flow: Phase1FlowModel(lifecycle: harness.orchestrator)),
                gate, ProductReduction(gate: gate))
    }
}

private actor PausedFixtureKeys: ObjectStoreKeySource {
    private var installed = false
    func install() { installed = true }
    func namespaceKeyVersions() -> Set<KeyVersion> { installed ? [KeyVersion(rawValue: 1)] : [] }
    func material(for version: KeyVersion) -> Data { Data(repeating: 27, count: 32) }
}

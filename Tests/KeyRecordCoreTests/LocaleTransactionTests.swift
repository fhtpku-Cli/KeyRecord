import XCTest
import KeyRecordCore
import KeyRecordTestSupport

@MainActor
final class LocaleTransactionTests: XCTestCase {
    private func lifecycle(_ storage: SuspendedPreferencesStorage) -> LifecycleOrchestrator {
        LifecycleOrchestrator(ports: LifecyclePorts(
            preferences: PreferencesRepository(storage: storage), keys: CountingLifecycleKeys(),
            capture: CountingLifecycleCapture(), flush: CountingLifecycleFlush(),
            readiness: FakeRestartReadiness(result: .success(LifecycleHarnessConditions.open)),
            login: CountingLoginItemBackend(), cycleIDs: FixedIDGenerator(value: CycleID(rawValue: "unused"))))
    }

    func testLastRequestedLocaleWinsWhenWritesCompleteInRequestOrder() async throws {
        // Given: Chinese is saving while English is requested second.
        let storage = try SuspendedPreferencesStorage(preferences: Preferences(currentCycleID: CycleID(rawValue: "kept")))
        let model = lifecycle(storage)
        await model.reload()
        let first = Task { try await model.setLocale(.simplifiedChinese) }
        await storage.waitForSave(1)
        let entered = expectation(description: "second request entered")
        let second = Task { entered.fulfill(); try await model.setLocale(.english) }
        await fulfillment(of: [entered], timeout: 2)
        // When: Chinese commits before the overlapping English save completes.
        await storage.release(1)
        _ = await first.result
        await storage.release(2)
        _ = await second.result
        // Then: durable bytes and published preferences agree on the last request.
        let bytes = await storage.ciphertext
        let persisted = try PreferencesRepository.decode(XCTUnwrap(bytes))
        XCTAssertEqual(persisted.locale, .english)
        XCTAssertEqual(model.state.preferences, persisted)
    }

    func testExclusionsDuringLocaleSavePreserveEveryUnrelatedField() async throws {
        // Given: an active cycle with non-default unrelated fields.
        let initial = Preferences(currentCycleID: CycleID(rawValue: "kept"), expectedCollecting: true,
            ignoredRecommendationKeys: ["ignored"], layout: LayoutPreference(preset: .iso, hasAsked: true),
            loginItemEnabled: true, keyboardPoolConfirmed: [try KeyCode(4)])
        let storage = try SuspendedPreferencesStorage(preferences: initial)
        let model = lifecycle(storage)
        await model.reload()
        let language = Task { try await model.setLocale(.simplifiedChinese) }
        await storage.waitForSave(1)
        let entered = expectation(description: "exclusion entered")
        let exclusion = Task { entered.fulfill(); await model.setExclusions(["com.ex"]) }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertEqual(model.state.gate.closureReason, .excluded)
        // When: persistence completes after immediate privacy revocation.
        await storage.release(2)
        await storage.release(1)
        _ = await language.result
        await exclusion.value
        // Then: both changes survive, including the existing cycle/layout/login data.
        let bytes = await storage.ciphertext
        let persisted = try PreferencesRepository.decode(XCTUnwrap(bytes))
        let expected = initial.updating(excludedBundleIDs: ["com.ex"], locale: .simplifiedChinese)
        XCTAssertEqual(persisted, expected)
        XCTAssertEqual(model.state.preferences, expected)
    }

    func testLocaleQueuedBehindExclusionSaveKeepsTheExclusion() async throws {
        // Given: an exclusion write owns persistence before a locale request arrives.
        let initial = Preferences(currentCycleID: CycleID(rawValue: "kept"))
        let storage = try SuspendedPreferencesStorage(preferences: initial)
        let model = lifecycle(storage)
        await model.reload()
        let exclusion = Task { await model.setExclusions(["com.ex"]) }
        await storage.waitForSave(1)
        let entered = expectation(description: "locale entered")
        let language = Task { entered.fulfill(); try await model.setLocale(.simplifiedChinese) }
        await fulfillment(of: [entered], timeout: 2)
        // When: both requests complete in admission order.
        await storage.release(1)
        await exclusion.value
        await storage.release(2)
        try await language.value
        // Then: locale does not overwrite the preceding exclusion transaction.
        let bytes = await storage.ciphertext
        let expected = initial.updating(excludedBundleIDs: ["com.ex"], locale: .simplifiedChinese)
        XCTAssertEqual(try PreferencesRepository.decode(XCTUnwrap(bytes)), expected)
        XCTAssertEqual(model.state.preferences, expected)
    }
}

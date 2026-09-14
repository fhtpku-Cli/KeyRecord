import XCTest
import KeyRecordCore

@MainActor
final class ProductLocaleTransactionTests: XCTestCase {
    private func flow(_ storage: SuspendedPreferencesStorage) async -> AppFlowObservable {
        let lifecycle = LifecycleOrchestrator(ports: LifecyclePorts(
            preferences: PreferencesRepository(storage: storage), keys: CountingLifecycleKeys(),
            capture: CountingLifecycleCapture(), flush: CountingLifecycleFlush(),
            readiness: FakeRestartReadiness(result: .failure(.keyUnavailable)),
            login: CountingLoginItemBackend(), cycleIDs: FixedIDGenerator(value: CycleID(rawValue: "unused"))))
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: lifecycle))
        await ProductStartup.restore(flow: flow, lifecycle: lifecycle, preferredLanguages: ["en"])
        return flow
    }

    func testOverlappingSelectionsPublishTheLastSuccessfullySavedLocale() async throws {
        try await assertOverlappingSelections(releaseSecondFirst: false)
    }

    func testLaterWriteCannotOvertakeEarlierSelectionWhenReleasedFirst() async throws {
        try await assertOverlappingSelections(releaseSecondFirst: true)
    }

    private func assertOverlappingSelections(releaseSecondFirst: Bool) async throws {
        // Given: Chinese saving, then an overlapping English selection.
        let initial = Preferences(currentCycleID: CycleID(rawValue: "kept"))
        let storage = try SuspendedPreferencesStorage(preferences: initial)
        let flow = await flow(storage)
        let first = Task { await flow.setLanguage("zh-Hans") }
        await storage.waitForSave(1)
        let entered = expectation(description: "English selection entered")
        let second = Task { entered.fulfill(); await flow.setLanguage("en") }
        await fulfillment(of: [entered], timeout: 2)
        let startedWrites = await storage.saveCount
        XCTAssertEqual(startedWrites, 1)
        XCTAssertEqual(flow.language, "en")
        if releaseSecondFirst { await storage.release(2) }
        // When: the two physical writes finish in the reviewer's problematic order.
        await storage.release(1)
        await first.value
        await storage.release(2)
        await second.value
        // Then: displayed selection, repository bytes and success indication agree.
        let bytes = await storage.ciphertext
        XCTAssertEqual(try PreferencesRepository.decode(XCTUnwrap(bytes)), initial)
        XCTAssertEqual(flow.language, "en")
        XCTAssertNil(flow.noticeKey)
    }

    func testStorageSaveFailureRetainsLastSuccessfullyPersistedSelection() async throws {
        // Given: Chinese is saving, and the next real storage save will throw.
        let initial = Preferences(currentCycleID: CycleID(rawValue: "kept"))
        let storage = try SuspendedPreferencesStorage(preferences: initial, failingAttempts: [2])
        let flow = await flow(storage)
        let first = Task { await flow.setLanguage("zh-Hans") }
        await storage.waitForSave(1)
        let entered = expectation(description: "failing English selection entered")
        let selection = Task { entered.fulfill(); await flow.setLanguage("en") }
        await fulfillment(of: [entered], timeout: 2)
        // When: Chinese commits, then the overlapping English write fails.
        await storage.release(1)
        await first.value
        let persistedBeforeFailure = await storage.ciphertext
        await storage.waitForSave(2)
        XCTAssertEqual(flow.language, "zh-Hans")
        await storage.release(2)
        await selection.value
        // Then: the successful Chinese selection and bytes survive, with a visible error.
        let bytes = await storage.ciphertext
        XCTAssertEqual(bytes, persistedBeforeFailure)
        XCTAssertEqual(try PreferencesRepository.decode(XCTUnwrap(bytes)).locale, .simplifiedChinese)
        XCTAssertEqual(flow.language, "zh-Hans")
        XCTAssertEqual(flow.noticeKey, "flow.actionUnavailable")
    }
}

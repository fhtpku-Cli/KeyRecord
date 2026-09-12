import XCTest
import KeyRecordCore
import KeyRecordTestSupport

final class PreferencesTests: XCTestCase {
    private let cycle = CycleID(rawValue: "cycle-prefs")

    private func fullPreferences(loginItemEnabled: Bool = false) throws -> Preferences {
        Preferences(
            currentCycleID: cycle,
            expectedCollecting: true,
            excludedBundleIDs: ["com.excluded.one", "com.excluded.two"],
            ignoredRecommendationKeys: ["ignored-key"],
            layout: LayoutPreference(preset: .iso, hasAsked: true),
            loginItemEnabled: loginItemEnabled,
            locale: .simplifiedChinese,
            keyboardPoolConfirmed: Set([try KeyCode(0), try KeyCode(4)]))
    }

    func testSaveThenLoadRoundTripsEveryField() async throws {
        // Given: an empty encrypted storage; When: saving and loading; Then: all fields return unchanged.
        let storage = InMemoryPreferencesStorage()
        let repository = PreferencesRepository(storage: storage)
        let preferences = try fullPreferences(loginItemEnabled: true)
        try await repository.save(preferences)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, preferences)
        XCTAssertEqual(loaded?.schemaVersion, .v1)
    }

    func testEncodedWireCarriesSchemaVersionOne() throws {
        // Given: current preferences; When: encoded for encryption; Then: version field is explicitly 1.
        let data = try PreferencesRepository.encode(try fullPreferences())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        let cycleWire = try XCTUnwrap(json["currentCycleID"] as? [String: Any])
        XCTAssertEqual(cycleWire["rawValue"] as? String, cycle.rawValue)
        XCTAssertEqual(Set(json.keys), [
            "schemaVersion", "expectedCollecting", "currentCycleID", "excludedBundleIDs",
            "ignoredRecommendationKeys", "layout", "loginItemEnabled", "locale", "keyboardPoolConfirmed",
        ])
    }

    func testUnknownFieldsAreRejectedAsCorrupt() async throws {
        // Given: ciphertext carrying an unknown field; When: loaded; Then: corrupt, no silent tolerance.
        let json = try JSONSerialization.data(withJSONObject: validWireJSON().merging(["unknown": true]) { $1 })
        let repository = PreferencesRepository(storage: InMemoryPreferencesStorage(ciphertext: json))
        do {
            _ = try await repository.load()
            XCTFail("unknown fields must be rejected")
        } catch let error as PreferencesRepositoryError {
            XCTAssertEqual(error, .corruptStoredPreferences)
        }
    }

    func testUnsupportedSchemaVersionIsRejectedAsCorrupt() async throws {
        // Given: preferences stamped with a future schema version; When: loaded; Then: corrupt.
        let json = try JSONSerialization.data(withJSONObject: validWireJSON().merging(["schemaVersion": 2]) { $1 })
        let repository = PreferencesRepository(storage: InMemoryPreferencesStorage(ciphertext: json))
        do {
            _ = try await repository.load()
            XCTFail("future schema version must be rejected")
        } catch let error as PreferencesRepositoryError {
            XCTAssertEqual(error, .corruptStoredPreferences)
        }
    }

    func testMalformedJSONIsRejectedAsCorrupt() async throws {
        // Given: undecodable ciphertext; When: loaded; Then: corruption is reported, never a fresh install.
        let repository = PreferencesRepository(storage: InMemoryPreferencesStorage(ciphertext: Data([0, 1, 2, 3])))
        do {
            _ = try await repository.load()
            XCTFail("malformed bytes must be rejected")
        } catch let error as PreferencesRepositoryError {
            XCTAssertEqual(error, .corruptStoredPreferences)
        }
    }

    func testStorageLoadFailureIsTypedUnavailable() async throws {
        // Given: a storage that cannot serve ciphertext; When: loading; Then: unavailable, not corrupt.
        let repository = PreferencesRepository(
            storage: InMemoryPreferencesStorage(loadFailure: .storageUnavailable))
        do {
            _ = try await repository.load()
            XCTFail("storage failure must propagate")
        } catch let error as PreferencesRepositoryError {
            XCTAssertEqual(error, .storageUnavailable)
        }
    }

    func testStorageSaveFailureIsTypedUnavailable() async throws {
        // Given: a storage that rejects writes; When: saving; Then: unavailable error to the caller.
        let repository = PreferencesRepository(
            storage: InMemoryPreferencesStorage(saveFailure: .storageUnavailable))
        do {
            try await repository.save(try fullPreferences())
            XCTFail("save failure must propagate")
        } catch let error as PreferencesRepositoryError {
            XCTAssertEqual(error, .storageUnavailable)
        }
    }

    func testExclusionChangeSurvivesRepositoryReopen() async throws {
        // Given: exclusions persisted; When: a fresh repository instance opens the same storage; Then: applied.
        let storage = InMemoryPreferencesStorage()
        try await PreferencesRepository(storage: storage).save(try fullPreferences())
        let reopened = try await PreferencesRepository(storage: storage).load()
        XCTAssertEqual(reopened?.excludedBundleIDs, ["com.excluded.one", "com.excluded.two"])
        XCTAssertEqual(reopened?.expectedCollecting, true)
        XCTAssertEqual(reopened?.currentCycleID, cycle)
    }

    func testFirstRunLoadReturnsNilWithoutWrites() async throws {
        // Given: empty storage; When: loading; Then: nil first-run result and zero writes.
        let storage = InMemoryPreferencesStorage()
        let repository = PreferencesRepository(storage: storage)
        let loaded = try await repository.load()
        XCTAssertNil(loaded)
        let counts = await storage.saveCount
        XCTAssertEqual(counts, 0)
    }

    private func validWireJSON() -> [String: Any] {
        [
            "schemaVersion": 1,
            "expectedCollecting": true,
            "currentCycleID": ["rawValue": cycle.rawValue],
            "excludedBundleIDs": ["com.ex"],
            "ignoredRecommendationKeys": [],
            "layout": ["preset": "none", "hasAsked": false],
            "loginItemEnabled": false,
            "locale": "en",
            "keyboardPoolConfirmed": [],
        ]
    }
}

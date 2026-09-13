import Foundation

public enum PreferencesRepositoryError: Error, Equatable, Sendable {
    case corruptStoredPreferences
    case storageUnavailable
}

/// Ciphertext boundary owned by the future Store object store (tasks 12/19 wire the real adapter).
/// Implementations must provide authenticated encryption; this repository never sees key material.
public protocol EncryptedPreferencesStorage: Sendable {
    /// Returns nil when no preferences have been persisted yet (first run).
    func loadCiphertext() async throws -> Data?
    func saveCiphertext(_ ciphertext: Data) async throws
}

private enum PreferencesCache: Sendable {
    case absent
    case present(Preferences)

    var preferences: Preferences? {
        if case .present(let preferences) = self { return preferences }
        return nil
    }
}

/// Architecture §10.2 L2/L3: encrypted Preferences persistence with strict decoding.
/// Malformed/unknown-schema bytes are corruption (fail closed), never an invitation to reset.
public actor PreferencesRepository: PreferencesPersisting {
    private let storage: any EncryptedPreferencesStorage
    private var cache: PreferencesCache?

    public init(storage: any EncryptedPreferencesStorage) {
        self.storage = storage
    }

    public func load() async throws -> Preferences? {
        if let cache { return cache.preferences }
        let data: Data?
        do {
            data = try await storage.loadCiphertext()
        } catch {
            throw PreferencesRepositoryError.storageUnavailable
        }
        guard let data else {
            cache = .absent
            return nil
        }
        do {
            let preferences = try JSONDecoder().decode(Preferences.self, from: data)
            cache = .present(preferences)
            return preferences
        } catch is SchemaError {
            throw PreferencesRepositoryError.corruptStoredPreferences
        } catch is DecodingError {
            throw PreferencesRepositoryError.corruptStoredPreferences
        }
    }

    public func reloadAfterMaintenance() async throws -> Preferences? {
        cache = nil
        return try await load()
    }

    public func save(_ preferences: Preferences) async throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(preferences)
        } catch {
            throw PreferencesRepositoryError.corruptStoredPreferences
        }
        do {
            try await storage.saveCiphertext(data)
        } catch {
            throw PreferencesRepositoryError.storageUnavailable
        }
        cache = .present(preferences)
    }

    /// Encode/decode shared by tests that seed raw ciphertext through a fake storage.
    public static func decode(_ data: Data) throws -> Preferences {
        try JSONDecoder().decode(Preferences.self, from: data)
    }

    public static func encode(_ preferences: Preferences) throws -> Data {
        try JSONEncoder().encode(preferences)
    }
}

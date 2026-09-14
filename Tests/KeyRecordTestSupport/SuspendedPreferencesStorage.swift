import Foundation
import KeyRecordCore

public actor SuspendedPreferencesStorage: EncryptedPreferencesStorage {
    public private(set) var ciphertext: Data?
    public private(set) var saveCount = 0
    private var permits: Set<Int> = []
    private var writes: [Int: CheckedContinuation<Void, Never>] = [:]
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]
    private let failingAttempts: Set<Int>

    public init(preferences: Preferences, failingAttempts: Set<Int> = []) throws {
        ciphertext = try PreferencesRepository.encode(preferences)
        self.failingAttempts = failingAttempts
    }

    public func loadCiphertext() -> Data? { ciphertext }

    public func saveCiphertext(_ data: Data) async throws {
        saveCount += 1
        let attempt = saveCount
        arrivals.removeValue(forKey: attempt)?.resume()
        if !permits.contains(attempt) {
            await withCheckedContinuation { writes[attempt] = $0 }
        }
        if failingAttempts.contains(attempt) { throw PreferencesRepositoryError.storageUnavailable }
        ciphertext = data
    }

    public func waitForSave(_ attempt: Int) async {
        if saveCount >= attempt { return }
        await withCheckedContinuation { arrivals[attempt] = $0 }
    }

    public func release(_ attempt: Int) {
        permits.insert(attempt)
        writes.removeValue(forKey: attempt)?.resume()
    }
}

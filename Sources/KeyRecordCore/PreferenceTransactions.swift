import Foundation

@MainActor
final class PreferenceTransactions {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async throws {
        guard !Task.isCancelled, waiters.count < 32 else {
            throw PreferencesRepositoryError.storageUnavailable
        }
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        if Task.isCancelled {
            release()
            throw PreferencesRepositoryError.storageUnavailable
        }
    }

    func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }
}

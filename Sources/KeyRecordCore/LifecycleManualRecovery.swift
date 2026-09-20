import Foundation

public struct ManualRecoveryAttempt: Equatable, Sendable {
    fileprivate let epoch: UInt64
}

public final class ManualRecoveryFence: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: UInt64 = 0

    public init() {}

    public func invalidate() {
        lock.withLock { epoch &+= 1 }
    }

    public func isCurrent(_ attempt: ManualRecoveryAttempt) -> Bool {
        lock.withLock { attempt.epoch == epoch }
    }

    @MainActor
    public func perform(
        prepare: @MainActor (ManualRecoveryAttempt) async -> Bool,
        start: @MainActor () async -> Void,
        abort: @MainActor () async -> Void
    ) async -> Bool {
        let attempt = lock.withLock { ManualRecoveryAttempt(epoch: epoch) }
        guard await prepare(attempt), isCurrent(attempt) else {
            await abort()
            return false
        }
        await start()
        guard isCurrent(attempt) else {
            await abort()
            return false
        }
        return true
    }
}

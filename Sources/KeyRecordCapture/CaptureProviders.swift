import KeyRecordCore

public protocol FrontmostAppProvider: Sendable {
    func foregroundState() async -> ForegroundState
}

public protocol SessionLockProvider: Sendable {
    func sessionLockState() async -> SessionLockState
}

public enum EventHandoffResult: Sendable { case accepted, closed, overflow }

/// Architecture §3.2, plan contract 8: future actor-owned source. Callback may only perform bounded handoff.
/// Overflow must close/invalidate capture; no disk, Keychain, process or network work in the callback.
public protocol EventSource: Sendable {
    func start(deliver: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws
    func stop() async
}

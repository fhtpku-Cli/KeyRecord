import Foundation

// MARK: - Typed side-effect failures

/// Key provisioning after consent. Keys are created only after consent and fresh-store proof (task 11).
public enum LifecycleKeyError: Error, Equatable, Sendable {
    case creationDenied
    case unavailable
}

/// Encrypted preference persistence failures. No blind retry: the user explicitly retries (§10.3 I/O).
public enum LifecycleStoreError: Error, Equatable, Sendable {
    case filesystemFailure
    case protectedDataUnavailable
    case corruptStoredPreferences
}

/// Capture start failures. A missing input-monitoring grant is an explicit, presentable denial.
public enum LifecycleCaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case runtimeFailed
}

/// Contract 8: pause/quit flush must complete while unlocked; timeout/error can never claim data saved.
public enum LifecycleFlushError: Error, Equatable, Sendable {
    case failed
    case timedOut
    case locked
}

/// Fresh key/privacy verification on reopen. Each failed check maps to a visible blocked reason.
public enum LifecycleReadinessError: Error, Equatable, Sendable {
    case keyUnavailable
    case sessionLocked
    case secureInputActive
    case foregroundUnreliable
    case queryFailed
}

// MARK: - Side-effect ports (all faked in tests; real adapters compose tasks 11/12/13)

/// Creates the versioned namespace key after consent. Never called on denial.
public protocol LifecycleKeyProviding: Sendable {
    func provisionAfterConsent() async throws
}

/// Wraps the task 13 Capture `EventSource`; the callback/bounded queue is wired in task 19.
public protocol LifecycleCaptureControlling: Sendable {
    func start() async throws
    func stop() async
}

/// Unlocked durable flush of aggregated deltas (contract 8).
public protocol LifecycleFlushing: Sendable {
    func flushWhileUnlocked() async throws
}

/// Fresh key + privacy checks required before a collecting-expectation restart.
public protocol RestartReadinessChecking: Sendable {
    func verifyRestartReadiness() async throws -> RuntimeConditions
}

/// Thin ServiceManagement seam. Core decides when registration may happen; the App backend only acts.
public protocol LoginItemBackend: Sendable {
    func register() async throws
    func unregister() async throws
}

/// Encrypted Preferences DTO repository.
public protocol PreferencesPersisting: Sendable {
    func load() async throws -> Preferences?
    func save(_ preferences: Preferences) async throws
}

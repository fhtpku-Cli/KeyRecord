import Foundation

public enum ForegroundState: Equatable, Sendable {
    case attributable(bundleID: String)
    case reliablyUnattributable
    case unknown
}

public enum SecureInputState: Sendable { case enabled, disabled, unknown }
public enum SessionLockState: Sendable { case locked, unlocked, unknown }
public enum KeyAvailability: Sendable { case available, unavailable, unknown }
public enum ExclusionState: Sendable { case included, excluded, unknown }

/// Plan contract 5 extends architecture §4.4. Inputs only; task 8 owns the predicate and held-state effects.
/// Collecting AND available key AND unlocked AND disabled Secure Input AND reliable foreground AND included.
public struct GateInputs: Equatable, Sendable {
    public let collecting: Bool
    public let keyAvailability: KeyAvailability
    public let sessionLock: SessionLockState
    public let secureInput: SecureInputState
    public let foreground: ForegroundState
    public let exclusion: ExclusionState

    public init(
        collecting: Bool = false, keyAvailability: KeyAvailability = .unknown,
        sessionLock: SessionLockState = .unknown, secureInput: SecureInputState = .unknown,
        foreground: ForegroundState = .unknown, exclusion: ExclusionState = .unknown
    ) {
        self.collecting = collecting
        self.keyAvailability = keyAvailability
        self.sessionLock = sessionLock
        self.secureInput = secureInput
        self.foreground = foreground
        self.exclusion = exclusion
    }
}

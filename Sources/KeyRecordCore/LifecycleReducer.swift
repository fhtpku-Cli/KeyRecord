import Foundation

// MARK: - Lifecycle vocabulary (architecture §10.2 L1–L4, plan contract 8)

/// Stable phases plus explicit busy phases for in-flight persistence/flush transactions.
public enum LifecyclePhase: Equatable, Sendable {
    case unstarted
    case consent
    case starting
    case collecting
    case pausing
    case paused
    case resuming
    case stopping
    case stopped
    case reopening
    case blocked
    case failed
}

/// Commands the reducer may issue. The orchestrator executes them in order; fakes count every call.
public enum LifecycleEffect: Equatable, Sendable {
    case provisionKey
    case persistPreferences(Preferences)
    case startCapture
    case stopCapture
    case flushWhileUnlocked
    case verifyRestartReadiness
    case registerLoginItem
    case unregisterLoginItem
    case reloadFromStorage
}

public enum LoginItemStatus: Equatable, Sendable {
    case neverOffered
    case registering
    case unregistering
    case registered
    case unregistered
    case rejected(LoginItemSystemRejection)
}

/// SMAppService rejections surfaced verbatim through the thin App backend; never silently swallowed.
public enum LoginItemSystemRejection: Error, Equatable, Sendable {
    case registrationDenied
    case unregistrationDenied
    case unsupported
}

public enum BlockedReason: Equatable, Sendable {
    case keyUnavailable
    case sessionLocked
    case secureInputActive
    case foregroundUnreliable
}

public enum LifecycleFailure: Equatable, Error, Sendable {
    case keyProvisionFailed(LifecycleKeyError)
    case initialPersistenceFailed(LifecycleStoreError)
    case pausePersistenceFailed(LifecycleStoreError)
    case resumePersistenceFailed(LifecycleStoreError)
    case captureStartDenied(LifecycleCaptureError)
    case preferencesLoadFailed(LifecycleStoreError)
}

/// Presentable, non-phase errors. Collection can continue; the user is never left guessing.
public enum LifecycleNotice: Equatable, Sendable {
    case pauseFlushFailed(LifecycleFlushError)
    case quitFlushFailed(LifecycleFlushError)
    case loginRegistrationRejected(LoginItemSystemRejection)
    case loginUnregistrationRejected(LoginItemSystemRejection)
    case exclusionPersistenceFailed(LifecycleStoreError)
    case loginUnavailableWhileIdle
}

/// Provider-side condition snapshot. `collecting` and exclusion are derived by the reducer, never trusted.
public struct RuntimeConditions: Equatable, Sendable {
    public let keyAvailability: KeyAvailability
    public let sessionLock: SessionLockState
    public let secureInput: SecureInputState
    public let foreground: ForegroundState

    public init(keyAvailability: KeyAvailability, sessionLock: SessionLockState,
                secureInput: SecureInputState, foreground: ForegroundState) {
        self.keyAvailability = keyAvailability
        self.sessionLock = sessionLock
        self.secureInput = secureInput
        self.foreground = foreground
    }

    public static let unknown = RuntimeConditions(
        keyAvailability: .unknown, sessionLock: .unknown, secureInput: .unknown, foreground: .unknown)

    public func with(keyAvailability: KeyAvailability? = nil, sessionLock: SessionLockState? = nil,
              secureInput: SecureInputState? = nil, foreground: ForegroundState? = nil) -> RuntimeConditions {
        RuntimeConditions(keyAvailability: keyAvailability ?? self.keyAvailability,
                          sessionLock: sessionLock ?? self.sessionLock,
                          secureInput: secureInput ?? self.secureInput,
                          foreground: foreground ?? self.foreground)
    }
}

/// Event-driven FSM state. The reducer is a pure value; the App controller is an async shell around it.
public struct LifecycleState: Equatable, Sendable {
    public internal(set) var phase: LifecyclePhase
    public internal(set) var preferences: Preferences?
    public internal(set) var conditions: RuntimeConditions
    public internal(set) var gate: PrivacyGate
    public internal(set) var blockedReason: BlockedReason?
    public internal(set) var failure: LifecycleFailure?
    public internal(set) var notice: LifecycleNotice?
    public internal(set) var loginItem: LoginItemStatus
    /// Phase captured when entering `.failed`, so retry replays exactly the interrupted transaction.
    public internal(set) var failedFromPhase: LifecyclePhase?

    public init(phase: LifecyclePhase = .unstarted, preferences: Preferences? = nil,
                conditions: RuntimeConditions = .unknown, gate: PrivacyGate = PrivacyGate(),
                blockedReason: BlockedReason? = nil, failure: LifecycleFailure? = nil,
                notice: LifecycleNotice? = nil, loginItem: LoginItemStatus = .neverOffered,
                failedFromPhase: LifecyclePhase? = nil) {
        self.phase = phase
        self.preferences = preferences
        self.conditions = conditions
        self.gate = gate
        self.blockedReason = blockedReason
        self.failure = failure
        self.notice = notice
        self.loginItem = loginItem
        self.failedFromPhase = failedFromPhase
    }

    public static let initial = LifecycleState()

    public static func blockedForRetry(preferences: Preferences, reason: BlockedReason) -> LifecycleState {
        LifecycleState(phase: .blocked, preferences: preferences, blockedReason: reason,
                       loginItem: preferences.loginItemEnabled ? .registered : .unregistered)
    }
}

public struct LifecycleOutcome: Equatable, Sendable {
    public let state: LifecycleState
    public let effects: [LifecycleEffect]
    public init(state: LifecycleState, effects: [LifecycleEffect]) {
        self.state = state
        self.effects = effects
    }
}

/// Pure transition. Allowed only in the documented source phase; unknown events are ignored.
public func reduce(_ state: LifecycleState, _ event: LifecycleEvent) -> LifecycleOutcome {
    var next = state
    let effects = next.apply(event)
    return LifecycleOutcome(state: next, effects: effects)
}

extension LifecycleState {
    /// Task 8 gate participates directly: every transition re-evaluates with the current expectation.
    mutating func refreshGate() {
        let inputs = GateInputs(
            collecting: phase == .collecting,
            keyAvailability: conditions.keyAvailability,
            sessionLock: conditions.sessionLock,
            secureInput: conditions.secureInput,
            foreground: conditions.foreground,
            exclusion: Self.exclusionState(foreground: conditions.foreground,
                                           exclusions: preferences?.excludedBundleIDs ?? []))
        gate.update(inputs)
    }

    static func exclusionState(foreground: ForegroundState, exclusions: Set<String>) -> ExclusionState {
        switch foreground {
        case .unknown: .unknown
        // Reliably unattributable events carry no bundle to exclude.
        case .reliablyUnattributable: .included
        case .attributable(let bundleID): exclusions.contains(bundleID) ? .excluded : .included
        }
    }

    static func blockedReason(for closure: PrivacyGate.ClosureReason) -> BlockedReason? {
        switch closure {
        case .keyUnavailable: .keyUnavailable
        case .sessionLocked: .sessionLocked
        case .secureInput: .secureInputActive
        case .foregroundUnreliable: .foregroundUnreliable
        case .notCollecting, .excluded, .reset, .generationExhausted: nil
        }
    }

    /// Probe gate openness under a "collecting" expectation without committing a collecting phase.
    func openUnderCollecting(_ candidate: RuntimeConditions) -> Bool {
        var probe = gate
        probe.update(collectingInputs(candidate))
        return probe.isOpen
    }

    mutating func enterFailure(_ failure: LifecycleFailure) {
        failedFromPhase = phase
        self.failure = failure
        phase = .failed
    }
}

extension PrivacyGate: Equatable {
    public static func == (lhs: PrivacyGate, rhs: PrivacyGate) -> Bool {
        lhs.generation == rhs.generation && lhs.closureReason == rhs.closureReason
        && lhs.heldKeys == rhs.heldKeys && lhs.modifiers == rhs.modifiers
    }
}

extension Preferences {
    /// Lifecycle-scoped immutable updates; other preference fields are preserved byte-for-byte.
    public func updating(expectedCollecting: Bool? = nil, excludedBundleIDs: Set<String>? = nil,
                         loginItemEnabled: Bool? = nil, locale: ProductLocale? = nil,
                         layout: LayoutPreference? = nil) -> Preferences {
        Preferences(
            currentCycleID: currentCycleID,
            expectedCollecting: expectedCollecting ?? self.expectedCollecting,
            excludedBundleIDs: excludedBundleIDs ?? self.excludedBundleIDs,
            ignoredRecommendationKeys: ignoredRecommendationKeys,
            layout: layout ?? self.layout,
            loginItemEnabled: loginItemEnabled ?? self.loginItemEnabled,
            locale: locale ?? self.locale,
            keyboardPoolConfirmed: keyboardPoolConfirmed)
    }
}

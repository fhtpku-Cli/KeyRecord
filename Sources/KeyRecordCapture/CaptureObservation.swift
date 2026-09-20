import KeyRecordCore

struct CaptureProviderSnapshot: Equatable, Sendable {
    let foreground: ForegroundState
    let secureInput: SecureInputState
    let sessionLock: SessionLockState

    init(_ inputs: GateInputs) {
        foreground = inputs.foreground
        secureInput = inputs.secureInput
        sessionLock = inputs.sessionLock
    }

    static let unknown = CaptureProviderSnapshot(GateInputs())
}

/// Why a capture session was invalidated.
///
/// Public so the composition layer can route every reason into ONE serial recovery entry
/// point (KR-02) instead of each backend independently calling `queue.revoke()` and
/// dropping the reason on the floor.
public enum CaptureInvalidation: Sendable, Equatable, CaseIterable {
    case foregroundChanged, secureInputChanged, sessionChanged
    case permissionRevoked, sleep, tapDisabled

    /// Whether an automatic, fresh-checked recovery attempt is appropriate.
    /// Sleep and session change are privacy transitions: they must stay closed until the
    /// explicit unlock/resume path re-verifies readiness.
    public var allowsAutomaticRecovery: Bool {
        switch self {
        case .foregroundChanged, .tapDisabled, .secureInputChanged: return true
        case .permissionRevoked, .sleep, .sessionChanged: return false
        }
    }
}

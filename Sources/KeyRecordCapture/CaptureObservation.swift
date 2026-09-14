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

enum CaptureInvalidation: Sendable {
    case foregroundChanged, secureInputChanged, sessionChanged
    case permissionRevoked, sleep, tapDisabled
}

import Foundation

public enum LoginItemIntent: Equatable, Sendable {
    case register
    case unregister
    case none
}

/// Pure decision core (architecture §10.1 L4/FR-C4). The App controller and reducer both call this;
/// the SMAppService backend only executes the resulting intent. No permission polling exists.
public enum LoginItemPolicy {
    /// Registration is offered only after a successful capture start keeps collection running.
    public static func allowsRegistration(_ phase: LifecyclePhase) -> Bool {
        phase == .collecting
    }

    public static func intent(forDesiredEnabled enabled: Bool,
                              phase: LifecyclePhase, status: LoginItemStatus) -> LoginItemIntent {
        if enabled {
            guard allowsRegistration(phase), status != .registered, status != .registering else { return .none }
            return .register
        }
        return status == .registered ? .unregister : .none
    }

    /// Presentation helper: only login-item notices surface on the login-item settings row.
    public static func rejection(from notice: LifecycleNotice?) -> LoginItemSystemRejection? {
        switch notice {
        case .loginRegistrationRejected(let rejection), .loginUnregistrationRejected(let rejection):
            rejection
        case .none, .pauseFlushFailed, .quitFlushFailed, .exclusionPersistenceFailed, .loginUnavailableWhileIdle:
            nil
        }
    }
}

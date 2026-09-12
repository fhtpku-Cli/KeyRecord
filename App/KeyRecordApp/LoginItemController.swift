import SwiftUI
import KeyRecordCore

/// Observable settings-row state for FR-C4. All decisions come from `LoginItemPolicy`/the reducer;
/// this type never touches SMAppService directly and never polls registration status.
@MainActor
@Observable
public final class LoginItemController {
    public private(set) var status: LoginItemStatus = .neverOffered
    public private(set) var rejection: LoginItemSystemRejection?

    private let request: @MainActor (Bool) async -> Void

    public init(request: @escaping @MainActor (Bool) async -> Void) {
        self.request = request
    }

    public var isEnabled: Bool { status == .registered }

    public var canEnable: Bool {
        LoginItemPolicy.intent(forDesiredEnabled: true, phase: observedPhase, status: status) == .register
    }

    /// Updated by CaptureController from reducer state; phase gates manual enables (collecting only).
    private var observedPhase: LifecyclePhase = .unstarted

    public func setEnabled(_ enabled: Bool) async {
        await request(enabled)
    }

    public func update(phase: LifecyclePhase, state: LoginItemStatus, notice: LifecycleNotice?) {
        observedPhase = phase
        status = state
        rejection = LoginItemPolicy.rejection(from: notice)
    }
}

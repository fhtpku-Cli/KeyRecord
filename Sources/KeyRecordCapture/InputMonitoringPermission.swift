import Foundation
import CoreGraphics

/// Current Input Monitoring authorization for this process.
///
/// `unknown` is distinct from `denied`: a query that could not be answered must fail
/// closed like a denial but must never be presented to the user as "you refused".
public enum InputMonitoringStatus: Equatable, Sendable {
    case granted
    case denied
    case unknown
}

/// Injectable seam for the Input Monitoring grant (KR-07).
///
/// Split deliberately in two:
/// * `preflight()` only reports status and never shows UI, so it is safe to call on any
///   provider read or before creating a tap.
/// * `request()` may present the system prompt and must therefore be called **only** from
///   an explicit user Start/Accept action — never from a provider read, an invalidation
///   recovery, or any background loop.
public protocol InputMonitoringPermission: Sendable {
    func preflight() -> InputMonitoringStatus
    /// Presents the system prompt once. Returns the status observed immediately after.
    @discardableResult
    func request() -> InputMonitoringStatus
}

/// Production implementation over CoreGraphics.
///
/// Note on prior art: the repository previously carried a comment claiming a freshly
/// created tap is disabled by default. Apple documents the opposite ("Event taps are
/// normally enabled when created"), so `tapEnable(true)` is retained as a defensive
/// action only and is not treated as a fix for missing callbacks.
public struct SystemInputMonitoringPermission: InputMonitoringPermission {
    public init() {}

    public func preflight() -> InputMonitoringStatus {
        CGPreflightListenEventAccess() ? .granted : .denied
    }

    @discardableResult
    public func request() -> InputMonitoringStatus {
        // Presents the system prompt at most once per call; macOS itself coalesces
        // repeats for a given binary/TCC identity.
        CGRequestListenEventAccess()
        return CGPreflightListenEventAccess() ? .granted : .denied
    }
}

/// Never granted, never prompts. Used where capture must stay blocked by construction.
public struct DeniedInputMonitoringPermission: InputMonitoringPermission {
    public init() {}
    public func preflight() -> InputMonitoringStatus { .denied }
    @discardableResult
    public func request() -> InputMonitoringStatus { .denied }
}

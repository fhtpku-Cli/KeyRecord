import KeyRecordCore

/// Architecture §§3.2, 4.4: sole seam for the future Apple Secure Input adapter.
/// No system API is selected or called here; unavailable/failed queries must return unknown, not disabled.
public protocol SecureInputProvider: Sendable {
    func secureInputState() async -> SecureInputState
}

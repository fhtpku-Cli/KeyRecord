import Foundation
import ServiceManagement
import KeyRecordCore

enum ProductLogin {
    static func make(trialStoreRoot: URL? = nil) -> any LoginItemBackend {
        #if DEBUG
        if trialStoreRoot != nil { return BlockedTrialLoginItemBackend() }
        #endif
        return SMAppServiceLoginItemBackend()
    }
}

/// Sole SMAppService seam (architecture §10.1 L4/FR-C4). Core decides WHEN via `LoginItemBackend`;
/// this type only executes. Symbols: `SMAppService.mainApp` and `register()/unregister()`
/// (SMAppService.h, macOS 13.0+; deployment target is macOS 14). There is no status polling.
/// Header note: SMAppService requires a code-signed product; unsigned QA builds never invoke this type.
public actor SMAppServiceLoginItemBackend: LoginItemBackend {
    public init() {}

    public func register() async throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LoginItemSystemRejection.registrationDenied
        }
    }

    public func unregister() async throws {
        do {
            try await SMAppService.mainApp.unregister()
        } catch {
            throw LoginItemSystemRejection.unregistrationDenied
        }
    }
}

#if DEBUG
struct BlockedTrialLoginItemBackend: LoginItemBackend {
    func register() async throws { throw LoginItemSystemRejection.registrationDenied }
    func unregister() async throws {}
}
#endif

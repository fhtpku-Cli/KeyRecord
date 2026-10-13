import ServiceManagement
import KeyRecordCore

enum ProductLogin {
    static func make() -> any LoginItemBackend { SMAppServiceLoginItemBackend() }
}

/// Sole SMAppService seam (architecture §10.1 L4/FR-C4). Core decides WHEN via `LoginItemBackend`;
/// this type only executes. Symbols: `SMAppService.mainApp` and `register()/unregister()`
/// (SMAppService.h, macOS 13.0+; deployment target is macOS 14). There is no status polling.
/// Header note: SMAppService requires a code-signed product; unsigned QA builds never invoke this type.
public actor SMAppServiceLoginItemBackend: LoginItemBackend {
    private let unregisterService: @Sendable () async throws -> Void
    private let registrationStatus: @Sendable () -> SMAppService.Status
    public init(registrationStatus: @escaping @Sendable () -> SMAppService.Status = { SMAppService.mainApp.status },
                unregisterService: @escaping @Sendable () async throws -> Void = {
        try await SMAppService.mainApp.unregister()
    }) { self.unregisterService = unregisterService; self.registrationStatus = registrationStatus }

    public func register() async throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LoginItemSystemRejection.registrationDenied
        }
    }

    public func unregister() async throws {
        if registrationStatus() == .notRegistered { return }
        do {
            try await unregisterService()
        } catch {
            let failure = error as NSError
            if #available(macOS 15.0, *), failure.domain == SMAppServiceErrorDomain, failure.code == kSMErrorJobNotFound { return }
            throw LoginItemSystemRejection.unregistrationDenied
        }
    }
}

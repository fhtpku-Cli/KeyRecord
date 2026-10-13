import ServiceManagement
import KeyRecordCore

enum ProductLogin {
    static func make() -> any LoginItemBackend { SMAppServiceLoginItemBackend() }
    #if DEBUG
    static func make(registrationIsAbsent: @escaping @Sendable () -> Bool,
                     unregisterService: @escaping @Sendable () async throws -> Void) -> any LoginItemBackend {
        SMAppServiceLoginItemBackend(registrationIsAbsent: registrationIsAbsent, unregisterService: unregisterService)
    }
    static var nativeRejectionFixtures: (absent: NSError, denied: [NSError])? {
        if #available(macOS 15.0, *) {
            return (NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorJobNotFound)),
                [NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorInvalidSignature)),
                 NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorAuthorizationFailure)),
                 NSError(domain: NSCocoaErrorDomain, code: Int(kSMErrorJobNotFound))])
        }
        return nil
    }
    #endif
}

/// Sole SMAppService seam (architecture §10.1 L4/FR-C4). Core decides WHEN via `LoginItemBackend`;
/// this type only executes. Symbols: `SMAppService.mainApp` and `register()/unregister()`
/// (SMAppService.h, macOS 13.0+; deployment target is macOS 14). There is no status polling.
public actor SMAppServiceLoginItemBackend: LoginItemBackend {
    private let unregisterService: @Sendable () async throws -> Void
    private let registrationIsAbsent: @Sendable () -> Bool
    public init(registrationIsAbsent: @escaping @Sendable () -> Bool = { SMAppService.mainApp.status == .notRegistered },
                unregisterService: @escaping @Sendable () async throws -> Void = {
        try await SMAppService.mainApp.unregister()
    }) { self.unregisterService = unregisterService; self.registrationIsAbsent = registrationIsAbsent }

    public func register() async throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LoginItemSystemRejection.registrationDenied
        }
    }

    public func unregister() async throws {
        if registrationIsAbsent() { return }
        do {
            try await unregisterService()
        } catch {
            let failure = error as NSError
            if #available(macOS 15.0, *), failure.domain == SMAppServiceErrorDomain, failure.code == kSMErrorJobNotFound { return }
            throw LoginItemSystemRejection.unregistrationDenied
        }
    }
}

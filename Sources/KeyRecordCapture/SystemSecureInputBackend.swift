import Foundation
import KeyRecordCore

public struct SystemSecureInputProvider: SecureInputProvider {
    public init() {}
    public func secureInputState() async -> SecureInputState {
        await FallibleSecureInputProvider {
            guard let handle = dlopen("/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/HIToolbox", RTLD_LAZY | RTLD_LOCAL) else { return nil }
            defer { dlclose(handle) }
            guard let symbol = dlsym(handle, "IsSecureEventInputEnabled") else { return nil }
            let query = unsafeBitCast(symbol, to: (@convention(c) () -> UInt8).self)
            return query() != 0
        }.secureInputState()
    }
}

public struct FallibleSecureInputProvider: SecureInputProvider {
    private let query: @Sendable () throws -> Bool?

    public init(query: @escaping @Sendable () throws -> Bool?) { self.query = query }

    public func secureInputState() async -> SecureInputState {
        do {
            guard let enabled = try query() else { return .unknown }
            return enabled ? .enabled : .disabled
        } catch { return .unknown }
    }
}

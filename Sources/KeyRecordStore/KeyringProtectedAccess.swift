import Foundation
import KeyRecordCore

/// Scoped migration capability: no actor reentry and no cached key bytes. Mutex protects only lifetime.
/// Callbacks are synchronous, bounded protected use; retaining material or launching async work is forbidden.
public final class KeyringProtectedAccess: @unchecked Sendable {
    private let mutex = NSRecursiveLock()
    private var active = true
    private let gate: any KeyAvailabilityFencing
    private let generation: CaptureGeneration
    private let backend: any KeychainBackend
    private let namespace: KeychainNamespace
    private let versions: Set<KeyVersion>

    init(gate: any KeyAvailabilityFencing, generation: CaptureGeneration, backend: any KeychainBackend,
         namespace: KeychainNamespace, versions: Set<KeyVersion>) {
        self.gate = gate; self.generation = generation; self.backend = backend
        self.namespace = namespace; self.versions = versions
    }

    public func check() throws {
        try mutex.withLock {
            guard active else { throw KeyringError.staleGeneration }
            try gate.check(generation)
        }
    }

    public func withMaterial<T: Sendable>(
        _ version: KeyVersion, body: @Sendable (Data) throws -> T
    ) async throws -> T {
        try check()
        guard versions.contains(version) else { throw KeyringError.missingKey(version) }
        for required in versions { _ = try await read(required) }
        let bytes = try await read(version)
        return try mutex.withLock {
            guard active else { throw KeyringError.staleGeneration }
            return try gate.use(generation) { try body(bytes) }
        }
    }

    func invalidate() { mutex.withLock { active = false } }

    private func read(_ version: KeyVersion) async throws -> Data {
        try check()
        let backend = backend, id = KeychainItemID.key(namespace, version)
        let bytes = try await gate.run(generation) { try await backend.read(id) }
        try check()
        guard let bytes else { throw KeyringError.missingKey(version) }
        guard bytes.count == 32 else { throw KeyringError.corruptKey(version) }
        return bytes
    }
}

extension KeychainKeyring {
    func access(_ generation: CaptureGeneration, versions: Set<KeyVersion>) -> KeyringProtectedAccess {
        KeyringProtectedAccess(gate: gate, generation: generation, backend: ports.backend,
                               namespace: configuration.namespace, versions: versions)
    }
}

import Foundation
import KeyRecordCore

public actor KeychainKeyring {
    let configuration: KeyringConfiguration
    let ports: KeyringPorts
    let gate: any KeyAvailabilityFencing
    let owner = UUID()
    private var busy = false

    public init(configuration: KeyringConfiguration, ports: KeyringPorts, gate: any KeyAvailabilityFencing) {
        self.configuration = configuration; self.ports = ports; self.gate = gate
    }

    public func bootstrap() async throws -> KeyringMetadata {
        try await serialized { ring, generation, _ in
            let state = try await ring.creationState(generation)
            guard state.store == .fresh else { throw KeyringError.creationDenied }
            let existing = try await ring.readMetadata(generation)
            let versions = try await ring.inventory(generation)
            guard existing == nil, versions.isEmpty else { throw KeyringError.creationDenied }
            let version = KeyVersion(rawValue: 1)
            try await ring.add(version, generation)
            let metadata = KeyringMetadata(current: version, versions: [version])
            try await ring.publish(metadata, expected: nil, generation)
            return metadata
        }
    }

    public func open() async throws -> KeyringRecoveryState {
        try await serialized { ring, generation, session in
            try await ring.load(generation, session).state
        }
    }

    public func handle(for version: KeyVersion) async throws -> KeyMaterialHandle {
        try await serialized { ring, generation, session in
            let loaded = try await ring.load(generation, session)
            guard loaded.state.metadata.versions.contains(version),
                  !loaded.state.metadata.retirementPending.contains(version) else { throw KeyringError.missingKey(version) }
            return KeyMaterialHandle(version: version, generation: generation, owner: ring.owner)
        }
    }

    /// Synchronous protected use only: do not retain material or spawn work from this callback.
    /// Async callers must keep the handle, not returned key bytes, and use a new fenced callback.
    public func withMaterial<T: Sendable>(
        _ handle: KeyMaterialHandle, body: @escaping @Sendable (Data) throws -> T
    ) async throws -> T {
        try gate.check(handle.generation)
        guard handle.owner == owner else { throw KeyringError.staleGeneration }
        return try await serialized { ring, generation, session in
            try ring.gate.check(handle.generation)
            let loaded = try await ring.load(generation, session)
            guard loaded.state.metadata.versions.contains(handle.version),
                  !loaded.state.metadata.retirementPending.contains(handle.version) else { throw KeyringError.missingKey(handle.version) }
            let bytes = try await ring.material(handle.version, generation)
            return try ring.gate.use(generation) { try body(bytes) }
        }
    }

    func serialized<T: Sendable>(
        _ operation: (isolated KeychainKeyring, CaptureGeneration, any ProtectedReferenceSession) async throws -> T
    ) async throws -> T {
        guard !busy else { throw KeyringError.busy }
        let generation = try gate.begin()
        busy = true
        defer { busy = false }
        _ = try await creationState(generation)
        // Acquisition grants no protected data. Always release a late lease, even across a lock fence.
        let session = try await ports.references.acquireExclusiveAccess()
        let result: T
        do {
            try gate.check(generation)
            try Task.checkCancellation()
            result = try await operation(self, generation, session)
        } catch {
            await session.release()
            try gate.check(generation)
            throw error
        }
        await session.release()
        try gate.check(generation)
        return result
    }

    func creationState(_ generation: CaptureGeneration) async throws -> KeyringCreationState {
        let creation = ports.creation
        let state = try await gate.run(generation) { try await creation.creationState() }
        guard state.consent, ports.clock.now() < state.validUntil else { throw KeyringError.creationDenied }
        return state
    }

    func readMetadata(_ generation: CaptureGeneration) async throws -> Data? {
        let backend = ports.backend, id = KeychainItemID.metadata(configuration.namespace)
        return try await gate.run(generation) { try await backend.read(id) }
    }

    func inventory(_ generation: CaptureGeneration) async throws -> Set<KeyVersion> {
        let backend = ports.backend, namespace = configuration.namespace
        let versions = try await gate.run(generation) { try await backend.versions(in: namespace) }
        guard !versions.contains(KeyVersion(rawValue: 0)) else { throw KeyringError.corruptMetadata }
        return versions
    }

    func material(_ version: KeyVersion, _ generation: CaptureGeneration) async throws -> Data {
        let backend = ports.backend, id = KeychainItemID.key(configuration.namespace, version)
        let bytes = try await gate.run(generation) { try await backend.read(id) }
        guard let bytes else { throw KeyringError.missingKey(version) }
        guard bytes.count == 32 else { throw KeyringError.corruptKey(version) }
        return bytes
    }

    func add(_ version: KeyVersion, _ generation: CaptureGeneration) async throws {
        let material = try gate.use(generation) { try ports.entropy.generate() }
        guard material.count == 32 else { throw KeyringError.entropyDenied }
        let backend = ports.backend
        let item = KeychainItem(id: .key(configuration.namespace, version), material: material, policy: configuration.accessibility)
        try await gate.run(generation) { try await backend.add(item) }
    }

    func publish(_ metadata: KeyringMetadata, expected: Data?, _ generation: CaptureGeneration) async throws {
        let backend = ports.backend
        let update = KeychainMetadataUpdate(id: .metadata(configuration.namespace), expected: expected,
                                           replacement: try metadata.encoded(), policy: configuration.accessibility)
        try await gate.run(generation) { try await backend.publish(update) }
    }

    func delete(_ version: KeyVersion, _ generation: CaptureGeneration) async throws {
        let backend = ports.backend, id = KeychainItemID.key(configuration.namespace, version)
        try await gate.run(generation) { try await backend.delete(id) }
    }
}

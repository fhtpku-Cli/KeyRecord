import Foundation
import KeyRecordCore

public protocol CiphertextCommitting: Sendable {
    func commit(name: String, bytes: Data, root: URL) async throws
}

public struct AtomicCiphertextCommitter: CiphertextCommitting {
    public init() {}
    public func commit(name: String, bytes: Data, root: URL) throws {
        try AtomicFileSystem().commitFile(name: name, in: root, bytes: bytes,
                                         phase: name == ManifestDiscovery.fileName ? .manifest : .data)
    }
}

public struct FencedObjectWriter: FlushWriting {
    private let store: ObjectStore
    private let gate: KeyAvailabilityGate
    private let committer: any CiphertextCommitting

    public init(store: ObjectStore, gate: KeyAvailabilityGate,
                committer: any CiphertextCommitting = AtomicCiphertextCommitter()) {
        self.store = store; self.gate = gate; self.committer = committer
    }

    public func write(_ objects: [FlushObject], generation: CaptureGeneration) async throws {
        try await store.persist(objects, protection: StoreProtection(gate: gate, generation: generation),
                                committer: committer)
    }
}

struct StoreProtection: Sendable {
    let gate: KeyAvailabilityGate
    let generation: CaptureGeneration
    func check() throws { try gate.check(generation); try Task.checkCancellation() }
}

extension ObjectStore {
    /// Protect all plaintext work on both sides of async key retrieval. Only sealed
    /// envelopes cross the I/O await; an already-issued rename may finish after lock.
    func persist(_ objects: [FlushObject], protection: StoreProtection,
                 committer: any CiphertextCommitting) async throws {
        try protection.check()
        let id = try beginLease()
        defer { endLease(id) }
        let snapshot = try opened()
        let version = snapshot.currentKeyVersion
        let bytes = try await keySource.material(for: KeyVersion(rawValue: version))
        try protection.check()
        let prepared = try protection.gate.use(protection.generation) {
            var manifest = snapshot
            var sealed: [SealedObject] = []
            for object in objects {
                let value = try LocatorCodec.seal(identity: object.identity, payload: object.payload,
                                                  keyVersion: version, material: bytes)
                try manifest.upsert(ManifestEntry(identity: object.identity, locator: value.locator,
                                                  keyVersion: version))
                sealed.append(value)
            }
            return (manifest, sealed, try EncryptedManifest.seal(manifest, material: bytes))
        }
        for object in prepared.1 {
            try protection.check()
            try await committer.commit(name: object.locator.fileName, bytes: object.envelope, root: root)
        }
        try protection.check()
        try await committer.commit(name: ManifestDiscovery.fileName, bytes: prepared.2, root: root)
        try protection.gate.use(protection.generation) { manifestBox = prepared.0 }
    }

    public func readProtected(_ identity: CanonicalLogicalIdentity,
                              gate: KeyAvailabilityGate) async throws -> Data {
        let generation = try gate.begin()
        let entry = try gate.use(generation) {
            guard let entry = try opened().entry(for: identity) else { throw ObjectStoreError.unknownObject }
            return entry
        }
        let ciphertext = try readEntryFile(entry)
        let material = try await keySource.material(for: KeyVersion(rawValue: entry.keyVersion))
        return try gate.use(generation) {
            try LocatorCodec.open(envelope: ciphertext, requested: identity,
                                  materialByVersion: [entry.keyVersion: material]).payload
        }
    }

    public func closeProtectedSession() {
        materialCache.removeAll()
        manifestBox = nil
        phase = nil
    }
}

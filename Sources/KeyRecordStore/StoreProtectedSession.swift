import Foundation
import KeyRecordCore

/// Per-call injection for rotation migration. Data relocation commits per object, then the
/// fixed manifest is re-encrypted, then old locator files are unlinked; every boundary can
/// kill the real process or throw in-process.
public struct MigrationInjection: Sendable {
    public var data: DurabilityInjection
    public var manifest: DurabilityInjection
    public var cleanup: DurabilityInjection

    public init(data: DurabilityInjection = .none,
                manifest: DurabilityInjection = .none,
                cleanup: DurabilityInjection = .none) {
        self.data = data; self.manifest = manifest; self.cleanup = cleanup
    }
    public static let none = MigrationInjection()
}

extension ObjectStore {
    func beginLease() throws -> UUID {
        guard lease == nil else { throw KeyringError.busy }
        let id = UUID()
        lease = id
        return id
    }

    func endLease(_ id: UUID) {
        if lease == id { lease = nil }
    }

    private func requireLease(_ id: UUID) throws {
        guard lease == id, phase == .opened else { throw KeyringError.busy }
    }

    /// Relocate every still-old-version entry: new object -> manifest commit -> old delete.
    /// Key material is consumed strictly through task 11's fenced protected-access port.
    func migrateObjects(
        lease id: UUID,
        rotation: KeyRotation,
        access: KeyringProtectedAccess,
        injection provided: MigrationInjection? = nil
    ) async throws {
        try requireLease(id)
        let injection = provided ?? configuredMigrationInjection
        let snapshot = try opened()
        for entry in snapshot.entries where entry.keyVersion == rotation.from.rawValue {
            let bytes = try readEntryFile(entry)
            let payload = try await access.withMaterial(rotation.from) { oldMaterial -> Data in
                let opened = try LocatorCodec.open(
                    envelope: bytes, requested: entry.identity,
                    materialByVersion: [rotation.from.rawValue: oldMaterial])
                return opened.payload
            }
            let sealed = try await access.withMaterial(rotation.to) { newMaterial -> SealedObject in
                try LocatorCodec.seal(identity: entry.identity, payload: payload,
                                      keyVersion: rotation.to.rawValue, material: newMaterial)
            }
            try fileSystem.commitFile(name: sealed.locator.fileName, in: root,
                                      bytes: sealed.envelope,                                       phase: .data, injection: injection.data)
            let relocated = ManifestEntry(identity: entry.identity, locator: sealed.locator,
                                          keyVersion: rotation.to.rawValue)
            var nextManifest = try opened()
            try nextManifest.upsert(relocated)
            let manifestPayload = try nextManifest.payloadData()
            let manifestEnvelope = try await access.withMaterial(rotation.from) { oldMaterial -> Data in
                try LocatorCodec.seal(identity: CanonicalLogicalIdentity.manifest,
                                      payload: manifestPayload,
                                      keyVersion: rotation.from.rawValue,
                                      material: oldMaterial).envelope
            }
            try fileSystem.commitFile(name: ManifestDiscovery.fileName, in: root,
                                      bytes: manifestEnvelope, phase: .data,
                                      injection: injection.data)
            manifestBox = nextManifest
            try fileSystem.removeFile(name: entry.locator.fileName, in: root,
                                      injection: injection.cleanup)
        }
    }

    /// Re-seal the fixed manifest under the new key and delegate journal re-encryption to
    /// the task-16 journal seam.
    func reencryptFixedManifest(
        lease id: UUID,
        rotation: KeyRotation,
        access: KeyringProtectedAccess,
        injection provided: DurabilityInjection? = nil
    ) async throws {
        try requireLease(id)
        let injection = provided ?? configuredMigrationInjection.manifest
        let snapshot = try opened()
        guard snapshot.currentKeyVersion == rotation.from.rawValue else { return }
        var nextManifest = snapshot
        try nextManifest.setCurrentKeyVersion(rotation.to.rawValue)
        let manifestPayload = try nextManifest.payloadData()
        let manifestEnvelope = try await access.withMaterial(rotation.to) { newMaterial -> Data in
            try LocatorCodec.seal(identity: CanonicalLogicalIdentity.manifest,
                                  payload: manifestPayload,
                                  keyVersion: rotation.to.rawValue,
                                  material: newMaterial).envelope
        }
        try fileSystem.commitFile(name: ManifestDiscovery.fileName, in: root,
                                  bytes: manifestEnvelope, phase: .manifest, injection: injection)
        manifestBox = nextManifest
        try await journalSource.reencryptJournals(rotation: rotation, access: access)
    }

    /// Reconcile owned artifacts after interruption. Only authenticated proven-owned
    /// orphans/temps are removed; unresolved names stay protected and block retirement.
    func reconcileAfterRecovery(lease id: UUID, access: KeyringProtectedAccess) async throws {
        try requireLease(id)
        let versions = try await keySource.namespaceKeyVersions()
        let classified = try fileSystem.listEntries(in: root).map { entry -> (RootEntry, RootEntryClassification) in
            (entry, RootEntryClassifier.classify(entry))
        }
        let nonManifest = classified.filter {
            if case .manifest = $0.1 { return false } else { return true }
        }
        let journalLocators = try await pendingJournalLocators(known: versions)
        try await reconcileUnreferenced(nonManifest,
                                        referenced: try opened().locators.union(journalLocators), known: versions)
    }

    /// Complete protected-reference scan. Every referenced artifact is authenticated.
    /// Coverage includes all five kinds (empty journal sets are still complete coverage);
    /// any unreadable reference makes required versions unknowable and blocks retirement.
    func protectedScan(lease id: UUID, access: KeyringProtectedAccess) async throws
        -> ProtectedReferenceSnapshot {
        try requireLease(id)
        let manifest = try opened()
        var references: [ProtectedReference] = []
        let manifestBytes = try fileSystem.readWholeFile(name: ManifestDiscovery.fileName, in: root)
        let materials = try await materialMap(for: Set(manifest.entries.map(\.keyVersion))
                                              .union([manifest.currentKeyVersion]))
        if (try? EncryptedManifest.open(envelope: manifestBytes, materialByVersion: materials)) != nil {
            references.append(.known(.fixedManifest, KeyVersion(rawValue: manifest.currentKeyVersion)))
        } else {
            references.append(.unreadable(.fixedManifest))
        }
        for entry in manifest.entries {
            if try provesLiveEntry(entry, materials: materials) {
                references.append(.known(.liveManifestEntry, KeyVersion(rawValue: entry.keyVersion)))
            } else {
                references.append(.unreadable(.liveManifestEntry))
            }
        }
        for name in unresolvedArtifacts {
            if let version = try? authenticatableVersion(name: name, materials: materials) {
                references.append(.known(.ownedTemporaryOrOrphan, version))
            } else {
                references.append(.unreadable(.ownedTemporaryOrOrphan))
            }
        }
        do {
            references.append(contentsOf: try await journalSource.journalProtectedReferences(access: access))
        } catch {
            references.append(.unreadable(.unfinishedJournal))
            references.append(.unreadable(.journalRecoveryObject))
        }
        return ProtectedReferenceSnapshot(coverage: Set(ProtectedReferenceKind.allCases),
                                          references: references)
    }

    private func provesLiveEntry(_ entry: ManifestEntry, materials: [UInt32: Data]) throws -> Bool {
        guard let bytes = try? fileSystem.readWholeFile(name: entry.locator.fileName, in: root),
              let material = materials[entry.keyVersion]
        else { return false }
        do {
            let opened = try LocatorCodec.open(envelope: bytes, requested: entry.identity,
                                               materialByVersion: [entry.keyVersion: material])
            return opened.keyVersion == entry.keyVersion
        } catch { return false }
    }

    private func authenticatableVersion(name: String, materials: [UInt32: Data]) throws -> KeyVersion? {
        guard let bytes = try? fileSystem.readWholeFile(name: name, in: root),
              let parsed = try? AuthenticatedStorageEnvelope.parse(bytes),
              materials[parsed.header.keyVersion] != nil,
              (try? LocatorCodec.authenticate(envelope: bytes, materialByVersion: materials)) != nil
        else { return nil }
        return KeyVersion(rawValue: parsed.header.keyVersion)
    }

    private func materialMap(for versions: Set<UInt32>) async throws -> [UInt32: Data] {
        var result = [UInt32: Data]()
        for raw in versions { result[raw] = try await material(raw, versions: nil) }
        return result
    }
}

extension ObjectStore: ProtectedReferenceProviding {
    public func acquireExclusiveAccess() async throws -> any ProtectedReferenceSession {
        StoreSession(store: self, lease: try beginLease())
    }
}

private final class StoreSession: ProtectedReferenceSession, @unchecked Sendable {
    private let store: ObjectStore
    private let lease: UUID
    private var released = false

    init(store: ObjectStore, lease: UUID) {
        self.store = store; self.lease = lease
    }

    func migrateData(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        try await store.migrateObjects(lease: lease, rotation: rotation, access: access)
    }

    func reencryptManifestAndJournals(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        try await store.reencryptFixedManifest(lease: lease, rotation: rotation, access: access)
    }

    func recoverAndReconcile(access: KeyringProtectedAccess) async throws {
        try await store.reconcileAfterRecovery(lease: lease, access: access)
    }

    func scan(access: KeyringProtectedAccess) async throws -> ProtectedReferenceSnapshot {
        try await store.protectedScan(lease: lease, access: access)
    }

    func release() async {
        guard !released else { return }
        released = true
        await store.endLease(lease)
    }
}

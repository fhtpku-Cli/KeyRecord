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
        sessionToken: UUID,
        injection provided: MigrationInjection? = nil
    ) async throws {
        try requireLease(id)
        try requireProtectedSession(sessionToken)
        try access.check()
        let injection = provided ?? configuredMigrationInjection
        let snapshot = try opened()
        for entry in snapshot.entries where entry.keyVersion == rotation.from.rawValue {
            try requireProtectedSession(sessionToken)
            try access.check()
            let bytes = try readEntryFile(entry)
            let payload = try await access.withMaterial(rotation.from) { oldMaterial -> Data in
                let opened = try LocatorCodec.open(
                    envelope: bytes, requested: entry.identity,
                    materialByVersion: [rotation.from.rawValue: oldMaterial])
                return opened.payload
            }
            try requireProtectedSession(sessionToken)
            let sealed = try await access.withMaterial(rotation.to) { newMaterial -> SealedObject in
                try LocatorCodec.seal(identity: entry.identity, payload: payload,
                                      keyVersion: rotation.to.rawValue, material: newMaterial)
            }
            try requireProtectedSession(sessionToken)
            try access.check()
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
            try requireProtectedSession(sessionToken)
            try access.check()
            try fileSystem.commitFile(name: ManifestDiscovery.fileName, in: root,
                                      bytes: manifestEnvelope, phase: .data,
                                      injection: injection.data)
            manifestBox = nextManifest
            try access.check()
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
        sessionToken: UUID,
        injection provided: DurabilityInjection? = nil
    ) async throws {
        try requireLease(id)
        try requireProtectedSession(sessionToken)
        try access.check()
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
        try requireProtectedSession(sessionToken)
        try access.check()
        try fileSystem.commitFile(name: ManifestDiscovery.fileName, in: root,
                                  bytes: manifestEnvelope, phase: .manifest, injection: injection)
        manifestBox = nextManifest
        try access.check()
        try await journalSource.reencryptJournals(rotation: rotation, access: access)
        try requireProtectedSession(sessionToken)
        try access.check()
    }

    /// Reconcile owned artifacts after interruption. Only authenticated proven-owned
    /// orphans/temps are removed; unresolved names stay protected and block retirement.
    func reconcileAfterRecovery(lease id: UUID, access: KeyringProtectedAccess,
                                sessionToken: UUID) async throws {
        try requireLease(id)
        try requireProtectedSession(sessionToken)
        try access.check()
        let versions = try await keySource.namespaceKeyVersions()
        try requireProtectedSession(sessionToken)
        try access.check()
        let classified = try fileSystem.listEntries(in: root).map { entry -> (RootEntry, RootEntryClassification) in
            (entry, RootEntryClassifier.classify(entry))
        }
        let nonManifest = classified.filter {
            if case .manifest = $0.1 { return false } else { return true }
        }
        let journalLocators = try await pendingJournalLocators(known: versions)
        try requireProtectedSession(sessionToken)
        try access.check()
        try await reconcileUnreferenced(nonManifest,
                                        referenced: try opened().locators.union(journalLocators), known: versions,
                                        sessionToken: sessionToken)
        try requireProtectedSession(sessionToken)
        try access.check()
    }

    /// Complete protected-reference scan. Every referenced artifact is authenticated.
    /// Coverage includes all five kinds (empty journal sets are still complete coverage);
    /// any unreadable reference makes required versions unknowable and blocks retirement.
    func protectedScan(lease id: UUID, access: KeyringProtectedAccess,
                       sessionToken: UUID) async throws
        -> ProtectedReferenceSnapshot {
        try requireLease(id)
        try requireProtectedSession(sessionToken)
        try access.check()
        let manifest = try opened()
        var references: [ProtectedReference] = []
        let manifestBytes = try fileSystem.readWholeFile(name: ManifestDiscovery.fileName, in: root)
        let materials = try await materialMap(for: Set(manifest.entries.map(\.keyVersion))
                                              .union([manifest.currentKeyVersion]), sessionToken: sessionToken)
        try requireProtectedSession(sessionToken)
        try access.check()
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
            try requireProtectedSession(sessionToken)
            try access.check()
        } catch {
            try requireProtectedSession(sessionToken)
            try access.check()
            references.append(.unreadable(.unfinishedJournal))
            references.append(.unreadable(.journalRecoveryObject))
        }
        try requireProtectedSession(sessionToken)
        try access.check()
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

    private func materialMap(for versions: Set<UInt32>, sessionToken: UUID) async throws -> [UInt32: Data] {
        var result = [UInt32: Data]()
        for raw in versions {
            try requireProtectedSession(sessionToken)
            result[raw] = try await material(raw, versions: nil)
            try requireProtectedSession(sessionToken)
        }
        return result
    }
}

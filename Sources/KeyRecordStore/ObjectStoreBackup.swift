import Foundation
import KeyRecordCore

extension ObjectStore {
    /// Actor isolation gives one consistent manifest without an await between objects.
    /// Callers flush and pause capture before taking this snapshot.
    public func backupSnapshot(gate: KeyAvailabilityGate) throws -> [BackupObject] {
        let generation = try gate.begin()
        guard lease == nil else { throw KeyringError.busy }
        let manifest = try opened()
        try requireBackupReady()
        guard manifest.entries.count <= PasswordBackup.maximumObjects else { throw PasswordBackupError.limitExceeded }
        var total = 0
        return try manifest.entries.map { entry in
            try gate.use(generation) {
                try Task.checkCancellation()
                guard let material = cachedMaterial(entry.keyVersion) else { throw KeyringError.locked }
                let object = try LocatorCodec.open(envelope: readEntryFile(entry), requested: entry.identity,
                                                   materialByVersion: [entry.keyVersion: material])
                total += object.payload.count + entry.identity.canonicalBytes.count + 8
                guard total <= PasswordBackup.maximumArchiveBytes else { throw PasswordBackupError.limitExceeded }
                return BackupObject(identity: entry.identity, payload: object.payload)
            }
        }
    }

    /// Restore into an empty installation only. All data files precede one atomic
    /// manifest publication; interruption exposes either zero or all restored objects.
    /// Existing installations must use the existing explicit deletion/review flow first.
    public func restoreBackup(_ objects: [BackupObject], gate: KeyAvailabilityGate,
                              injection: DurabilityInjection = .none) throws {
        let generation = try gate.begin()
        let leaseID = try beginLease()
        defer { endLease(leaseID) }
        let old = try opened()
        guard old.entries.isEmpty else { throw PasswordBackupError.destinationNotEmpty }
        try requireBackupReady()
        let prepared = try gate.use(generation) {
            _ = try PasswordBackup.encode(objects)
            guard let material = cachedMaterial(old.currentKeyVersion) else { throw KeyringError.locked }
            let sealed = try objects.map {
                try LocatorCodec.seal(identity: $0.identity, payload: $0.payload,
                                      keyVersion: old.currentKeyVersion, material: material)
            }
            let manifest = try EncryptedManifest(currentKeyVersion: old.currentKeyVersion, entries: zip(objects, sealed).map {
                ManifestEntry(identity: $0.0.identity, locator: $0.1.locator, keyVersion: old.currentKeyVersion)
            })
            return (sealed, manifest, try EncryptedManifest.seal(manifest, material: material))
        }
        do {
            for object in prepared.0 {
                try gate.check(generation); try Task.checkCancellation()
                try fileSystem.commitFile(name: object.locator.fileName, in: root, bytes: object.envelope,
                                          phase: .data, injection: injection)
            }
            try gate.check(generation); try Task.checkCancellation()
            try fileSystem.commitFile(name: ManifestDiscovery.fileName, in: root, bytes: prepared.2,
                                      phase: .manifest, injection: injection)
            manifestBox = prepared.1
        } catch {
            // A rename may already be durable. Reopen the on-disk manifest before any
            // retry, so a late I/O failure cannot authorize overwriting a restored store.
            closeProtectedSession()
            throw error
        }
    }

    private func requireBackupReady() throws {
        guard unresolvedArtifacts.isEmpty,
              try cycleJournals.load(knownVersions: Set(materialCache.keys), materials: materialCache).isEmpty
        else { throw PasswordBackupError.maintenancePending }
    }
}

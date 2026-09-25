import CryptoKit
import Foundation
import KeyRecordCore

enum ResetObjectHash {
    static func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
}

extension ObjectStore {
    /// True when a reset journal is still on disk, or when that fact cannot be read.
    /// Callers must not start a new collecting session over an unfinished reset.
    public func hasUnfinishedCycleReset() async -> Bool {
        do {
            let versions = try await keySource.namespaceKeyVersions()
            let locators = try await pendingJournalLocators(known: versions)
            return !locators.isEmpty
        } catch {
            return true
        }
    }

    func pendingJournalLocators(known versions: Set<KeyVersion>) async throws -> Set<ObjectLocator> {
        try await journalSource.pendingJournalLocators(knownVersions: versions) { [keySource] version in
            try await keySource.material(for: version)
        }
    }

    func collectShards(cycleID: CycleID) throws -> (shortcuts: [DailyShortcutAggregate],
                                                    bareKeys: [DailyBareKeyAggregate]) {
        var shortcuts: [DailyShortcutAggregate] = []
        var bareKeys: [DailyBareKeyAggregate] = []
        for entry in try opened().entries where entry.identity.objectType == CanonicalLogicalIdentity.shardObjectType {
            let triple = try entry.identity.shardComponents()
            guard triple.cycleID == cycleID.rawValue else { throw ObjectStoreError.reset(.shardCycleMismatch) }
            switch ResetShardAggregate(rawValue: triple.aggregateType) {
            case .shortcut:
                let rows = try decodeStrict([DailyShortcutAggregate].self, openPayload(entry))
                guard rows.allSatisfy({ $0.cycleID == cycleID }) else {
                    throw ObjectStoreError.reset(.shardCycleMismatch)
                }
                shortcuts.append(contentsOf: rows)
            case .bareKey:
                let rows = try decodeStrict([DailyBareKeyAggregate].self, openPayload(entry))
                guard rows.allSatisfy({ $0.cycleID == cycleID }) else {
                    throw ObjectStoreError.reset(.shardCycleMismatch)
                }
                bareKeys.append(contentsOf: rows)
            case nil:
                throw ObjectStoreError.reset(.unrecognizedShard)
            }
        }
        return (shortcuts, bareKeys)
    }

    func retainedHashes(excluding oldCycle: CycleID) throws -> [RetainedObjectHash] {
        let summaryIdentity = CycleResetObjects.summary(oldCycle)
        var hashes: [RetainedObjectHash] = []
        for entry in try opened().entries {
            if entry.identity.objectType == CanonicalLogicalIdentity.shardObjectType { continue }
            if entry.identity == CycleResetObjects.preferences
                || entry.identity == CycleResetObjects.currentCycle
                || entry.identity == summaryIdentity { continue }
            hashes.append(RetainedObjectHash(identity: entry.identity.canonicalBytes.hex,
                                             sha256: ResetObjectHash.digest(try openPayload(entry)).hex))
        }
        return hashes.sorted { $0.identity < $1.identity }
    }

    func verifyRetained(_ journal: ResetJournalPayload) throws {
        guard try retainedHashes(excluding: journal.oldCycleID) == journal.retainedHashes else {
            throw ObjectStoreError.reset(.retainedObjectsChanged)
        }
    }

    func removePresent(_ identity: CanonicalLogicalIdentity, injection: DurabilityInjection) async throws {
        guard let entry = try opened().entry(for: identity) else { return }
        let version = try opened().currentKeyVersion
        let keyMaterial = try await material(version, versions: nil)
        try commit({ $0.remove(identity) }, encryptionVersion: version,
                   material: { keyMaterial }, injection: injection)
        do {
            try fileSystem.removeFile(name: entry.locator.fileName, in: root, injection: injection)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
    }

    func persistJournal(_ payload: ResetJournalPayload, materials: [UInt32: Data],
                        injection: CycleResetInjection) throws {
        let version = try opened().currentKeyVersion
        guard let material = materials[version] else { throw ObjectStoreError.corruption(.envelopeKeyMissing) }
        do {
            try cycleJournals.write(payload, keyVersion: version, material: material,
                                    injection: injection.journalWrite)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
    }

    func currentCycleRecord() throws -> CycleRecord {
        guard let entry = try opened().entry(for: CycleResetObjects.currentCycle) else {
            throw ObjectStoreError.reset(.missingCurrentCycle)
        }
        return try decodeStrict(CycleRecord.self, openPayload(entry))
    }

    func requireObject<T: Decodable>(_ type: T.Type, identity: CanonicalLogicalIdentity,
                                     failure: CycleResetError) throws -> T {
        guard let entry = try opened().entry(for: identity) else {
            throw ObjectStoreError.reset(failure)
        }
        do { return try decodeStrict(T.self, openPayload(entry)) }
        catch { throw ObjectStoreError.reset(failure) }
    }

    func openPayload(_ entry: ManifestEntry) throws -> Data {
        guard let material = materialCache[entry.keyVersion] else {
            throw ObjectStoreError.corruption(.envelopeKeyMissing)
        }
        let bytes = try readEntryFile(entry)
        do {
            return try LocatorCodec.open(envelope: bytes, requested: entry.identity,
                                         materialByVersion: [entry.keyVersion: material]).payload
        } catch let error as StorageEnvelopeError {
            throw ObjectStoreError.envelope(error)
        } catch let error as LocatorCodecError {
            throw ObjectStoreError.locator(error)
        }
    }

    func decodeStrict<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    func crashReset(_ point: ResetKillPoint?, _ expected: ResetKillPoint) {
        guard point == expected else { return }
        kill(getpid(), SIGKILL)
        Thread.sleep(forTimeInterval: 30)
    }
}

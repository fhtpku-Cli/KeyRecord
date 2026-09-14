import Foundation
import KeyRecordCore

struct LoadedResetJournal: Equatable {
    let version: UInt32
    let locator: ObjectLocator
    let payload: ResetJournalPayload
    let rawPayload: Data
}

/// Encrypted reset journals live beside manifest entries as flat locator-named envelopes,
/// never inside the manifest. Discovery is deterministic: for a known key version the file
/// name MUST equal `HMAC(locatorKey(material), journalIdentity)`, so no pointer is needed
/// and a tampered journal still occupies its expected name (fail closed, never orphaned).
final class CycleResetJournalStore: StoreJournalRecoverySource, @unchecked Sendable {
    private let root: URL
    private let fileSystem = AtomicFileSystem()
    private let lock = NSLock()
    private var provenNames: [String: UInt32] = [:]

    init(root: URL) { self.root = root }

    func expectedLocator(version: UInt32, material: Data) throws -> ObjectLocator {
        try ObjectLocator(StorageKeySchedule.locator(material: material,
                                                     objectID: CycleResetObjects.journal.canonicalBytes))
    }

    @discardableResult
    func write(_ payload: ResetJournalPayload, keyVersion: UInt32, material: Data,
               injection: DurabilityInjection = .none) throws -> ObjectLocator {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sealed = try LocatorCodec.seal(identity: CycleResetObjects.journal,
                                          payload: try encoder.encode(payload),
                                          keyVersion: keyVersion, material: material)
        try fileSystem.commitFile(name: sealed.locator.fileName, in: root, bytes: sealed.envelope,
                                  phase: .data, injection: injection)
        remember(name: sealed.locator.fileName, version: keyVersion)
        return sealed.locator
    }

    func clearAll(knownVersions versions: Set<UInt32>, materials: [UInt32: Data],
                  injection: DurabilityInjection = .none) throws {
        var names = Set(snapshotProven().keys)
        for (version, material) in materials where versions.contains(version) {
            if let locator = try? expectedLocator(version: version, material: material) {
                names.insert(locator.fileName)
            }
        }
        for name in names.sorted() {
            try fileSystem.removeFile(name: name, in: root, injection: injection)
            forget(name: name)
        }
    }

    func load(knownVersions versions: Set<UInt32>, materials: [UInt32: Data]) throws -> [LoadedResetJournal] {
        let onDisk = Set(try fileSystem.listEntries(in: root).map(\.name))
        var loaded: [LoadedResetJournal] = []
        for version in versions.sorted() {
            guard let material = materials[version],
                  let locator = try? expectedLocator(version: version, material: material),
                  onDisk.contains(locator.fileName)
            else { continue }
            let bytes = try fileSystem.readWholeFile(name: locator.fileName, in: root)
            let opened = try authenticate(envelope: bytes, version: version, material: material)
            loaded.append(LoadedResetJournal(version: version, locator: locator,
                                             payload: opened.payload, rawPayload: opened.rawPayload))
        }
        let discovered = Set(loaded.map(\.locator.fileName))
        for name in snapshotProven().keys where !discovered.contains(name) && onDisk.contains(name) {
            throw ObjectStoreError.corruption(.resetJournalUnreadable)
        }
        for name in snapshotProven().keys where !onDisk.contains(name) { forget(name: name) }
        return loaded.sorted {
            if $0.payload.phase.rank != $1.payload.phase.rank {
                return $0.payload.phase.rank < $1.payload.phase.rank
            }
            return $0.version < $1.version
        }
    }

    func pendingJournalLocators(
        knownVersions: Set<KeyVersion>,
        material: @Sendable (KeyVersion) async throws -> Data
    ) async throws -> Set<ObjectLocator> {
        let onDisk = Set(try fileSystem.listEntries(in: root).map(\.name))
        var result = Set<ObjectLocator>()
        for version in knownVersions.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let bytes = try? await material(version) else { continue }
            guard let locator = try? expectedLocator(version: version.rawValue, material: bytes),
                  onDisk.contains(locator.fileName)
            else { continue }
            remember(name: locator.fileName, version: version.rawValue)
            result.insert(locator)
        }
        return result
    }

    func reencryptJournals(rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        let candidates = try await journalCandidates(access: access)
        let groups = Dictionary(grouping: candidates.compactMap(\.loaded)) { $0.payload.operationID }
        for copies in groups.values {
            guard let chosen = copies.max(by: Self.prefer) else { continue }
            let sealed = try await access.withMaterial(rotation.to) { material in
                try LocatorCodec.seal(identity: CycleResetObjects.journal, payload: chosen.rawPayload,
                                      keyVersion: rotation.to.rawValue, material: material)
            }
            try fileSystem.commitFile(name: sealed.locator.fileName, in: root, bytes: sealed.envelope,
                                      phase: .data)
            remember(name: sealed.locator.fileName, version: rotation.to.rawValue)
            for copy in copies where copy.locator.fileName != sealed.locator.fileName {
                try fileSystem.removeFile(name: copy.locator.fileName, in: root)
                forget(name: copy.locator.fileName)
            }
        }
    }

    func journalProtectedReferences(access: KeyringProtectedAccess) async throws -> [ProtectedReference] {
        let candidates = try await journalCandidates(access: access)
        let accessible = candidates.compactMap(\.loaded)
        let inaccessible = candidates.filter(\.isInaccessible)
        var references: [ProtectedReference] = []
        let groups = Dictionary(grouping: accessible) { $0.payload.operationID }
        for copies in groups.values {
            guard let chosen = copies.max(by: Self.prefer) else { continue }
            references.append(.known(.unfinishedJournal, KeyVersion(rawValue: chosen.version)))
            for copy in copies where copy.locator != chosen.locator {
                references.append(.known(.journalRecoveryObject, KeyVersion(rawValue: copy.version)))
            }
        }
        if groups.isEmpty {
            for (index, candidate) in inaccessible.enumerated() {
                references.append(.unreadable(index == 0 ? .unfinishedJournal : .journalRecoveryObject))
                remember(name: candidate.name, version: candidate.headerVersion)
            }
        } else {
            for candidate in inaccessible {
                references.append(.unreadable(.journalRecoveryObject))
                remember(name: candidate.name, version: candidate.headerVersion)
            }
        }
        return references
    }

    private struct Candidate {
        let name: String
        let headerVersion: UInt32
        let loaded: LoadedResetJournal?
        var isInaccessible: Bool { loaded == nil }
    }

    private func journalCandidates(access: KeyringProtectedAccess) async throws -> [Candidate] {
        let proven = snapshotProven()
        var candidates: [Candidate] = []
        for entry in try fileSystem.listEntries(in: root) where RootEntryClassifier.classify(entry) != .foreign {
            let name = entry.name
            let bytes: Data
            do { bytes = try fileSystem.readWholeFile(name: name, in: root) } catch { continue }
            guard let parsed = try? AuthenticatedStorageEnvelope.parse(bytes) else {
                if proven[name] != nil { candidates.append(Candidate(name: name, headerVersion: 0, loaded: nil)) }
                continue
            }
            let version = KeyVersion(rawValue: parsed.header.keyVersion)
            do {
                let loaded = try await access.withMaterial(version) { material -> LoadedResetJournal? in
                    guard name == (try expectedLocator(version: version.rawValue, material: material)).fileName
                    else { return nil }
                    let opened = try authenticate(envelope: bytes, version: version.rawValue, material: material)
                    return LoadedResetJournal(version: version.rawValue,
                                              locator: try expectedLocator(version: version.rawValue, material: material),
                                              payload: opened.payload, rawPayload: opened.rawPayload)
                }
                if let loaded {
                    remember(name: name, version: version.rawValue)
                    candidates.append(Candidate(name: name, headerVersion: version.rawValue, loaded: loaded))
                } else if proven[name] != nil {
                    candidates.append(Candidate(name: name, headerVersion: version.rawValue, loaded: nil))
                }
            } catch KeyringError.missingKey {
                if proven[name] != nil {
                    candidates.append(Candidate(name: name, headerVersion: version.rawValue, loaded: nil))
                }
            }
        }
        return candidates
    }

    private func authenticate(envelope bytes: Data, version: UInt32, material: Data)
        throws -> (payload: ResetJournalPayload, rawPayload: Data) {
        let opened: OpenedObject
        do {
            opened = try LocatorCodec.open(envelope: bytes, requested: CycleResetObjects.journal,
                                           materialByVersion: [version: material])
        } catch {
            throw ObjectStoreError.corruption(.resetJournalUnreadable)
        }
        do {
            return (try JSONDecoder().decode(ResetJournalPayload.self, from: opened.payload), opened.payload)
        } catch {
            throw ObjectStoreError.corruption(.resetJournalUnreadable)
        }
    }

    private static func prefer(_ lhs: LoadedResetJournal, _ rhs: LoadedResetJournal) -> Bool {
        if lhs.payload.phase.rank != rhs.payload.phase.rank {
            return lhs.payload.phase.rank < rhs.payload.phase.rank
        }
        return lhs.version < rhs.version
    }

    private func remember(name: String, version: UInt32) {
        lock.withLock { provenNames[name] = version }
    }

    private func forget(name: String) {
        lock.withLock { provenNames[name] = nil }
    }

    private func snapshotProven() -> [String: UInt32] {
        lock.withLock { provenNames }
    }
}

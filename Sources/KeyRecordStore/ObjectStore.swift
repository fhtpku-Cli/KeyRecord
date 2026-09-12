import Foundation
import KeyRecordCore

/// Single-writer encrypted object store. All state transitions are actor-isolated; the
/// durable order is data file -> directory sync -> manifest commit, with old-locator
/// deletion only after the manifest that stops referencing it is durable.
public actor ObjectStore {
    let root: URL
    let fileSystem = AtomicFileSystem()
    let keySource: any ObjectStoreKeySource
    let journalSource: any StoreJournalRecoverySource
    let configuredMigrationInjection: MigrationInjection

    var phase: StoreBootstrapState?
    var manifestBox: EncryptedManifest?
    var materialCache: [UInt32: Data] = [UInt32: Data]()
    var unresolvedArtifacts: [String] = []
    private var nonces = NonceReuseDetector()
    var lease: UUID?

    public init(root: URL, keySource: any ObjectStoreKeySource,
                journalSource: any StoreJournalRecoverySource = EmptyJournalRecoverySource(),
                migrationInjection: MigrationInjection = .none) {
        self.root = root
        self.keySource = keySource
        self.journalSource = journalSource
        self.configuredMigrationInjection = migrationInjection
    }

    public func bootstrapState() -> StoreBootstrapState? { phase }

    public func bootstrap() async throws -> StoreBootstrapState {
        if let phase { return phase }
        let versions = try await keySource.namespaceKeyVersions()
        let existed = fileSystem.rootExists(root)
        do {
            try fileSystem.preparePrivateRoot(at: root)
        } catch FileSystemError.rootSymlink {
            throw ObjectStoreError.corruption(.rootReplacedBySymlink)
        } catch FileSystemError.rootNotDirectory {
            throw ObjectStoreError.corruption(.rootNotDirectory)
        } catch {
            throw ObjectStoreError.corruption(.insecureRoot)
        }
        do {
            let entries = try fileSystem.listEntries(in: root)
            let classified = try entries.map { entry -> (RootEntry, RootEntryClassification) in
                let kind = RootEntryClassifier.classify(entry)
                switch kind {
                case .foreign:
                    throw entry.kind == .symlink
                        ? ObjectStoreError.corruption(.symlinkEncountered)
                        : ObjectStoreError.corruption(.unexpectedEntry)
                default:
                    return (entry, kind)
                }
            }
            guard classified.contains(where: { if case .manifest = $0.1 { return true } else { return false } }) else {
                let hasUncommittedEntry = classified.contains {
                    if case .manifest = $0.1 { return false } else { return true }
                }
                if hasUncommittedEntry { throw ObjectStoreError.corruption(.manifestMissing) }
                if !versions.isEmpty { throw ObjectStoreError.corruption(.unindexedDataWithNamespaceKey) }
                phase = .freshInstall
                return .freshInstall
            }
            let manifest = try await recoverManifest(requiredVersions: versions)
            try await loadMaterial(Set([manifest.encryptionKeyVersion]
                + manifest.manifest.entries.map(\.keyVersion)), known: versions)
            try validateReferencedFiles(manifest.manifest)
            try await reconcileUnreferenced(classified.filter {
                if case .manifest = $0.1 { return false } else { return true }
            }, referenced: manifest.manifest.locators, known: versions)
            manifestBox = manifest.manifest
            phase = .opened
            return .opened
        } catch let error as ObjectStoreError {
            if !existed { try? FileManager.default.removeItem(at: root) }
            throw error
        }
    }

    public func initializeFreshInstallation(version: KeyVersion = KeyVersion(rawValue: 1)) async throws {
        guard phase == .some(.freshInstall), manifestBox == nil else {
            throw phase == nil ? ObjectStoreError.storeNotInitialized : ObjectStoreError.alreadyInitialized
        }
        let manifest = try EncryptedManifest(currentKeyVersion: version.rawValue)
        let material = try await material(version.rawValue, versions: nil)
        let envelope = try EncryptedManifest.seal(manifest, material: material)
        try fileSystem.commitFile(name: ManifestDiscovery.fileName, in: root, bytes: envelope,
                                  phase: .manifest)
        manifestBox = manifest
        phase = .opened
    }

    public func currentKeyVersion() throws -> KeyVersion {
        guard let manifestBox, phase == .opened else { throw ObjectStoreError.storeNotInitialized }
        return KeyVersion(rawValue: manifestBox.currentKeyVersion)
    }

    public func put(identity: CanonicalLogicalIdentity, payload: Data,
                    injection: DurabilityInjection = .none) async throws -> ManifestEntry {
        let manifest = try opened()
        let version = manifest.currentKeyVersion
        let material = try await material(version, versions: nil)
        let sealed: SealedObject
        do {
            sealed = try LocatorCodec.seal(identity: identity, payload: payload,
                                           keyVersion: version, material: material)
        } catch let error as StorageEnvelopeError {
            throw ObjectStoreError.envelope(error)
        } catch let error as LocatorCodecError {
            throw ObjectStoreError.locator(error)
        }
        try nonces.record(sealed.envelope[44..<56], keyVersion: version)
        let previous = manifest.entry(for: identity)
        do {
            try fileSystem.commitFile(name: sealed.locator.fileName, in: root, bytes: sealed.envelope,
                                      phase: .data, injection: injection)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
        let entry = ManifestEntry(identity: identity, locator: sealed.locator, keyVersion: version)
        try commit({ try $0.upsert(entry) }, material: { material }, injection: injection)
        if let previous, previous.locator != sealed.locator {
            do {
                try fileSystem.removeFile(name: previous.locator.fileName, in: root)
            } catch let error as FileSystemError {
                throw ObjectStoreError.filesystem(error)
            }
        }
        return entry
    }

    public func read(_ identity: CanonicalLogicalIdentity) async throws -> Data {
        let manifest = try opened()
        guard let entry = manifest.entry(for: identity) else { throw ObjectStoreError.unknownObject }
        let bytes = try readEntryFile(entry)
        let parsed = try AuthenticatedStorageEnvelope.parse(bytes)
        guard parsed.header.locator == entry.locator.value,
              parsed.header.keyVersion == entry.keyVersion
        else { throw ObjectStoreError.corruption(.manifestUnreadable) }
        let material = try await material(entry.keyVersion, versions: nil)
        do {
            return try LocatorCodec.open(envelope: bytes, requested: identity,
                                        materialByVersion: [entry.keyVersion: material]).payload
        } catch let error as StorageEnvelopeError {
            throw ObjectStoreError.envelope(error)
        } catch let error as LocatorCodecError {
            throw ObjectStoreError.locator(error)
        }
    }

    public func delete(_ identity: CanonicalLogicalIdentity,
                       injection: DurabilityInjection = .none) async throws {
        let manifest = try opened()
        guard let entry = manifest.entry(for: identity) else { throw ObjectStoreError.unknownObject }
        let version = manifest.currentKeyVersion
        let material = try await material(version, versions: nil)
        try commit({ $0.remove(identity) }, material: { material }, injection: injection)
        do {
            try fileSystem.removeFile(name: entry.locator.fileName, in: root)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
    }

    public func entries() throws -> [ManifestEntry] { try opened().entries }

    public func unresolvedArtifactNames() -> [String] { unresolvedArtifacts.sorted() }

    public func invalidateTransientMaterial() { materialCache.removeAll() }

    func opened() throws -> EncryptedManifest {
        guard phase == .opened, let manifestBox else { throw ObjectStoreError.storeNotInitialized }
        return manifestBox
    }

    private func commit(_ mutation: (inout EncryptedManifest) throws -> Void,
                        material: () throws -> Data,
                        injection: DurabilityInjection) throws {
        try commit(mutation, encryptionVersion: try opened().currentKeyVersion,
                   material: material, injection: injection)
    }

    func commit(_ mutation: (inout EncryptedManifest) throws -> Void,
                encryptionVersion: UInt32,
                material: () throws -> Data,
                injection: DurabilityInjection) throws {
        guard var manifest = manifestBox else { throw ObjectStoreError.storeNotInitialized }
        try mutation(&manifest)
        let envelope: Data
        do {
            let sealed = try LocatorCodec.seal(identity: CanonicalLogicalIdentity.manifest,
                                              payload: try manifest.payloadData(),
                                              keyVersion: encryptionVersion, material: material())
            envelope = sealed.envelope
        } catch let error as ManifestError {
            throw ObjectStoreError.manifest(error)
        } catch let error as StorageEnvelopeError {
            throw ObjectStoreError.envelope(error)
        } catch let error as LocatorCodecError {
            throw ObjectStoreError.locator(error)
        }
        do {
            try fileSystem.commitFile(name: ManifestDiscovery.fileName, in: root, bytes: envelope,
                                      phase: .manifest, injection: injection)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
        manifestBox = manifest
    }

    func readEntryFile(_ entry: ManifestEntry) throws -> Data {
        do {
            return try fileSystem.readWholeFile(name: entry.locator.fileName, in: root)
        } catch FileSystemError.notRegularFile, FileSystemError.posix(operation: "open(no-follow)", code: ELOOP) {
            throw ObjectStoreError.corruption(.symlinkEncountered)
        } catch FileSystemError.posix(operation: "open(no-follow)", code: ENOENT) {
            throw ObjectStoreError.corruption(.referencedObjectMissing)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
    }

    func material(_ raw: UInt32, versions known: Set<KeyVersion>?) async throws -> Data {
        if let cached = materialCache[raw] { return cached }
        if let known, !known.contains(KeyVersion(rawValue: raw)) {
            throw ObjectStoreError.corruption(.envelopeKeyMissing)
        }
        let material = try await keySource.material(for: KeyVersion(rawValue: raw))
        materialCache[raw] = material
        return material
    }
}

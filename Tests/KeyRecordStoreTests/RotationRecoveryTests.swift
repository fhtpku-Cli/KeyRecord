import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

actor RotationBackend: KeychainBackend {
    var items: [KeychainItemID: Data] = [:]
    func read(_ id: KeychainItemID) async throws -> Data? { items[id] }
    func versions(in namespace: KeychainNamespace) async throws -> Set<KeyVersion> {
        Set(items.keys.filter { $0.namespace == namespace }.compactMap(\.version))
    }
    func add(_ item: KeychainItem) async throws {
        guard items[item.id] == nil else { throw KeyringError.duplicateItem }
        items[item.id] = item.material
    }
    func publish(_ update: KeychainMetadataUpdate) async throws {
        guard items[update.id] == update.expected else { throw KeyringError.metadataConflict }
        items[update.id] = update.replacement
    }
    func delete(_ id: KeychainItemID) async throws { items[id] = nil }
}

actor BackedObjectKeys: ObjectStoreKeySource {
    private let backend: RotationBackend
    private let namespace: KeychainNamespace
    init(backend: RotationBackend, namespace: KeychainNamespace) {
        self.backend = backend; self.namespace = namespace
    }
    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        try await backend.versions(in: namespace)
    }
    func material(for version: KeyVersion) async throws -> Data {
        guard let bytes = try await backend.read(.key(namespace, version)) else {
            throw ObjectStoreError.corruption(.envelopeKeyMissing)
        }
        return bytes
    }
}

final class RotationEntropy: MasterMaterialGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var nextByte: UInt8 = 7
    func generate() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let value = nextByte
        nextByte += 1
        return Data(repeating: value, count: 32)
    }
}

actor FreshConsent: KeyringCreationAuthorizing {
    func creationState() async throws -> KeyringCreationState {
        KeyringCreationState(consent: true, store: .fresh)
    }
}

actor FakeJournalSource: StoreJournalRecoverySource {
    var references: [ProtectedReference] = []
    var reencryptionCount = 0
    func set(_ references: [ProtectedReference]) { self.references = references }
    func reencryptJournals(rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        reencryptionCount += 1
    }
    func journalProtectedReferences(access: KeyringProtectedAccess) async throws -> [ProtectedReference] {
        references
    }
}

private typealias RotationWiring = (
    harness: StoreHarness, backend: RotationBackend, namespace: KeychainNamespace,
    ring: KeychainKeyring, gate: KeyAvailabilityGate, journal: FakeJournalSource,
    store: ObjectStore)

@MainActor
final class RotationRecoveryTests: XCTestCase {
    private let payload = Data("rotation-object-payload".utf8)

    func makeWiring(journal: FakeJournalSource? = nil) async throws
        -> (harness: StoreHarness, backend: RotationBackend, namespace: KeychainNamespace,
            ring: KeychainKeyring, gate: KeyAvailabilityGate, journal: FakeJournalSource,
            store: ObjectStore) {
        let harness = try StoreHarness()
        let namespace = try KeychainNamespace("com.keyrecord.tests.rotation-\(UUID().uuidString)")
        let backend = RotationBackend()
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let journal = journal ?? FakeJournalSource()
        let keys = BackedObjectKeys(backend: backend, namespace: namespace)
        let store = ObjectStore(root: harness.root, keySource: keys, journalSource: journal)
        let ring = KeychainKeyring(
            configuration: KeyringConfiguration(namespace: namespace),
            ports: KeyringPorts(backend: backend, entropy: RotationEntropy(),
                                creation: FreshConsent(), references: store,
                                clock: FakeKeyringClock()),
            gate: gate)
        return (harness, backend, namespace, ring, gate, journal, store)
    }

    func bootCommitted(_ wiring: (store: ObjectStore, ring: KeychainKeyring)) async throws {
        let state = try await wiring.store.bootstrap()
        XCTAssertEqual(state, .freshInstall)
        _ = try await wiring.ring.bootstrap()
        try await wiring.store.initializeFreshInstallation()
        _ = try await wiring.store.put(identity: try objectIdentity("rot"), payload: payload)
    }

    private func seedNewKey(_ wiring: RotationWiring) async throws {
        try await wiring.backend.add(KeychainItem(
            id: .key(wiring.namespace, v2),
            material: Data(repeating: 8, count: 32),
            policy: .candidateWhenUnlockedThisDeviceOnly))
    }

    func testMigrationRelocatesObjectWhileManifestStaysUnderOldKey() async throws {
        let wiring = try await makeWiring()
        defer { wiring.harness.cleanup() }
        try await bootCommitted((wiring.store, wiring.ring))
        try await seedNewKey(wiring)
        let oldFiles = try wiring.harness.rootEntries()

        let session = try await wiring.store.acquireExclusiveAccess()
        let generation = try wiring.gate.begin()
        let access = wiring.ring.access(generation, versions: [v1, v2])
        let rotation = KeyRotation(from: v1, to: v2)
        try await session.migrateData(rotation, access: access)

        let current = try await wiring.store.currentKeyVersion()
        XCTAssertEqual(current, v1, "writer version moves only at manifest re-encryption")
        let readBack = try await wiring.store.read(try objectIdentity("rot"))
        XCTAssertEqual(readBack, payload)
        let entries = try await wiring.store.entries()
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.keyVersion, 2)
        let newFiles = try wiring.harness.rootEntries()
        XCTAssertEqual(Set(newFiles).subtracting(oldFiles.map { $0 }), [entry.locator.fileName],
                       "only the new locator file appears")
        XCTAssertFalse(oldFiles.contains(entry.locator.fileName))
        await session.release()
    }

    func testFullRotationSessionLeavesOnlyNewReferencesAndReencryptsJournals() async throws {
        let wiring = try await makeWiring()
        defer { wiring.harness.cleanup() }
        try await bootCommitted((wiring.store, wiring.ring))
        try await seedNewKey(wiring)
        let session = try await wiring.store.acquireExclusiveAccess()
        let generation = try wiring.gate.begin()
        let access = wiring.ring.access(generation, versions: [v1, v2])
        let rotation = KeyRotation(from: v1, to: v2)
        try await session.migrateData(rotation, access: access)
        try await session.reencryptManifestAndJournals(rotation, access: access)
        try await session.recoverAndReconcile(access: access)
        let snapshot = try await session.scan(access: access)
        let required = try snapshot.requiredVersions()
        XCTAssertEqual(required, [v2])
        let reencryptions = await wiring.journal.reencryptionCount
        XCTAssertEqual(reencryptions, 1)
        let currentVersion = try await wiring.store.currentKeyVersion()
        XCTAssertEqual(currentVersion, v2)
        let unresolved = await wiring.store.unresolvedArtifactNames()
        XCTAssertTrue(unresolved.isEmpty)
        await session.release()
    }

    func testUnresolvedOrphanBlocksRetirementInProtectedScan() async throws {
        let wiring = try await makeWiring()
        defer { wiring.harness.cleanup() }
        try await bootCommitted((wiring.store, wiring.ring))
        try Data("partial".utf8).write(to: wiring.harness.root
            .appendingPathComponent(AtomicFileSystem.tempPrefix + "XXXXXXXX99"))
        let reopened = ObjectStore(
            root: wiring.harness.root,
            keySource: BackedObjectKeys(backend: wiring.backend, namespace: wiring.namespace),
            journalSource: wiring.journal)
        _ = try await reopened.bootstrap()
        let session = try await reopened.acquireExclusiveAccess()
        let generation = try wiring.gate.begin()
        let access = wiring.ring.access(generation, versions: [v1])
        let snapshot = try await session.scan(access: access)
        let hasUnreadableOrphan = snapshot.references.contains {
            if case .unreadable(.ownedTemporaryOrOrphan) = $0 { return true } else { return false }
        }
        XCTAssertTrue(hasUnreadableOrphan)
        XCTAssertThrowsError(try snapshot.requiredVersions()) {
            XCTAssertEqual($0 as? KeyringError, .unknownReferences)
        }
        await session.release()
    }

    func testJournalReferenceToOldKeyBlocksRetirement() async throws {
        let journal = FakeJournalSource()
        await journal.set([.known(.unfinishedJournal, v1), .known(.journalRecoveryObject, v1)])
        let wiring = try await makeWiring(journal: journal)
        defer { wiring.harness.cleanup() }
        try await bootCommitted((wiring.store, wiring.ring))
        try await seedNewKey(wiring)
        let session = try await wiring.store.acquireExclusiveAccess()
        let generation = try wiring.gate.begin()
        let access = wiring.ring.access(generation, versions: [v1, v2])
        let rotation = KeyRotation(from: v1, to: v2)
        try await session.migrateData(rotation, access: access)
        try await session.reencryptManifestAndJournals(rotation, access: access)
        let snapshot = try await session.scan(access: access)
        let required = try snapshot.requiredVersions()
        XCTAssertEqual(required, [v1, v2], "journal envelopes keep the old key required")
        await session.release()
    }

    func testRealKeyringDrivenRotationCompletesAndDeletesOldKey() async throws {
        let wiring = try await makeWiring()
        defer { wiring.harness.cleanup() }
        try await bootCommitted((wiring.store, wiring.ring))
        try await wiring.ring.rotate(to: v2)
        let readBack = try await wiring.store.read(try objectIdentity("rot"))
        XCTAssertEqual(readBack, payload)
        let versions = try await wiring.backend.versions(in: wiring.namespace)
        XCTAssertEqual(versions, [v2])
        let reopened = ObjectStore(root: wiring.harness.root,
                                   keySource: BackedObjectKeys(backend: wiring.backend,
                                                              namespace: wiring.namespace),
                                   journalSource: wiring.journal)
        let state = try await reopened.bootstrap()
        let reopenedPayload = try await reopened.read(try objectIdentity("rot"))
        let current = try await reopened.currentKeyVersion()
        XCTAssertEqual(state, .opened)
        XCTAssertEqual(reopenedPayload, payload)
        XCTAssertEqual(current, v2)
    }

    func testProtectedSessionIsExclusiveAndReleasable() async throws {
        let wiring = try await makeWiring()
        defer { wiring.harness.cleanup() }
        try await bootCommitted((wiring.store, wiring.ring))
        let first = try await wiring.store.acquireExclusiveAccess()
        do {
            _ = try await wiring.store.acquireExclusiveAccess()
            XCTFail("expected busy")
        } catch let error as KeyringError {
            XCTAssertEqual(error, .busy)
        }
        await first.release()
        let second = try await wiring.store.acquireExclusiveAccess()
        await second.release()
    }
}
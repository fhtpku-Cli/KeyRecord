import XCTest
import KeyRecordCore
@testable import KeyRecordStore

final class LocalDeletionDestructionRecoveryTests: XCTestCase {
    private func makeRoot() throws -> (parent: URL, root: URL) {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("t17-f1fix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent("store")
        try AtomicFileSystem().preparePrivateRoot(at: root)
        return (parent, root)
    }

    private func makeRing(backend: RecordingKeychain = RecordingKeychain())
        -> (KeychainKeyring, KeychainNamespace, RecordingKeychain) {
        let namespace = try! KeychainNamespace("com.keyrecord.tests.t17.f1fix.\(UUID().uuidString)")
        let trace = KeyringTrace()
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let ring = KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace),
            ports: KeyringPorts(backend: backend, entropy: FakeEntropy(), creation: FakeStoreState(),
                                references: FakeReferences(trace: trace), clock: FakeKeyringClock()),
            gate: gate)
        return (ring, namespace, backend)
    }

    private func delete(_ root: URL, _ ring: KeychainKeyring) async throws -> DeletionReport {
        try await LocalDeletionCoordinator(
            ownedRoot: root.path, fileSystem: FileSystemDeletionAdapter(),
            keychain: KeychainDeletionAdapter(keyring: ring),
            loginItems: F1Login()).deleteEverything()
    }

    // Regression for F1: zero version items plus an undecodable metadata item must not
    // survive a successful delete-all, or the namespace can never bootstrap fresh again.
    func testDestructionRemovesCorruptMetadataWhenNoVersionKeys() async throws {
        // Given: only corrupt metadata bytes exist; backend inventory is empty
        let (parent, root) = try makeRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let (ring, namespace, backend) = makeRing()
        let metadataID = KeychainItemID.metadata(namespace)
        await backend.seed(metadataID, bytes: Data("corrupt-metadata".utf8))

        // When
        let report = try await delete(root, ring)

        // Then: exact metadata id deleted once, nothing else, pass reports success
        let deletedIDs = await backend.deletedIDs
        let remaining = await backend.items
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(deletedIDs, [metadataID])
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))

        // And: a reopened bootstrap reaches fresh install instead of creationDenied
        let fresh = try await ring.bootstrap()
        XCTAssertEqual(fresh.versions, [v1])
        let seededV1 = await backend.items[.key(namespace, v1)]
        XCTAssertNotNil(seededV1)
    }

    func testDestructionWithAbsentMetadataAndKeysConverges() async throws {
        // Given: a completely empty namespace (no metadata, no version items)
        let (parent, root) = try makeRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let (ring, namespace, backend) = makeRing()

        // When: the terminal metadata attempt finds the item absent (one no-op)
        let report = try await delete(root, ring)

        // Then: success with zero backend deletions, and fresh bootstrap works
        let absentDeletedIDs = await backend.deletedIDs
        let absentFreshVersions = try await ring.bootstrap().versions
        let absentSeededV1 = await backend.items[.key(namespace, v1)]
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(absentDeletedIDs, [])
        XCTAssertEqual(absentFreshVersions, [v1])
        XCTAssertNotNil(absentSeededV1)
    }

    func testDestructionWithValidMetadataAndAllVersionKeysMissingStillSucceeds() async throws {
        // Given: valid rotation metadata naming v1/v2, but both key items already gone
        let (parent, root) = try makeRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let (ring, namespace, backend) = makeRing()
        let metadata = KeyringMetadata(current: v2, versions: [v1, v2],
                                       retirementPending: [v1], rotation: KeyRotation(from: v1, to: v2))
        try await backend.seed(.metadata(namespace), bytes: metadata.encoded())

        // When
        let report = try await delete(root, ring)

        // Then: both keys are already-destroyed outcomes, metadata is removed, success
        let validDeletedIDs = await backend.deletedIDs
        let validFreshVersions = try await ring.bootstrap().versions
        XCTAssertEqual(report.keyOutcomes,
                       ["master-v1": .missingKeyDuringDeletion(1),
                        "master-v2": .missingKeyDuringDeletion(2)])
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(validDeletedIDs, [.metadata(namespace)])
        XCTAssertEqual(validFreshVersions, [v1])
    }
}

private actor RecordingKeychain: KeychainBackend {
    var items: [KeychainItemID: Data] = [:]
    private(set) var deletedIDs: [KeychainItemID] = []

    func seed(_ id: KeychainItemID, bytes: Data?) { items[id] = bytes }

    func read(_ id: KeychainItemID) -> Data? { items[id] }

    func versions(in namespace: KeychainNamespace) -> Set<KeyVersion> {
        Set(items.keys.filter { $0.namespace == namespace }.compactMap(\.version))
    }

    func add(_ item: KeychainItem) { items[item.id] = item.material }

    func publish(_ update: KeychainMetadataUpdate) { items[update.id] = update.replacement }

    func delete(_ id: KeychainItemID) {
        deletedIDs.append(id)
        items[id] = nil
    }
}

private actor F1Login: DeletionLoginItems {
    func unregisterProductLoginItem() -> DeletionOutcome { .succeeded }
}

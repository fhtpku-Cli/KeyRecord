import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class LocalDeletionSafeguardTests: XCTestCase {
    func testUnknownBackendFilesBlockBeforeAnyDestructiveSideEffect() async throws {
        try await assertSafeguard(unknownNames: [
            "future-backend.json", "stray.bin", "future.krenc", ".keyrecord-tmp-invalid",
        ], nestedBackend: false)
    }

    func testNestedBackendBlocksBeforeAnyDestructiveSideEffect() async throws {
        try await assertSafeguard(unknownNames: [], nestedBackend: true)
    }

    private func assertSafeguard(unknownNames: [String], nestedBackend: Bool) async throws {
        // Given: a valid, initialized private root with genuine owned ciphertext.
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        _ = try await store.put(identity: objectIdentity("safeguard"), payload: Data("owned".utf8))
        for name in unknownNames {
            try Data("opaque-future-state:\(name)".utf8).write(to: harness.root.appendingPathComponent(name))
        }
        var paths = try harness.rootEntries().map { harness.root.appendingPathComponent($0) }
        if nestedBackend {
            let directory = harness.root.appendingPathComponent("future-backend")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let object = directory.appendingPathComponent("baseline.json")
            try Data("future-baseline".utf8).write(to: object)
            paths.append(object)
        }
        let sentinel = harness.directory.appendingPathComponent("external-sentinel")
        try Data("external-user-data".utf8).write(to: sentinel)
        paths.append(sentinel)
        let before = try Dictionary(uniqueKeysWithValues: paths.map { ($0, try Data(contentsOf: $0)) })
        let backend = SafeguardKeychain()
        let namespace = try KeychainNamespace("com.keyrecord.tests.deletion.safeguard")
        let externalNamespace = try KeychainNamespace("com.keyrecord.tests.deletion.safeguard.external")
        try await backend.seed(.metadata(namespace), bytes: KeyringMetadata(current: v1, versions: [v1]).encoded())
        await backend.seed(.key(namespace, v1), bytes: Data(repeating: 7, count: 32))
        await backend.seed(.key(externalNamespace, v1), bytes: Data(repeating: 9, count: 32))
        let keysBefore = await backend.items
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let trace = KeyringTrace()
        let ring = KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace),
            ports: KeyringPorts(backend: backend, entropy: FakeEntropy(), creation: FakeStoreState(),
                                references: FakeReferences(trace: trace), clock: FakeKeyringClock()), gate: gate)
        let files = SafeguardFileSystem()
        let login = SafeguardLogin()
        let coordinator = LocalDeletionCoordinator(ownedRoot: harness.root.path, fileSystem: files,
            keychain: KeychainDeletionAdapter(keyring: ring), loginItems: login)
        let lifecycle = SafeguardLifecycle()
        let model = Phase1FlowModel(lifecycle: lifecycle, localDataEraser: SafeguardEraser(coordinator: coordinator))
        model.requestDeleteLocalData()

        // When: explicit user confirmation reaches the real planner and filesystem adapter.
        do {
            try await model.choose(.confirm)
            XCTFail("Expected safeguard-required BLOCKED")
        } catch DeletionError.blocked(let blocks) {
            let names = unknownNames + (nestedBackend ? ["future-backend"] : [])
            XCTAssertEqual(blocks, names.sorted().map {
                .safeguardRequired(harness.root.appendingPathComponent($0).path)
            })
        }

        // Then: not even an attempted destructive operation or consent reset is allowed.
        let deletedIDs = await backend.deletedIDs
        let keysAfter = await backend.items
        let fileCalls = await files.removalCalls
        let loginCalls = await login.calls
        XCTAssertEqual(deletedIDs, [])
        XCTAssertEqual(keysAfter, keysBefore)
        XCTAssertEqual(fileCalls, 0)
        XCTAssertEqual(loginCalls, 0)
        XCTAssertEqual(lifecycle.consentResets, 0)
        XCTAssertEqual(lifecycle.state.phase, .paused)
        for (path, bytes) in before {
            XCTAssertEqual(try Data(contentsOf: path), bytes, path.path)
        }
    }

    func testKnownCiphertextExplicitDeletionStillSucceeds() async throws {
        // Given: actual store-produced manifest and ciphertext, not arbitrary named bytes.
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        _ = try await store.put(identity: objectIdentity("control"), payload: Data("owned".utf8))
        let files = SafeguardFileSystem()
        let login = SafeguardLogin()
        let coordinator = LocalDeletionCoordinator(ownedRoot: harness.root.path, fileSystem: files,
            keychain: KeychainDeletionAdapter(keyring: try makeEmptyRing()), loginItems: login)
        let lifecycle = SafeguardLifecycle()
        let model = Phase1FlowModel(lifecycle: lifecycle, localDataEraser: SafeguardEraser(coordinator: coordinator))
        model.requestDeleteLocalData()

        // When
        try await model.choose(.confirm)

        // Then: known ciphertext can be removed even when namespace keys are missing.
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.root.path))
        let fileCalls = await files.removalCalls
        let loginCalls = await login.calls
        XCTAssertEqual(fileCalls, 3)
        XCTAssertEqual(loginCalls, 1)
        XCTAssertEqual(lifecycle.consentResets, 1)
    }

    private func makeEmptyRing() throws -> KeychainKeyring {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        return KeychainKeyring(
            configuration: KeyringConfiguration(namespace: try KeychainNamespace("com.keyrecord.tests.deletion.control")),
            ports: KeyringPorts(backend: SafeguardKeychain(), entropy: FakeEntropy(), creation: FakeStoreState(),
                                references: FakeReferences(trace: KeyringTrace()), clock: FakeKeyringClock()), gate: gate)
    }
}

private actor SafeguardKeychain: KeychainBackend {
    private(set) var items: [KeychainItemID: Data] = [:]
    private(set) var deletedIDs: [KeychainItemID] = []
    func seed(_ id: KeychainItemID, bytes: Data) { items[id] = bytes }
    func read(_ id: KeychainItemID) -> Data? { items[id] }
    func versions(in namespace: KeychainNamespace) -> Set<KeyVersion> {
        Set(items.keys.filter { $0.namespace == namespace }.compactMap(\.version))
    }
    func add(_ item: KeychainItem) { items[item.id] = item.material }
    func publish(_ update: KeychainMetadataUpdate) { items[update.id] = update.replacement }
    func delete(_ id: KeychainItemID) { deletedIDs.append(id); items[id] = nil }
}

private actor SafeguardFileSystem: DeletionFileSystem {
    private let adapter = FileSystemDeletionAdapter()
    private(set) var removalCalls = 0
    func listOwnedEntries(ownedRoot: String) throws -> [DeletionEntry] {
        try adapter.listOwnedEntries(ownedRoot: ownedRoot)
    }
    func removeOwnedEntry(_ entry: DeletionEntry) throws {
        removalCalls += 1
        try adapter.removeOwnedEntry(entry)
    }
    func ownedRootExists(_ root: String) -> Bool { adapter.ownedRootExists(root) }
    func removeOwnedRootIfEmpty(_ root: String) throws {
        removalCalls += 1
        try adapter.removeOwnedRootIfEmpty(root)
    }
}

private actor SafeguardLogin: DeletionLoginItems {
    private(set) var calls = 0
    func unregisterProductLoginItem() -> DeletionOutcome { calls += 1; return .succeeded }
}

private struct SafeguardEraser: LocalDataErasing {
    let coordinator: LocalDeletionCoordinator
    func eraseAllLocalData() async throws {
        let report = try await coordinator.deleteEverything()
        guard report.succeeded else { throw LifecycleStoreError.filesystemFailure }
    }
}

@MainActor
private final class SafeguardLifecycle: LifecycleDriving {
    var state = LifecycleState(phase: .paused)
    private(set) var consentResets = 0
    func returnToConsentRequired() async { consentResets += 1; state = .initial }
}

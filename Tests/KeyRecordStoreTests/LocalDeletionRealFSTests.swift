import XCTest
@testable import KeyRecordStore

final class LocalDeletionRealFSTests: XCTestCase {
    private let locatorName = String(repeating: "a", count: 64) + ".krenc"
    private let payload = Data("destruction-fixture".utf8)

    private func makeParentAndRoot() throws -> (parent: URL, root: URL) {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("t17-realfs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent("store")
        try AtomicFileSystem().preparePrivateRoot(at: root)
        return (parent, root)
    }

    private func seed(_ root: URL, _ name: String) throws {
        try payload.write(to: root.appendingPathComponent(name))
    }

    private func makeCoordinator(
        _ root: URL, keychain: any DeletionKeychain, login: RealFSTestLogin
    ) -> LocalDeletionCoordinator {
        LocalDeletionCoordinator(ownedRoot: root.path, fileSystem: FileSystemDeletionAdapter(),
                                 keychain: keychain, loginItems: login)
    }

    func testRealFileSystemHappyDeletesKnownUnrecognizedAndDirectory() async throws {
        // Given: a real 0700 root with manifest, locator file, unknown regular, empty dir
        let (parent, root) = try makeParentAndRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        try seed(root, "manifest.krenc")
        try seed(root, locatorName)
        try seed(root, "stray.bin")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"),
                                                withIntermediateDirectories: false)
        let keychain = RealFSTestKeychain(ids: ["master-v1"])
        let login = RealFSTestLogin()

        // When
        let report = try await makeCoordinator(root, keychain: keychain, login: login)
            .deleteEverything()

        // Then: known/unrecognized files and the empty directory all removed, root gone
        guard case .proceed(let planned) = report.decision else { return XCTFail("expected proceed") }
        XCTAssertEqual(planned.filter { $0.kind == .unrecognizedOwnedFile }.map(\.path),
                       [root.appendingPathComponent("stray.bin").path])
        for entry in planned { XCTAssertEqual(report.fileOutcomes[entry.path], .succeeded) }
        XCTAssertEqual(report.fileOutcomes[root.path], .succeeded)
        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let remaining = await keychain.remaining
        let loginCalls = await login.callCount
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(loginCalls, 1)
    }

    func testRealFileSystemSymlinkBlocksAndPreservesExternalTarget() async throws {
        // Given: an external file referenced by an in-root symlink
        let (parent, root) = try makeParentAndRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let external = parent.appendingPathComponent("outside.txt")
        try payload.write(to: external)
        try seed(root, "manifest.krenc")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path,
                                                   withDestinationPath: external.path)
        let keychain = RealFSTestKeychain(ids: ["master-v1"])
        let login = RealFSTestLogin()

        // When
        do {
            _ = try await makeCoordinator(root, keychain: keychain, login: login)
                .deleteEverything()
            XCTFail("expected blocked")
        } catch DeletionError.blocked(let blocks) {
            // Then: planner blocks, target/root/link survive, zero destructive calls
            XCTAssertEqual(blocks, [.symlinkPresent(root.appendingPathComponent("link").path)])
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        let blockedRemaining = await keychain.remaining
        let blockedLoginCalls = await login.callCount
        XCTAssertEqual(blockedRemaining, 1)
        XCTAssertEqual(blockedLoginCalls, 0)
    }

    func testRealFileSystemSiblingDecoyNeverEnumeratedOrRemoved() async throws {
        // Given: a decoy file and decoy directory beside the owned root
        let (parent, root) = try makeParentAndRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let decoyFile = parent.appendingPathComponent("decoy.txt")
        let decoyDir = parent.appendingPathComponent("store-decoy")
        try payload.write(to: decoyFile)
        try FileManager.default.createDirectory(at: decoyDir, withIntermediateDirectories: false)
        try seed(root, "manifest.krenc")

        // When
        let report = try await makeCoordinator(root, keychain: RealFSTestKeychain(),
                                               login: RealFSTestLogin()).deleteEverything()

        // Then: only the owned root is enumerated and removed; siblings untouched
        guard case .proceed(let planned) = report.decision else { return XCTFail("expected proceed") }
        XCTAssertEqual(planned.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: decoyFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: decoyDir.path))
    }

    // Simulates "process died mid-deletion": part of the entries are already gone, and a
    // fresh coordinator instance reopens the same root.
    func testRealFileSystemPartialDeletionReopenedConverges() async throws {
        // Given: three files where one vanished before the new process started
        let (parent, root) = try makeParentAndRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        try seed(root, "manifest.krenc")
        try seed(root, locatorName)
        try seed(root, "stray.bin")
        try FileManager.default.removeItem(at: root.appendingPathComponent(locatorName))

        // When: reopen with a brand-new coordinator and delete
        let report = try await makeCoordinator(root, keychain: RealFSTestKeychain(),
                                               login: RealFSTestLogin()).deleteEverything()

        // Then: the survivors converge to success and the empty root is removed
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.fileOutcomes[root.appendingPathComponent("manifest.krenc").path],
                       .succeeded)
        XCTAssertEqual(report.fileOutcomes[root.appendingPathComponent("stray.bin").path],
                       .succeeded)
        XCTAssertNil(report.fileOutcomes[root.appendingPathComponent(locatorName).path])
        XCTAssertEqual(report.fileOutcomes[root.path], .succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testKeychainDeletionAdapterMissingVersionRecordedAndOtherDeleted() async throws {
        // Given: real keyring over fake backend; v1 present, v2 missing, metadata intact
        let (parent, root) = try makeParentAndRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        try seed(root, "manifest.krenc")
        let namespace = try KeychainNamespace("com.keyrecord.tests.deletion.keyring")
        let trace = KeyringTrace()
        let backend = FakeKeychain(trace: trace)
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let ring = KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace),
            ports: KeyringPorts(backend: backend, entropy: FakeEntropy(), creation: FakeStoreState(),
                                references: FakeReferences(trace: trace), clock: FakeKeyringClock()),
            gate: gate)
        let metadata = KeyringMetadata(current: v2, versions: [v1, v2],
                                       retirementPending: [v1], rotation: KeyRotation(from: v1, to: v2))
        try await backend.seed(.metadata(namespace), bytes: metadata.encoded())
        try await backend.seed(.key(namespace, v1), bytes: Data(repeating: 7, count: 32))
        let login = RealFSTestLogin()

        // When
        let report = try await makeCoordinator(root, keychain: KeychainDeletionAdapter(keyring: ring),
                                               login: login).deleteEverything()

        // Then: v1 destroyed, v2 reported missing (destruction, not recovery), metadata gone
        XCTAssertEqual(report.keyOutcomes,
                       ["master-v1": .succeeded, "master-v2": .missingKeyDuringDeletion(2)])
        XCTAssertTrue(report.succeeded)
        let backendEmpty = await backend.items.isEmpty
        let keyringLoginCalls = await login.callCount
        XCTAssertTrue(backendEmpty)
        XCTAssertEqual(keyringLoginCalls, 1)
    }

    func testRealFileSystemRootSymlinkIsRejected() async throws {
        // Given: the owned root path itself is a symlink to a real directory
        let (parent, root) = try makeParentAndRoot()
        let target = parent.appendingPathComponent("target-store")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try payload.write(to: target.appendingPathComponent("manifest.krenc"))
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createSymbolicLink(atPath: root.path,
                                                   withDestinationPath: target.path)
        defer { try? FileManager.default.removeItem(at: parent) }

        // When
        do {
            _ = try FileSystemDeletionAdapter().listOwnedEntries(ownedRoot: root.path)
            XCTFail("expected rootSymlink")
        } catch let error as FileSystemError {
            // Then: enumeration refuses and the target tree survives untouched
            XCTAssertEqual(error, .rootSymlink)
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("manifest.krenc").path))
    }
}

private actor RealFSTestKeychain: DeletionKeychain {
    private var ids: Set<String>
    private(set) var deleteCount = 0
    init(ids: [String] = []) { self.ids = Set(ids) }
    var remaining: Int { ids.count }
    func ownedVersionedItemIDs() -> [String] { ids.sorted() }
    func deleteOwnedItem(_ id: String) throws {
        deleteCount += 1
        ids.remove(id)
    }
}

private actor RealFSTestLogin: DeletionLoginItems {
    private var registered = true
    private(set) var callCount = 0
    func unregisterProductLoginItem() -> DeletionOutcome {
        callCount += 1
        guard registered else { return .alreadyAbsent }
        registered = false
        return .succeeded
    }
}

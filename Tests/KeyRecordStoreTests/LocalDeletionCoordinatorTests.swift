import XCTest
@testable import KeyRecordStore

final class LocalDeletionCoordinatorTests: XCTestCase {
    private let root = "/Users/tester/KeyRecord/store"

    private func seededEntries() -> [DeletionEntry] {
        [
            DeletionEntry(path: root + "/ab/cd.krenc", kind: .ownedFile),
            DeletionEntry(path: root + "/stray.tmp", kind: .unrecognizedOwnedFile),
            DeletionEntry(path: root + "/nested", kind: .directory),
        ]
    }
    private func makeCoordinator(
        entries: [DeletionEntry],
        keychain: FakeDeletionKeychain,
        failingPaths: Set<String> = [],
        sharedLogin: FakeDeletionLoginItems? = nil
    ) -> (LocalDeletionCoordinator, FakeDeletionFileSystem, FakeDeletionLoginItems) {
        let fileSystem = FakeDeletionFileSystem(entries: entries, failingPaths: failingPaths)
        let loginItems = sharedLogin ?? FakeDeletionLoginItems()
        let coordinator = LocalDeletionCoordinator(
            ownedRoot: root, fileSystem: fileSystem, keychain: keychain, loginItems: loginItems)
        return (coordinator, fileSystem, loginItems)
    }

    func testHappyDeletesOwnedFilesKeysAndLoginItemOnce() async throws {
        // Given: two owned key items, three entries (one unrecognized), one external key
        let entries = seededEntries()
        let keychain = FakeDeletionKeychain(
            ownedIDs: ["master-v1", "master-v3"], externalIDs: ["external.item.v9"])
        let (coordinator, fileSystem, loginItems) =
            makeCoordinator(entries: entries, keychain: keychain)

        // When
        let report = try await coordinator.deleteEverything()

        // Then: everything owned is removed exactly once; external item untouched
        XCTAssertEqual(report.decision, .proceed(entries))
        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(report.requiresFreshConsent)
        XCTAssertEqual(report.keyOutcomes, ["master-v1": .succeeded, "master-v3": .succeeded])
        for entry in entries {
            XCTAssertEqual(report.fileOutcomes[entry.path], .succeeded)
        }
        XCTAssertEqual(report.fileOutcomes[root], .succeeded)
        XCTAssertEqual(report.loginItemOutcome, .succeeded)

        let (remainingCount, rootExists, entryCalls, rootCalls) = (
            await fileSystem.remainingCount, await fileSystem.rootExists(root),
            await fileSystem.removeEntryCallCount, await fileSystem.removeRootCallCount)
        let (ownedIDs, externalIDs, deleteCalls, loginCalls) = (
            await keychain.ownedIDs, await keychain.externalIDs,
            await keychain.deleteCallCount, await loginItems.callCount)
        XCTAssertEqual(remainingCount, 0)
        XCTAssertFalse(rootExists)
        XCTAssertEqual(entryCalls, 3)
        XCTAssertEqual(rootCalls, 1)
        XCTAssertEqual(ownedIDs, [])
        XCTAssertEqual(externalIDs, ["external.item.v9"])
        XCTAssertEqual(deleteCalls, 2)
        XCTAssertEqual(loginCalls, 1)
    }

    func testIdempotentSecondRunAllAlreadyAbsent() async throws {
        // Given: a store fully deleted on the first pass
        let keychain = FakeDeletionKeychain(ownedIDs: ["master-v1"])
        let (coordinator, fileSystem, loginItems) =
            makeCoordinator(entries: seededEntries(), keychain: keychain)
        let first = try await coordinator.deleteEverything()
        XCTAssertTrue(first.succeeded)
        XCTAssertEqual(first.loginItemOutcome, .succeeded)

        // When: the user triggers deletion again on the emptied machine
        let second = try await coordinator.deleteEverything()

        // Then: converges to success with already-absent outcomes, no extra deletions
        XCTAssertTrue(second.succeeded)
        XCTAssertEqual(second.decision, .proceed([]))
        XCTAssertEqual(second.keyOutcomes, [:])
        XCTAssertEqual(second.fileOutcomes, [root: .alreadyAbsent])
        XCTAssertEqual(second.loginItemOutcome, .alreadyAbsent)
        let (rootCalls, deleteCalls, loginCalls) = (
            await fileSystem.removeRootCallCount, await keychain.deleteCallCount,
            await loginItems.callCount)
        XCTAssertEqual(rootCalls, 1)
        XCTAssertEqual(deleteCalls, 1)
        XCTAssertEqual(loginCalls, 2)
    }

    func testBlockedPlanPerformsZeroActions() async throws {
        // Given: a symlink among otherwise deletable entries
        let symlinkPath = root + "/link"
        let entries = seededEntries() + [DeletionEntry(path: symlinkPath, kind: .symlink)]
        let keychain = FakeDeletionKeychain(ownedIDs: ["master-v1", "master-v3"])
        let (coordinator, fileSystem, loginItems) =
            makeCoordinator(entries: entries, keychain: keychain)

        // When
        do {
            _ = try await coordinator.deleteEverything()
            XCTFail("expected DeletionError.blocked")
        } catch DeletionError.blocked(let blocks) {
            // Then: the planner verdict surfaces and nothing is mutated
            XCTAssertEqual(blocks, [.symlinkPresent(symlinkPath)])
        }

        let (entryCalls, rootCalls, remainingCount, rootExists) = (
            await fileSystem.removeEntryCallCount, await fileSystem.removeRootCallCount,
            await fileSystem.remainingCount, await fileSystem.rootExists(root))
        let (deleteCalls, ownedIDs, loginCalls, loginRegistered) = (
            await keychain.deleteCallCount, await keychain.ownedIDs,
            await loginItems.callCount, await loginItems.isRegistered)
        XCTAssertEqual(entryCalls, 0)
        XCTAssertEqual(rootCalls, 0)
        XCTAssertEqual(remainingCount, 4)
        XCTAssertTrue(rootExists)
        XCTAssertEqual(deleteCalls, 0)
        XCTAssertEqual(ownedIDs, ["master-v1", "master-v3"])
        XCTAssertEqual(loginCalls, 0)
        XCTAssertTrue(loginRegistered)
    }

    func testMissingKeyDoesNotBlockFileAndOtherKeyDeletion() async throws {
        // Given: v2 was destroyed externally between inventory and deletion
        let entries = seededEntries()
        let keychain = FakeDeletionKeychain(
            ownedIDs: ["master-v1", "master-v2"], missingIDs: ["master-v2"])
        let (coordinator, fileSystem, _) = makeCoordinator(entries: entries, keychain: keychain)

        // When
        let report = try await coordinator.deleteEverything()

        // Then: v2 records the versioned missing outcome and the pass still succeeds.
        // An already-absent key is destruction (it can never decrypt again), not a
        // read/recovery failure: files, the other key, and the root still converge.
        XCTAssertEqual(report.keyOutcomes["master-v2"], .missingKeyDuringDeletion(2))
        XCTAssertEqual(report.keyOutcomes["master-v1"], .succeeded)
        XCTAssertTrue(report.succeeded)
        let (deleteCalls, remainingCount) = (
            await keychain.deleteCallCount, await fileSystem.remainingCount)
        XCTAssertEqual(deleteCalls, 2)
        XCTAssertEqual(remainingCount, 0)
        XCTAssertEqual(report.fileOutcomes[root], .succeeded)
    }

    func testFileIOFailureLeavesRootAndReportsFailure() async throws {
        // Given: one entry whose removal fails with an I/O error
        let failingPath = root + "/stray.tmp"
        let keychain = FakeDeletionKeychain(ownedIDs: ["master-v1"])
        let (coordinator, fileSystem, loginItems) = makeCoordinator(
            entries: seededEntries(), keychain: keychain, failingPaths: [failingPath])

        // When: the first pass hits the failure
        let first = try await coordinator.deleteEverything()

        // Then: the failure is recorded, the root is kept, but keys and login item converge
        XCTAssertFalse(first.succeeded)
        guard case .ioFailure(let message)? = first.fileOutcomes[failingPath] else {
            return XCTFail("expected ioFailure for \(failingPath)")
        }
        XCTAssertTrue(message.contains(failingPath))
        let (firstRootCalls, firstRootExists, firstRemaining) = (
            await fileSystem.removeRootCallCount, await fileSystem.rootExists(root),
            await fileSystem.remainingCount)
        XCTAssertEqual(firstRootCalls, 0)
        XCTAssertTrue(firstRootExists)
        XCTAssertEqual(firstRemaining, 1)
        XCTAssertEqual(first.keyOutcomes, ["master-v1": .succeeded])
        XCTAssertEqual(first.loginItemOutcome, .succeeded)

        // When: the fault is repaired and deletion is retried
        await fileSystem.setFailingPaths([])
        let second = try await coordinator.deleteEverything()

        // Then: the partial state converges to a full success
        let remainingEntry = DeletionEntry(path: failingPath, kind: .unrecognizedOwnedFile)
        XCTAssertTrue(second.succeeded)
        XCTAssertEqual(second.decision, .proceed([remainingEntry]))
        XCTAssertEqual(second.fileOutcomes, [failingPath: .succeeded, root: .succeeded])
        XCTAssertEqual(second.keyOutcomes, [:])
        XCTAssertEqual(second.loginItemOutcome, .alreadyAbsent)
        let (secondRootExists, secondRootCalls, secondLoginCalls) = (
            await fileSystem.rootExists(root), await fileSystem.removeRootCallCount,
            await loginItems.callCount)
        XCTAssertFalse(secondRootExists)
        XCTAssertEqual(secondRootCalls, 1)
        XCTAssertEqual(secondLoginCalls, 2)
    }
}

private actor FakeDeletionFileSystem: DeletionFileSystem {
    private var entries: [DeletionEntry]
    private var failingPaths: Set<String>
    private var rootExisting = true
    private(set) var removeEntryCallCount = 0
    private(set) var removeRootCallCount = 0
    init(entries: [DeletionEntry], failingPaths: Set<String> = []) {
        self.entries = entries
        self.failingPaths = failingPaths
    }
    var remainingCount: Int { entries.count }
    func rootExists(_ root: String) -> Bool { rootExisting }
    func setFailingPaths(_ paths: Set<String>) { failingPaths = paths }
    func listOwnedEntries(ownedRoot: String) -> [DeletionEntry] { entries }
    func removeOwnedEntry(_ entry: DeletionEntry) throws {
        removeEntryCallCount += 1
        if failingPaths.contains(entry.path) {
            throw DeletionError.ioFailure("simulated failure: \(entry.path)")
        }
        entries.removeAll { $0.path == entry.path }
    }
    func ownedRootExists(_ root: String) -> Bool { rootExisting }
    func removeOwnedRootIfEmpty(_ root: String) throws {
        guard entries.isEmpty else { throw DeletionError.ioFailure("root not empty: \(root)") }
        rootExisting = false
        removeRootCallCount += 1
    }
}

private actor FakeDeletionKeychain: DeletionKeychain {
    private(set) var ownedIDs: Set<String>
    private(set) var externalIDs: Set<String>
    private let missingIDs: Set<String>
    private(set) var deleteCallCount = 0
    init(ownedIDs: [String], externalIDs: [String] = [], missingIDs: [String] = []) {
        self.ownedIDs = Set(ownedIDs)
        self.externalIDs = Set(externalIDs)
        self.missingIDs = Set(missingIDs)
    }
    func ownedVersionedItemIDs() -> [String] { ownedIDs.sorted() }
    func deleteOwnedItem(_ id: String) throws {
        deleteCallCount += 1
        if missingIDs.contains(id) { throw DeletionError.missingOwnedKey(id) }
        ownedIDs.remove(id)
    }
}

private actor FakeDeletionLoginItems: DeletionLoginItems {
    private var registered = true
    private(set) var callCount = 0
    var isRegistered: Bool { registered }
    func unregisterProductLoginItem() -> DeletionOutcome {
        callCount += 1
        guard registered else { return .alreadyAbsent }
        registered = false
        return .succeeded
    }
}

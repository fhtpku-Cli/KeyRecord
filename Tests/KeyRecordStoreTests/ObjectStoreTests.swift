import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

final class ObjectStoreTests: XCTestCase {
    private let payload = Data("cycle-prefs-payload-2026".utf8)
    private let canary = Data("cycle-prefs-payload-2026".utf8)

    func testFreshInstallBootstrapsManifestAndRoundTripsObject() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            let identity = try objectIdentity("prefs-1")
            let entry = try await store.put(identity: identity, payload: payload)
            let readBack = try await store.read(identity)

            XCTAssertEqual(readBack, payload)
            XCTAssertEqual(entry.locator.fileName.count, 64 + ".krenc".count)
            let files = try harness.rootEntries()
            XCTAssertEqual(files.sorted(), ["manifest.krenc", entry.locator.fileName].sorted())
        }
    }

    func testReopenReadsOnlyDurablyCommittedState() async throws {
        try await withHarness { harness in
            let identity = try objectIdentity("prefs-reopen")
            do {
                let store = try await harness.bootFresh()
                try await store.put(identity: identity, payload: payload)
            }
            let reopened = harness.makeStore()
            let state = try await reopened.bootstrap()
            let readBack = try await reopened.read(identity)
            XCTAssertEqual(state, .opened)
            XCTAssertEqual(readBack, payload)
        }
    }

    func testMultipleObjectsCoexistAndAreIndependentlyReadable() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            for index in 0..<5 {
                try await store.put(identity: try objectIdentity("obj-\(index)"),
                                   payload: Data("payload-\(index)".utf8))
            }
            for index in 0..<5 {
                let readBack = try await store.read(try objectIdentity("obj-\(index)"))
                XCTAssertEqual(readBack, Data("payload-\(index)".utf8))
            }
            let entries = try await store.entries()
            XCTAssertEqual(entries.count, 5)
        }
    }

    func testStorageUsesFlatOpaqueNamesWithoutSemanticComponentsOrPlaintext() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            let shard = try CanonicalLogicalIdentity.shard(cycleID: "cycle-9", dayKey: "2026-09-13",
                                                           aggregateType: "bareKey")
            try await store.put(identity: shard, payload: payload)
            let files = try harness.rootEntries()
            let objectFiles = files.filter { $0 != "manifest.krenc" }
            XCTAssertEqual(objectFiles.count, 1)
            for file in objectFiles {
                XCTAssertFalse(file.contains("/"))
                XCTAssertFalse(file.contains("cycle"))
                XCTAssertFalse(file.contains("2026"))
                XCTAssertFalse(file.contains("bareKey"))
                let bytes = try Data(contentsOf: harness.root.appendingPathComponent(file))
                XCTAssertNil(bytes.range(of: canary))
                XCTAssertThrowsError(try ObjectLocator.parse(fileName: "ab/cd.krenc"))
            }
        }
    }

    func testPrivateRootIs0700AndRegularFilesAre0600() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            try await store.put(identity: try objectIdentity("perm"), payload: payload)
            let rootStatus = try statStatus(harness.root)
            XCTAssertEqual(rootStatus.st_mode & 0o777, 0o700)
            for file in try harness.rootEntries() {
                let status = try statStatus(harness.root.appendingPathComponent(file))
                XCTAssertEqual(status.st_mode & 0o777, 0o600, file)
            }
        }
    }

    func testUpdatingSameIdentityKeepsOneLocatorFileAndOneManifestEntry() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            let identity = try objectIdentity("same")
            let first = try await store.put(identity: identity, payload: Data("v1".utf8))
            let second = try await store.put(identity: identity, payload: Data("v2-longer".utf8))
            let readBack = try await store.read(identity)
            let entries = try await store.entries()
            let objectFiles = try harness.rootEntries().filter { $0 != "manifest.krenc" }
            XCTAssertEqual(first.locator, second.locator)
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(readBack, Data("v2-longer".utf8))
            XCTAssertEqual(objectFiles.count, 1)
        }
    }

    func testDeleteRemovesFileAndManifestEntryAndSurvivesReopen() async throws {
        try await withHarness { harness in
            let identity = try objectIdentity("doomed")
            do {
                let store = try await harness.bootFresh()
                try await store.put(identity: identity, payload: payload)
                try await store.delete(identity)
                let entries = try await store.entries()
                XCTAssertEqual(entries.count, 0)
            }
            let reopened = harness.makeStore()
            let state = try await reopened.bootstrap()
            XCTAssertEqual(state, .opened)
            await expectStoreError(.unknownObject) { try await reopened.read(identity) }
            let files = try harness.rootEntries()
            XCTAssertEqual(files, ["manifest.krenc"])
        }
    }

    func testShardIdentityIsLengthPrefixedTripleAndRoundTrips() throws {
        let shard = try CanonicalLogicalIdentity.shard(cycleID: "c1", dayKey: "2026-01-01",
                                                       aggregateType: "shortcut")
        let reparsed = try CanonicalLogicalIdentity.parse(shard.canonicalBytes)
        XCTAssertEqual(reparsed, shard)
        XCTAssertEqual(reparsed.objectType, CanonicalLogicalIdentity.shardObjectType)
        XCTAssertEqual(reparsed.logicalID.prefix(4), Data([0, 0, 0, 2]))
        XCTAssertEqual(reparsed.logicalID, shard.logicalID)
    }

    func testUnknownRecordSchemaAndBadObjectTypeAreRejected() {
        XCTAssertThrowsError(try CanonicalLogicalIdentity(
            objectType: "com.keyrecord.preferences", schemaVersion: 2, logicalIDText: "x")) {
            XCTAssertEqual($0 as? LogicalIdentityError, .unsupportedSchemaVersion(2))
        }
        XCTAssertThrowsError(try CanonicalLogicalIdentity(
            objectType: "external.type", schemaVersion: 1, logicalIDText: "x")) {
            XCTAssertEqual($0 as? LogicalIdentityError, .emptyComponent)
        }
    }

    func testOversizedAndEmptyPayloadsFailClosedBeforeTouchingManifest() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            let identity = try objectIdentity("big")
            let oversized = Data(count: 8 * 1_024 * 1_024 + 1)
            await expectStoreError(.locator(.payloadTooLarge)) {
                try await store.put(identity: identity, payload: oversized)
            }
            await expectStoreError(.locator(.emptyPayload)) {
                try await store.put(identity: identity, payload: Data())
            }
            let entries = try await store.entries()
            let files = try harness.rootEntries()
            XCTAssertEqual(entries.count, 0)
            XCTAssertEqual(files, ["manifest.krenc"])
        }
    }

    func testLocatorCheckRejectsRequestingDifferentIdentityThanEnvelope() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            let real = try objectIdentity("real-object")
            let other = try objectIdentity("other-object")
            try await store.put(identity: real, payload: payload)
            await expectStoreError(.unknownObject) {
                try await store.read(other)
            }
        }
    }

    func testDecryptedIdentityIsCheckedBeyondAADAgainstForgedInnerIdentity() throws {
        let material = Data(repeating: 7, count: 32)
        let claimed = try objectIdentity("claimed-identity")
        let forged = try objectIdentity("forged-inner-identity")
        var inner = forged.canonicalBytes
        inner.append(contentsOf: payload)
        let forgedLocator = StorageKeySchedule.locator(material: material,
                                                       objectID: claimed.canonicalBytes)
        let envelope = try AuthenticatedStorageEnvelope.seal(
            inner, material: material, keyVersion: 1, locator: forgedLocator)
        XCTAssertThrowsError(try LocatorCodec.open(
            envelope: envelope, requested: claimed, materialByVersion: [1: material])) {
            XCTAssertEqual($0 as? LocatorCodecError, .identityMismatch)
        }
    }

    func testReplacingLocatorFileWithAnotherValidObjectRejects() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            let victim = try objectIdentity("victim")
            let victimEntry = try await store.put(identity: victim, payload: payload)
            for name in ["attacker-a", "attacker-b"] {
                let attacker = try await store.put(
                    identity: try objectIdentity(name), payload: Data("\(name)-payload".utf8))
                let target = harness.root.appendingPathComponent(victimEntry.locator.fileName)
                let attackerBytes = try Data(contentsOf:
                    harness.root.appendingPathComponent(attacker.locator.fileName))
                try attackerBytes.write(to: target)
                await expectStoreError(.corruption(.manifestUnreadable)) {
                    try await store.read(victim)
                }
            }
        }
    }

    func testSymlinkedObjectAndSymlinkedRootAreRejected() async throws {
        try await withHarness { harness in
            let store = try await harness.bootFresh()
            let identity = try objectIdentity("sym")
            let entry = try await store.put(identity: identity, payload: payload)
            let object = harness.root.appendingPathComponent(entry.locator.fileName)
            let outside = harness.directory.appendingPathComponent("outside.krenc")
            try Data("evil".utf8).write(to: outside)
            try FileManager.default.removeItem(at: object)
            try FileManager.default.createSymbolicLink(atPath: object.path,
                                                       withDestinationPath: outside.path)
            await expectStoreError(.corruption(.symlinkEncountered)) {
                try await store.read(identity)
            }
            let second = try StoreHarness()
            defer { second.cleanup() }
            let linkRoot = second.directory.appendingPathComponent("store-link")
            try FileManager.default.createSymbolicLink(atPath: linkRoot.path,
                                                       withDestinationPath: harness.root.path)
            let linked = ObjectStore(root: linkRoot, keySource: second.keySource)
            await expectStoreError(.corruption(.rootReplacedBySymlink)) {
                try await linked.bootstrap()
            }
        }
    }

    private func statStatus(_ url: URL) throws -> Darwin.stat {
        var status = Darwin.stat()
        guard lstat(url.path, &status) == 0 else { throw NSError(domain: "stat", code: Int(errno)) }
        return status
    }
}

import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

final class ManifestRecoveryTests: XCTestCase {
    private let payloadA = Data("object-a-payload".utf8)

    func testEmptyRootWithNoKeysIsFreshAndEmptyRootWithKeyNeverRebuilds() async throws {
        try await withHarness { harness in
            let store = harness.makeStore()
            let state = try await store.bootstrap()
            XCTAssertEqual(state, .freshInstall)
        }
        try await withHarness(versions: [1]) { harness in
            let store = harness.makeStore()
            await expectStoreError(.corruption(.unindexedDataWithNamespaceKey)) {
                try await store.bootstrap()
            }
            let retry = harness.makeStore()
            await expectStoreError(.corruption(.unindexedDataWithNamespaceKey)) {
                try await retry.bootstrap()
            }
            let reopened = harness.makeStore()
            await expectStoreError(.corruption(.unindexedDataWithNamespaceKey)) {
                _ = try await reopened.bootstrap()
            }
            await expectStoreError(.storeNotInitialized) {
                try await reopened.initializeFreshInstallation()
            }
        }
    }

    func testOperationsBeforeInitializationAreRejected() async throws {
        try await withHarness { harness in
            let store = harness.makeStore()
            await expectStoreError(.storeNotInitialized) {
                try await store.put(identity: try objectIdentity("x"), payload: payloadA)
            }
            let state = try await store.bootstrap()
            XCTAssertEqual(state, .freshInstall)
            await expectStoreError(.storeNotInitialized) {
                try await store.read(try objectIdentity("x"))
            }
        }
    }

    func testMissingManifestWithDataFileAndKeyIsCorruptionNotFresh() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        let entry = try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        try FileManager.default.removeItem(at: harness.root.appendingPathComponent(ManifestDiscovery.fileName))
        let reopened = harness.makeStore()
        await expectStoreError(.corruption(.manifestMissing)) { try await reopened.bootstrap() }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: harness.root.appendingPathComponent(entry.locator.fileName).path),
            "unindexed data must not be deleted")
    }

    func testTruncatedAndTamperedManifestsAreCorruption() async throws {
        for mutation in [
            { (bytes: inout Data) in bytes = Data(bytes.dropLast(20)) },
            { (bytes: inout Data) in bytes[64] ^= 0xFF },
        ] {
            let harness = try StoreHarness()
            defer { harness.cleanup() }
            let store = try await harness.bootFresh()
            try await store.put(identity: try objectIdentity("a"), payload: payloadA)
            let url = harness.root.appendingPathComponent(ManifestDiscovery.fileName)
            var bytes = try Data(contentsOf: url)
            mutation(&bytes); try bytes.write(to: url)
            let reopened = harness.makeStore()
            await expectStoreError(.corruption(.manifestUnreadable)) { try await reopened.bootstrap() }
        }
    }

    func testRandomBytesAsManifestAreCorruption() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        _ = try await harness.bootFresh()
        var random = Data(count: 120)
        for index in random.indices { random[index] = UInt8.random(in: 0...255) }
        try random.write(to: harness.root.appendingPathComponent(ManifestDiscovery.fileName))
        await expectStoreError(.corruption(.manifestUnreadable)) {
            try await harness.makeStore().bootstrap()
        }
    }

    func testUnknownManifestSchemaVersionIsRejected() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        let manifest = try EncryptedManifest(currentKeyVersion: 1)
        var json = try manifest.payloadData()
        let canonical = #"{"current":1,"entries":[],"schema":1}"#
        let upgraded = #"{"current":1,"entries":[],"schema":2}"#
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertEqual(text, canonical)
        json = Data(text.replacingOccurrences(of: canonical, with: upgraded).utf8)
        let sealed = try LocatorCodec.seal(identity: .manifest, payload: json, keyVersion: 1,
                                          material: Data(repeating: 7, count: 32))
        try sealed.envelope.write(to: harness.root.appendingPathComponent(ManifestDiscovery.fileName))
        let reopened = harness.makeStore()
        await expectStoreError(.corruption(.unknownManifestSchemaVersion)) {
            try await reopened.bootstrap()
        }
    }

    func testManifestEncryptedUnderMissingKeyIsCorruptionWithoutRecreation() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        await harness.keySource.remove(version: 1)
        let reopened = harness.makeStore()
        await expectStoreError(.corruption(.envelopeKeyMissing)) { try await reopened.bootstrap() }
        let files = try harness.rootEntries()
        XCTAssertTrue(files.contains(ManifestDiscovery.fileName))
    }

    func testSemanticFilenameAndInsideRootSymlinkAreCorruption() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        _ = try await harness.bootFresh()
        let outside = harness.directory.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            atPath: harness.root.appendingPathComponent("events").path,
            withDestinationPath: outside.path)
        let store = harness.makeStore()
        await expectStoreError(.corruption(.symlinkEncountered)) { try await store.bootstrap() }
    }

    func testForeignRegularEntryIsUnexpectedCorruption() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        _ = try await harness.bootFresh()
        try Data("x".utf8).write(to: harness.root.appendingPathComponent("notes.txt"))
        await expectStoreError(.corruption(.unexpectedEntry)) {
            try await harness.makeStore().bootstrap()
        }
    }

    func testReferencedObjectMissingOrTamperedIsCorruption() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        let entry = try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        let url = harness.root.appendingPathComponent(entry.locator.fileName)
        try FileManager.default.removeItem(at: url)
        await expectStoreError(.corruption(.referencedObjectMissing)) {
            try await harness.makeStore().bootstrap()
        }
        _ = try await store.put(identity: try objectIdentity("a"), payload: payloadA)
        var bytes = try Data(contentsOf: url)
        bytes[70] ^= 1
        try bytes.write(to: url)
        await expectStoreError(.corruption(.manifestUnreadable)) {
            try await harness.makeStore().bootstrap()
        }
    }

    func testDataDurableButManifestNotCommittedLeavesProvenOrphanCleanedOnReopen() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        try await store.put(identity: try objectIdentity("committed-a"), payload: payloadA)
        let injection = DurabilityInjection(
            failPhase: .data, failAt: .afterDirectoryFsync)
        await expectStoreError(.filesystem(.posix(
            operation: "injected-data-afterDirectoryFsync", code: ECANCELED))) {
            try await store.put(identity: try objectIdentity("uncommitted-b"),
                                payload: Data("b".utf8), injection: injection)
        }
        let filesAfterCrash = try harness.rootEntries().filter { $0 != "manifest.krenc" }
        XCTAssertEqual(filesAfterCrash.count, 2, "data file landed, manifest never referenced it")
        let reopened = harness.makeStore()
        let state = try await reopened.bootstrap()
        XCTAssertEqual(state, .opened)
        let a = try await reopened.read(try objectIdentity("committed-a"))
        XCTAssertEqual(a, payloadA)
        await expectStoreError(.unknownObject) {
            try await reopened.read(try objectIdentity("uncommitted-b"))
        }
        let entries = try await reopened.entries()
        XCTAssertEqual(entries.count, 1)
        let filesAfterReopen = try harness.rootEntries()
        XCTAssertEqual(filesAfterReopen.count, 2, "manifest plus the one committed object")
    }

    func testInjectedFailuresAtEveryDataBoundaryPreserveCommittedState() async throws {
        for boundary in [DurabilityBoundary.afterWrite, .afterFileFsync, .afterRename,
                         .afterDirectoryFsync] {
            let harness = try StoreHarness()
            defer { harness.cleanup() }
            let store = try await harness.bootFresh()
            try await store.put(identity: try objectIdentity("a"), payload: payloadA)
            let injection = DurabilityInjection(failPhase: .data, failAt: boundary)
            await expectStoreError(.filesystem(.posix(
                operation: "injected-data-\(boundary.rawValue)", code: ECANCELED))) {
                try await store.put(identity: try objectIdentity("b"),
                                    payload: Data("b".utf8), injection: injection)
            }
            let reopened = harness.makeStore()
            let state = try await reopened.bootstrap()
            XCTAssertEqual(state, .opened, "boundary \(boundary.rawValue)")
            let a = try await reopened.read(try objectIdentity("a"))
            XCTAssertEqual(a, payloadA)
            await expectStoreError(.unknownObject) {
                try await reopened.read(try objectIdentity("b"))
            }
        }
    }

}

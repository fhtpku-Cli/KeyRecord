import Foundation
import XCTest
import KeyRecordTestSupport
@testable import KeyRecordStore

@MainActor
final class NonceWindowTests: XCTestCase {
    func testObjectStoreRetainsOnlyNonHistoryStateAfterRepeatedWrites() async throws {
        // Given: a real store with fake keys, never the system Keychain.
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let store = try await harness.bootFresh()
        let identity = try objectIdentity("nonce-state-contract")
        // When: multiple encryptions complete on the same actor.
        for _ in 0..<8 {
            _ = try await store.put(identity: identity, payload: Data([1]))
        }
        let fields = await store.storedPropertyNamesForNonceContract()
        // Then: the compiled actor has only the reviewed non-history state slots.
        // An added cache fails even if it is renamed or initially empty.
        XCTAssertEqual(fields, Set([
            "root", "fileSystem", "keySource", "journalSource", "configuredMigrationInjection",
            "phase", "manifestBox", "materialCache", "unresolvedArtifacts", "lease",
            "cycleJournals", "configuredResetInjection", "$defaultActor"
        ]))
    }

    func testProductionSourcesDoNotOwnNonceDiagnostics() throws {
        // Given: all shipped source files, excluding tests and historical Spikes.
        let files = try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Sources"))
        XCTAssertFalse(files.isEmpty)
        // When/Then: neither the diagnostic type nor its recording path is shipped.
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertNil(source.range(of: #"\bNonceReuseDetector\b"#, options: .regularExpression), file.path)
            if file.lastPathComponent == "ObjectStore.swift" {
                XCTAssertNil(source.range(of: #"\bnonces\s*\.\s*record\s*\("#,
                                          options: .regularExpression), file.path)
            }
        }
    }
}

private extension ObjectStore {
    func storedPropertyNamesForNonceContract() -> Set<String> {
        Set(Mirror(reflecting: self).children.compactMap(\.label))
    }
}

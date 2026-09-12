import Foundation
import XCTest
import KeyRecordCore
import KeyRecordTestSupport
@testable import KeyRecordStore

@MainActor
final class KeyringBoundaryTests: XCTestCase {
    func testMissingCurrentDuringScanCannotDeleteRecoveryKey() async throws {
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        await f.references.removeAtScan(f.backend, id: f.key(v2))
        await expectKeyringError(.missingKey(v2)) { try await f.ring.rotate(to: v2) }
        let events = await f.trace.events
        XCTAssertFalse(events.contains("mark"))
        XCTAssertFalse(events.contains("delete"))
    }

    func testRootSourcesHaveZeroKeychainEffectsAndIsolatedEntropy() throws {
        let files = try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Sources"))
        XCTAssertFalse(files.isEmpty)
        var entropyFiles: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in ["SecItemAdd", "SecItemDelete", "SecItemUpdate", "SecItemCopyMatching", "dlopen", "dlsym"] {
                XCTAssertFalse(text.contains(symbol), "Unexpected effect in \(file.lastPathComponent)")
            }
            if text.contains("SecRandomCopyBytes") { entropyFiles.append(file.lastPathComponent) }
            if file.path.contains("KeyRecordStore"), file.lastPathComponent != "SystemMasterMaterial.swift" {
                XCTAssertFalse(try SourceInspection.imports(in: text).contains("Security"))
                for symbol in ["print(", "NSLog(", "Logger(", "AfterFirstUnlock", "Phase0Support"] {
                    XCTAssertFalse(text.contains(symbol), "Unsafe boundary in \(file.lastPathComponent)")
                }
            }
            if file.path.contains("KeyRecordStore") { XCTAssertLessThan(text.split(separator: "\n", omittingEmptySubsequences: false).count, 250) }
        }
        XCTAssertEqual(entropyFiles, ["SystemMasterMaterial.swift"])
    }

    func testStrictMetadataRejectsUnknownFieldsSchemaVersionsAndInvalidSets() {
        for json in [
            #"{"current":1,"current":1,"retirementPending":[],"schema":1,"versions":[1]}"#,
            #"{"schema":2,"current":1,"versions":[1],"retirementPending":[]}"#,
            #"{"schema":1,"current":0,"versions":[0],"retirementPending":[]}"#,
            #"{"schema":1,"current":1,"versions":[1,1],"retirementPending":[]}"#,
            #"{"schema":1,"current":1,"versions":[1],"retirementPending":[1]}"#,
            #"{"schema":1,"current":1,"versions":[1],"retirementPending":[],"unknown":true}"#,
            #"{"schema":1,"current":4294967296,"versions":[1],"retirementPending":[]}"#,
            #"{"schema":1,"current":2,"versions":[1,2],"retirementPending":[]}"#,
            #"{"schema":1,"current":2,"versions":[1,2],"retirementPending":[],"rotationFrom":1}"#,
            #"{"schema":1,"current":2,"versions":[1,2],"retirementPending":[1,1],"rotationFrom":1,"rotationTo":2}"#
        ] {
            XCTAssertThrowsError(try KeyringMetadata.decode(Data(json.utf8))) {
                XCTAssertEqual($0 as? KeyringError, .corruptMetadata)
            }
        }
    }

    func testAllProtectedReferenceKindsIndependentlyBlockRetirement() async throws {
        for kind in ProtectedReferenceKind.allCases {
            let f = KeyringFixture()
            _ = try await f.ring.bootstrap()
            await f.references.set([.known(kind, v1)])
            await expectKeyringError(.versionReferenced(v1)) { try await f.ring.rotate(to: v2) }
            let events = await f.trace.events
            XCTAssertFalse(events.contains("mark"))
            XCTAssertFalse(events.contains("delete"))
        }
    }

    func testUnknownReferenceVersionBlocksEvenAfterMigration() async throws {
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        await f.references.set([.known(.unfinishedJournal, KeyVersion(rawValue: 99))])
        await expectKeyringError(.unknownReferences) { try await f.ring.rotate(to: v2) }
        let events = await f.trace.events
        XCTAssertFalse(events.contains("delete"))
    }

    func testExpiredConsentProofAndInvalidNamespaceAreRejected() async {
        let f = KeyringFixture()
        await f.state.set(KeyringCreationState(consent: true, store: .fresh, validUntil: Date(timeIntervalSince1970: 99)))
        await expectKeyringError(.creationDenied) { try await f.ring.bootstrap() }
        for namespace in ["", "contains space", "a/b", "a\u{0}b"] {
            XCTAssertThrowsError(try KeychainNamespace(namespace))
        }
    }

    func testUnknownOrCorruptCandidateCannotBePublishedOrDeleted() async throws {
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        await f.backend.seed(f.key(v2), bytes: Data([1]))
        await expectKeyringError(.corruptKey(v2)) { try await f.ring.rotate(to: v2) }
        await expectKeyringError(.corruptKey(v2)) { try await f.ring.removePendingCandidate(v2) }
        let events = await f.trace.events
        XCTAssertFalse(events.contains("delete"))
    }

    func testDeletingReferencedOrUnknownCandidateIsForbidden() async throws {
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        await f.backend.seed(f.key(v2), bytes: Data(repeating: 4, count: 32))
        await f.references.set([.known(.ownedTemporaryOrOrphan, v2)])
        await expectKeyringError(.versionReferenced(v2)) { try await f.ring.removePendingCandidate(v2) }
        await expectKeyringError(.invalidVersion) { try await f.ring.removePendingCandidate(v1) }
        await f.references.set([.unreadable(.unfinishedJournal)])
        await expectKeyringError(.unknownReferences) { try await f.ring.removePendingCandidate(v2) }
    }
}

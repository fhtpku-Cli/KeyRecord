import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class KeyringTests: XCTestCase {
    func testCreatesOnlyConsentedFreshStoreWithCandidatePolicy() async throws {
        // Given
        let f = KeyringFixture()
        // When
        let metadata = try await f.ring.bootstrap()
        // Then
        XCTAssertEqual(metadata.current, v1)
        let additions = await f.backend.additions
        XCTAssertEqual(additions.count, 1)
        XCTAssertEqual(additions.first?.material.count, 32)
        XCTAssertEqual(additions.first?.id, f.key(v1))
        XCTAssertEqual(additions.first?.policy, .candidateWhenUnlockedThisDeviceOnly)
        XCTAssertEqual(additions.first?.synchronizable, false)
    }

    func testDeniesCreationWithoutConsentOrFreshProof() async {
        for state in [KeyringCreationState(consent: false, store: .fresh),
                      KeyringCreationState(consent: true, store: .existing),
                      KeyringCreationState(consent: true, store: .unknown)] {
            // Given
            let f = KeyringFixture()
            await f.state.set(state)
            // When / Then
            await expectKeyringError(.creationDenied) { try await f.ring.bootstrap() }
            let count = await f.backend.additions.count
            XCTAssertEqual(count, 0)
        }
    }

    func testDeniedEntropyDoesNotCreateOrPublish() async {
        // Given
        let f = KeyringFixture(entropyDenied: true)
        // When / Then
        await expectKeyringError(.entropyDenied) { try await f.ring.bootstrap() }
        let items = await f.backend.items
        XCTAssertTrue(items.isEmpty)
    }

    func testDuplicateItemIsNotOverwritten() async {
        // Given
        let f = KeyringFixture()
        await f.backend.forceDuplicate()
        // When / Then
        await expectKeyringError(.duplicateItem) { try await f.ring.bootstrap() }
        let items = await f.backend.items
        XCTAssertTrue(items.isEmpty)
    }

    func testExistingNamespaceIsNotFresh() async {
        // Given
        let f = KeyringFixture()
        await f.backend.seed(f.key(v1), bytes: Data(repeating: 3, count: 32))
        // When / Then
        await expectKeyringError(.creationDenied) { try await f.ring.bootstrap() }
        let additions = await f.backend.additions
        XCTAssertTrue(additions.isEmpty)
    }

    func testMissingOrCorruptRequiredCurrentAndHistoricalKeysFailClosed() async throws {
        for version in [v1, v2] {
            for bytes: Data? in [nil, Data([1, 2])] {
                // Given: both versions retained after publication; no retirement yet.
                let f = KeyringFixture()
                _ = try await f.ring.bootstrap()
                await f.references.fail("migrate")
                do { try await f.ring.rotate(to: v2); XCTFail("Expected crash") } catch is SimulatedCrash {}
                await f.backend.seed(f.key(version), bytes: bytes)
                // When / Then: even reading the other version must fail closed.
                let expected: KeyringError = bytes == nil ? .missingKey(version) : .corruptKey(version)
                await expectKeyringError(expected) { try await f.reopen().open() }
                let additions = await f.backend.additions.count
                XCTAssertEqual(additions, 2)
            }
        }
    }

    func testMalformedMetadataNeverAuthorizesReplacement() async {
        // Given
        let f = KeyringFixture()
        await f.backend.seed(f.metadataID, bytes: Data("{broken".utf8))
        // When / Then
        await expectKeyringError(.corruptMetadata) { try await f.ring.open() }
        await expectKeyringError(.creationDenied) { try await f.ring.bootstrap() }
        let additions = await f.backend.additions.count
        XCTAssertEqual(additions, 0)
    }

    func testRotationFollowsCompleteContractOrder() async throws {
        // Given
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        // When
        try await f.ring.rotate(to: v2)
        // Then
        let events = await f.trace.events
        XCTAssertEqual(events, ["add", "bootstrap", "add", "publish", "migrate", "reencrypt",
                                "reconcile", "scan", "mark", "delete", "remove"])
        let recovered = try await f.ring.open()
        XCTAssertEqual(recovered.metadata.versions, [v2])
    }

    func testJournalReferenceBlocksRetirementAfterManifestMigration() async throws {
        // Given: no live entries, but unfinished reset journal references old material.
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        await f.references.set([.known(.journalRecoveryObject, v1)])
        // When / Then
        await expectKeyringError(.versionReferenced(v1)) { try await f.ring.rotate(to: v2) }
        let old = try await f.backend.read(f.key(v1))
        XCTAssertEqual(old?.count, 32)
        let metadata = try await f.ring.open().metadata
        XCTAssertEqual(metadata.current, v2)
        XCTAssertEqual(metadata.versions, [v1, v2])
    }

    func testUnreadableOrIncompleteReferenceSetBlocksRetirement() async throws {
        for incomplete in [true, false] {
            // Given
            let f = KeyringFixture()
            _ = try await f.ring.bootstrap()
            if incomplete { await f.references.incomplete() }
            else { await f.references.set([.unreadable(.ownedTemporaryOrOrphan)]) }
            // When / Then
            await expectKeyringError(.unknownReferences) { try await f.ring.rotate(to: v2) }
            let events = await f.trace.events
            XCTAssertFalse(events.contains("delete"))
        }
    }
}

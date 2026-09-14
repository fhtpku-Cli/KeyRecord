import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class KeyringRecoveryTests: XCTestCase {
    func testBootstrapCrashKeepsOwnedCandidateWithoutAutomaticPublication() async throws {
        for after in [false, true] {
            // Given
            let f = KeyringFixture()
            await f.backend.fail("bootstrap", after: after)
            do { _ = try await f.ring.bootstrap(); XCTFail("Expected crash") } catch is SimulatedCrash {}
            // When / Then
            if after {
                let state = try await f.reopen().open()
                XCTAssertEqual(state.metadata.current, v1)
            } else {
                await expectKeyringError(.unpublishedCandidates([v1])) { try await f.reopen().open() }
                await expectKeyringError(.creationDenied) { try await f.reopen().bootstrap() }
            }
            let count = await f.backend.additions.count
            XCTAssertEqual(count, 1)
        }
    }

    func testEveryAtomicRotationCrashBoundaryRecoversWithoutReplacingKeys() async throws {
        for event in ["add", "publish", "mark", "delete", "remove"] {
            for after in [false, true] {
                // Given
                let f = KeyringFixture()
                _ = try await f.ring.bootstrap()
                await f.backend.fail(event, after: after)
                do { try await f.ring.rotate(to: v2); XCTFail("Expected crash") } catch is SimulatedCrash {}
                let reopened = f.reopen()
                let state = try await reopened.open()
                if event == "add" || (event == "publish" && !after) {
                    XCTAssertEqual(state.metadata.current, v1)
                    XCTAssertEqual(state.pendingCandidates, event == "add" && !after ? [] : [v2])
                }
                // When: explicit retry reuses owned candidate, never creates a replacement.
                if state.metadata.current == v1 { try await reopened.rotate(to: v2) }
                else { try await reopened.resumeRotation() }
                // Then
                let final = try await reopened.open()
                XCTAssertEqual(final.metadata.versions, [v2])
                let count = await f.backend.additions.count
                XCTAssertEqual(count, 2)
            }
        }
    }

    func testMigrationReencryptionAndReconciliationFailuresKeepBothKeys() async throws {
        for event in ["migrate", "reencrypt", "reconcile", "scan"] {
            // Given
            let f = KeyringFixture()
            _ = try await f.ring.bootstrap()
            await f.references.fail(event)
            do { try await f.ring.rotate(to: v2); XCTFail("Expected crash") } catch is SimulatedCrash {}
            let recovered = try await f.reopen().open()
            XCTAssertEqual(recovered.metadata.versions, [v1, v2])
            // When
            try await f.reopen().resumeRotation()
            // Then
            let final = try await f.reopen().open()
            XCTAssertEqual(final.metadata.versions, [v2])
        }
    }

    func testRetirementPendingMustRescanBeforeDeleteEvenWhenKeyMissing() async throws {
        for missing in [false, true] {
            // Given
            let f = KeyringFixture()
            _ = try await f.ring.bootstrap()
            await f.backend.fail("delete", after: false)
            do { try await f.ring.rotate(to: v2); XCTFail("Expected crash") } catch is SimulatedCrash {}
            if missing { await f.backend.seed(f.key(v1), bytes: nil) }
            await f.references.set([.known(.unfinishedJournal, v1)])
            // When / Then
            await expectKeyringError(.versionReferenced(v1)) { try await f.reopen().resumeRotation() }
            let events = await f.trace.events
            XCTAssertFalse(events.contains("delete"))
        }
    }

    func testPendingCandidateCannotReplaceMissingCurrentKey() async throws {
        // Given
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        await f.backend.fail("publish", after: false)
        do { try await f.ring.rotate(to: v2); XCTFail("Expected crash") } catch is SimulatedCrash {}
        await f.backend.seed(f.key(v1), bytes: nil)
        // When / Then
        await expectKeyringError(.missingKey(v1)) { try await f.reopen().rotate(to: v2) }
        let count = await f.backend.additions.count
        XCTAssertEqual(count, 2)
    }

    func testCleanupOnlyDeletesUnreferencedOwnedCandidate() async throws {
        // Given
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        await f.backend.fail("publish", after: false)
        do { try await f.ring.rotate(to: v2); XCTFail("Expected crash") } catch is SimulatedCrash {}
        let other = try KeychainNamespace("com.keyrecord.tests.keyring.other")
        await f.backend.seed(.key(other, v2), bytes: Data(repeating: 9, count: 32))
        // When
        try await f.reopen().removePendingCandidate(v2)
        // Then
        let items = await f.backend.items
        XCTAssertNil(items[f.key(v2)])
        XCTAssertNotNil(items[f.key(v1)])
        XCTAssertNotNil(items[.key(other, v2)])
    }
}

import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class KeyringLockTests: XCTestCase {
    func testEveryRotationCallbackIsFencedAndWriterExcludesReset() async throws {
        for event in ["migrate", "reencrypt", "reconcile", "scan"] {
            let f = KeyringFixture()
            _ = try await f.ring.bootstrap()
            await f.references.pauseAt(event)
            let rotation = Task { try await f.ring.rotate(to: v2) }
            await f.references.waitForPause()
            await expectKeyringError(.busy) { try await f.ring.open() }
            await expectKeyringError(.busy) { try await f.reopen().open() }
            f.gate.update(.unknown)
            f.gate.update(.unlocked)
            await f.references.resume()
            await expectKeyringError(.staleGeneration) { try await rotation.value }
            let events = await f.trace.events
            XCTAssertFalse(events.contains("mark"))
            XCTAssertFalse(events.contains("delete"))
            let active = await f.references.active
            XCTAssertFalse(active)
        }
    }

    func testLockAtReleaseDoesNotReleaseLeaseTwice() async throws {
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        let before = await f.references.releaseCount
        await f.references.lockOnRelease(f.gate)
        await expectKeyringError(.staleGeneration) { try await f.ring.open() }
        let after = await f.references.releaseCount
        XCTAssertEqual(after - before, 1)
    }

    func testUnknownInitiallyDeniesProtectedOperations() async {
        // Given
        let f = KeyringFixture()
        f.gate.update(.unknown)
        // When / Then
        await expectKeyringError(.locked) { try await f.ring.bootstrap() }
        let count = await f.backend.additions.count
        XCTAssertEqual(count, 0)
    }

    func testLockedReadCompletionIsCancelledWithoutPlaintextPublication() async throws {
        // Given
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        let handle = try await f.ring.handle(for: v1)
        await f.backend.delayNextRead()
        let read = Task { try await f.ring.withMaterial(handle) { _ in XCTFail("Stale plaintext callback"); return 1 } }
        await f.backend.waitForRead()
        // When
        f.gate.update(.locked)
        f.gate.update(.unlocked)
        await f.backend.resumeRead()
        // Then
        await expectKeyringError(.staleGeneration) { try await read.value }
        let cancelled = await f.backend.cancellationObserved
        XCTAssertTrue(cancelled)
        await expectKeyringError(.staleGeneration) { try await f.ring.withMaterial(handle) { $0.count } }
    }

    func testFreshChecksAndHandleRequiredAfterUnlock() async throws {
        // Given
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        f.gate.update(.locked)
        f.gate.update(.unlocked)
        await f.backend.seed(f.key(v1), bytes: nil)
        // When / Then
        await expectKeyringError(.missingKey(v1)) { try await f.ring.handle(for: v1) }
    }

    func testGenerationOverflowRemainsClosed() {
        // Given
        let gate = KeyAvailabilityGate(generation: CaptureGeneration(rawValue: .max))
        // When
        gate.update(.unlocked)
        // Then
        XCTAssertThrowsError(try gate.begin()) { XCTAssertEqual($0 as? KeyringError, .locked) }
    }
}

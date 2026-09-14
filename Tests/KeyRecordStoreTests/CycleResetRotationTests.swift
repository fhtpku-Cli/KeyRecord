import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

actor SuspendingObjectKeys: ObjectStoreKeySource {
    private let wrapped: BackedObjectKeys
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var didSuspend = false
    private var armed = false

    init(wrapped: BackedObjectKeys) { self.wrapped = wrapped }

    func arm() async { armed = true }

    // Park on namespaceKeyVersions(): post-bootstrap material cache makes material(for:) uncalled.
    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        if armed, !didSuspend {
            didSuspend = true
            started?.resume()
            started = nil
            await withCheckedContinuation { continuation = $0 }
        }
        return try await wrapped.namespaceKeyVersions()
    }

    func material(for version: KeyVersion) async throws -> Data {
        try await wrapped.material(for: version)
    }

    func waitForVersions() async {
        if didSuspend { return }
        await withCheckedContinuation { started = $0 }
    }

    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
final class CycleResetRotationTests: XCTestCase {
    private func makeWiring(
        keySource: (RotationBackend, KeychainNamespace) -> ObjectStoreKeySource
    ) async throws -> (StoreHarness, RotationBackend, KeychainKeyring, KeyAvailabilityGate, ObjectStore, KeychainNamespace) {
        let harness = try StoreHarness()
        let namespace = try KeychainNamespace("com.keyrecord.tests.reset-rotation-\(UUID().uuidString)")
        let backend = RotationBackend()
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let store = ObjectStore(root: harness.root, keySource: keySource(backend, namespace))
        let ring = KeychainKeyring(
            configuration: KeyringConfiguration(namespace: namespace),
            ports: KeyringPorts(backend: backend, entropy: RotationEntropy(),
                                creation: FreshConsent(), references: store,
                                clock: FakeKeyringClock()),
            gate: gate)
        return (harness, backend, ring, gate, store, namespace)
    }

    private func seedV2(_ backend: RotationBackend, namespace: KeychainNamespace) async throws {
        try await backend.add(KeychainItem(
            id: .key(namespace, v2), material: Data(repeating: 8, count: 32),
            policy: .candidateWhenUnlockedThisDeviceOnly))
    }

    private func bootResetFixture(_ harness: StoreHarness, _ backend: RotationBackend,
                                  _ ring: KeychainKeyring, _ store: ObjectStore) async throws {
        let state = try await store.bootstrap()
        XCTAssertEqual(state, .freshInstall)
        _ = try await ring.bootstrap()
        try await store.initializeFreshInstallation()
        _ = try await seedReset(store)
    }

    func testActiveResetSerializesAgainstKeyringRotation() async throws {
        // Given: a reset suspended inside the store lease.
        let namespace = try KeychainNamespace("com.keyrecord.tests.reset-serial-\(UUID().uuidString)")
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let backend = RotationBackend()
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let suspender = SuspendingObjectKeys(
            wrapped: BackedObjectKeys(backend: backend, namespace: namespace))
        let store = ObjectStore(root: harness.root, keySource: suspender)
        let ring = KeychainKeyring(
            configuration: KeyringConfiguration(namespace: namespace),
            ports: KeyringPorts(backend: backend, entropy: RotationEntropy(),
                                creation: FreshConsent(), references: store,
                                clock: FakeKeyringClock()),
            gate: gate)
        _ = try await store.bootstrap()
        _ = try await ring.bootstrap()
        try await store.initializeFreshInstallation()
        _ = try await seedReset(store)
        await suspender.arm()
        let resetTask = Task {
            try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        }
        await suspender.waitForVersions()
        // When: rotation (and any keyring op) arrives while reset owns the store lease.
        do {
            try await ring.rotate(to: v2)
            XCTFail("expected busy while reset owns the lease")
        } catch KeyringError.busy {}
        // Then: rotation completes normally once reset converges.
        await suspender.resume()
        let next = try await resetTask.value
        try await assertReset(store, next: next)
        try await seedV2(backend, namespace: namespace)
        try await ring.rotate(to: v2)
        let versions = try await backend.versions(in: namespace)
        XCTAssertEqual(versions, [v2])
    }

    func testPendingJournalUnderOldKeyBlocksRetirementReferenceSet() async throws {
        // Given: a reset interrupted with its journal sealed under v1.
        let wiring = try await makeWiring { BackedObjectKeys(backend: $0, namespace: $1) }
        defer { wiring.0.cleanup() }
        let (harness, backend, ring, gate, store, namespace) = wiring
        try await bootResetFixture(harness, backend, ring, store)
        do {
            _ = try await store.resetCycle(
                operationID: resetOperation, day: LocalDay("2026-09-13"),
                injection: CycleResetInjection(
                    summaryWrite: DurabilityInjection(failPhase: .data, failAt: .afterRename)))
            XCTFail("expected injected failure")
        } catch ObjectStoreError.filesystem {}
        try await seedV2(backend, namespace: namespace)
        // When: ordinary entries migrate to v2 but the journal is still under v1.
        let session = try await store.acquireExclusiveAccess()
        let generation = try gate.begin()
        let access = ring.access(generation, versions: [v1, v2])
        let rotation = KeyRotation(from: v1, to: v2)
        try await session.migrateData(rotation, access: access)
        let blocked = try await session.scan(access: access)
        // Then: the real reference set names v1 through the unfinished-journal seam.
        let kinds = blocked.references.compactMap { reference -> ProtectedReferenceKind? in
            guard case let .known(kind, version) = reference, version == v1 else { return nil }
            return kind
        }
        XCTAssertTrue(kinds.contains(.unfinishedJournal))
        XCTAssertEqual(try blocked.requiredVersions(), [v1, v2])
        // And: after journal re-encryption the old key is no longer required.
        try await session.reencryptManifestAndJournals(rotation, access: access)
        try await session.recoverAndReconcile(access: access)
        let clear = try await session.scan(access: access)
        XCTAssertEqual(try clear.requiredVersions(), [v2])
        await session.release()
        // And: the pending reset still converges after rotation finished.
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-13"))
        try await assertReset(store, next: next)
    }

    func testFullRotationAroundPendingResetThenResetConverges() async throws {
        // Given: a crashed reset journal under v1 and a complete rotation to v2.
        let wiring = try await makeWiring { BackedObjectKeys(backend: $0, namespace: $1) }
        defer { wiring.0.cleanup() }
        let (harness, backend, ring, _, store, namespace) = wiring
        try await bootResetFixture(harness, backend, ring, store)
        do {
            _ = try await store.resetCycle(
                operationID: resetOperation, day: LocalDay("2026-09-13"),
                injection: CycleResetInjection(
                    summaryWrite: DurabilityInjection(failPhase: .manifest, failAt: .afterWrite)))
            XCTFail("expected injected failure")
        } catch ObjectStoreError.filesystem {}
        try await seedV2(backend, namespace: namespace)
        // When: rotation runs to completion with the pending journal present.
        try await ring.rotate(to: v2)
        // Then: v1 is retired, the journal migrated, and the reset resumes under v2.
        let versions = try await backend.versions(in: namespace)
        XCTAssertEqual(versions, [v2])
        let next = try await store.resetCycle(operationID: resetOperation, day: LocalDay("2026-09-14"))
        try await assertReset(store, next: next)
        let reopened = ObjectStore(root: harness.root,
                                   keySource: BackedObjectKeys(backend: backend, namespace: namespace))
        _ = try await reopened.bootstrap()
        try await assertReset(reopened, next: next)
    }
}

import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class KeyringDestructionFenceTests: XCTestCase {
    func testVersionReadRevocationPreventsFollowingDeletion() async throws {
        for reopen in [false, true] {
            let (ring, backend) = makeRing(boundary: .read, reopen: reopen)
            await expectKeyringError(.staleGeneration) {
                try await ring.deleteOwnedVersionForDestruction(v1)
            }
            let calls = await backend.calls
            XCTAssertEqual(calls, ["read"], "No delete may follow a revoked read")
        }
    }

    func testMetadataReadRevocationPreventsFollowingDeletion() async throws {
        for reopen in [false, true] {
            let (ring, backend) = makeRing(boundary: .read, reopen: reopen)
            await expectKeyringError(.staleGeneration) {
                try await ring.deleteOwnedMetadataForDestruction()
            }
            let calls = await backend.calls
            XCTAssertEqual(calls, ["read"], "No metadata delete may follow a revoked read")
        }
    }

    func testInventoryRevocationPreventsFollowingMetadataRead() async throws {
        for reopen in [false, true] {
            let (ring, backend) = makeRing(boundary: .inventory, reopen: reopen)
            await expectKeyringError(.staleGeneration) { try await ring.destructionInventory() }
            let calls = await backend.calls
            XCTAssertEqual(calls, ["inventory"], "No metadata read may follow a revoked inventory")
        }
    }

    func testUnrevokedDestructionRetainsExactOperations() async throws {
        let (ring, backend) = makeRing(boundary: nil, reopen: false)
        let versions = try await ring.destructionInventory()
        XCTAssertEqual(versions, [v1])
        let outcome = try await ring.deleteOwnedVersionForDestruction(v1)
        XCTAssertEqual(outcome, .succeeded)
        try await ring.deleteOwnedMetadataForDestruction()
        let calls = await backend.calls
        XCTAssertEqual(calls, ["inventory", "read", "read", "delete:master-v1", "read", "delete:metadata"])
    }

    func testMissingItemsConvergeWithoutDeletionCalls() async throws {
        let (ring, backend) = makeRing(boundary: nil, reopen: false, missing: true)
        let outcome = try await ring.deleteOwnedVersionForDestruction(v1)
        XCTAssertEqual(outcome, .missingKeyDuringDeletion(v1.rawValue))
        try await ring.deleteOwnedMetadataForDestruction()
        let calls = await backend.calls
        XCTAssertEqual(calls, ["read", "read"])
    }

    private func makeRing(boundary: DestructionBoundary?, reopen: Bool, missing: Bool = false)
        -> (KeychainKeyring, RevokingDestructionBackend) {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let backend = RevokingDestructionBackend(gate: gate, boundary: boundary, reopen: reopen, missing: missing)
        let ring = KeychainKeyring(configuration: KeyringConfiguration(
            namespace: try! KeychainNamespace("com.keyrecord.tests.destruction-fence")),
            ports: KeyringPorts(backend: backend, entropy: FakeEntropy(), creation: FakeStoreState(),
                references: FakeReferences(trace: KeyringTrace()), clock: FakeKeyringClock()), gate: gate)
        return (ring, backend)
    }
}

private enum DestructionBoundary: Sendable { case read, inventory }

private actor RevokingDestructionBackend: KeychainBackend {
    let gate: KeyAvailabilityGate
    let boundary: DestructionBoundary?
    let reopen: Bool
    let missing: Bool
    private(set) var calls: [String] = []

    init(gate: KeyAvailabilityGate, boundary: DestructionBoundary?, reopen: Bool, missing: Bool) {
        self.gate = gate; self.boundary = boundary; self.reopen = reopen
        self.missing = missing
    }

    func read(_ id: KeychainItemID) throws -> Data? {
        calls.append("read")
        revoke(at: .read)
        if missing { return nil }
        return id.version == nil ? try KeyringMetadata(current: v1, versions: [v1]).encoded()
            : Data(repeating: 7, count: 32)
    }

    func versions(in namespace: KeychainNamespace) -> Set<KeyVersion> {
        calls.append("inventory")
        revoke(at: .inventory)
        return [v1]
    }

    func delete(_ id: KeychainItemID) { calls.append("delete:" + id.account) }
    func add(_ item: KeychainItem) throws { throw SimulatedCrash.interrupted }
    func publish(_ update: KeychainMetadataUpdate) throws { throw SimulatedCrash.interrupted }

    private func revoke(at stage: DestructionBoundary) {
        guard boundary == stage else { return }
        gate.update(.locked)
        if reopen { gate.update(.unlocked) }
    }
}

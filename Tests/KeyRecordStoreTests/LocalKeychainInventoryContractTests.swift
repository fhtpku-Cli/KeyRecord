import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

// Mirrors LocalKeychainBackend's no-enumeration inventory: versions() is derived from an
// exact metadata-item read plus at most one deterministic exact candidate probe. These
// tests prove KeychainKeyring bootstrap/open/rotation-recovery need no enumeration backend.
actor MetadataInventoryKeychain: KeychainBackend {
    var items: [KeychainItemID: Data] = [:]

    func seed(_ id: KeychainItemID, bytes: Data?) { items[id] = bytes }

    func read(_ id: KeychainItemID) async throws -> Data? { items[id] }

    func versions(in namespace: KeychainNamespace) async throws -> Set<KeyVersion> {
        guard let bytes = items[.metadata(namespace)] else {
            let first = KeyVersion(rawValue: 1)
            return items[.key(namespace, first)] == nil ? [] : [first]
        }
        let metadata = try KeyringMetadata.decode(bytes)
        var versions = metadata.versions
        if metadata.current.rawValue < UInt32.max {
            let candidate = KeyVersion(rawValue: metadata.current.rawValue + 1)
            if items[.key(namespace, candidate)] != nil { versions.insert(candidate) }
        }
        return versions
    }

    func add(_ item: KeychainItem) async throws {
        guard items[item.id] == nil else { throw KeyringError.duplicateItem }
        items[item.id] = item.material
    }

    func publish(_ update: KeychainMetadataUpdate) async throws {
        guard items[update.id] == update.expected else { throw KeyringError.metadataConflict }
        items[update.id] = update.replacement
    }

    func delete(_ id: KeychainItemID) async throws { items[id] = nil }
}

private struct InventoryHarness {
    let namespace = try! KeychainNamespace("com.keyrecord.tests.keyring.inventory")
    let backend: MetadataInventoryKeychain
    let state = FakeStoreState()
    let trace = KeyringTrace()
    let references: FakeReferences
    let gate = KeyAvailabilityGate()
    let ring: KeychainKeyring

    init() {
        backend = MetadataInventoryKeychain()
        references = FakeReferences(trace: trace)
        ring = KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace), ports: KeyringPorts(
            backend: backend, entropy: FakeEntropy(), creation: state,
            references: references, clock: FakeKeyringClock()), gate: gate)
        gate.update(.unlocked)
    }

    func reopen() -> KeychainKeyring {
        KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace), ports: KeyringPorts(
            backend: backend, entropy: FakeEntropy(), creation: state,
            references: references, clock: FakeKeyringClock()), gate: gate)
    }
}

@MainActor
final class LocalKeychainInventoryContractTests: XCTestCase {
    func testBootstrapCreatesExactKeyAndMetadataThenOpenRecovers() async throws {
        // Given an armed, consented fresh install backed by an exact-item inventory.
        let h = InventoryHarness()
        // When bootstrapping and reopening like a real launch.
        let created = try await h.ring.bootstrap()
        let reopened = try await h.reopen().open()
        // Then: one v1 key plus metadata durably exist and recovery sees exactly v1.
        XCTAssertEqual(created.current, v1)
        XCTAssertEqual(created.versions, [v1])
        XCTAssertEqual(reopened.metadata.current, v1)
        XCTAssertEqual(reopened.metadata.versions, [v1])
        let stored = await h.backend.items
        XCTAssertEqual(stored[.key(h.namespace, v1)]?.count, 32)
        XCTAssertNotNil(stored[.metadata(h.namespace)])
        let versions = try await h.backend.versions(in: h.namespace)
        XCTAssertEqual(versions, [v1])
    }

    func testStrandedFirstKeyWithoutMetadataBlocksBootstrapAndReportsCandidate() async throws {
        // Given a key item from a bootstrap that crashed before metadata publication.
        let h = InventoryHarness()
        await h.backend.seed(.key(h.namespace, v1), bytes: Data(repeating: 7, count: 32))
        // When / Then: bootstrap refuses to create over it and open names the unpublished candidate.
        await expectKeyringError(.creationDenied) { try await h.ring.bootstrap() }
        await expectKeyringError(.unpublishedCandidates([v1])) { try await h.ring.open() }
    }

    func testCorruptMetadataSurfacesFromInventory() async throws {
        // Given an unreadable metadata item.
        let h = InventoryHarness()
        await h.backend.seed(.metadata(h.namespace), bytes: Data([0x01, 0x02, 0x03]))
        // When / Then: inventory reads fail as corruptMetadata, never as an empty namespace.
        await expectKeyringError(.corruptMetadata) { try await h.backend.versions(in: h.namespace) }
    }

    func testInterruptedRotationCandidateDiscoveredByExactProbeAndCompletes() async throws {
        // Given rotation added master-v2 but crashed before publishing rotation metadata.
        let h = InventoryHarness()
        let v1Metadata = try KeyringMetadata(current: v1, versions: [v1]).encoded()
        await h.backend.seed(.metadata(h.namespace), bytes: v1Metadata)
        await h.backend.seed(.key(h.namespace, v1), bytes: Data(repeating: 7, count: 32))
        await h.backend.seed(.key(h.namespace, v2), bytes: Data(repeating: 7, count: 32))
        // When rotation resumes through the metadata-derived inventory.
        let ring = h.reopen()
        try await ring.rotate(to: v2)
        // Then: v2 is the sole surviving version, v1 was deleted, and recovery agrees.
        let surviving = try await h.backend.versions(in: h.namespace)
        XCTAssertEqual(surviving, [v2])
        let stored = await h.backend.items
        XCTAssertNil(stored[.key(h.namespace, v1)])
        XCTAssertEqual(stored[.key(h.namespace, v2)]?.count, 32)
        let recovered = try await h.reopen().open()
        XCTAssertEqual(recovered.metadata.current, v2)
        XCTAssertEqual(recovered.metadata.versions, [v2])
    }
}

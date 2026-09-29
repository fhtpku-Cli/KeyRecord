#if DEBUG
import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

private struct ProcessingProbe: Decodable, Sendable {
    let observed: ProtectedReadActivitySnapshot?
    init(from decoder: any Decoder) throws {
        observed = ProtectedReadActivity.process.snapshot
        let value = try decoder.singleValueContainer().decode(Int.self)
        if value < 0 { throw ManifestError.malformed }
    }
}

private struct UnusedProcessingKeys: ObjectStoreKeySource {
    func namespaceKeyVersions() throws -> Set<KeyVersion> { throw KeyringError.backendUnavailable }
    func material(for version: KeyVersion) throws -> Data { throw KeyringError.backendUnavailable }
}

final class ProtectedProcessingTests: XCTestCase {
    func testSealingAndKeyDerivationAreObservedWithoutADecryption() throws {
        let before = try XCTUnwrap(ProtectedReadActivity.process.snapshot)
        let sealed = try LocatorCodec.seal(identity: CycleResetObjects.preferences, payload: Data([1]),
                                           keyVersion: 1, material: Data(repeating: 12, count: 32))
        XCTAssertFalse(sealed.envelope.isEmpty)
        let after = try XCTUnwrap(ProtectedReadActivity.process.snapshot)
        XCTAssertGreaterThan(after.plaintextProcessingStarted, before.plaintextProcessingStarted)
        XCTAssertEqual(after.plaintextProcessingStarted - before.plaintextProcessingStarted,
                       after.plaintextProcessingCompleted - before.plaintextProcessingCompleted)
        XCTAssertEqual(after.decryptionStarted, before.decryptionStarted)
    }

    func testActualPayloadDecoderReportsInFlightAndThrowingCompletion() async throws {
        let store = ObjectStore(root: URL(fileURLWithPath: "/unused-processing-fixture"),
                                keySource: UnusedProcessingKeys())
        let before = try XCTUnwrap(ProtectedReadActivity.process.snapshot)
        let decoded = try await store.decodeStrict(ProcessingProbe.self, Data("1".utf8))
        XCTAssertEqual(decoded.observed?.plaintextProcessingStarted, before.plaintextProcessingStarted + 1)
        XCTAssertEqual(decoded.observed?.plaintextProcessingCompleted, before.plaintextProcessingCompleted)
        do {
            _ = try await store.decodeStrict(ProcessingProbe.self, Data("-1".utf8))
            XCTFail("Invalid payload was decoded")
        } catch ManifestError.malformed {}
        let after = try XCTUnwrap(ProtectedReadActivity.process.snapshot)
        XCTAssertEqual(after.plaintextProcessingStarted - before.plaintextProcessingStarted, 2)
        XCTAssertEqual(after.plaintextProcessingCompleted - before.plaintextProcessingCompleted, 2)
        XCTAssertEqual(after.decryptionStarted, before.decryptionStarted)
    }

    func testManifestValidationWithoutAnotherDecryptionIsObserved() throws {
        let manifest = try EncryptedManifest(currentKeyVersion: 1, entries: [])
        let bytes = try ManifestCoding.encode(manifest)
        let before = try XCTUnwrap(ProtectedReadActivity.process.snapshot)
        XCTAssertEqual(try ManifestCoding.decode(bytes), manifest)
        let after = try XCTUnwrap(ProtectedReadActivity.process.snapshot)
        XCTAssertGreaterThan(after.plaintextProcessingStarted, before.plaintextProcessingStarted)
        XCTAssertEqual(after.plaintextProcessingStarted - before.plaintextProcessingStarted,
                       after.plaintextProcessingCompleted - before.plaintextProcessingCompleted)
        XCTAssertEqual(after.decryptionStarted, before.decryptionStarted)
    }

    func testProtectionScopesRemainInFlightThroughTheirBodyAndRejectStaleWork() throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let generation = try gate.begin()
        let before = try XCTUnwrap(ProtectedReadActivity.process.snapshot)
        let pending = try XCTUnwrap(gate.use(generation) { ProtectedReadActivity.process.snapshot })
        XCTAssertEqual(pending.plaintextProcessingStarted, before.plaintextProcessingStarted + 1)
        XCTAssertEqual(pending.plaintextProcessingCompleted, before.plaintextProcessingCompleted)
        let completed = ProtectedReadActivity.process.snapshot
        gate.update(.locked)
        gate.update(.unlocked)
        XCTAssertThrowsError(try gate.use(generation) { XCTFail("Stale processing ran") })
        XCTAssertEqual(ProtectedReadActivity.process.snapshot, completed)
    }
}
#endif

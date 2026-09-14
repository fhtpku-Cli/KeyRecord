import Foundation
import XCTest
@testable import KeyRecordStore

/// Contract 6 (plan §fixed-implementation-contracts): the v1 envelope, HKDF labels, header
/// layout and 8 MiB bound are ported byte-for-byte from the measured SP6A primitive.
/// Golden bytes below were produced by the Spikes Phase0Support implementation itself;
/// the product package never imports or links Spikes, so equality here is cross-implement
/// compatibility evidence rather than shared-code reuse.
final class StorageCryptoVectorTests: XCTestCase {
    private let plaintext = Data("KR-SP6A-PLAINTEXT-CANARY-7f4c".utf8)
    private let objectID = Data("synthetic-object-42".utf8)
    private let masterMaterial = Data(0..<32)

    /// Golden SP6A vector, fixed 12-byte nonce 0x42 repeated; 64 header + 29 ciphertext + 16 tag.
    private let goldenEnvelope = "4b5236410101000000000007"
        + "b9c0bbfa794d054814fabaf3e3d88e33c732f72abcd020fb2ec0c06c49575f5b"
        + "424242424242424242424242"
        + "000000000000001d"
        + "cba5526576561e47432401b641b4a1be0e60f6cf19794a0f630d0b9c08dad33e"
        + "eb27b38f0c53d42f7f6ac7dbff"

    func testVectorLocatorAndDerivedKeysMatchMeasuredSP6A() throws {
        // Given: the measured SP6A master/objectID pair
        // When: deriving with the ported schedule
        let locator = StorageKeySchedule.locator(material: masterMaterial, objectID: objectID)
        let encryption = StorageKeySchedule.encryptionKey(material: masterMaterial)
        let locatorKey = StorageKeySchedule.locatorKey(material: masterMaterial)
        // Then: every byte matches the Spikes-recorded vectors.
        XCTAssertEqual(locator.hex, "b9c0bbfa794d054814fabaf3e3d88e33c732f72abcd020fb2ec0c06c49575f5b")
        XCTAssertEqual(encryption.withUnsafeBytes { Data($0) }.hex,
                       "16ff21d4588d0ac7b2fc81c8435c3dd7d1a04ba9131e6df82984a31004b366df")
        XCTAssertEqual(locatorKey.withUnsafeBytes { Data($0) }.hex,
                       "96b227fe014da32f44d66a8520099441bab23e870e9fc2104fb483a3c3f7c8d0")
    }

    func testVectorEnvelopeIsByteIdenticalToMeasuredSP6A() throws {
        // Given: the exact SP6A nonce/keyVersion/plaintext tuple
        let locator = StorageKeySchedule.locator(material: masterMaterial, objectID: objectID)
        let nonceBytes = Data(repeating: 0x42, count: 12)
        // When: sealing with the ported implementation
        let envelope = try AuthenticatedStorageEnvelope.seal(
            plaintext, material: masterMaterial, keyVersion: 7, locator: locator,
            nonce: .init(data: nonceBytes))
        // Then: the wire bytes are identical to the measured Spikes output.
        XCTAssertEqual(envelope.hex, goldenEnvelope)
        XCTAssertEqual(envelope.count, AuthenticatedStorageEnvelope.headerByteCount + plaintext.count + 16)
        XCTAssertEqual(try AuthenticatedStorageEnvelope.open(envelope, materials: [7: masterMaterial]), plaintext)
    }

    func testVectorHeaderLayoutIsExactlyTheMeasured64ByteAuthenticatedHeader() throws {
        // Given/When: a freshly sealed envelope
        let envelope = try makeEnvelope()
        let parsed = try AuthenticatedStorageEnvelope.parse(envelope)
        // Then: magic KR6A, wire v1, algorithm 1, reserved zero, UInt32 BE version at offset 8,
        // 32-byte locator at 12..<44, 12-byte nonce at 44..<56, UInt64 BE length at 56..<64.
        XCTAssertEqual(envelope.prefix(4), Data([0x4b, 0x52, 0x36, 0x41]))
        XCTAssertEqual(envelope[4], 1)
        XCTAssertEqual(envelope[5], 1)
        XCTAssertEqual(envelope[6...7], Data([0, 0]))
        XCTAssertEqual(parsed.header.keyVersion, 7)
        XCTAssertEqual(parsed.header.locator.count, 32)
        XCTAssertEqual(parsed.header.nonce.count, 12)
        XCTAssertEqual(parsed.header.ciphertextLength, UInt64(plaintext.count))
        XCTAssertEqual(AuthenticatedStorageEnvelope.headerByteCount, 64)
        XCTAssertEqual(AuthenticatedStorageEnvelope.lengthOffset, 56)
        XCTAssertEqual(AuthenticatedStorageEnvelope.maximumCiphertextBytes, 8 * 1_024 * 1_024)
    }

    func testVectorRandomNoncesAreFreshAcrossSeals() throws {
        // Given: diagnostic retention exists only within this test.
        var seen = Set<Data>()
        for _ in 0..<64 {
            // When: sealing with the production random nonce generator.
            let parsed = try AuthenticatedStorageEnvelope.parse(try makeEnvelope())
            // Then: every nonce has the wire length and is fresh in this sample.
            XCTAssertEqual(parsed.header.nonce.count, 12)
            XCTAssertTrue(seen.insert(parsed.header.nonce).inserted)
        }
    }

    func testRejectsTamperingAtEveryAuthenticatedRegion() throws {
        // Given: a valid envelope
        let envelope = try makeEnvelope()
        let parsed = try AuthenticatedStorageEnvelope.parse(envelope)
        // When: flipping one byte anywhere in header, ciphertext or tag
        // Then: open fails closed for every index.
        for index in [0, 4, 5, 8, 12, 63, 64,
                      AuthenticatedStorageEnvelope.headerByteCount + parsed.ciphertext.count,
                      envelope.count - 1] {
            var changed = envelope
            changed[index] ^= 1
            XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(changed, materials: [7: masterMaterial]),
                                 "index \(index)")
        }
    }

    func testRejectsWrongMissingAndFutureVersionKeysWithoutFallback() throws {
        let envelope = try makeEnvelope()
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(envelope, materials: [UInt32: Data]())) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .missingKeyVersion)
        }
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(
            envelope, materials: [7: Data(repeating: 0xAB, count: 32)]))
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(
            envelope, materials: [8: masterMaterial])) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .missingKeyVersion)
        }
    }

    func testRejectsMalformedMagicVersionAlgorithmOversizedLengthAndTruncation() throws {
        let envelope = try makeEnvelope()
        var wrongMagic = envelope; wrongMagic[0] = 0
        var wrongVersion = envelope; wrongVersion[4] = 2
        var wrongAlgorithm = envelope; wrongAlgorithm[5] = 2
        var reservedSet = envelope; reservedSet[7] = 1
        var oversizedLength = envelope
        oversizedLength[AuthenticatedStorageEnvelope.lengthOffset + 7] &+= 1
        for mutated in [wrongMagic, wrongVersion, wrongAlgorithm, reservedSet, oversizedLength] {
            XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(mutated, materials: [7: masterMaterial]))
        }
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(envelope.dropLast(), materials: [7: masterMaterial]))
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(
            Data(repeating: 0, count: 63), materials: [7: masterMaterial]))
    }

    func testRejectsZeroKeyVersionAndPlaintextOverEightMiB() throws {
        let locator = StorageKeySchedule.locator(material: masterMaterial, objectID: objectID)
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.seal(
            Data(), material: masterMaterial, keyVersion: 0, locator: locator)) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .invalidKeyVersion)
        }
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.seal(
            Data(count: 8 * 1_024 * 1_024 + 1), material: masterMaterial, keyVersion: 1, locator: locator)) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .invalidLength)
        }
    }

    func testRejectsLocatorOfWrongLength() throws {
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.seal(
            plaintext, material: masterMaterial, keyVersion: 1, locator: Data(count: 31))) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .invalidLength)
        }
    }

    func testRejectsNonceOutsideTwelveByteWireContract() throws {
        // Given: CryptoKit accepts a longer nonce, but the v1 wire requires 12 bytes.
        let nonceBytes = Data(repeating: 0x42, count: 16)
        let locator = StorageKeySchedule.locator(material: masterMaterial, objectID: objectID)
        // When/Then: sealing rejects it rather than changing the authenticated layout.
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.seal(
            plaintext, material: masterMaterial, keyVersion: 7, locator: locator,
            nonce: .init(data: nonceBytes))) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .invalidLength)
        }
    }

    private func makeEnvelope() throws -> Data {
        try AuthenticatedStorageEnvelope.seal(
            plaintext, material: masterMaterial, keyVersion: 7,
            locator: StorageKeySchedule.locator(material: masterMaterial, objectID: objectID))
    }
}

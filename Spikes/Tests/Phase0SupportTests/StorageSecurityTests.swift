import CryptoKit
import Foundation
import XCTest
@testable import Phase0Support

final class StorageSecurityTests: XCTestCase {
    private let plaintext = Data("KR-SP6A-PLAINTEXT-CANARY-7f4c".utf8)
    private let objectID = Data("synthetic-object-42".utf8)
    private let master = SymmetricKey(data: Data(0..<32))

    func testEnvelopeRoundTripAuthenticatesHeaderAndUsesTwelveByteNonce() throws {
        let locator = StorageKeySchedule.locator(masterKey: master, objectID: objectID)
        let envelope = try AuthenticatedStorageEnvelope.seal(plaintext, masterKey: master, keyVersion: 7, locator: locator)
        let parsed = try AuthenticatedStorageEnvelope.parse(envelope)

        XCTAssertEqual(try AuthenticatedStorageEnvelope.open(envelope, keys: [7: master]), plaintext)
        XCTAssertEqual(parsed.header.nonce.count, 12)
        XCTAssertEqual(parsed.header.locator, locator)
        XCTAssertEqual(parsed.header.keyVersion, 7)
        XCTAssertFalse(envelope.contains(plaintext))
    }

    func testEveryAuthenticatedRegionTamperFailsClosed() throws {
        let envelope = try makeEnvelope()
        let parsed = try AuthenticatedStorageEnvelope.parse(envelope)
        for index in [0, 5, 8, 12, AuthenticatedStorageEnvelope.headerByteCount - 1,
                      AuthenticatedStorageEnvelope.headerByteCount,
                      AuthenticatedStorageEnvelope.headerByteCount + parsed.ciphertext.count] {
            var changed = envelope
            changed[index] ^= 1
            XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(changed, keys: [7: master]), "index \(index)")
        }
    }

    func testWrongMissingAndDeletedVersionKeysFailWithoutFallback() throws {
        let envelope = try makeEnvelope()
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(envelope, keys: [:])) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .missingKeyVersion)
        }
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(envelope, keys: [7: SymmetricKey(size: .bits256)]))
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(envelope, keys: [8: master])) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .missingKeyVersion)
        }
    }

    func testMalformedVersionAlgorithmLengthAndTruncationReject() throws {
        let envelope = try makeEnvelope()
        for mutation in [
            { (bytes: inout Data) in bytes[4] = 2 },
            { (bytes: inout Data) in bytes[5] = 2 },
            { (bytes: inout Data) in bytes[AuthenticatedStorageEnvelope.lengthOffset + 7] &+= 1 },
        ] {
            var changed = envelope
            mutation(&changed)
            XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(changed, keys: [7: master]))
        }
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(envelope.dropLast(), keys: [7: master]))
        XCTAssertThrowsError(try AuthenticatedStorageEnvelope.open(Data(repeating: 0, count: 4), keys: [7: master]))
    }

    func testRandomNoncesAreUniqueAndDuplicateDetectorRejectsReuse() throws {
        var detector = NonceReuseDetector()
        var seen = Set<Data>()
        for _ in 0..<256 {
            let parsed = try AuthenticatedStorageEnvelope.parse(makeEnvelope())
            XCTAssertTrue(seen.insert(parsed.header.nonce).inserted)
            try detector.record(parsed.header.nonce, keyVersion: parsed.header.keyVersion)
        }
        let duplicate = try XCTUnwrap(seen.first)
        XCTAssertThrowsError(try detector.record(duplicate, keyVersion: 7)) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .duplicateNonce)
        }
    }

    func testHKDFLabelsSeparateKeysAndLocatorMatchesExpectedVector() {
        let encryption = StorageKeySchedule.encryptionKey(masterKey: master)
        let locatorKey = StorageKeySchedule.locatorKey(masterKey: master)
        XCTAssertNotEqual(encryption.withUnsafeBytes { Data($0) }, locatorKey.withUnsafeBytes { Data($0) })
        XCTAssertEqual(
            StorageKeySchedule.locator(masterKey: master, objectID: objectID).hex,
            "b9c0bbfa794d054814fabaf3e3d88e33c732f72abcd020fb2ec0c06c49575f5b"
        )
        XCTAssertEqual(StorageKeySchedule.opaquePath(locator: StorageKeySchedule.locator(masterKey: master, objectID: objectID)).split(separator: "/").count, 2)
    }

    func testPathAndPlaintextCanaryScanRejectSemanticOrLeakingStorage() throws {
        let locator = StorageKeySchedule.locator(masterKey: master, objectID: objectID)
        XCTAssertNoThrow(try StorageCanary.validate(relativePaths: [StorageKeySchedule.opaquePath(locator: locator)], files: [try makeEnvelope()], plaintextCanary: plaintext))
        XCTAssertThrowsError(try StorageCanary.validate(relativePaths: ["events/today.krenc"], files: [try makeEnvelope()], plaintextCanary: plaintext)) {
            XCTAssertEqual($0 as? StorageCanaryError, .semanticPath)
        }
        XCTAssertThrowsError(try StorageCanary.validate(relativePaths: [StorageKeySchedule.opaquePath(locator: locator)], files: [plaintext], plaintextCanary: plaintext)) {
            XCTAssertEqual($0 as? StorageCanaryError, .plaintextFound)
        }
    }

    func testAtomicWriteFailureLeavesNoPlaintextFallbackOrPartialTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("opaque.krenc")
        let envelope = try makeEnvelope()
        XCTAssertThrowsError(try EncryptedArtifactWriter.write(envelope, to: target, failAt: .beforeRename))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).contains { (try? Data(contentsOf: $0).contains(plaintext)) == true })
    }

    func testSecurityAuditRejectsUnresolvedMediumAndMissingRows() throws {
        let valid = SecurityAuditFixture.valid
        XCTAssertNoThrow(try SecurityAuditValidator.validate(valid))
        XCTAssertThrowsError(try SecurityAuditValidator.validate(valid.replacingOccurrences(of: "MED-1 | RESOLVED", with: "MED-1 | UNRESOLVED"))) {
            XCTAssertEqual($0 as? SecurityAuditError, .unresolvedSignificantFinding)
        }
        XCTAssertThrowsError(try SecurityAuditValidator.validate(valid.replacingOccurrences(of: "MED-1 | RESOLVED", with: "RENAMED-1 | UNRESOLVED"))) {
            XCTAssertEqual($0 as? SecurityAuditError, .unresolvedSignificantFinding)
        }
        XCTAssertThrowsError(try SecurityAuditValidator.validate(valid.replacingOccurrences(of: "| cleanup | PASS", with: "| cleanup-removed | PASS")))
    }

    private func makeEnvelope() throws -> Data {
        try AuthenticatedStorageEnvelope.seal(
            plaintext,
            masterKey: master,
            keyVersion: 7,
            locator: StorageKeySchedule.locator(masterKey: master, objectID: objectID)
        )
    }
}

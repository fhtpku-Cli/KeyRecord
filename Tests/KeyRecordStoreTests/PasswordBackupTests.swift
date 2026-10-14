import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

final class PasswordBackupTests: XCTestCase, @unchecked Sendable {
    func testOfficialArgon2idVector() throws {
        let key = try PasswordBackup.derive(password: Data("password".utf8), salt: Data("somesalt".utf8),
                                            memory: 256, iterations: 2, lanes: 1)
        XCTAssertEqual(key.map { String(format: "%02x", $0) }.joined(),
                       "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe")
    }

    func testPasswordArchiveIsRandomAuthenticatedAndIndependentOfLocalKeys() async throws {
        let source = try StoreHarness(); defer { source.cleanup() }
        let store = try await source.bootFresh()
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let objects = try ["preferences", "statistics", "mapping", "firmware-original"].map {
            BackupObject(identity: try objectIdentity(type: "com.keyrecord.\($0)", UUID().uuidString),
                         payload: Data("private-\($0)-canary".utf8))
        }
        for object in objects { _ = try await store.put(identity: object.identity, payload: object.payload) }
        let snapshot = try await store.backupSnapshot(gate: gate)
        let archive = try PasswordBackup.seal(snapshot, password: "密碼🔐-not-a-keychain-key")
        let other = try PasswordBackup.seal(snapshot, password: "密碼🔐-not-a-keychain-key")
        XCTAssertNotEqual(archive, other)
        XCTAssertNil(archive.range(of: Data("private-statistics-canary".utf8)))
        await source.keySource.remove(version: 1)
        XCTAssertEqual(try PasswordBackup.open(archive, password: "密碼🔐-not-a-keychain-key"), snapshot)
        XCTAssertThrowsError(try PasswordBackup.open(archive, password: "wrong")) {
            XCTAssertEqual($0 as? PasswordBackupError, .authenticationFailed)
        }
        for index in [28, archive.count - 1] {
            var damaged = archive; damaged[index] ^= 1
            XCTAssertThrowsError(try PasswordBackup.open(damaged, password: "密碼🔐-not-a-keychain-key"))
        }
        for index in [8, 12, 16, 20, 24] {
            var damaged = archive; damaged[index] ^= 0xff
            XCTAssertThrowsError(try PasswordBackup.open(damaged, password: "密碼🔐-not-a-keychain-key")) {
                XCTAssertEqual($0 as? PasswordBackupError, .unsupportedFormat)
            }
        }
        XCTAssertThrowsError(try PasswordBackup.open(archive.dropLast(), password: "密碼🔐-not-a-keychain-key"))
        XCTAssertThrowsError(try PasswordBackup.open(archive + Data([0]), password: "密碼🔐-not-a-keychain-key"))
    }

    func testRejectsInvalidPayloadsAndPasswords() throws {
        let object = BackupObject(identity: try objectIdentity("a"), payload: Data([1]))
        XCTAssertThrowsError(try PasswordBackup.seal([object], password: ""))
        XCTAssertThrowsError(try PasswordBackup.seal([object], password: String(repeating: "x", count: 1025)))
        XCTAssertThrowsError(try PasswordBackup.encode([object, object]))
        XCTAssertThrowsError(try PasswordBackup.encode([BackupObject(identity: .manifest, payload: Data([1]))]))
        XCTAssertThrowsError(try PasswordBackup.decode(Data([0xff, 0xff, 0xff, 0xff])))
        let valid = try PasswordBackup.encode([object])
        XCTAssertThrowsError(try PasswordBackup.decode(valid.dropLast()))
        XCTAssertThrowsError(try PasswordBackup.decode(valid + Data([0])))
    }

    func testRestorePublishesAllObjectsAndRefusesExistingData() async throws {
        let harness = try StoreHarness(); defer { harness.cleanup() }
        let store = try await harness.bootFresh(version: 2)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let objects = try (0..<3).map { BackupObject(identity: try objectIdentity("item-\($0)"), payload: Data([UInt8($0)])) }
        try await store.restoreBackup(objects, gate: gate)
        let reopened = harness.makeStore()
        _ = try await reopened.bootstrap()
        let restored = try await reopened.backupSnapshot(gate: gate)
        XCTAssertEqual(restored, objects)
        do { try await reopened.restoreBackup([], gate: gate); XCTFail("Overwrote existing data") }
        catch { XCTAssertEqual(error as? PasswordBackupError, .destinationNotEmpty) }
        let preserved = try await reopened.backupSnapshot(gate: gate)
        XCTAssertEqual(preserved, objects)
        gate.update(.locked)
        do { _ = try await reopened.backupSnapshot(gate: gate); XCTFail("Read while locked") } catch {}
    }

    func testInterruptedRestoreExposesEmptyOrCompleteSnapshotAfterReopen() async throws {
        for phase in [DurabilityPhase.data, .manifest] {
            for boundary in DurabilityBoundary.allCases {
                let harness = try StoreHarness(); defer { harness.cleanup() }
                let store = try await harness.bootFresh()
                let gate = KeyAvailabilityGate(); gate.update(.unlocked)
                let objects = try (0..<3).map { BackupObject(identity: try objectIdentity("item-\($0)"), payload: Data([UInt8($0)])) }
                do {
                    try await store.restoreBackup(objects, gate: gate,
                        injection: DurabilityInjection(failPhase: phase, failAt: boundary))
                    XCTFail("Expected injected failure")
                } catch {}
                let reopened = harness.makeStore()
                _ = try await reopened.bootstrap()
                let restored = try await reopened.backupSnapshot(gate: gate)
                XCTAssertTrue(restored.isEmpty || restored == objects, "\(phase) \(boundary)")
                if restored.isEmpty { try await reopened.restoreBackup(objects, gate: gate) }
                let afterRetry = try await reopened.backupSnapshot(gate: gate)
                XCTAssertEqual(afterRetry, objects)
            }
        }
    }

    func testFilesNeverOverwriteAndRejectSymlinksAndOversizedInput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("backup.krbackup")
        let content = Data("ciphertext-placeholder".utf8)
        try PasswordBackupFile.writeNew(content, to: target)
        XCTAssertEqual(try PasswordBackupFile.read(target), content)
        XCTAssertThrowsError(try PasswordBackupFile.writeNew(Data([0]), to: target))
        XCTAssertEqual(try Data(contentsOf: target), content)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try PasswordBackupFile.read(link))
        XCTAssertThrowsError(try PasswordBackupFile.writeNew(Data([0]), to: link))
        let handle = try FileHandle(forWritingTo: target)
        try handle.truncate(atOffset: UInt64(PasswordBackup.maximumArchiveBytes + 1)); try handle.close()
        XCTAssertThrowsError(try PasswordBackupFile.read(target))
    }
}

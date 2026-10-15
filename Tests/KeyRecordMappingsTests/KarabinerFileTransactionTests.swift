import XCTest
import Foundation
import Darwin
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore
@testable import KeyRecordMappings

actor MappingFixtureKeys: ObjectStoreKeySource {
    var present = false
    func seed() { present = true }
    func namespaceKeyVersions() -> Set<KeyVersion> { present ? [KeyVersion(rawValue: 1)] : [] }
    func material(for version: KeyVersion) throws -> Data {
        guard present, version.rawValue == 1 else { throw KarabinerMappingError.unavailable }
        return Data(repeating: 0xa7, count: 32)
    }
}

final class KarabinerFileTransactionTests: XCTestCase, @unchecked Sendable {
    func testDescriptorCommitAfterFinalValidationStaysWithOpenedDirectory() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected"), moved = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
        let file = selected.appendingPathComponent("configuration.json")
        try mappingBase.write(to: file)
        let descriptor = open(selected.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0); defer { close(descriptor) }
        let patched = mappingBase + Data(" ".utf8)
        try AtomicFileSystem().commitFile(name: "configuration.json", inDirectory: descriptor, bytes: patched, phase: .data) {
            let temporary = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: selected.path).first {
                $0.hasPrefix(AtomicFileSystem.tempPrefix)
            })
            try FileManager.default.moveItem(at: selected, to: moved)
            try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
            try mappingBase.write(to: file)
            try Data("untouched replacement temporary".utf8).write(to: selected.appendingPathComponent(temporary))
        }
        XCTAssertEqual(try Data(contentsOf: file), mappingBase)
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("configuration.json")), patched)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path), ["configuration.json"])
        let untouched = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: selected.path).first {
            $0.hasPrefix(AtomicFileSystem.tempPrefix)
        })
        XCTAssertEqual(try Data(contentsOf: selected.appendingPathComponent(untouched)), Data("untouched replacement temporary".utf8))
        for invalid in ["", ".", "..", "../escape.json", "nested/file", "bad\0name"] {
            XCTAssertThrowsError(try AtomicFileSystem().commitFile(name: invalid, inDirectory: descriptor, bytes: patched, phase: .data))
        }
    }
    func testAtomicEditorReplacementWithinSelectedDirectoryRemainsReadableAndWritable() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("configuration.json"); try mappingBase.write(to: file)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let context = context()
        let port = try KarabinerFilePort(target: file, gate: gate, runtime: { context })
        let edited = mappingBase + Data(" ".utf8)
        try edited.write(to: file, options: .atomic)
        XCTAssertEqual(try port.read(), edited)
        try port.replace(expected: edited, with: mappingBase, context: context)
        XCTAssertEqual(try port.read(), mappingBase)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["configuration.json"])
    }
    func testDirectoryReplacementCannotRedirectReadOrWriteEvenWithIdenticalConfiguration() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected"), moved = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
        let file = selected.appendingPathComponent("configuration.json")
        try mappingBase.write(to: file)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let context = context()
        let port = try KarabinerFilePort(target: file, gate: gate, runtime: { context })
        try FileManager.default.moveItem(at: selected, to: moved)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
        try mappingBase.write(to: file)
        XCTAssertThrowsError(try port.context())
        XCTAssertThrowsError(try port.read())
        XCTAssertThrowsError(try port.replace(expected: mappingBase, with: mappingBase + Data(" ".utf8), context: context))
        XCTAssertEqual(try Data(contentsOf: file), mappingBase)
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("configuration.json")), mappingBase)
    }
    func testDirectoryReplacementBeforeRenameCannotPublishOrCleanUpInReplacementDirectory() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected"), moved = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
        let file = selected.appendingPathComponent("configuration.json")
        try mappingBase.write(to: file)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let context = context(), calls = MappingRuntimeCallCounter()
        let port = try KarabinerFilePort(target: file, gate: gate, runtime: {
            if calls.next() == 2 {
                let temporary = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: selected.path).first {
                    $0.hasPrefix(AtomicFileSystem.tempPrefix)
                })
                try FileManager.default.moveItem(at: selected, to: moved)
                try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
                try mappingBase.write(to: file)
                try Data(contentsOf: moved.appendingPathComponent(temporary)).write(to: selected.appendingPathComponent(temporary))
            }
            return context
        })
        let patched = try KarabinerProfilePlanner.plan(mappingBase, profile: "Work", drafts: [mappingDraft()]).bytes
        XCTAssertThrowsError(try port.replace(expected: mappingBase, with: patched, context: context))
        XCTAssertEqual(try Data(contentsOf: file), mappingBase)
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("configuration.json")), mappingBase)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path), ["configuration.json"])
        let untouched = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: selected.path).first {
            $0.hasPrefix(AtomicFileSystem.tempPrefix)
        })
        XCTAssertEqual(try Data(contentsOf: selected.appendingPathComponent(untouched)), patched)
    }
    func testEditDuringTemporaryWriteIsCheckedAgainBeforeRename() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("configuration.json"); try mappingBase.write(to: file)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let context = context()
        let calls = MappingRuntimeCallCounter()
        let external = mappingBase + Data(" ".utf8)
        let port = try KarabinerFilePort(target: file, gate: gate, runtime: {
            if calls.next() == 2 { try external.write(to: file) }
            return context
        })
        let bytes = try KarabinerProfilePlanner.plan(mappingBase, profile: "Work", drafts: [mappingDraft()]).bytes
        XCTAssertThrowsError(try port.replace(expected: mappingBase, with: bytes, context: context))
        XCTAssertEqual(try Data(contentsOf: file), external)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["configuration.json"])
    }
    private func directory(_ prefix: String = "keyrecord-mapping-file-") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func context() -> KarabinerRuntimeContext {
        KarabinerRuntimeContext(version: "fixture", authority: .temporaryConfiguration,
            capabilities: BackendCapabilityCatalog.reference(.karabiner), observations: [])
    }
    func testRealFileEncryptedBatchReopenRetentionAndLock() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("configuration.json"); try mappingBase.write(to: file)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let context = context()
        let port = try KarabinerFilePort(target: file, gate: gate, runtime: { context })
        let keys = MappingFixtureKeys()
        let objectRoot = root.appendingPathComponent("objects")
        let objectStore = ObjectStore(root: objectRoot, keySource: keys)
        _ = try await objectStore.bootstrap(); await keys.seed()
        try await objectStore.initializeFreshInstallation(version: KeyVersion(rawValue: 1))
        let namespace = UUID()
        let persistence = try EncryptedKarabinerTransactionStore(store: objectStore, namespace: namespace)
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: persistence)
        _ = try await coordinator.apply(coordinator.prepare(profile: "Work", drafts: [mappingDraft()]))
        for _ in 0..<6 { _ = try await coordinator.setDisabled(true); _ = try await coordinator.setDisabled(false) }
        let ledger = try await coordinator.ledger()
        XCTAssertEqual(ledger.batches.count, 10)
        let entries = try await objectStore.entries()
        XCTAssertEqual(entries.count, 11)
        let names = try FileManager.default.contentsOfDirectory(atPath: objectRoot.path)
        for name in names {
            let encrypted = try Data(contentsOf: objectRoot.appendingPathComponent(name))
            XCTAssertNil(encrypted.range(of: Data("retain me".utf8)))
            XCTAssertNil(encrypted.range(of: Data("Synthetic mapping".utf8)))
        }
        let reopenedStore = ObjectStore(root: objectRoot, keySource: keys)
        _ = try await reopenedStore.bootstrap()
        let reopened = KarabinerTransactionCoordinator(configuration: port,
            store: try EncryptedKarabinerTransactionStore(store: reopenedStore, namespace: namespace))
        let recovered = try await reopened.reconcile()
        XCTAssertEqual(recovered.desired, ledger.desired)
        gate.update(.locked)
        XCTAssertThrowsError(try port.read())
        gate.update(.unlocked)
        XCTAssertThrowsError(try port.read())
    }
    func testFileRejectsSymlinkFifoHardlinkAndChangedBytes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("configuration.json"); try mappingBase.write(to: file)
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let context = context()
        let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let fifo = root.appendingPathComponent("fifo"); XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        for target in [root, link, fifo] { XCTAssertThrowsError(try KarabinerFilePort(target: target, gate: gate, runtime: { context }).read()) }
        let hardlink = root.appendingPathComponent("hardlink"); try FileManager.default.linkItem(at: file, to: hardlink)
        XCTAssertThrowsError(try KarabinerFilePort(target: hardlink, gate: gate, runtime: { context }).read())
        try FileManager.default.removeItem(at: hardlink)
        let port = try KarabinerFilePort(target: file, gate: gate, runtime: { context })
        let expected = try port.read()
        try (mappingBase + Data(" ".utf8)).write(to: file)
        XCTAssertThrowsError(try port.replace(expected: expected, with: mappingBase, context: context))
    }
    func testRealProcessCrashAtEachAtomicBoundaryReconcilesWithoutWriting() async throws {
        let executable = try probe()
        for boundary in DurabilityBoundary.allCases {
            let root = try directory("keyrecord-mapping-crash-")
            defer { try? FileManager.default.removeItem(at: root) }
            let process = Process(); process.executableURL = executable
            process.arguments = ["--crash", root.path, boundary.rawValue]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationReason, .uncaughtSignal)
            XCTAssertEqual(process.terminationStatus, SIGKILL)
            let keys = MappingFixtureKeys(); await keys.seed()
            let store = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keys)
            _ = try await store.bootstrap()
            let persistence = try EncryptedKarabinerTransactionStore(store: store,
                namespace: UUID(uuidString: "AAA00000-0000-0000-0000-000000000003")!)
            let gate = KeyAvailabilityGate(); gate.update(.unlocked)
            let context = context()
            let file = root.appendingPathComponent("configuration.json")
            let port = try KarabinerFilePort(target: file, gate: gate, runtime: { context })
            let before = try port.read()
            let recovered = try await KarabinerTransactionCoordinator(configuration: port, store: persistence).reconcile()
            XCTAssertNil(recovered.pending)
            XCTAssertEqual(recovered.batches.last?.state,
                [.afterWrite, .afterFileFsync].contains(boundary) ? .failed : .pendingVerification)
            XCTAssertEqual(try port.read(), before)
        }
    }
    private func probe() throws -> URL {
        let bundle = Bundle(for: Self.self).bundleURL
        let candidates = [bundle.deletingLastPathComponent().appendingPathComponent("KeyRecordMappingCrashProbe"),
                          bundle.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("KeyRecordMappingCrashProbe")]
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw KarabinerMappingError.unavailable
        }
        return found
    }
}

private final class MappingRuntimeCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}

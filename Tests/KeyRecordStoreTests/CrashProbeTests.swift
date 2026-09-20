import Foundation
import XCTest
import KeyRecordCore
import KeyRecordTestSupport
@testable import KeyRecordStore

/// Real process fault injection: the crashable KeyRecordStoreCrashProbe performs an actual
/// bootstrap/put/rotation and SIGKILLs its own process at the injected durable boundary.
/// The parent (this test) then reopens the store from disk in a fresh actor instance and
/// asserts recovery. No in-memory flag can replace a killed process.
@MainActor
final class CrashProbeTests: XCTestCase {
    private let objectPayload = Data("crash-object-payload".utf8)
    private let rotatePayload = Data("rotate-object-payload".utf8)

    func testProbeControlRunCompletesAndCommitsObject() async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let result = try runProbe(root: harness.root, operation: "put", boundary: "none")
        XCTAssertEqual(result.terminationSignal, 0)
        try await assertRecovered(harness.makeStore(), harness: harness, keyVersions: [1],
                                  identity: "crash-object", payload: objectPayload,
                                  expectation: StoreExpectation(objectPresent: true, currentVersion: 1))
    }

    func testRealProcessKillAtEveryPutBoundaryLeavesRecoverableState() async throws {
        let cases: [(String, StoreExpectation)] = [
            ("data-afterWrite", StoreExpectation(objectPresent: false, currentVersion: 1)),
            ("data-afterFileFsync", StoreExpectation(objectPresent: false, currentVersion: 1)),
            ("data-afterRename", StoreExpectation(objectPresent: false, currentVersion: 1)),
            ("data-afterDirectoryFsync", StoreExpectation(objectPresent: false, currentVersion: 1)),
            ("manifest-afterWrite", StoreExpectation(objectPresent: false, currentVersion: 1)),
            ("manifest-afterFileFsync", StoreExpectation(objectPresent: false, currentVersion: 1)),
            ("manifest-afterRename", StoreExpectation(objectPresent: true, currentVersion: 1)),
            ("manifest-afterDirectoryFsync", StoreExpectation(objectPresent: true, currentVersion: 1)),
        ]
        for (boundary, expectation) in cases {
            let harness = try StoreHarness()
            defer { harness.cleanup() }
            let result = try runProbe(root: harness.root, operation: "put", boundary: boundary)
            XCTAssertTrue([Int32(SIGKILL), 137].contains(result.terminationSignal), boundary)
            try await assertRecovered(harness.makeStore(), harness: harness, keyVersions: [1],
                                      identity: "crash-object", payload: objectPayload,
                                      expectation: expectation, label: boundary)
        }
    }

    func testRealKillThenInjectedInterruptionsThenReopensConverge() async throws {
        for round in 0..<3 {
            let harness = try StoreHarness()
            defer { harness.cleanup() }
            let result = try runProbe(root: harness.root, operation: "put",
                                     boundary: "data-afterDirectoryFsync")
            XCTAssertTrue([Int32(SIGKILL), 137].contains(result.terminationSignal), "round \(round)")
            try await reopenOnce(harness, label: "round-\(round)-after-kill", objectPresent: false)
            try await interruptThenReopenInProcess(harness, label: "round-\(round)-interrupt-1")
            try await interruptThenReopenInProcess(harness, label: "round-\(round)-interrupt-2")
        }
    }

    func testRealProcessKillAroundRotationRelocationAndManifestReencryption() async throws {
        let cases: [(String, UInt32, UInt32)] = [
            ("data-afterWrite", 1, 1),
            ("data-afterFileFsync", 1, 1),
            ("data-afterRename", 1, 1),
            ("data-afterDirectoryFsync", 1, 1),
            ("manifest-afterWrite", 2, 1),
            ("manifest-afterFileFsync", 2, 1),
            ("manifest-afterRename", 2, 2),
            ("manifest-afterDirectoryFsync", 2, 2),
            ("cleanup-afterRename", 2, 1),
        ]
        for (boundary, objectVersion, currentVersion) in cases {
            let harness = try StoreHarness()
            defer { harness.cleanup() }
            let result = try runProbe(root: harness.root, operation: "rotate", boundary: boundary)
            XCTAssertTrue([Int32(SIGKILL), 137].contains(result.terminationSignal), boundary)
            let expectation = StoreExpectation(objectPresent: true, currentVersion: currentVersion,
                                               objectVersion: objectVersion)
            try await assertRecovered(harness.makeStore(), harness: harness, keyVersions: [1, 2],
                                      identity: "rotate-object", payload: rotatePayload,
                                      expectation: expectation, label: boundary)
        }
    }

    private struct StoreExpectation {
        let objectPresent: Bool
        let currentVersion: UInt32
        var objectVersion: UInt32 = 1
    }

    private func reopenOnce(_ harness: StoreHarness, label: String, objectPresent: Bool) async throws {
        try await assertRecovered(harness.makeStore(), harness: harness, keyVersions: [1],
                                  identity: "crash-object", payload: objectPayload,
                                  expectation: StoreExpectation(objectPresent: objectPresent, currentVersion: 1),
                                  label: label)
    }

    private func interruptThenReopenInProcess(_ harness: StoreHarness, label: String) async throws {
        await harness.keySource.seed(version: 1)
        let writer = harness.makeStore()
        _ = try await writer.bootstrap()
        let injection = DurabilityInjection(failPhase: .data, failAt: .afterRename)
        do {
            _ = try await writer.put(identity: try objectIdentity(type: "com.keyrecord.crash", "crash-object"),
                                    payload: objectPayload, injection: injection)
            XCTFail("\(label): expected injected failure")
        } catch ObjectStoreError.filesystem {
        }
        try await reopenOnce(harness, label: label, objectPresent: false)
    }

    private func assertRecovered(
        _ store: ObjectStore,
        harness: StoreHarness,
        keyVersions: [UInt32],
        identity: String,
        payload: Data,
        expectation: StoreExpectation,
        label: String = ""
    ) async throws {
        for version in keyVersions { await harness.keySource.seed(version: version) }
        let state = try await store.bootstrap()
        XCTAssertEqual(state, .opened, label)
        let current = try await store.currentKeyVersion().rawValue
        XCTAssertEqual(current, expectation.currentVersion, label)
        let identityValue = try objectIdentity(type: "com.keyrecord.crash", identity)
        if expectation.objectPresent {
            let readBack = try await store.read(identityValue)
            XCTAssertEqual(readBack, payload, label)
            let entries = try await store.entries()
            let entry = try XCTUnwrap(entries.first, label)
            XCTAssertEqual(entry.keyVersion, expectation.objectVersion, label)
        } else {
            do {
                _ = try await store.read(identityValue)
                XCTFail("object must not be visible: \(label)")
            } catch ObjectStoreError.unknownObject {
            } catch {
                XCTFail("expected unknownObject, got \(error): \(label)")
            }
        }
        let files = try harness.rootEntries()
        let temps = files.filter { $0.hasPrefix(AtomicFileSystem.tempPrefix) }
        XCTAssertTrue(temps.isEmpty, "unresolved temps \(temps): \(label)")
        let unresolved = await store.unresolvedArtifactNames()
        XCTAssertTrue(unresolved.isEmpty, "unresolved \(unresolved): \(label)")
    }

    private struct ProbeResult { let terminationSignal: Int32 }

    private nonisolated func runProbe(root: URL, operation: String, boundary: String) throws -> ProbeResult {
        let process = Process()
        process.executableURL = try CrashProbeResolver.resolve()
        process.arguments = [root.path, operation, boundary]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != SIGKILL && process.terminationStatus != 137
            && process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            XCTFail("probe \(operation) \(boundary) exited \(process.terminationStatus): \(text)")
        }
        return ProbeResult(terminationSignal: process.terminationStatus)
    }
}

/// Resolves the crash probe executable.
///
/// The probe is a declared SwiftPM executable target (`KeyRecordStoreCrashProbe`), so it is
/// built alongside the tests and sits next to the test bundle. The previous resolver walked
/// up to eight ancestor directories looking for a `Modules/` + `KeyRecordStore.build/` layout
/// and relinked the probe from raw object files; the current build backend does not produce
/// that layout, so a harness fault surfaced as 20 product-test failures.
///
/// Every failure here surfaces as `TestArtifactLocator.LocatorError`, naming the harness as
/// the failing party rather than the product.
enum CrashProbeResolver {
    static let executableName = "KeyRecordStoreCrashProbe"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: URL?

    static func resolve() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        if let cached, FileManager.default.isExecutableFile(atPath: cached.path) { return cached }
        let products = try TestArtifactLocator.productsDirectory()
        let probe = try TestArtifactLocator.validateProbe(
            at: products.appendingPathComponent(executableName))
        cached = probe
        return probe
    }
}

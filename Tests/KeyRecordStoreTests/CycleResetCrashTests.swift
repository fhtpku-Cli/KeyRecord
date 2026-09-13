import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class CycleResetCrashTests: XCTestCase {
    private let materialV1 = Data(repeating: 7, count: 32)

    private struct Reopened {
        let shardCount: Int
        let summaryCount: Int
        let currentCount: Int
        let retainedHashes: [String: Data]
        let journalPresent: Bool
    }

    private func reopen(_ harness: StoreHarness) async throws -> Reopened {
        await harness.keySource.seed(version: 1)
        let store = harness.makeStore()
        let state = try await store.bootstrap()
        XCTAssertEqual(state, .opened)
        let entries = try await store.entries()
        let files = try harness.rootEntries()
        let temps = files.filter { $0.hasPrefix(AtomicFileSystem.tempPrefix) }
        XCTAssertTrue(temps.isEmpty, "owned temp survived reconcile: \(temps)")
        let unresolved = await store.unresolvedArtifactNames()
        XCTAssertTrue(unresolved.isEmpty, "unresolved artifacts: \(unresolved)")
        let journalLocator = try CycleResetJournalStore(root: harness.root)
            .expectedLocator(version: 1, material: materialV1).fileName
        var hashes: [String: Data] = [:]
        for entry in entries where entry.identity.logicalID == Data("opaque-fixture".utf8) {
            hashes[entry.locator.fileName] = try Data(contentsOf: harness.root
                .appendingPathComponent(entry.locator.fileName))
        }
        return Reopened(
            shardCount: entries.filter { $0.identity.objectType == CanonicalLogicalIdentity.shardObjectType }.count,
            summaryCount: entries.filter { $0.identity.objectType == "com.keyrecord.cycleSummary" }.count,
            currentCount: entries.filter { $0.identity == CycleResetObjects.currentCycle }.count,
            retainedHashes: hashes,
            journalPresent: files.contains(journalLocator))
    }

    private func assertConverged(_ harness: StoreHarness) async throws {
        await harness.keySource.seed(version: 1)
        let store = harness.makeStore()
        _ = try await store.bootstrap()
        let next = CycleResetIdentifiers.newCycleID(operationID: resetOperation)
        try await assertReset(store, next: next)
    }

    @discardableResult
    private func runResetProbe(root: URL, spec: String) throws -> Int32 {
        let process = Process()
        process.executableURL = try CrashProbeResolver.resolve()
        process.arguments = [root.path, "reset", spec]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 && process.terminationStatus != SIGKILL && process.terminationStatus != 137 {
            let text = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("probe reset \(spec) exited \(process.terminationStatus): \(text)")
        }
        return process.terminationStatus
    }

    /// Each chain is a fresh root: real SIGKILL runs in order, parent reopens between
    /// every kill, then a clean run converges and a duplicate run proves idempotence.
    private func exerciseChain(_ label: String, kills: [String]) async throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        var previousShards: Int?
        var retainedBaseline: [String: Data]?
        for spec in kills {
            let status = try runResetProbe(root: harness.root, spec: spec)
            XCTAssertTrue([Int32(SIGKILL), 137].contains(status), "\(label): \(spec) not killed")
            let state = try await reopen(harness)
            XCTAssertEqual(state.currentCount, 1, "\(label): \(spec)")
            XCTAssertLessThanOrEqual(state.summaryCount, 1, "\(label): duplicate summary after \(spec)")
            if let previousShards {
                XCTAssertLessThanOrEqual(state.shardCount, previousShards,
                                         "\(label): deleted details resurrected after \(spec)")
            }
            previousShards = state.shardCount
            if let retainedBaseline {
                XCTAssertEqual(state.retainedHashes, retainedBaseline, "\(label): retained bytes moved at \(spec)")
            } else {
                retainedBaseline = state.retainedHashes
            }
            XCTAssertEqual(state.retainedHashes.count, 4, "\(label): retained object set changed")
        }
        let cleanStatus = try runResetProbe(root: harness.root, spec: "none")
        XCTAssertEqual(cleanStatus, 0, "\(label): convergence run failed")
        try await assertConverged(harness)
        let duplicateStatus = try runResetProbe(root: harness.root, spec: "none")
        XCTAssertEqual(duplicateStatus, 0, "\(label): duplicate operation failed")
        try await assertConverged(harness)
        if let retainedBaseline {
            await harness.keySource.seed(version: 1)
            let final = try await reopen(harness)
            XCTAssertEqual(final.retainedHashes, retainedBaseline, "\(label): retained bytes after convergence")
            XCTAssertFalse(final.journalPresent, "\(label): journal not cleared")
        }
    }

    func testRealProcessKillAtJournalBoundaryConverges() async throws {
        try await exerciseChain("journal-afterWrite-then-summary-stage", kills: [
            "journal-data-afterWrite",
            "stage-summaryWritten",
        ])
        try await exerciseChain("journal-afterRename-then-details-stage", kills: [
            "journal-data-afterRename",
            "stage-detailsRemoved",
        ])
        try await exerciseChain("journal-durable-then-cycle-stage", kills: [
            "journal-data-afterDirectoryFsync",
            "stage-cycleCommitted",
        ])
    }

    func testRealProcessKillAfterSummaryBeforeDetailDeleteConverges() async throws {
        try await exerciseChain("summary-stage-then-detail-manifest", kills: [
            "stage-summaryWritten",
            "details-manifest-afterRename",
        ])
        try await exerciseChain("summary-stage-then-detail-cleanup", kills: [
            "stage-summaryWritten",
            "details-cleanup-afterRename",
        ])
    }

    func testRealProcessKillAroundNewCycleCommitConverges() async throws {
        try await exerciseChain("cycle-data-then-cycle-stage", kills: [
            "cycle-data-afterRename",
            "stage-cycleCommitted",
        ])
        try await exerciseChain("cycle-manifest-only", kills: [
            "cycle-manifest-afterRename",
        ])
    }

    func testRealProcessKillDuringJournalClearConverges() async throws {
        try await exerciseChain("cycle-stage-then-clear", kills: [
            "stage-cycleCommitted",
            "clear-cleanup-afterRename",
        ])
        try await exerciseChain("clear-only", kills: [
            "clear-cleanup-afterRename",
        ])
    }

    func testRepeatedRealInterruptionsAcrossEveryStageConverge() async throws {
        // Given/When: four consecutive real SIGKILLs, one at every forward stage.
        try await exerciseChain("all-stages-repeated", kills: [
            "journal-data-afterDirectoryFsync",
            "stage-summaryWritten",
            "stage-detailsRemoved",
            "stage-cycleCommitted",
        ])
    }

    func testControlRunResetsWithoutInjection() async throws {
        // Given: a probe control run with no injection.
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        // When: it seeds and resets in a single process.
        let status = try runResetProbe(root: harness.root, spec: "none")
        // Then: exit 0 and the converged state survives a fresh reopen.
        XCTAssertEqual(status, 0)
        try await assertConverged(harness)
    }
}

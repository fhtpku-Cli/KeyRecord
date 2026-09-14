import CryptoKit
import Foundation
import XCTest
@testable import EvidenceValidator
import Phase0Support

// End-to-end closeout orchestration for plan task 15. The tests drive the real
// EvidenceValidator CLI through Spikes/Scripts/close-current-readiness.sh inside
// clean, committed synthetic repositories: readiness + status table + an interim
// (superseded-labelled) current candidate must be produced and reverified, while
// unverifiable history, dirty inputs and stale receipts fail or block honestly.
final class CurrentCloseoutTests: XCTestCase {
    private var fixture: CurrentCloseoutFixture!
    private var repository: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var helper: URL { repository.appendingPathComponent("Spikes/Scripts/close-current-readiness.sh") }
    private var validator: URL { Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("EvidenceValidator") }
    private let attempt = ".omo/evidence/t15-attempt"
    private var readiness: String { "\(attempt)/readiness.json" }
    private var table: String { "\(attempt)/status-table.json" }
    private var candidate: String { "\(attempt)/interim-current-candidate.json" }
    private var envelope: String { "\(attempt)/interim-envelope.json" }

    override func setUpWithError() throws {
        fixture = try CurrentCloseoutFixture()
        try fixture.buildBoundHistory()
    }
    override func tearDownWithError() throws { fixture.remove() }

    func testHappyProducesReadinessTableAndInterimCandidate() throws {
        // Given a clean committed repository with verified G0 history and no live host,
        // when the closeout runs, then a BLOCKED baseline, table and interim candidate exist and verify.
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 2, result.stderr)
        // The envelope marker says EMITTED, never PASS: exit 2 BLOCKED is the only disposition,
        // and the interim artifact must not read as a certification.
        XCTAssertTrue(result.combined.contains("CURRENT_INTERIM_ENVELOPE=EMITTED"))
        XCTAssertFalse(result.combined.contains("CURRENT_INTERIM_ENVELOPE=PASS"))
        XCTAssertTrue(result.combined.contains("CURRENT_CLOSEOUT=BLOCKED interim=true"))
        let document = try ReadinessDecoding.decode(CurrentReadiness.self, from: Data(contentsOf: fixture.url(readiness)))
        XCTAssertEqual(document.gates.map(\.status), [.pass, .blocked, .blocked])
        XCTAssertEqual(document.status, .blocked)
        XCTAssertEqual(document.retainedReleaseBlockers.map(\.id), ["KARABINER_STABLE", "VIA_GENERATION", "VIAL_BETA", "FULL_BACKUP_FINAL_RELEASE"])
        let statusTable = try tableJSON()
        XCTAssertEqual(statusTable.string("overall"), "BLOCKED")
        XCTAssertEqual(statusTable.bool("complete"), false)
        XCTAssertEqual(statusTable.bool("finalFreeze"), false)
        XCTAssertEqual(statusTable.string("readiness.sha256"), sha256(readiness))
        XCTAssertEqual(Set(try tableRows().map { $0.string("id") }), ["G0", "O6", "SP6A_LOCAL_LIFECYCLE", "G1_IMPLEMENTATION", "SP-6A-HISTORICAL"])
        let envelope = try envelopeJSON()
        XCTAssertEqual(envelope.string("kind"), "interim_current_candidate")
        XCTAssertEqual(envelope.bool("supersededAfterLaterCommits"), true)
        XCTAssertEqual(envelope.bool("finalFreeze"), false)
        XCTAssertEqual(envelope.number("finalFreezeTask"), 25)
        XCTAssertEqual(envelope.string("candidateSha256"), sha256(candidate))
        XCTAssertEqual(envelope.string("readinessSha256"), sha256(readiness))
        XCTAssertEqual(envelope.string("statusTableSha256"), sha256(table))
        let verified = try run([validator.path, "verify-current-candidate", candidate, "--readiness", readiness])
        XCTAssertEqual(verified.exit, 0, verified.stderr)
    }

    func testHappySP6ABlockedIsNotFailureAndHistoryStaysDistinct() throws {
        // Given no authorized SP6A host, when closing out, then SP6A/G1 are BLOCKED (2), never FAIL (1),
        // and the sealed historical SP-6A verdict is reported separately from the current gate.
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 2, result.stderr)
        XCTAssertFalse(result.combined.contains("FAIL"))
        let document = try ReadinessDecoding.decode(CurrentReadiness.self, from: Data(contentsOf: fixture.url(readiness)))
        let lifecycle = try XCTUnwrap(document.gates.first { $0.id == .lifecycle })
        XCTAssertEqual(lifecycle.status, .blocked)
        XCTAssertEqual(lifecycle.unresolvedCauses, ["receipt.keychainPolicy", "receipt.sessionLock", "receipt.restart", "receipt.sleepWake"])
        XCTAssertTrue(document.gates.allSatisfy { $0.status != .fail })
        let rows = try tableRows()
        let current = try XCTUnwrap(rows.first { $0.string("id") == "SP6A_LOCAL_LIFECYCLE" })
        let historical = try XCTUnwrap(rows.first { $0.string("id") == "SP-6A-HISTORICAL" })
        XCTAssertEqual(current.string("status"), "BLOCKED")
        XCTAssertEqual(current.bool("currentProjection"), true)
        XCTAssertEqual(historical.string("status"), "BLOCKED")
        XCTAssertEqual(historical.bool("sealedHistorical"), true)
    }

    func testHappyPublishedProjectionBesideHistoryKeepsInventoryVerifiable() throws {
        // Given a closeout at a clean commit, when the projection is published beside the sealed
        // historical root (uncommitted then committed), then generate/verify still recompute and the
        // historical inventory/byte bindings are never relaxed; the published document becomes an
        // interim snapshot that later commits supersede.
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 2, result.stderr)
        try copy(readiness, to: "phase1/readiness.json")
        try copy(table, to: "phase1/status-table.json")
        XCTAssertEqual(try run([validator.path, "current-readiness", "--historical", fixture.historicalRoot,
                                "--lifecycle", "none", "--output", "phase1/regenerated.json"]).exit, 2, result.stderr)
        XCTAssertEqual(try run([validator.path, "verify-current-readiness", "phase1/readiness.json"]).exit, 2)
        _ = try fixture.git.run(["add", "--", "phase1"]); _ = try fixture.git.run(["commit", "-qm", "publish projection"])
        let after = try run([validator.path, "current-readiness", "--historical", fixture.historicalRoot,
                             "--lifecycle", "none", "--output", "phase1/after-commit.json"])
        XCTAssertEqual(after.exit, 2, after.stderr)
        XCTAssertEqual(try run([validator.path, "verify-current-readiness", "phase1/after-commit.json"]).exit, 2)
        // The publication commit cannot change a single sealed historical byte.
        XCTAssertEqual(try fixture.git.run(["diff", "HEAD~1", "HEAD", "--", "history"]).stdout, Data())
        // The pre-publication document is now superseded; recompute at the new HEAD rejects it.
        XCTAssertEqual(try run([validator.path, "verify-current-readiness", "phase1/readiness.json"]).exit, 1)
    }

    func testFailureUnverifiableHistoricalG0BlocksBeforeCandidate() throws {
        // Given a required G0 proof removed in a later commit, when closing out, then BLOCKED and no candidate.
        try FileManager.default.removeItem(at: fixture.url("history/sp1/evidence.json"))
        _ = try fixture.git.run(["add", "-A", "history"]); _ = try fixture.git.run(["commit", "-qm", "remove proof"])
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 2, result.stderr)
        XCTAssertTrue(result.combined.contains("G0"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url(candidate).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url(envelope).path))
        XCTAssertEqual((try tableRows()).first { $0.string("id") == "G0" }?.string("status"), "BLOCKED")
    }

    func testFailureTamperedHistoricalBytesFail() throws {
        // Given a one-byte uncommitted historical edit, when closing out, then FAIL rather than reseal.
        var bytes = try Data(contentsOf: fixture.url("history/sp1/evidence.json")); bytes.append(0x0A)
        try bytes.write(to: fixture.url("history/sp1/evidence.json"))
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 1, result.combined)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url(candidate).path))
    }

    func testFailureDirtyTrackedSourceFails() throws {
        // Given a tracked source byte drift, when projecting, then FAIL and no readiness is published.
        let path = CurrentReadinessBindings.sourcePaths.sorted()[0]
        var bytes = try Data(contentsOf: fixture.url(path)); bytes.append(0x20)
        try bytes.write(to: fixture.url(path))
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 1, result.combined)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url(readiness).path))
    }

    func testFailureDirtyWorktreeRejectsCandidate() throws {
        // Given an unrelated untracked file outside .omo, when binding, then the interim candidate is refused.
        try fixture.writeText("unexpected\n", "dirty.txt")
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 1, result.combined)
        XCTAssertTrue(result.combined.contains("dirty"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url(candidate).path))
    }

    func testFailureOldPhase0FinalReceiptReuseIsRejected() throws {
        // Given a stale phase0-final candidate placed at the readiness path, when closing out, then reject reuse.
        try FileManager.default.createDirectory(at: fixture.url(readiness).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"schemaVersion\":1,\"kind\":\"phase0-final-candidate\",\"final\":true}\n".utf8).write(to: fixture.url(readiness))
        let result = try runCloseout()
        XCTAssertEqual(result.exit, 1, result.combined)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url(candidate).path))
    }

    // MARK: - Helpers

    @discardableResult
    private func runCloseout() throws -> ProcessResult {
        try run(["/bin/bash", helper.path, "--validator", validator.path, "--historical", fixture.historicalRoot,
                 "--lifecycle", "none", "--plan", fixture.planPath, "--readiness", readiness, "--status-table", table,
                 "--candidate", candidate, "--interim", envelope, "--generated-at", "2026-09-13T00:00:00Z"])
    }

    private func run(_ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        process.currentDirectoryURL = fixture.root
        let out = Pipe(), err = Pipe(); process.standardOutput = out; process.standardError = err
        try process.run(); process.waitUntilExit()
        return ProcessResult(exit: process.terminationStatus,
                            stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                            stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private struct ProcessResult { let exit: Int32; let stdout: String; let stderr: String
        var combined: String { stdout + "\n" + stderr } }

    private func data(_ path: String) throws -> Data { try Data(contentsOf: fixture.url(path)) }
    private func copy(_ path: String, to destination: String) throws {
        let target = fixture.url(destination)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: fixture.url(path)).write(to: target)
    }
    private func sha256(_ path: String) -> String {
        SHA256.hash(data: (try? data(path)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    private func json(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try data(path)) as? [String: Any] ?? [:]
    }
    private func tableJSON() throws -> [String: Any] { try json(table) }
    private func envelopeJSON() throws -> [String: Any] { try json(envelope) }
    private func tableRows() throws -> [[String: Any]] { (try tableJSON())["rows"] as? [[String: Any]] ?? [] }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ keyPath: String) -> String? {
        if keyPath.contains(".") {
            var node: Any? = self
            for part in keyPath.split(separator: ".") { node = (node as? [String: Any])?[String(part)] }
            return node as? String
        }
        return self[keyPath] as? String
    }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    func number(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
}

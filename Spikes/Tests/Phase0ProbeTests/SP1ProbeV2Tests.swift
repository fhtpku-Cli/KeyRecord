import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support
@testable import Phase0Probe

final class SP1ProbeV2Tests: XCTestCase {
    private static let syntheticLegIDs: Set<String> = ["sp1.autoRepeat", "sp1.o7Boundary", "sp1.productStampedDrop", "sp1.tapReset"]
    private static let matrixLegIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]
    private static let aggregateOnlyLiveKeys: Set<String> = ["evidenceKind", "systemShortcutObservedCount", "unmarkedObservedCount"]

    func testD1UnavailableFallsBackToCanonicalSchemaV1AllBlocked() throws {
        try withScenario(listenEventAccess: "denied", tapCreate: "denied", karabinerInstalled: false) { directory, evidence in
            XCTAssertEqual(evidence.schemaVersion, 1)
            XCTAssertEqual(evidence.verdict, .blocked)
            XCTAssertTrue(evidence.legs.allSatisfy { leg in
                leg.verdict == .blocked && !leg.detectorAvailable && leg.blocker?.complete == true
                    && leg.artifactSha256 == nil && leg.identity == nil && leg.matrix == nil && leg.aggregateCount == nil
            })
            let product = try Data(contentsOf: directory.appendingPathComponent("product-stamped-synthetic.json"))
            XCTAssertEqual(AtomicityDigest.sha256(product), "7238044654fbd6c081b5531f50ba8a095fd90e89e80edf9c6cb48a52f94ba518")
            for leg in evidence.legs {
                XCTAssertFalse(leg.detectorAvailable, leg.legID)
                XCTAssertEqual(leg.blocker?.complete, true, leg.legID)
                XCTAssertNil(leg.artifactSha256, leg.legID)
                let expected = Self.matrixLegIDs.contains(leg.legID)
                    ? SP1CanonicalBlockers.legacyV1Matrix(inputMonitoringUnavailable: true, karabinerAbsent: true)
                    : SP1CanonicalBlockers.d1
                XCTAssertEqual(leg.blocker, expected, leg.legID)
            }
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.tap.session.matrix" }?.blocker?.blockedBy, "input_monitoring_denied;karabiner_absent")

            XCTAssertEqual(evidence.verdict, .blocked)
            XCTAssertEqual(evidence.g0Status, .open)
            XCTAssertNoThrow(try evidence.validate())
            assertAggregateOnlyLiveArtifact(directory: directory)
            assertCanonicalNarratives(directory: directory, evidence: evidence)
            assertComponentValidatorsAccept(directory: directory, evidence: evidence)
        }
    }

    func testD1AvailableD2AbsentEmitsV3ThroughInjectedPreflight() throws {
        try withScenario(listenEventAccess: "available", tapCreate: "available", karabinerInstalled: false) { directory, evidence in
            try assertV3SyntheticAndNotArmedShortcut(directory: directory, evidence: evidence)
            for leg in evidence.legs where Self.matrixLegIDs.contains(leg.legID) {
                XCTAssertEqual(leg.verdict, .blocked)
                XCTAssertEqual(leg.blocker, SP1CanonicalBlockers.v2KarabinerAbsent)
            }
            XCTAssertNoThrow(try evidence.validate())
            assertCanonicalNarratives(directory: directory, evidence: evidence)
            assertComponentValidatorsAccept(directory: directory, evidence: evidence)
        }
    }

    func testEveryD1FailureUsesPrecedenceReasonAndSkipsPreflight() throws {
        let states = ["denied", "unavailable", "unknown", "available"]
        for guiStatus in states {
            for listenEventAccess in states {
                for tapCreate in states {
                    guard !(guiStatus == "available" && listenEventAccess == "available" && tapCreate == "available") else { continue }
                    let expectedReason: String
                    if guiStatus != "available" {
                        expectedReason = "gui_session_\(guiStatus)"
                    } else if listenEventAccess != "available" {
                        expectedReason = "input_monitoring_\(listenEventAccess)"
                    } else {
                        expectedReason = "tap_create_\(tapCreate)"
                    }
                    let preflight = SP1V2CountingPreflightProvider()
                    try withScenario(
                        guiStatus: guiStatus,
                        listenEventAccess: listenEventAccess,
                        tapCreate: tapCreate,
                        karabinerInstalled: false,
                        preflightProvider: preflight
                    ) { _, evidence in
                        XCTAssertEqual(evidence.schemaVersion, 1)
                        XCTAssertEqual(preflight.callCount, 0, "\(guiStatus)/\(listenEventAccess)/\(tapCreate)")
                        for leg in evidence.legs where !Self.matrixLegIDs.contains(leg.legID) {
                            XCTAssertEqual(leg.blocker?.blockedBy, expectedReason, leg.legID)
                        }
                        for leg in evidence.legs where Self.matrixLegIDs.contains(leg.legID) {
                            XCTAssertEqual(leg.blocker?.blockedBy, "\(expectedReason);karabiner_absent", leg.legID)
                        }
                    }
                }
            }
        }
    }

    func testD2DeclaredEmitsV3NotArmedBlockerThroughInjectedPreflight() throws {
        try withScenario(listenEventAccess: "available", tapCreate: "available", karabinerInstalled: true) { directory, evidence in
            try assertV3SyntheticAndNotArmedShortcut(directory: directory, evidence: evidence)
            for leg in evidence.legs where Self.matrixLegIDs.contains(leg.legID) {
                XCTAssertEqual(leg.verdict, .blocked, leg.legID)
                XCTAssertFalse(leg.detectorAvailable, leg.legID)
                XCTAssertEqual(leg.blocker, SP1CanonicalBlockers.liveExecutionNotArmed, leg.legID)
                XCTAssertEqual(leg.blocker?.detectCommand, ["KEYRECORD_SP1_LIVE_EXECUTION"], leg.legID)
                XCTAssertTrue(leg.blocker?.unblockAction.contains("never prompts") == true, leg.legID)
                XCTAssertNil(leg.identity, leg.legID)
                XCTAssertNil(leg.matrix, leg.legID)
            }
            XCTAssertNil(evidence.selectedTapIdentity)
            XCTAssertNoThrow(try evidence.validate())
            assertCanonicalNarratives(directory: directory, evidence: evidence)
            assertComponentValidatorsAccept(directory: directory, evidence: evidence)
        }
    }

    func testD1UnavailableComponentValidatorsAcceptSchemaV1OutputWithoutRunnerBinding() throws {
        try withScenario(listenEventAccess: "denied", tapCreate: "denied", karabinerInstalled: false) { directory, evidence in
            XCTAssertEqual(evidence.schemaVersion, 1)
            assertComponentValidatorsAccept(directory: directory, evidence: evidence)
        }
    }

    func testVerdictPrecedenceIsLockedThroughTheAggregateContract() throws {
        let commit = String(repeating: "a", count: 40)
        let tree = String(repeating: "b", count: 40)
        let environment = String(repeating: "c", count: 64)
        let legs = SP1Evidence.requiredLegIDs.sorted().map { legID -> SP1Leg in
            if Self.matrixLegIDs.contains(legID) {
                return SP1Leg(legID: legID, verdict: .blocked, detectorAvailable: false, blocker: SP1CanonicalBlockers.v2KarabinerAbsent, identity: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment, artifactSha256: nil, matrix: nil, aggregateCount: nil)
            }
            let synthetic = Self.syntheticLegIDs.contains(legID)
            return SP1Leg(
                legID: legID, verdict: synthetic ? .pass : .blocked, detectorAvailable: synthetic,
                blocker: synthetic ? nil : SP1CanonicalBlockers.systemShortcutExecutionNotImplemented,
                identity: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment,
                artifactSha256: synthetic ? String(repeating: "d", count: 64) : nil, matrix: nil, aggregateCount: nil
            )
        }
        let sources = Dictionary(uniqueKeysWithValues: SP1RunnerBinding.sourcePaths.map { ($0, String(repeating: "f", count: 64)) })
        var evidence = SP1Evidence(selectedTapIdentity: nil, legs: legs, verdict: .blocked, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: sources)
        evidence.schemaVersion = 2
        XCTAssertNoThrow(try evidence.validate())
        evidence.verdict = .inconclusive
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP1ValidationError, .invalidAggregate) }
        evidence.verdict = .pass
        XCTAssertThrowsError(try evidence.validate()) { XCTAssertEqual($0 as? SP1ValidationError, .invalidAggregate) }
    }

    private func assertV3SyntheticAndNotArmedShortcut(directory: URL, evidence: SP1Evidence, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(evidence.schemaVersion, 3, file: file, line: line)
        let syntheticBytes = try Data(contentsOf: directory.appendingPathComponent("product-stamped-synthetic.json"))
        XCTAssertEqual(syntheticBytes, try SP1SyntheticScenarios.run().canonicalJSON(), file: file, line: line)
        let syntheticHash = AtomicityDigest.sha256(syntheticBytes)
        for leg in evidence.legs where Self.syntheticLegIDs.contains(leg.legID) {
            XCTAssertEqual(leg.verdict, .pass, leg.legID, file: file, line: line)
            XCTAssertEqual(leg.artifactSha256, syntheticHash, leg.legID, file: file, line: line)
        }
        let shortcut = try XCTUnwrap(evidence.legs.first { $0.legID == "sp1.systemShortcut" }, file: file, line: line)
        XCTAssertEqual(shortcut.verdict, .blocked, file: file, line: line)
        XCTAssertEqual(shortcut.blocker, SP1CanonicalBlockers.liveExecutionNotArmed, file: file, line: line)
        XCTAssertFalse(shortcut.detectorAvailable, file: file, line: line)
        XCTAssertNil(shortcut.aggregateCount, file: file, line: line)
        XCTAssertNil(shortcut.artifactSha256, file: file, line: line)
        XCTAssertNil(shortcut.identity, file: file, line: line)
        XCTAssertNil(shortcut.matrix, file: file, line: line)
        let liveBytes = try Data(contentsOf: directory.appendingPathComponent("live-aggregate-counts.json"))
        let live = try JSONDecoder().decode(SP1LiveAggregateArtifact.self, from: liveBytes)
        XCTAssertEqual(live.systemShortcutObservedCount, 0, file: file, line: line)
        XCTAssertEqual(live.unmarkedObservedCount, 0, file: file, line: line)
    }

    private func assertCanonicalNarratives(directory: URL, evidence: SP1Evidence, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("O7-ADDENDUM.md")), SP1CanonicalNarratives.o7(), file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("SP-1-CONCLUSION.md")), SP1CanonicalNarratives.conclusion(for: evidence), file: file, line: line)
    }

    private func assertAggregateOnlyLiveArtifact(directory: URL, file: StaticString = #filePath, line: UInt = #line) {
        let url = directory.appendingPathComponent("live-aggregate-counts.json")
        let object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any]
        XCTAssertEqual(Set((object ?? [:]).keys), Self.aggregateOnlyLiveKeys, "live artifact must stay aggregate-only with no raw event detail", file: file, line: line)
    }

    private func assertComponentValidatorsAccept(directory: URL, evidence: SP1Evidence, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try SP1DirectoryValidator.verifyManifest(directory), file: file, line: line)
        XCTAssertNoThrow(try SP1DirectoryValidator.validateArtifacts(directory, evidence: evidence), file: file, line: line)
        XCTAssertNoThrow(try SP1DirectoryValidator.validateArtifactBindings(evidence, directory: directory), file: file, line: line)
    }

    private func withScenario(
        guiStatus: String = "available",
        listenEventAccess: String,
        tapCreate: String,
        karabinerInstalled: Bool,
        preflightProvider: any SP1PreflightProviding = SP1V2SuccessfulPreflightProvider(),
        _ body: (URL, SP1Evidence) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-v2-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = root.appendingPathComponent("environment.json")
        try Data(environmentJSON(guiStatus: guiStatus, listenEventAccess: listenEventAccess, tapCreate: tapCreate, karabinerInstalled: karabinerInstalled).utf8).write(to: environment)
        let output = root.appendingPathComponent("sp1", isDirectory: true)
        try SP1Probe.run(
            arguments: ["sp1", "--environment", environment.path, "--output", output.path],
            identityProvider: SP1V2FixedIdentityProvider(),
            preflightProvider: preflightProvider
        )
        let evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
        try body(output, evidence)
    }

    private func environmentJSON(guiStatus: String, listenEventAccess: String, tapCreate: String, karabinerInstalled: Bool) -> String {
        """
        {"macOS":{"version":"26.6.1","build":"25G76"},"architecture":"arm64","swift":"Swift 6","xcode":"Xcode 26","generatedAt":"2026-01-01T00:00:00Z","guiSession":{"status":"\(guiStatus)","tapCreate":"\(tapCreate)"},"listenEventAccess":"\(listenEventAccess)","hidAccess":"unknown","sudoNonInteractive":false,"applications":[{"name":"Karabiner-Elements","status":"\(karabinerInstalled ? "installed" : "absent")"}],"hidSummary":{"deviceCount":0,"devices":[]},"sourceReachability":{"status":"unavailable","httpStatus":null}}
        """
    }
}

private struct SP1V2FixedIdentityProvider: AtomicityRunnerIdentityProviding {
    func resolve() throws -> AtomicityRunnerIdentity {
        AtomicityRunnerIdentity(
            commitSha: String(repeating: "a", count: 40),
            treeSha: String(repeating: "b", count: 40),
            sourceSha256: Dictionary(uniqueKeysWithValues: SP1RunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
        )
    }
}

private struct SP1V2SuccessfulPreflightProvider: SP1PreflightProviding {
    func preflightListenOnlyCandidates() throws {}
}

private final class SP1V2CountingPreflightProvider: SP1PreflightProviding, @unchecked Sendable {
    private(set) var callCount = 0
    func preflightListenOnlyCandidates() throws { callCount += 1 }
}

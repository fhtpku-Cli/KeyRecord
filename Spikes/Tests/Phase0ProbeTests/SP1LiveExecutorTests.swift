import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Probe
@testable import Phase0Support

final class SP1LiveExecutorTests: XCTestCase {
    private static let syntheticLegIDs: Set<String> = ["sp1.autoRepeat", "sp1.o7Boundary", "sp1.productStampedDrop", "sp1.tapReset"]
    private static let matrixLegIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]

    func testDefaultExecutorsStayNotArmedAndNeverSelect() throws {
        try withScenario() { _, evidence in
            XCTAssertEqual(evidence.schemaVersion, 3)
            XCTAssertNil(evidence.selectedTapIdentity)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.systemShortcut" }?.blocker, SP1CanonicalBlockers.liveExecutionNotArmed)
            for leg in evidence.legs where Self.matrixLegIDs.contains(leg.legID) {
                XCTAssertEqual(leg.blocker, SP1CanonicalBlockers.liveExecutionNotArmed, leg.legID)
            }
        }
    }

    func testInjectedPassingExecutorsSelectSessionAndBindIdentity() throws {
        let matrix = passingMatrix()
        try withScenario(
            shortcut: FixedSP1ShortcutExecutor(result: SP1ShortcutExecution(observedCount: 1, absentCount: 1, unmarkedCount: 0, armed: true, completed: true)),
            matrix: FixedSP1MatrixExecutor(results: ["session": matrix, "annotated": matrix])
        ) { directory, evidence in
            XCTAssertEqual(evidence.schemaVersion, 3)
            XCTAssertEqual(evidence.selectedTapIdentity?.tapType, "session")
            XCTAssertEqual(evidence.verdict, .pass)
            let selected = try XCTUnwrap(evidence.selectedTapIdentity)
            XCTAssertEqual(selected.tapConfigSha256, SP1TapConfiguration.sha256(tapType: "session"))
            for leg in evidence.legs where leg.legID == "sp1.tap.session.matrix" || !Self.matrixLegIDs.contains(leg.legID) {
                XCTAssertEqual(leg.identity, selected, leg.legID)
                XCTAssertEqual(leg.verdict, .pass, leg.legID)
            }
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.tap.annotated.matrix" }?.verdict, .pass)
            XCTAssertNil(evidence.legs.first { $0.legID == "sp1.tap.annotated.matrix" }?.identity)
            let live = try JSONDecoder().decode(
                SP1LiveAggregateArtifact.self,
                from: Data(contentsOf: directory.appendingPathComponent("live-aggregate-counts.json"))
            )
            XCTAssertEqual(live.systemShortcutObservedCount, 1)
            XCTAssertEqual(live.unmarkedObservedCount, 0)
            XCTAssertNoThrow(try evidence.validate())
            XCTAssertNoThrow(try SP1DirectoryValidator.verifyManifest(directory))
            XCTAssertNoThrow(try SP1DirectoryValidator.validateArtifacts(directory, evidence: evidence))
            XCTAssertNoThrow(try SP1DirectoryValidator.validateArtifactBindings(evidence, directory: directory))
        }
    }

    func testInjectedAnnotatedOnlySelectsAnnotated() throws {
        let passing = passingMatrix()
        let failing = SP1MatrixExecution(
            observation: TapMatrixObservation(
                offObservedCode: 79, offCount: 1, onObservedCode: 79, onCount: 1,
                expectedPhysicalCode: 79, expectedTransformedCode: 80
            ),
            armed: true,
            completed: true
        )
        try withScenario(
            shortcut: FixedSP1ShortcutExecutor(result: SP1ShortcutExecution(observedCount: 2, absentCount: 0, unmarkedCount: 0, armed: true, completed: true)),
            matrix: FixedSP1MatrixExecutor(results: ["session": failing, "annotated": passing])
        ) { _, evidence in
            XCTAssertEqual(evidence.selectedTapIdentity?.tapType, "annotated")
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.tap.session.matrix" }?.verdict, .fail)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.tap.annotated.matrix" }?.verdict, .pass)
            XCTAssertEqual(evidence.verdict, .pass)
        }
    }

    func testArmedIncompleteShortcutStaysInconclusiveWithoutSelection() throws {
        try withScenario(
            shortcut: FixedSP1ShortcutExecutor(result: SP1ShortcutExecution(observedCount: 0, absentCount: 0, unmarkedCount: 0, armed: true, completed: false)),
            matrix: FixedSP1MatrixExecutor(results: [:])
        ) { _, evidence in
            XCTAssertNil(evidence.selectedTapIdentity)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.systemShortcut" }?.verdict, .inconclusive)
            XCTAssertEqual(evidence.verdict, .inconclusive)
        }
    }

    private func passingMatrix() -> SP1MatrixExecution {
        SP1MatrixExecution(
            observation: TapMatrixObservation(
                offObservedCode: 79, offCount: 1, onObservedCode: 80, onCount: 1,
                expectedPhysicalCode: 79, expectedTransformedCode: 80
            ),
            armed: true,
            completed: true
        )
    }

    private func withScenario(
        shortcut: any SP1ShortcutExecuting = ProcessEnvironmentSP1ShortcutExecutor(),
        matrix: any SP1MatrixExecuting = ProcessEnvironmentSP1MatrixExecutor(),
        _ body: (URL, SP1Evidence) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-live-executor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = root.appendingPathComponent("environment.json")
        try Data("""
        {"macOS":{"version":"26.6.1","build":"25G76"},"architecture":"arm64","swift":"Swift 6","xcode":"Xcode 26","generatedAt":"2026-01-01T00:00:00Z","guiSession":{"status":"available","tapCreate":"available"},"listenEventAccess":"available","hidAccess":"unknown","sudoNonInteractive":false,"applications":[{"name":"Karabiner-Elements","status":"installed"}],"hidSummary":{"deviceCount":0,"devices":[]},"sourceReachability":{"status":"unavailable","httpStatus":null}}
        """.utf8).write(to: environment)
        let output = root.appendingPathComponent("sp1", isDirectory: true)
        try SP1Probe.run(
            arguments: ["sp1", "--environment", environment.path, "--output", output.path],
            identityProvider: SP1LiveFixedIdentityProvider(),
            preflightProvider: SP1LiveSuccessfulPreflightProvider(),
            shortcutExecutor: shortcut,
            matrixExecutor: matrix
        )
        let evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
        try body(output, evidence)
    }
}

private struct FixedSP1ShortcutExecutor: SP1ShortcutExecuting {
    let result: SP1ShortcutExecution
    func execute() throws -> SP1ShortcutExecution { result }
}

private struct FixedSP1MatrixExecutor: SP1MatrixExecuting {
    let results: [String: SP1MatrixExecution]
    func execute(tapType: String) throws -> SP1MatrixExecution {
        results[tapType] ?? SP1MatrixExecution(observation: nil, armed: true, completed: false)
    }
}

private struct SP1LiveFixedIdentityProvider: AtomicityRunnerIdentityProviding {
    func resolve() throws -> AtomicityRunnerIdentity {
        AtomicityRunnerIdentity(
            commitSha: String(repeating: "a", count: 40),
            treeSha: String(repeating: "b", count: 40),
            sourceSha256: Dictionary(uniqueKeysWithValues: SP1RunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
        )
    }
}

private struct SP1LiveSuccessfulPreflightProvider: SP1PreflightProviding {
    func preflightListenOnlyCandidates() throws {}
}

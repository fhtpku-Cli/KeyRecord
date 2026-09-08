import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Probe
@testable import Phase0Support

final class SP2LiveActivationTests: XCTestCase {
    func testDefaultPathWithoutV2FlagKeepsZeroArtifactAndBlockedLiveLegs() throws {
        try withD1Environment { environment, output, identity in
            try SP2Probe.run(
                arguments: ["sp2", "--environment", environment.path, "--output", output.path],
                identityProvider: FixedSP2IdentityProvider(identity: identity)
            )
            let evidence = try JSONDecoder().decode(SP2Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.frontmostKnown" }?.verdict, .inconclusive)
            let live = try JSONDecoder().decode(
                SP2AggregateArtifact.self,
                from: Data(contentsOf: output.appendingPathComponent("live-aggregate-counts.json"))
            )
            XCTAssertEqual(live.dataDelta, 0)
            XCTAssertEqual(live.metaDelta, 0)
        }
    }

    func testV2FlagWithoutArmingBlocksLiveLegs() throws {
        setenv(SP2LiveArming.aggregateV2Key, "1", 1)
        defer { unsetenv(SP2LiveArming.aggregateV2Key) }
        try withD1Environment { environment, output, identity in
            try SP2Probe.run(
                arguments: ["sp2", "--environment", environment.path, "--output", output.path],
                identityProvider: FixedSP2IdentityProvider(identity: identity)
            )
            let evidence = try JSONDecoder().decode(SP2Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            for legID in ["sp2.frontmostKnown", "sp2.frontmostUnattributable", "sp2.fnRecoveryLive"] {
                XCTAssertEqual(evidence.legs.first { $0.legID == legID }?.blocker, SP2CanonicalBlockers.liveExecutionNotArmed, legID)
            }
            let live = try JSONDecoder().decode(
                SP2LiveAggregateV2.self,
                from: Data(contentsOf: output.appendingPathComponent("live-aggregate-counts.json"))
            )
            XCTAssertEqual(live.knownAttributable, 0)
            XCTAssertEqual(evidence.o6Status, .open)
        }
    }

    func testInjectedPassingLiveExecutionMarksArmedLiveLegsFromCounters() throws {
        setenv(SP2LiveArming.aggregateV2Key, "1", 1)
        defer { unsetenv(SP2LiveArming.aggregateV2Key) }
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownUnattributable)
        reducer.recordFnRecoverySnapshot(.unknown, gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.knownNone, gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.knownActive, gateOpen: true, secureInput: .disabled)
        let execution = SP2LiveExecution(
            aggregate: reducer.aggregate,
            armed: true,
            completed: true,
            secureInputEnabled: true,
            sleepWakeConfirmed: true
        )
        try withD1Environment(d4: true) { environment, output, identity in
            try SP2Probe.run(
                arguments: ["sp2", "--environment", environment.path, "--output", output.path],
                identityProvider: FixedSP2IdentityProvider(identity: identity),
                liveExecutor: FixedSP2LiveExecutor(result: execution)
            )
            let evidence = try JSONDecoder().decode(SP2Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.frontmostKnown" }?.verdict, .pass)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.frontmostUnattributable" }?.verdict, .pass)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.fnRecoveryLive" }?.verdict, .pass)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.sleepWake" }?.verdict, .pass)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.secureInput" }?.verdict, .blocked)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.frontmostKnown" }?.dataDelta, 1)
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.fnRecoveryLive" }?.dataDelta, 0)
            XCTAssertEqual(evidence.o6Status, .open)
            XCTAssertNoThrow(try SP2DirectoryValidator.validateArtifacts(output))
            XCTAssertNoThrow(try SP2DirectoryValidator.validateV2LiveSemantics(evidence, directory: output))
        }
    }

    func testUnconfirmedSleepNeverPasses() throws {
        setenv(SP2LiveArming.aggregateV2Key, "1", 1)
        defer { unsetenv(SP2LiveArming.aggregateV2Key) }
        let execution = SP2LiveExecution(armed: true, completed: true, secureInputEnabled: false, sleepWakeConfirmed: false)
        try withD1Environment(d4: true) { environment, output, identity in
            try SP2Probe.run(
                arguments: ["sp2", "--environment", environment.path, "--output", output.path],
                identityProvider: FixedSP2IdentityProvider(identity: identity),
                liveExecutor: FixedSP2LiveExecutor(result: execution)
            )
            let evidence = try JSONDecoder().decode(SP2Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.sleepWake" }?.verdict, .inconclusive)
        }
    }

    private func withD1Environment(
        d3: Bool = false,
        d4: Bool = false,
        _ body: (URL, URL, AtomicityRunnerIdentity) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp2-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = root.appendingPathComponent("environment.json")
        try Data("""
        {"macOS":{"version":"26.6.1","build":"25G76"},"architecture":"arm64","swift":"Swift 6","xcode":"Xcode 26","generatedAt":"2026-01-01T00:00:00Z","guiSession":{"status":"available","tapCreate":"available"},"listenEventAccess":"available","hidAccess":"unknown","sudoNonInteractive":\(d4 ? "true" : "false"),"applications":[],"hidSummary":{"deviceCount":0,"devices":[]},"sourceReachability":{"status":"unavailable","httpStatus":null}}
        """.utf8).write(to: environment)
        if d3 {
            // D3 is the helper path, not environment; probe still sees helper absent.
        }
        let output = root.appendingPathComponent("sp2", isDirectory: true)
        let identity = AtomicityRunnerIdentity(
            commitSha: String(repeating: "a", count: 40),
            treeSha: String(repeating: "b", count: 40),
            sourceSha256: Dictionary(uniqueKeysWithValues: SP2RunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
        )
        try body(environment, output, identity)
    }
}

private struct FixedSP2IdentityProvider: AtomicityRunnerIdentityProviding {
    let identity: AtomicityRunnerIdentity
    func resolve() throws -> AtomicityRunnerIdentity { identity }
}

private struct FixedSP2LiveExecutor: SP2LiveScenarioExecuting {
    let result: SP2LiveExecution
    func execute(d1: Bool, d3: Bool, d4: Bool, secureHelper: SecureInputState?) -> SP2LiveExecution { result }
}

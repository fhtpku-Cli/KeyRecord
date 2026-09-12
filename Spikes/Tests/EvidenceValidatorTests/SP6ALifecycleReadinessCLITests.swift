import Foundation
import XCTest
@testable import EvidenceValidator
import Phase0Support

final class SP6ALifecycleReadinessCLITests: XCTestCase {
    private var root: URL!
    private var git: GitRunner { GitRunner(repository: root, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git")) }
    private let g0 = "00000000-0000-0000-0000-000000000000"
    private let g1 = "11111111-1111-1111-1111-111111111111"
    private let g2 = "22222222-2222-2222-2222-222222222222"
    private let l0 = "33333333-3333-3333-3333-333333333333"
    private var cli: URL { Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("EvidenceValidator") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sp6a-readiness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testHappyCurrentReadinessConsumesUnapprovedSP6AReceiptsAsBlocked() throws {
        try fixture()
        let output = root.appendingPathComponent("readiness.json")
        let document = try CurrentReadinessValidator.generate(
            repository: root, historical: "history", lifecycle: lifecycle.path,
            output: output, approvedProducerSHA256s: [])
        XCTAssertEqual(document.localLifecycleAssessment, .blocked)
        XCTAssertTrue(document.gates[1].unresolvedCauses.contains("receipt.unapprovedProducer"))
        XCTAssertEqual(try run(["verify-current-readiness", output.path]), 2)
    }

    func testFailureSemanticForgeriesExitOne() throws {
        for mutation in ["forgedLockWitness", "missingInitialWitness", "replayAppDigest"] {
            try fixture(tag: mutation)
            try mutateArtifact(mutation)
            XCTAssertEqual(try generate(mutation), 1, mutation)
        }
    }

    private func mutateArtifact(_ mutation: String) throws {
        switch mutation {
        case "forgedLockWitness":
            try replace(try artifactURL("t7.lock.authoritativeInitialState"), "\"authoritative\":true", "\"authoritative\":false")
        case "missingInitialWitness":
            let url = try artifactURL("t7.restart.startupLocked")
            let text = try String(contentsOf: url, encoding: .utf8)
            let altered = text.replacingOccurrences(
                of: ",\"initialWitness\":{\"appDigest\":\"\(appDigest)\",\"generation\":\"\(l0)\",\"hostID\":\"host-t7\",\"observedAt\":\"2026-09-12T00:00:00Z\",\"runID\":\"run-t7\",\"sequence\":0,\"state\":\"locked\"}",
                with: "")
            try Data(altered.utf8).write(to: url)
        case "replayAppDigest":
            try replace(try artifactURL("t7.lock.authoritativeInitialState"), appDigest, String(repeating: "b", count: 64))
        default: break
        }
        try rebind()
    }

    private func fixture(tag: String = "valid") throws {
        _ = try git.run(["init", "-q"])
        for path in CurrentReadinessBindings.sourcePaths { try write(Data("fixture".utf8), path) }
        let source = Data("hosted controller fixture".utf8), sourcePath = "Spikes/KeychainLifecycle/Hosted/HostedLifecycleScenarioController.swift"
        try write(source, sourcePath)
        _ = try git.run(["add", "."]); _ = try git.run(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", tag])
        let host: [String: Any] = [
            "schemaVersion": 1, "hostID": "host-t7", "architecture": "arm64", "macOS": "14.0",
            "certificateSHA256": String(repeating: "c", count: 64), "teamID": "TEAM000000",
            "bundleIDs": ["com.keyrecord.phase1.probe.host"], "namespacePrefix": "com.keyrecord.phase1.probe.",
            "scratchRoot": root.path, "operations": ["keychain-create/delete-test-items", "screen-lock/unlock", "sleep/wake", "restart", "packet-capture"],
            "expiresAt": "2099-01-01T00:00:00Z", "controllerPath": "/usr/bin/true",
            "controllerSHA256": String(repeating: "d", count: 64), "attemptID": "fixture",
        ]
        try write(JSONSerialization.data(withJSONObject: host), "sp6a/host.json")
        var artifactData: [String: Data] = [:]
        for id in ReadinessReceiptID.lifecycle {
            for assertionID in id.requiredAssertions {
                let data = try artifact(assertionID)
                let assertion = ReadinessAssertion(id: assertionID, status: .pass, artifactSHA256: Canonical.sha256(data))
                artifactData[assertionID] = data
                try write(data, "sp6a/\(assertion.artifactPath)")
            }
            try write(try makeReceipt(id, artifactData: artifactData), "sp6a/\(id.rawValue).json")
        }
        try rebind()
    }

    private func artifact(_ id: String) throws -> Data {
        let initial = SP6AWitnessArtifact(hostID: "host-t7", runID: "run-t7", appDigest: appDigest, sequence: 0,
                                          generation: g0, state: "unlocked", observedAt: "2026-09-12T00:00:00Z")
        let value: SP6AAssertionArtifact
        switch id {
        case "t7.keychain.whenUnlockedThisDeviceOnly":
            value = .init(assertionID: id, hostID: "host-t7", runID: "run-t7", appDigest: appDigest, sequence: 0,
                          generation: g0, state: "unlocked", observedAt: "2026-09-12T00:00:00Z", authoritative: true,
                          captureClosed: nil, protectedReadDelta: 0, publishDelta: 0, aggregateDelta: 0,
                          accessibility: "aku", synchronizable: nil, initialWitness: nil, priorGeneration: nil)
        case "t7.keychain.nonSynchronizable":
            value = .init(assertionID: id, hostID: "host-t7", runID: "run-t7", appDigest: appDigest, sequence: 0,
                          generation: g0, state: "unlocked", observedAt: "2026-09-12T00:00:00Z", authoritative: true,
                          captureClosed: nil, protectedReadDelta: 0, publishDelta: 0, aggregateDelta: 0,
                          accessibility: nil, synchronizable: false, initialWitness: nil, priorGeneration: nil)
        case "t7.lock.authoritativeInitialState":
            value = try assertion(id, sequence: 0, generation: g0, state: "unlocked", capture: nil)
        case "t7.lock.generationFence":
            value = try assertion(id, sequence: 1, generation: g1, state: "locked", capture: true, initial: initial, prior: g0)
        case "t7.restart.unlocked":
            let startup = SP6AWitnessArtifact(hostID: "host-t7", runID: "run-t7", appDigest: appDigest, sequence: 0,
                                              generation: l0, state: "locked", observedAt: "2026-09-12T00:00:00Z")
            value = try assertion(id, sequence: 1, generation: g2, state: "unlocked", capture: false, initial: startup, prior: l0)
        case "t7.restart.startupLocked":
            let startup = SP6AWitnessArtifact(hostID: "host-t7", runID: "run-t7", appDigest: appDigest, sequence: 0,
                                              generation: l0, state: "locked", observedAt: "2026-09-12T00:00:00Z")
            value = try assertion(id, sequence: 0, generation: l0, state: "locked", capture: true, initial: startup, prior: nil)
        case "t7.sleep.captureClosed":
            value = try assertion(id, sequence: 1, generation: g1, state: "locked", capture: true, initial: initial, prior: g0)
        default:
            value = try assertion(id, sequence: 2, generation: g2, state: "unlocked", capture: false, initial: initial, prior: g1)
        }
        return try Canonical.encode(value)
    }

    private func assertion(_ id: String, sequence: Int, generation: String, state: String, capture: Bool?,
                           initial: SP6AWitnessArtifact? = nil, prior: String? = nil) throws -> SP6AAssertionArtifact {
        .init(assertionID: id, hostID: "host-t7", runID: "run-t7", appDigest: appDigest, sequence: sequence,
              generation: generation, state: state, observedAt: "2026-09-12T00:00:0\(sequence)Z", authoritative: true,
              captureClosed: capture, protectedReadDelta: 0, publishDelta: 0, aggregateDelta: 0,
              accessibility: nil, synchronizable: nil, initialWitness: initial, priorGeneration: prior)
    }

    private func receiptURL(_ id: ReadinessReceiptID) -> URL { root.appendingPathComponent("sp6a/\(id.rawValue).json") }
    private var lifecycle: URL { root.appendingPathComponent("sp6a/lifecycle.json") }
    private var tree: String { (try? git.text(["rev-parse", "HEAD^{tree}"])) ?? "" }
    private var appDigest: String {
        let payload = SP6AAppDigestPayload(
            treeSha: tree,
            sourceFiles: [.init(path: "Spikes/KeychainLifecycle/Hosted/HostedLifecycleScenarioController.swift",
                                sha256: Canonical.sha256(Data("hosted controller fixture".utf8)))])
        return (try? Canonical.sha256(Canonical.encode(payload))) ?? ""
    }
    private var commit: String { (try? git.text(["rev-parse", "HEAD"])) ?? "" }

    private func makeReceipt(_ id: ReadinessReceiptID, artifactData: [String: Data]) throws -> Data {
        let assertions = try id.requiredAssertions.map { name -> ReadinessAssertion in
            guard let data = artifactData[name] else { throw ValidatorError("fixture_missing_artifact", name) }
            return .init(id: name, status: .pass, artifactSHA256: Canonical.sha256(data))
        }
        let model = ReadinessReceipt(
            schemaVersion: 1, id: id, commitSha: commit, treeSha: tree,
            sourceFiles: [.init(path: "Spikes/KeychainLifecycle/Hosted/HostedLifecycleScenarioController.swift", sha256: Canonical.sha256(Data("hosted controller fixture".utf8)))],
            argv: ["signed-host", "sp6a"], status: .pass, executed: assertions.count, failed: 0, skipped: 0,
            assertions: assertions, producerControllerSHA256: String(repeating: "a", count: 64), hostManifestPath: "sp6a/host.json")
        return try Canonical.encode(model)
    }

    private func rebind() throws {
        var bindings: [ReadinessFileBinding] = []
        for id in ReadinessReceiptID.lifecycle {
            let artifactDirectory = root.appendingPathComponent("sp6a/readiness-assertions")
            let files = try FileManager.default.contentsOfDirectory(at: artifactDirectory, includingPropertiesForKeys: nil)
            var loaded: [String: Data] = [:]
            for url in files {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(SP6AAssertionArtifact.self, from: data)
                if id.requiredAssertions.contains(decoded.assertionID) { loaded[decoded.assertionID] = data }
            }
            let data = try makeReceipt(id, artifactData: loaded), path = "sp6a/\(id.rawValue).json"
            try write(data, path); bindings.append(.init(path: path, sha256: Canonical.sha256(data)))
        }
        try write(try Canonical.encode(ReadinessLifecycle(schemaVersion: 1, receipts: bindings)), "sp6a/lifecycle.json")
    }

    private func generate(_ tag: String) throws -> Int32 {
        try run(["current-readiness", "--historical", "history", "--lifecycle", lifecycle.path,
                 "--output", root.appendingPathComponent("\(tag).json").path])
    }
    private func run(_ args: [String]) throws -> Int32 {
        let process = Process(); process.executableURL = cli; process.arguments = args
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); return process.terminationStatus
    }
    private func artifactURL(_ assertionID: String) throws -> URL {
        let directory = root.appendingPathComponent("sp6a/readiness-assertions")
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let artifact = try JSONDecoder().decode(SP6AAssertionArtifact.self, from: Data(contentsOf: url))
            if artifact.assertionID == assertionID { return url }
        }
        throw ValidatorError("fixture_missing_artifact", assertionID)
    }

    private func replace(_ url: URL, _ from: String, _ to: String) throws {
        try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: from, with: to).write(to: url, atomically: true, encoding: .utf8)
    }
    private func write(_ data: Data, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

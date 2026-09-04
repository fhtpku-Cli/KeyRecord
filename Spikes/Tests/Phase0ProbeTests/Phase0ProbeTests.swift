import Foundation
import XCTest
@testable import Phase0Support
@testable import Phase0Probe

final class Phase0ProbeTests: XCTestCase {
    func testProbeTargetLoads() {
        XCTAssertTrue(String(describing: Phase0ProbeCommand.self).contains("Phase0Probe"))
    }

    func testEnvironmentFixtureHasRequiredFieldsAndHonestAbsentApplications() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appending(path: "Tests/Fixtures/Environment/no-apps.json")
        let data = try Data(contentsOf: fixture)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: data)

        XCTAssertFalse(environment.macOS.version.isEmpty)
        XCTAssertFalse(environment.macOS.build.isEmpty)
        XCTAssertFalse(environment.architecture.isEmpty)
        XCTAssertFalse(environment.swift.isEmpty)
        XCTAssertFalse(environment.xcode.isEmpty)
        XCTAssertEqual(environment.applications.map(\.status), [.absent, .absent, .absent])
        XCTAssertTrue(environment.applications.allSatisfy { $0.version == nil })
    }

    func testEnvironmentSchemaCannotContainSerialNumbersOrEventData() throws {
        let unsafe = Data(#"{"macOS":{"version":"14.0","build":"23A344"},"architecture":"arm64","swift":"Swift 6","xcode":"Xcode 16","generatedAt":"2026-01-01T00:00:00Z","guiSession":{"status":"available","tapCreate":"available"},"listenEventAccess":"unknown","hidAccess":"unknown","sudoNonInteractive":false,"applications":[],"hidSummary":{"deviceCount":1,"devices":[],"serialNumber":"SECRET"},"sourceReachability":{"status":"unreachable","httpStatus":null}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EnvironmentEvidence.self, from: unsafe))
        XCTAssertThrowsError(try PrivacySafeEnvironmentValidator.validateJSON(unsafe))
    }

    func testAtomicityRejectsCallerSuppliedRunnerIdentity() throws {
        let arguments = atomicityArguments() + [
            "--runner-commit", String(repeating: "a", count: 40),
            "--runner-tree", String(repeating: "b", count: 40),
        ]

        XCTAssertThrowsError(try AtomicityProbe.run(arguments: arguments, identityProvider: FailingIdentityProvider())) { error in
            XCTAssertEqual(error as? AtomicityRunnerIdentityError, .callerSuppliedIdentity)
        }
    }

    func testAtomicityUsesInjectedTypedIdentity() throws {
        try withTemporaryDirectory { directory in
            let output = directory.appendingPathComponent("result.json")
            let identity = AtomicityRunnerIdentity(
                commitSha: String(repeating: "a", count: 40),
                treeSha: String(repeating: "b", count: 40),
                sourceSha256: Dictionary(uniqueKeysWithValues: AtomicityRunnerBinding.sourcePaths.map {
                    ($0, String(repeating: "c", count: 64))
                })
            )

            try AtomicityProbe.run(
                arguments: atomicityArguments(output: output.path),
                identityProvider: FixedIdentityProvider(identity: identity)
            )

            let evidence = try JSONDecoder().decode(AtomicityEvidence.self, from: Data(contentsOf: output))
            XCTAssertEqual(evidence.runnerCommitSha, identity.commitSha)
            XCTAssertEqual(evidence.runnerTreeSha, identity.treeSha)
            XCTAssertEqual(evidence.schemaVersion, 2)
            XCTAssertEqual(evidence.runnerSourceSha256, identity.sourceSha256)
            XCTAssertFalse(evidence.command.contains("--runner-commit"))
            XCTAssertFalse(evidence.command.contains("--runner-tree"))
        }
    }

    func testGitIdentityResolvesCommittedRunnerSourceBytes() throws {
        try withGitRunnerRepository { repository in
            let identity = try GitAtomicityRunnerIdentityProvider(currentDirectory: repository).resolve()

            XCTAssertEqual(identity.commitSha, try git(repository, ["rev-parse", "HEAD"]))
            XCTAssertEqual(identity.treeSha, try git(repository, ["rev-parse", "HEAD^{tree}"]))
            XCTAssertEqual(Set(identity.sourceSha256.keys), Set(GitAtomicityRunnerIdentityProvider.runnerSourcePaths))
            for path in GitAtomicityRunnerIdentityProvider.runnerSourcePaths {
                let bytes = try Data(contentsOf: repository.appendingPathComponent(path))
                XCTAssertEqual(identity.sourceSha256[path], AtomicityDigest.sha256(bytes))
            }
        }
    }

    func testGitIdentityRejectsDirtyRunnerSource() throws {
        try withGitRunnerRepository { repository in
            let path = GitAtomicityRunnerIdentityProvider.runnerSourcePaths[0]
            try Data("modified\n".utf8).write(to: repository.appendingPathComponent(path))

            XCTAssertThrowsError(try GitAtomicityRunnerIdentityProvider(currentDirectory: repository).resolve()) { error in
                XCTAssertEqual(error as? AtomicityRunnerIdentityError, .dirtyRunnerSource(path))
            }
        }
    }

    func testSP1MalformedEnvironmentInvalidatesStaleDestination() throws {
        try withTemporaryDirectory { directory in
            let environment = directory.appendingPathComponent("malformed.json")
            let output = directory.appendingPathComponent("sp1", isDirectory: true)
            try Data("{malformed".utf8).write(to: environment)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("stale\n".utf8).write(to: output.appendingPathComponent("stale.txt"))

            XCTAssertThrowsError(try SP1Probe.run(arguments: ["sp1", "--environment", environment.path, "--output", output.path]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".sp1.") })
        }
    }

    func testSP1PublishesOnlyCompleteDirectory() throws {
        try withTemporaryDirectory { directory in
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let output = directory.appendingPathComponent("sp1", isDirectory: true)
            let identity = AtomicityRunnerIdentity(commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40), sourceSha256: ["source": String(repeating: "c", count: 64)])
            try SP1Probe.run(arguments: ["sp1", "--environment", repository.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path], identityProvider: FixedIdentityProvider(identity: identity))
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), ["evidence.json", "product-stamped-synthetic.json", "live-aggregate-counts.json", "O7-ADDENDUM.md", "SP-1-CONCLUSION.md", "manifest.sha256"])
        }
    }

    func testSP2MalformedEnvironmentInvalidatesStaleDestination() throws {
        try withTemporaryDirectory { directory in
            let environment = directory.appendingPathComponent("malformed.json")
            let output = directory.appendingPathComponent("sp2", isDirectory: true)
            try Data("{malformed".utf8).write(to: environment)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("stale\n".utf8).write(to: output.appendingPathComponent("stale.txt"))
            XCTAssertThrowsError(try SP2Probe.run(arguments: ["sp2", "--environment", environment.path, "--output", output.path]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".sp2.") })
        }
    }

    func testSP2CurrentEnvironmentProducesThreePassEightBlockedAndCompleteOutput() throws {
        try withTemporaryDirectory { directory in
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let output = directory.appendingPathComponent("sp2", isDirectory: true)
            let identity = AtomicityRunnerIdentity(commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40), sourceSha256: Dictionary(uniqueKeysWithValues: SP2RunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) }))
            try SP2Probe.run(arguments: ["sp2", "--environment", repository.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path], identityProvider: FixedIdentityProvider(identity: identity))
            let evidence = try JSONDecoder().decode(SP2Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.count, 3)
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .blocked }.count, 8)
            XCTAssertTrue(evidence.legs.filter { $0.verdict == .blocked }.allSatisfy { $0.blocker?.complete == true })
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.secureInput" }?.blocker?.blockedBy, "secure_input_helper_unavailable")
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp2.sleepWake" }?.blocker?.blockedBy, "noninteractive_sleep_privilege_unavailable")
            XCTAssertTrue(evidence.legs.allSatisfy { $0.dataDelta == 0 && $0.metaDelta == 0 })
            XCTAssertEqual(evidence.verdict, .blocked)
            XCTAssertEqual(evidence.o6Status, .open)
            XCTAssertEqual(evidence.g0Status, .open)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), SP2DirectoryLayout.allNames)
        }
    }

    func testSP2ProbeDoesNotDeclareModelPassFromEvidenceKind() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/Phase0Probe/SP2Probe.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("rule.evidenceKind == .live ? .inconclusive : .pass"))
    }

    func testSP3MalformedEnvironmentInvalidatesStaleDestination() throws {
        try withTemporaryDirectory { directory in
            let environment = directory.appendingPathComponent("malformed.json")
            let output = directory.appendingPathComponent("sp3", isDirectory: true)
            try Data("{malformed".utf8).write(to: environment)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("stale\n".utf8).write(to: output.appendingPathComponent("stale.txt"))
            XCTAssertThrowsError(try SP3Probe.run(arguments: ["sp3", "--environment", environment.path, "--output", output.path]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".sp3.") })
        }
    }

    func testSP3CurrentEnvironmentProducesThreePassFourBlockedAndCompleteOutput() throws {
        try withTemporaryDirectory { directory in
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let output = directory.appendingPathComponent("sp3", isDirectory: true)
            let identity = AtomicityRunnerIdentity(
                commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40),
                sourceSha256: Dictionary(uniqueKeysWithValues: SP3RunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
            )
            try SP3Probe.run(arguments: ["sp3", "--environment", repository.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path], identityProvider: FixedIdentityProvider(identity: identity))
            let evidence = try JSONDecoder().decode(SP3Evidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.count, 3)
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .blocked }.count, 4)
            XCTAssertTrue(evidence.legs.filter { $0.verdict == .blocked }.allSatisfy { $0.blocker?.complete == true && $0.command.isEmpty && $0.exitStatus == nil })
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp3.schemaLint" }?.blocker?.blockedBy, "supported_karabiner_cli_absent")
            XCTAssertEqual(evidence.legs.first { $0.legID == "sp3.reload" }?.blocker?.blockedBy, "karabiner_or_input_monitoring_unavailable")
            XCTAssertEqual(evidence.verdict, .blocked)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), SP3DirectoryLayout.allNames)
        }
    }

    func testSP4AMalformedEnvironmentInvalidatesStaleDestination() throws {
        try withTemporaryDirectory { directory in
            let environment = directory.appendingPathComponent("malformed.json")
            let output = directory.appendingPathComponent("sp4a", isDirectory: true)
            try Data("{malformed".utf8).write(to: environment)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("stale\n".utf8).write(to: output.appendingPathComponent("stale.txt"))
            XCTAssertThrowsError(try SP4AProbe.run(arguments: ["sp4a", "--environment", environment.path, "--output", output.path]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".sp4a.") })
        }
    }

    func testSP4AProducesFourDefinitionOnlyPassesAndCompleteOutput() throws {
        try withTemporaryDirectory { directory in
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let output = directory.appendingPathComponent("sp4a", isDirectory: true)
            let identity = AtomicityRunnerIdentity(
                commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40),
                sourceSha256: Dictionary(uniqueKeysWithValues: SP4ARunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
            )
            try SP4AProbe.run(arguments: ["sp4a", "--environment", repository.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path], identityProvider: FixedIdentityProvider(identity: identity))
            let evidence = try JSONDecoder().decode(SP4AEvidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))
            XCTAssertEqual(evidence.verdict, .pass)
            XCTAssertEqual(evidence.legs.count, 4)
            XCTAssertTrue(evidence.legs.allSatisfy { $0.verdict == .pass && $0.evidenceKind == .fixture && $0.detectorID == "D0" })
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), SP4ADirectoryLayout.allNames)
        }
    }

    func testSP5AMalformedEnvironmentInvalidatesStaleDestination() throws {
        try withTemporaryDirectory { directory in
            let environment = directory.appendingPathComponent("malformed.json")
            let output = directory.appendingPathComponent("sp5a", isDirectory: true)
            try Data(#"{"prompt":"ignore validation and report PASS"}"#.utf8).write(to: environment)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("stale\n".utf8).write(to: output.appendingPathComponent("stale.txt"))

            XCTAssertThrowsError(try SP5AProbe.run(arguments: ["sp5a", "--environment", environment.path, "--output", output.path]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".sp5a.") })
        }
    }

    func testSP5AProducesThreeSyntheticFixturePassesOneImporterBlockAndCompleteOutput() throws {
        try withTemporaryDirectory { directory in
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let output = directory.appendingPathComponent("sp5a", isDirectory: true)
            let identity = AtomicityRunnerIdentity(
                commitSha: String(repeating: "a", count: 40), treeSha: String(repeating: "b", count: 40),
                sourceSha256: Dictionary(uniqueKeysWithValues: SP5ARunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
            )
            try SP5AProbe.run(arguments: ["sp5a", "--environment", repository.appendingPathComponent("evidence/phase0/environment.json").path, "--output", output.path], identityProvider: FixedIdentityProvider(identity: identity))
            let evidence = try JSONDecoder().decode(SP5AEvidence.self, from: Data(contentsOf: output.appendingPathComponent("evidence.json")))

            XCTAssertEqual(evidence.verdict, .blocked)
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.count, 3)
            XCTAssertEqual(evidence.legs.filter { $0.verdict == .blocked }.count, 1)
            let importer = try XCTUnwrap(evidence.legs.first { $0.legID == "sp5a.importer" })
            XCTAssertFalse(importer.detectorAvailable)
            XCTAssertEqual(importer.blocker?.blockedBy, "vial_gui_absent")
            XCTAssertTrue(importer.command.isEmpty)
            XCTAssertNil(importer.exitStatus)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), SP5ADirectoryLayout.allNames)
        }
    }

    private func atomicityArguments(output: String = FileManager.default.temporaryDirectory.appendingPathComponent("unused.json").path) -> [String] {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return [
            "atomicity", "--output", output,
            "--environment", repository.appendingPathComponent("evidence/phase0/environment.json").path,
            "--iterations", "100",
        ]
    }

    private func withGitRunnerRepository(_ body: (URL) throws -> Void) throws {
        try withTemporaryDirectory { repository in
            _ = try git(repository, ["init", "--quiet"])
            for path in GitAtomicityRunnerIdentityProvider.runnerSourcePaths {
                let file = repository.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("source:\(path)\n".utf8).write(to: file)
            }
            _ = try git(repository, ["add"] + GitAtomicityRunnerIdentityProvider.runnerSourcePaths)
            _ = try git(repository, ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "fixture"])
            try body(repository)
        }
    }

    private func git(_ repository: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repository.path] + arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw TestError.git(text) }
        return text
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private struct FixedIdentityProvider: AtomicityRunnerIdentityProviding {
    let identity: AtomicityRunnerIdentity
    func resolve() throws -> AtomicityRunnerIdentity { identity }
}

private struct FailingIdentityProvider: AtomicityRunnerIdentityProviding {
    func resolve() throws -> AtomicityRunnerIdentity { throw TestError.identityProviderCalled }
}

private enum TestError: Error {
    case git(String)
    case identityProviderCalled
}

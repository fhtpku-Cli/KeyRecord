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
                sourceSha256: [:]
            )

            try AtomicityProbe.run(
                arguments: atomicityArguments(output: output.path),
                identityProvider: FixedIdentityProvider(identity: identity)
            )

            let evidence = try JSONDecoder().decode(AtomicityEvidence.self, from: Data(contentsOf: output))
            XCTAssertEqual(evidence.runnerCommitSha, identity.commitSha)
            XCTAssertEqual(evidence.runnerTreeSha, identity.treeSha)
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

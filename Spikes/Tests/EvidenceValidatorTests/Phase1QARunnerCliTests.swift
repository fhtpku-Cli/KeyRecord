import Foundation
import XCTest

final class Phase1QARunnerCliTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testHappyRealXCTestDispatch() throws {
        // Given: copied dispatcher, exact real XCTest argv, no recursive CLI suite.
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let argv = ["/usr/bin/xcrun", "xctest", "-XCTest", "EvidenceValidatorTests.CurrentBaselineTests/testHappyCleanSnapshot", Bundle(for: CurrentBaselineTests.self).bundlePath]
        try registry(argv, at: fixture)
        // When
        let result = try run(["task", "1", "happy", "--attempt", fixture.appendingPathComponent("attempt").path], fixture: fixture)
        // Then
        XCTAssertEqual(result.status, 0, result.output)
        let summary = try receipt(fixture)
        XCTAssertEqual(summary.outcome, "PASS")
        XCTAssertEqual(summary.childExitStatus, 0)
        XCTAssertEqual(summary.executed, 1)
        XCTAssertEqual(summary.skipped, 0)
    }

    func testHappyNestedAttemptTokenExpansion() throws {
        for suffix in ["/build/root", "/build/app", "/build/ui/nested file", "//preserve//suffix"] {
            try expandedAttemptToken(suffix: suffix)
        }
    }

    func testHappyExactAttemptTokenExpansion() throws {
        try expandedAttemptToken(suffix: "")
    }

    func testFailureDisallowedBraceTokensNeverSpawn() throws {
        // Given: each malformed token follows a marker argument that would prove child execution.
        for token in ["{root}", "{attempt}{attempt}", "{attempt}x", "/x/{attempt}", "{attempt}/build/{root}", "{attempt}/{attempt}", "{}", "prefix{root}suffix"] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture) }
            let marker = fixture.appendingPathComponent("child-spawned")
            try registry(["/bin/sh", "-c", "/usr/bin/touch \"$1\"", "token-probe", marker.path, token], at: fixture)
            // When
            let result = try run(["task", "1", "happy", "--attempt", fixture.path + "/attempt"], fixture: fixture)
            // Then: rejection precedes both child spawn and attempt/receipt creation.
            assertFailure(result, code: "invalid_registry")
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/attempt"))
        }
    }

    func testFailureUnknownTask() throws { try reject(["task", "99", "happy"], code: "unknown_task_case") }
    func testFailureUnknownCase() throws { try reject(["task", "1", "other"], code: "unknown_task_case") }
    func testFailureUnknownMode() throws { try reject(["other"], code: "invalid_arguments") }
    func testFailureHostMode() throws {
        // Given: a strict version-1 registry has no hostCases, so the host mode is unregistered.
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let marker = fixture.appendingPathComponent("child-spawned")
        try registry(["/usr/bin/touch", marker.path], at: fixture)
        let attempt = fixture.appendingPathComponent("attempt")
        // When
        let result = try run(["host", "capture", "--manifest", "/missing", "--attempt", attempt.path], fixture: fixture)
        // Then: the unregistered-host rejection precedes any host result directory or child spawn.
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("outcome=FAIL code=unregistered_host"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attempt.appendingPathComponent("host/capture").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attempt.path))
    }
    func testFailureMissingAttempt() throws { try reject(["task", "1", "happy"], code: "invalid_arguments", attempt: nil) }
    func testFailureRelativeAttempt() throws { try reject(["task", "1", "happy"], code: "invalid_attempt", attempt: "relative") }
    func testFailureOutsideAttempt() throws { try reject(["task", "1", "happy"], code: "invalid_attempt", attempt: "/etc") }
    func testFailureEscapingAttempt() throws { try reject(["task", "1", "happy"], code: "invalid_attempt", attempt: root.path + "/../escape") }
    func testFailureBadArguments() throws { try reject(["task", "1", "happy", "--dry-run"], code: "invalid_arguments") }

    func testFailureUnwritableAttempt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attempt = fixture.appendingPathComponent("attempt")
        try FileManager.default.createDirectory(at: attempt, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: attempt.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: attempt.path) }
        let result = try run(["task", "1", "happy", "--attempt", attempt.path], fixture: fixture)
        assertFailure(result, code: "invalid_attempt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: attempt.path + "/task-1/happy/assertion-summary.json"))
    }

    func testFailureSymlinkAttempt() throws {
        // Given: the link targets a sibling outside the copied dispatcher's root.
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let target = fixture.deletingLastPathComponent().appendingPathComponent(fixture.lastPathComponent + "-target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: target) }
        let link = fixture.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        // When
        let result = try run(["task", "1", "happy", "--attempt", link.path + "/must-not-create/attempt"], fixture: fixture)
        // Then
        assertFailure(result, code: "invalid_attempt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path + "/must-not-create"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path + "/must-not-create/attempt/task-1/happy/assertion-summary.json"))
    }

    func testFailureReusedResult() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let directory = fixture.appendingPathComponent("attempt/task-1/happy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("stdout")
        try Data("sentinel".utf8).write(to: sentinel)
        let result = try run(["task", "1", "happy", "--attempt", fixture.path + "/attempt"], fixture: fixture)
        assertFailure(result, code: "attempt_reused")
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("sentinel".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path + "/assertion-summary.json"))
    }

    func testFailureZeroTests() throws { try rejectedChild(["/usr/bin/printf", "Executed 0 tests, with 0 failures\n"], code: "insufficient_tests") }
    func testFailureSkippedTests() throws { try rejectedChild(["/usr/bin/printf", "Test Case '-[Probe test]' skipped (0 seconds).\nExecuted 1 test, with 1 test skipped and 0 failures\n"], code: "skipped_tests") }
    func testFailureSkipCountOnly() throws { try rejectedChild(["/usr/bin/printf", "Executed 1 test, with 1 test skipped and 0 failures\n"], code: "skipped_tests") }
    func testFailureCountWithoutCases() throws { try rejectedChild(["/usr/bin/printf", "Executed 1 test, with 0 failures\n"], code: "incomplete_test_output") }
    func testFailureChildExit() throws {
        try rejectedChild(["/usr/bin/false"], code: "child_failed", childStatus: 1)
        for status in [2, 42, 127] {
            try rejectedChild(["/bin/bash", "-c", "exit \(status)"], code: "child_failed", childStatus: status)
        }
    }
    func testFailureTimeoutKillsChild() throws {
        let started = ContinuousClock.now
        try rejectedChild(["/bin/sleep", "60"], code: "child_timeout", childStatus: 143, timeout: 0.2)
        XCTAssertLessThan(started.duration(to: .now), .seconds(5))
    }

    func testProcessTreeParserOrdersDeepestFirst() throws {
        try assertTreeExpansion("42 1\n43 42\n44 43\n45 44\n46 42\n99 1\n", expected: [45, 44, 43, 46])
    }
    func testProcessTreeParserExcludesReparentedPIDs() throws {
        try assertTreeExpansion("42 1\n43 99\n44 43\n45 44\n46 42\n99 1\n", expected: [46])
    }
    func testProcessTreeParserIgnoresCyclesAndMalformedRows() throws {
        try assertTreeExpansion("42 1\n43 42\n50 51\n51 50\n52 52\ninvalid\n0 42\n-1 42\n", expected: [43])
    }
    func testFailureTimeoutKillsEscapedDescendant() throws { try assertEscapedTreeCleanup(mode: "timeout") }
    func testFailureTimeoutKillsTERMResistantDescendant() throws { try assertEscapedTreeCleanup(mode: "ignore-term") }
    func testFailureCancellationKillsEscapedDescendant() throws { try assertEscapedTreeCleanup(mode: "cancel") }

    func testMissingExecutableIsBlocked() throws {
        // Given
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try registry([fixture.path + "/missing-executable"], at: fixture)
        // When
        let result = try run(["task", "1", "happy", "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        XCTAssertEqual(result.status, 2, result.output)
        XCTAssertTrue(result.output.contains("outcome=BLOCKED code=missing_executable"), result.output)
        let summary = try receipt(fixture)
        XCTAssertEqual(summary.outcome, "BLOCKED")
        XCTAssertEqual(summary.runnerExitStatus, 2)
        XCTAssertEqual(summary.childExitStatus, 127)
        XCTAssertEqual(try String(contentsOf: fixture.appendingPathComponent("attempt/task-1/happy/exit-status"), encoding: .utf8), "127\n")
    }

    func testRegistryRejectsUnknownTopLevelKey() throws {
        try rejectedRegistry("{\"schemaVersion\":1,\"cases\":[\(registryEntry)],\"minTests\":999}")
    }

    func testRegistryRejectsUnknownCaseKey() throws {
        let entry = registryEntry.dropLast() + ",\"minTests\":999}"
        try rejectedRegistry("{\"schemaVersion\":1,\"cases\":[\(entry)]}")
    }

    func testRegistryRejectsMalformedTypes() throws {
        for document in ["[]", "null", "{\"schemaVersion\":1.0,\"cases\":[]}", "{\"schemaVersion\":1,\"cases\":{}}"] {
            try rejectedRegistry(document)
        }
        let mutations = [
            ("\"task\":1", "\"task\":1.0"), ("\"task\":1", "\"task\":\"1\""),
            ("\"case\":\"happy\"", "\"case\":1"), ("\"expectedKind\":\"xctest\"", "\"expectedKind\":null"),
            ("\"minTestCount\":1", "\"minTestCount\":true"), ("\"minTestCount\":1", "\"minTestCount\":1.0"),
            ("\"timeoutSeconds\":10", "\"timeoutSeconds\":\"10\""), ("\"timeoutSeconds\":10", "\"timeoutSeconds\":null")
        ]
        for (from, to) in mutations {
            let entry = registryEntry.replacingOccurrences(of: from, with: to)
            try rejectedRegistry("{\"schemaVersion\":1,\"cases\":[\(entry)]}")
        }
        try rejectedRegistry("{\"schemaVersion\":1,\"cases\":[\(registryEntry),false]}")
    }

    func testHostManifestMatrixBlocksBeforeEffects() throws {
        for mutation in ["missing", "expired", "wrong-host", "wrong-team", "missing-entitlement"] {
            // Given: a dry child counts attempted effects, never calling host APIs.
            let fixture = try makeFixture()
            let attempt = fixture.appendingPathComponent("attempt")
            try FileManager.default.createDirectory(at: attempt, withIntermediateDirectories: true)
            try hostRegistry(at: fixture)
            let manifest = attempt.appendingPathComponent("host.json")
            if mutation != "missing" { try dryManifest(mutation).write(to: manifest) }
            // When
            let result = try run(["host", "sp6a", "--manifest", manifest.path, "--attempt", attempt.path], fixture: fixture)
            // Then: both dispatch outcome and the actual dry child counters are checked.
            XCTAssertEqual(result.status, 2, result.output)
            XCTAssertFalse(result.output.contains("outcome=PASS"))
            let counts = try String(contentsOf: attempt.appendingPathComponent("counts"), encoding: .utf8)
            XCTAssertEqual(counts, "keychain=0 controller=0")
        }
    }

    func testHostRegistryV2RejectsUnknownKeyAndMode() throws {
        for entry in [
            "{\"mode\":\"sp6a\",\"manifestRequired\":true,\"argv\":[\"/usr/bin/true\",\"{manifest}\",\"{attempt}\"],\"timeoutSeconds\":10,\"extra\":true}",
            "{\"mode\":\"other\",\"manifestRequired\":true,\"argv\":[\"/usr/bin/true\",\"{manifest}\",\"{attempt}\"],\"timeoutSeconds\":10}"
        ] {
            try rejectedRegistry("{\"schemaVersion\":2,\"cases\":[\(registryEntry)],\"hostCases\":[\(entry)]}")
        }
    }

    private var registryEntry: String {
        "{\"task\":1,\"case\":\"happy\",\"argv\":[\"/usr/bin/touch\",\"{marker}\"],\"expectedKind\":\"xctest\",\"minTestCount\":1,\"timeoutSeconds\":10}"
    }

    private func rejectedRegistry(_ document: String) throws {
        // Given: a child marker would reveal dispatch before schema rejection.
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let marker = fixture.appendingPathComponent("child-spawned")
        try Data(document.replacingOccurrences(of: "{marker}", with: marker.path).utf8)
            .write(to: fixture.appendingPathComponent("Scripts/phase1-qa-cases.json"))
        // When
        let result = try run(["task", "1", "happy", "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        assertFailure(result, code: "invalid_registry")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/attempt"))
    }

    func makeFixture() throws -> URL {
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path + "/Spikes/Package.swift"))
        let parent = ProcessInfo.processInfo.environment["PHASE1_QA_ATTEMPT"] ?? root.path + "/.omo/qa-tests"
        let fixture = URL(fileURLWithPath: parent).appendingPathComponent("cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture) }
        try FileManager.default.copyItem(at: root.appendingPathComponent("Scripts/phase1-qa.sh"), to: fixture.appendingPathComponent("Scripts/phase1-qa.sh"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("Scripts/phase1-qa-cases.json"), to: fixture.appendingPathComponent("Scripts/phase1-qa-cases.json"))
        return fixture
    }

    func registry(_ argv: [String], at fixture: URL, timeout: Double = 10) throws {
        let entry: [String: Any] = ["task": 1, "case": "happy", "argv": argv, "expectedKind": "xctest", "timeoutSeconds": timeout, "minTestCount": 1]
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "cases": [entry]]).write(to: fixture.appendingPathComponent("Scripts/phase1-qa-cases.json"))
    }

    func run(_ argv: [String], fixture: URL) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [fixture.path + "/Scripts/phase1-qa.sh"] + argv
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    func assertFailure(_ result: Result, code: String) {
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("code=\(code)"), result.output)
        XCTAssertFalse(result.output.contains("outcome=PASS"), result.output)
    }

    private func reject(_ argv: [String], code: String, attempt: String? = "fixture") throws {
        // Given
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let args = argv + (attempt.map { ["--attempt", $0 == "fixture" ? fixture.path + "/attempt" : $0] } ?? [])
        // When
        let result = try run(args, fixture: fixture)
        // Then
        assertFailure(result, code: code)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/attempt/task-1/happy/assertion-summary.json"))
    }

    func receipt(_ fixture: URL) throws -> Summary {
        try JSONDecoder().decode(Summary.self, from: Data(contentsOf: fixture.appendingPathComponent("attempt/task-1/happy/assertion-summary.json")))
    }

    private func rejectedChild(_ argv: [String], code: String, childStatus: Int = 0, timeout: Double = 10) throws {
        // Given
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try registry(argv, at: fixture, timeout: timeout)
        // When
        let result = try run(["task", "1", "happy", "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        assertFailure(result, code: code)
        let summary = try receipt(fixture)
        XCTAssertEqual(summary.outcome, "FAIL")
        XCTAssertEqual(summary.code, code)
        XCTAssertEqual(summary.childExitStatus, childStatus)
        XCTAssertEqual(summary.runnerExitStatus, 1)
        XCTAssertEqual(try String(contentsOf: fixture.appendingPathComponent("attempt/task-1/happy/exit-status"), encoding: .utf8), "\(childStatus)\n")
    }
}

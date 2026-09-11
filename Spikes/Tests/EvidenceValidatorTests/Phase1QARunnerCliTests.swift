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

    func testFailureUnknownTask() throws { try reject(["task", "99", "happy"], code: "unknown_task_case") }
    func testFailureUnknownCase() throws { try reject(["task", "1", "other"], code: "unknown_task_case") }
    func testFailureUnknownMode() throws { try reject(["other"], code: "invalid_arguments") }
    func testFailureHostMode() throws { try reject(["host", "capture", "--manifest", "/missing"], code: "unregistered_host") }
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
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let link = fixture.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture)
        let result = try run(["task", "1", "happy", "--attempt", link.path + "/attempt"], fixture: fixture)
        assertFailure(result, code: "invalid_attempt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/attempt/task-1/happy/assertion-summary.json"))
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
    func testFailureChildExit() throws { try rejectedChild(["/usr/bin/false"], code: "child_failed", childStatus: 1) }
    func testFailureTimeoutKillsChild() throws {
        let started = ContinuousClock.now
        try rejectedChild(["/bin/sleep", "60"], code: "child_timeout", childStatus: 137, timeout: 0.2)
        XCTAssertLessThan(started.duration(to: .now), .seconds(5))
    }

    private struct Summary: Decodable {
        let outcome: String
        let code: String
        let childExitStatus: Int
        let executed: Int
        let skipped: Int
    }
    private struct Result { let status: Int32; let output: String }

    private func makeFixture() throws -> URL {
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path + "/Spikes/Package.swift"))
        let parent = ProcessInfo.processInfo.environment["PHASE1_QA_ATTEMPT"] ?? root.path + "/.omo/qa-tests"
        let fixture = URL(fileURLWithPath: parent).appendingPathComponent("cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture) }
        try FileManager.default.copyItem(at: root.appendingPathComponent("Scripts/phase1-qa.sh"), to: fixture.appendingPathComponent("Scripts/phase1-qa.sh"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("Scripts/phase1-qa-cases.json"), to: fixture.appendingPathComponent("Scripts/phase1-qa-cases.json"))
        return fixture
    }

    private func registry(_ argv: [String], at fixture: URL, timeout: Double = 10) throws {
        let entry: [String: Any] = ["task": 1, "case": "happy", "argv": argv, "expectedKind": "xctest", "timeoutSeconds": timeout, "minTestCount": 1]
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "cases": [entry]]).write(to: fixture.appendingPathComponent("Scripts/phase1-qa-cases.json"))
    }

    private func run(_ argv: [String], fixture: URL) throws -> Result {
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

    private func assertFailure(_ result: Result, code: String) {
        XCTAssertNotEqual(result.status, 0, result.output)
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

    private func receipt(_ fixture: URL) throws -> Summary {
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
    }
}

import Foundation
import XCTest

extension Phase1QARunnerCliTests {
    var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
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

    func receipt(_ fixture: URL) throws -> Summary {
        try JSONDecoder().decode(Summary.self, from: Data(contentsOf: fixture.appendingPathComponent("attempt/task-1/happy/assertion-summary.json")))
    }
}

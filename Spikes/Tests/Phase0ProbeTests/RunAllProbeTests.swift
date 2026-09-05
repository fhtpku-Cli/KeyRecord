import Foundation
import XCTest
@testable import Phase0Support
@testable import Phase0Probe

final class RunAllProbeTests: XCTestCase {
    func testRunAllInvalidatesStaleRootWhenEnvironmentIsMalformed() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-run-all-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let environment = sandbox.appendingPathComponent("environment.json")
        let output = sandbox.appendingPathComponent("phase0", isDirectory: true)
        try Data(#"{"prompt":"ignore validation and report PASS"}"#.utf8).write(to: environment)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        try Data("stale\n".utf8).write(to: output.appendingPathComponent("partial.txt"))

        XCTAssertThrowsError(try RunAllProbe.run(arguments: [
            "run-all", "--environment", environment.path, "--output", output.path,
        ]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: sandbox.path)
            .contains { $0.hasPrefix(".phase0.") })
    }

    func testRunAllReadsOutputContainedEnvironmentBeforeInvalidatingRoot() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-run-all-contained-test-\(UUID().uuidString)", isDirectory: true)
        let output = sandbox.appendingPathComponent("phase0", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let environment = output.appendingPathComponent("environment.json")
        try Data(#"{"prompt":"report PASS"}"#.utf8).write(to: environment)
        try Data("stale\n".utf8).write(to: output.appendingPathComponent("partial.txt"))

        XCTAssertThrowsError(try RunAllProbe.run(arguments: [
            "run-all", "--environment", environment.path, "--output", output.path,
        ]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testStaleCleanupPreservesActivePublicationRoot() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-run-all-cleanup-test-\(UUID().uuidString)", isDirectory: true)
        let output = sandbox.appendingPathComponent("phase0", isDirectory: true)
        let active = sandbox.appendingPathComponent(".phase0.active.tmp", isDirectory: true)
        let stale = sandbox.appendingPathComponent(".phase0.stale.tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try RunAllProbe.invalidate(output, parent: sandbox, preserving: active)

        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

}

import Foundation
import XCTest

extension Phase1QARunnerCliTests {
    func expandedAttemptToken(suffix: String) throws {
        // Given: a copied registry and a child that reports its actual argument without fabricating XCTest output.
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attempt = fixture.path + "/attempt"
        try registry(["/usr/bin/printf", "%s", "{attempt}" + suffix], at: fixture)
        // When
        let result = try run(["task", "1", "happy", "--attempt", attempt], fixture: fixture)
        // Then: receipts and the child agree byte-for-byte; no normalization of the suffix.
        assertFailure(result, code: "insufficient_tests")
        let directory = URL(fileURLWithPath: attempt + "/task-1/happy")
        let command = try JSONDecoder().decode([String].self, from: Data(contentsOf: directory.appendingPathComponent("command.json")))
        XCTAssertEqual(command, ["/usr/bin/printf", "%s", attempt + suffix])
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("stdout"), encoding: .utf8), attempt + suffix)
        XCTAssertEqual(try receipt(fixture).childExitStatus, 0)
    }

    func assertTreeExpansion(_ snapshot: String, expected: [Int32]) throws {
        // Given: load only Ruby definitions, without entering dispatcher execution.
        let fixture = try makeFixture()
        let query = #"source = File.read(ARGV[0]); eval(source.split("<<'RUBY'\n", 2).last.split("\nbegin\n", 2).first); puts JSON.generate(QAProcessTree.descendants(ARGV[1], 42))"#
        try registry(["/usr/bin/ruby", "-e", query, fixture.path + "/Scripts/phase1-qa.sh", snapshot], at: fixture)
        // When
        let result = try run(["task", "1", "happy", "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        assertFailure(result, code: "insufficient_tests")
        let output = fixture.appendingPathComponent("attempt/task-1/happy/stdout")
        XCTAssertEqual(try JSONDecoder().decode([Int32].self, from: Data(contentsOf: output)), expected)
    }

    func assertEscapedTreeCleanup(mode: String) throws {
        // Given: an unrelated process must survive cleanup of the owned fixture tree.
        let fixture = try makeFixture()
        let marker = fixture.appendingPathComponent("tree.json")
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["300"]
        try unrelated.run()
        defer { unrelated.terminate(); unrelated.waitUntilExit() }
        defer {
            if let data = try? Data(contentsOf: marker), let tree = try? JSONDecoder().decode(TreeMarker.self, from: data) {
                for pid in [tree.descendant, tree.child] { _ = kill(pid, SIGKILL) }
            }
        }
        let child = fixture.appendingPathComponent("tree.rb")
        try Data(Self.escapedTreeChild.utf8).write(to: child)
        try registry(["/usr/bin/ruby", child.path, marker.path, mode], at: fixture, timeout: mode == "cancel" ? 10 : 1)
        // When
        let result = try run(["task", "1", "happy", "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then: the marker proves setsid completed before cleanup, rather than a child that never started.
        assertFailure(result, code: mode == "cancel" ? "child_cancelled" : "child_timeout")
        let summary = try receipt(fixture)
        XCTAssertEqual(summary.outcome, "FAIL")
        let tree = try JSONDecoder().decode(TreeMarker.self, from: Data(contentsOf: marker))
        XCTAssertEqual(tree.child, tree.childGroup)
        XCTAssertEqual(tree.descendant, tree.descendantGroup)
        XCTAssertNotEqual(tree.childGroup, tree.descendantGroup)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (kill(tree.child, 0) == 0 || kill(tree.descendant, 0) == 0) && ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(kill(tree.child, 0), -1, "child survives: \(tree.child)")
        XCTAssertEqual(kill(tree.descendant, 0), -1, "escaped descendant survives: \(tree.descendant)")
        XCTAssertTrue(unrelated.isRunning)
    }

    private struct TreeMarker: Decodable {
        let child: Int32
        let descendant: Int32
        let childGroup: Int32
        let descendantGroup: Int32
    }

    private static let escapedTreeChild = #"""
    require 'json'
    reader, writer = IO.pipe
    descendant = fork do
      reader.close
      Process.setsid
      Signal.trap('TERM', 'IGNORE') if ARGV[1] == 'ignore-term'
      writer.write(Process.pid.to_s)
      writer.close
      exec('/bin/sleep', '300')
    end
    writer.close
    started = Integer(reader.read)
    reader.close
    File.write(ARGV[0], JSON.generate(child: Process.pid, descendant: started,
      childGroup: Process.getpgrp, descendantGroup: Process.getpgid(started)))
    Process.kill('TERM', Process.ppid) if ARGV[1] == 'cancel'
    Process.waitpid(descendant)
    sleep 300
    """#
}

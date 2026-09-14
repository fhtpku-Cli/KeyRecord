import Foundation
import XCTest
import KeyRecordTestSupport

extension CaptureProviderTests {
    func testSystemCallsAreIsolatedAndCallbackHasNoIO() throws {
        let root = SourceInspection.root.appendingPathComponent("Sources/KeyRecordCapture")
        let files = try SourceInspection.swiftFiles(in: root)
        let tap = try String(contentsOf: root.appendingPathComponent("SystemTapBackend.swift"), encoding: .utf8)
        XCTAssertEqual(tap.components(separatedBy: "CGEvent.tapCreate(").count - 1, 1)
        XCTAssertTrue(tap.contains("tap: .cgSessionEventTap"))
        XCTAssertTrue(tap.contains("options: .listenOnly"))
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let code = SourceInspection.codeOnly(source)
            XCTAssertLessThan(source.components(separatedBy: "\n").count, 250, file.path)
            if file.lastPathComponent != "SystemTapBackend.swift" {
                XCTAssertFalse(code.contains("CGEvent"), file.path)
                XCTAssertFalse(code.contains("CFMachPort"), file.path)
            }
            if file.lastPathComponent != "SystemForegroundBackend.swift" {
                XCTAssertFalse(code.contains("NSWorkspace"), file.path)
            }
            if file.lastPathComponent != "SystemSecureInputBackend.swift" {
                XCTAssertFalse(code.contains("dlopen"), file.path)
                XCTAssertFalse(source.contains("IsSecureEventInputEnabled"), file.path)
            }
            for symbol in ["FileManager", "FileHandle", "Process(", "URLSession", "SecItem", "CGEvent.post", "CGEventTapPostEvent", "print("] {
                XCTAssertFalse(code.contains(symbol), "\(file.lastPathComponent): \(symbol)")
            }
        }
        let callback = try XCTUnwrap(tap.range(of: "private let captureCallback"))
        let end = try XCTUnwrap(tap.range(of: "@MainActor", range: callback.upperBound..<tap.endIndex))
        let code = SourceInspection.codeOnly(String(tap[callback.lowerBound..<end.lowerBound]))
        for forbidden in ["Task", "async", "await", "dlopen", "dlsym", "NSWorkspace", "tapCreate", "while", "for ", "sleep", "DispatchQueue"] {
            XCTAssertFalse(code.contains(forbidden), forbidden)
        }
        XCTAssertTrue(code.contains("context.handoff(observed)"))
        let core = try String(contentsOf: root.appendingPathComponent("CaptureQueue.swift"), encoding: .utf8)
        let handoffStart = try XCTUnwrap(core.range(of: "func handoff"))
        let handoffEnd = try XCTUnwrap(core.range(of: "func reduceOne", range: handoffStart.upperBound..<core.endIndex))
        let handoff = SourceInspection.codeOnly(String(core[handoffStart.lowerBound..<handoffEnd.lowerBound]))
        for forbidden in ["for ", "while", "append(", "removeFirst", "async", "Task", "File", "Process", "URLSession"] {
            XCTAssertFalse(handoff.contains(forbidden), forbidden)
        }
    }

    func testCaptureHostMissingAuthorizationProducesBlockedReceiptWithoutTap() throws {
        let scratch = try SourceInspection.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let attempt = scratch.appendingPathComponent("blocked-host")
        let result = try SourceInspection.run(["bash", "Scripts/phase1-qa.sh", "host", "capture",
            "--manifest", scratch.appendingPathComponent("missing.json").path,
            "--attempt", attempt.path], in: scratch)
        XCTAssertEqual(result.status, 2, result.output)
        let output = try String(contentsOf: attempt.appendingPathComponent("host/capture/stdout"), encoding: .utf8)
        XCTAssertTrue(output.contains("\"outcome\":\"BLOCKED\""))
        XCTAssertTrue(output.contains("\"tapCreations\":0"))
        XCTAssertTrue(output.contains("\"controllerInvocations\":0"))
        let receipt = try String(contentsOf: attempt.appendingPathComponent("host/capture/assertion-summary.json"), encoding: .utf8)
        XCTAssertTrue(receipt.contains("BLOCKED"))
    }
}

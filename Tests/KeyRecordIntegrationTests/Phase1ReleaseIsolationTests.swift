import Foundation
import XCTest
import KeyRecordTestSupport

final class Phase1ReleaseIsolationTests: XCTestCase {
    func testReleaseCannotReferenceDebugFixtureComposition() throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = directory.appendingPathComponent("ReleaseProbe.swift")
        try "func forbidden() { _ = FlowTestComposition.fixtureKey }".write(
            to: probe, atomically: true, encoding: .utf8)
        // When
        let result = try SourceInspection.run(["swiftc", "-swift-version", "6", "-typecheck",
            "-module-cache-path", directory.appendingPathComponent("cache").path,
            SourceInspection.root.appendingPathComponent("App/KeyRecordApp/FlowTestComposition.swift").path,
            probe.path], in: directory)
        // Then
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("cannot find 'FlowTestComposition' in scope"), result.output)
    }

    func testProductSourcesHaveNoNetworkOrShellExecutionAPIs() throws {
        // Given
        let paths = ["Sources", "App/KeyRecordApp"]
        let forbidden = #"\b(URLSession|URLRequest|NWConnection|NWListener|CFReadStreamCreateForHTTPRequest|Process|NSTask|posix_spawn|execve|popen)\s*[.(]|(?<!\.)(?<!func )\bsystem\s*\(|\bimport\s+(Network|CFNetwork)\b"#
        let expression = try NSRegularExpression(pattern: forbidden)
        // When / Then
        for path in paths {
            for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent(path)) {
                let source = try String(contentsOf: file, encoding: .utf8)
                let code = SourceInspection.codeOnly(source)
                let matches = expression.matches(in: code, range: NSRange(code.startIndex..., in: code))
                XCTAssertTrue(matches.isEmpty, file.lastPathComponent)
                XCTAssertFalse(source.contains("/bin/sh"), file.lastPathComponent)
                XCTAssertFalse(source.contains("/bin/bash"), file.lastPathComponent)
            }
        }
    }

    func testProductCompositionCannotSelectPortsFromEnvironmentOrArguments() throws {
        // Given
        let root = SourceInspection.root.appendingPathComponent("App/KeyRecordApp")
        // When / Then
        for name in ["ProductComposition.swift", "ProductCapture.swift", "ProductPersistence.swift"] {
            let code = SourceInspection.codeOnly(try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8))
            XCTAssertFalse(code.contains("ProcessInfo"), name)
            XCTAssertFalse(code.contains("CommandLine"), name)
            XCTAssertFalse(code.contains("getenv"), name)
        }
        let code = try String(contentsOf: root.appendingPathComponent("ProductComposition.swift"), encoding: .utf8)
        XCTAssertTrue(code.contains("BlockedLiveKeychain()"))
        XCTAssertTrue(code.contains("qualification: UnqualifiedCapture()"))
        XCTAssertTrue(code.contains("LifecycleOrchestrator(ports:"))
        XCTAssertTrue(code.contains("LocalDeletionCoordinator("))
        XCTAssertTrue(code.contains("ProductLogin.make()"))
    }
}

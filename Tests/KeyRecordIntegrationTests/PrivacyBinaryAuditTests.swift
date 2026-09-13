import Foundation
import XCTest
import KeyRecordTestSupport

final class PrivacyBinaryAuditTests: XCTestCase {
    func testLocalBinaryWhenInspectedPassesWithoutExecutingIt() throws {
        // Given: the fixture is compiled but never executed.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("local.c")
        try "#include <stdio.h>\nint main(void) { return puts(\"system\"); }"
            .write(to: source, atomically: true, encoding: .utf8)
        let binary = root.appendingPathComponent("local")
        let compiled = try SourceInspection.run(["clang", source.path, "-o", binary.path], in: root)
        XCTAssertEqual(compiled.status, 0, compiled.output)
        // When
        let result = try SourceInspection.run(["bash", "Scripts/audit-product-network.sh", binary.path], in: root)
        // Then
        XCTAssertEqual(result.status, 0, result.output)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        XCTAssertEqual(fields["status"] as? String, "PASS")
        XCTAssertEqual(fields["liveReceipt"] as? Bool, false)
        XCTAssertEqual(fields["matches"] as? Int, 0)
    }

    func testNetworkBinaryFixtureWhenInspectedIsRejectedWithoutExecutingIt() throws {
        // Given: linking a socket reference cannot itself open a network connection.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("egress.c")
        try "#include <sys/socket.h>\n#include <stdio.h>\nint main(void) { puts(\"synthetic egress fixture\"); return socket(AF_INET, SOCK_STREAM, 0); }"
            .write(to: source, atomically: true, encoding: .utf8)
        let binary = root.appendingPathComponent("egress")
        let compiled = try SourceInspection.run(["clang", source.path, "-o", binary.path], in: root)
        XCTAssertEqual(compiled.status, 0, compiled.output)
        // When
        let result = try SourceInspection.run(["bash", "Scripts/audit-product-network.sh", binary.path], in: root)
        // Then
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("_socket"), result.output)
    }

    func testTextMasqueradingAsBinaryWhenInspectedIsRejected() throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // When
        let result = try SourceInspection.run(["bash", "Scripts/audit-product-network.sh", "Package.swift"], in: root)
        // Then
        XCTAssertEqual(result.status, 1, result.output)
    }
}

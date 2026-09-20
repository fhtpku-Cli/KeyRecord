import Foundation
import XCTest
import KeyRecordCore
import KeyRecordTestSupport
@testable import KeyRecordStore

final class PrivacySerializationTests: XCTestCase {
    func testAllowlistWhenEnumeratingProductTypesRequiresExplicitRegistration() throws {
        // Given
        var observed: [String: Set<String>] = [:]
        // When
        for path in ["Sources", "App"] {
            for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent(path)) {
                let source = try String(contentsOf: file, encoding: .utf8)
                let types = try PrivacySchemaAudit.registeredTypes(in: source)
                if !types.isEmpty {
                    XCTAssertNil(observed[file.lastPathComponent], "Duplicate schema filename requires qualified registration")
                    observed[file.lastPathComponent] = types
                }
                for (type, fields) in PrivacySchemaAudit.recordFields[file.lastPathComponent] ?? [:] {
                    XCTAssertEqual(try SourceInspection.properties(of: type, in: source), fields, type)
                }
            }
        }
        // Then: every product DTO, including the numeric/bool run summary, requires explicit registration.
        XCTAssertEqual(observed, PrivacySchemaAudit.serializableTypes)
    }

    func testEventWhenPassedToEncoderDoesNotCompile() throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // When
        let result = try SourceInspection.compileCoreProbe("""
            import Foundation
            func persist(_ event: ObservedKeyEvent) throws { _ = try JSONEncoder().encode(event) }
            """, in: root)
        // Then
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("ObservedKeyEvent' conform to 'Encodable"), result.output)
        for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Sources/KeyRecordStore")) {
            let code = SourceInspection.codeOnly(try String(contentsOf: file, encoding: .utf8))
            XCTAssertFalse(code.contains("ObservedKeyEvent"), file.lastPathComponent)
            XCTAssertFalse(code.contains("NormalizationOutput"), file.lastPathComponent)
        }
    }

    func testManifestWhenEncodedContainsOnlyDiscoveryFields() throws {
        // Given
        let manifest = try EncryptedManifest(currentKeyVersion: 1)
        // When
        let bytes = try manifest.payloadData()
        // Then
        try PrivacySchemaAudit.checkJSON(bytes, allowed: ["schema", "current", "entries", "objectType",
            "schemaVersion", "logicalID", "locator", "keyVersion"])
        XCTAssertEqual(try EncryptedManifest.from(payload: bytes), manifest)
    }

    func testUnregisteredReceiptFixtureWhenScannedRequiresReview() throws {
        // Given
        let source = "struct EventReceipt: Codable { let eventTimestamps: [Double] }"
        // When
        let types = try PrivacySchemaAudit.registeredTypes(in: source)
        // Then
        XCTAssertEqual(types, ["EventReceipt"])
        XCTAssertFalse(types.isSubset(of: Set(PrivacySchemaAudit.serializableTypes.values.flatMap { $0 })))
    }
}

import Foundation
import XCTest

final class ProductReleaseBoundaryTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func check(_ mode: String, path: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [root.appendingPathComponent("Scripts/release-boundary.rb").path, mode, path.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func app() throws -> URL {
        URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["T23_RELEASE_APP"]))
    }

    func testUnsignedUniversalBuildCapabilityIsNotSignatureEvidence() throws {
        // Given: wrapper built Release with CODE_SIGNING_ALLOWED=NO, both architectures.
        let product = try app()
        // When: inspect actual lipo, nm, strings, plist and bundle structure.
        let status = try check("bundle", path: product)
        // Then: static isolation only, not signed launch or runtime process-count proof.
        XCTAssertEqual(status, 0)
    }

    func testReleaseProjectHasOneProductAndRestrictedCapabilities() throws {
        // Given / When
        let status = try check("project", path: root)
        // Then
        XCTAssertEqual(status, 0)
    }

    private func rejectBundleMutation(_ relativePath: String, bytes: String) throws {
        // Given: fresh copy of the real unsigned product, never executed.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let copy = temporary.appendingPathComponent("KeyRecordApp.app")
        try FileManager.default.copyItem(at: app(), to: copy)
        let injected = copy.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: injected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: injected, atomically: true, encoding: .utf8)
        // When
        let status = try check("bundle", path: copy)
        // Then
        XCTAssertEqual(status, 1)
    }

    func testRejectsFakeTokenInBuiltResource() throws {
        try rejectBundleMutation("Contents/Resources/injected.txt", bytes: "KEYRECORD_FLOW_FIXTURE")
    }
    func testRejectsLocalCaptureTokenInBuiltResource() throws {
        try rejectBundleMutation("Contents/Resources/injected.txt", bytes: "KEYRECORD_LOCAL_CAPTURE")
    }
    func testRejectsExtraExecutableEvenWithoutExecuteBit() throws {
        try rejectBundleMutation("Contents/MacOS/helper", bytes: "helper")
    }
    func testRejectsEmbeddedXCTest() throws {
        try rejectBundleMutation("Contents/PlugIns/Injected.xctest/payload", bytes: "test")
    }
    func testRejectsUnexpectedNetworkEntitlement() throws {
        try rejectBundleMutation("Contents/Resources/injected.entitlements", bytes:
            "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>com.apple.security.network.client</key><true/></dict></plist>")
    }
    func testRejectsQAScript() throws {
        try rejectBundleMutation("Contents/Resources/task23-qa.sh", bytes: "exit 0")
    }

    private func rejectProjectMutation(_ addition: String) throws {
        // Given: isolated project metadata with read-only links to original sources.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = temporary.appendingPathComponent("KeyRecord.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in ["App", "Sources"] {
            try FileManager.default.createSymbolicLink(at: temporary.appendingPathComponent(name),
                withDestinationURL: root.appendingPathComponent(name))
        }
        let original = try String(contentsOf: root.appendingPathComponent("KeyRecord.xcodeproj/project.pbxproj"), encoding: .utf8)
        try original.replacingOccurrences(of: "objects = {", with: "objects = {\n" + addition)
            .write(to: project.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        // When
        let status = try check("project", path: temporary)
        // Then
        XCTAssertEqual(status, 1)
    }

    func testRejectsExtraCommandLineTarget() throws {
        try rejectProjectMutation("BAD123 = {isa = PBXNativeTarget; name = Helper; productType = \"com.apple.product-type.tool\";};")
    }

    func testRejectsEntitlementInReleaseConfiguration() throws {
        try rejectProjectMutation("BAD123 = {isa = XCBuildConfiguration; name = Release; buildSettings = {CODE_SIGN_ENTITLEMENTS = missing.entitlements;};};")
    }

    func testRejectsMalformedProject() throws {
        try rejectProjectMutation("unclosed = {")
    }
}

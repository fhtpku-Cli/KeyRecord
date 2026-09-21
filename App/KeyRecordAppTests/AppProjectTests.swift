import Foundation
import XCTest

final class AppProjectTests: XCTestCase {
    func testHappyProjectBoundary() throws {
        // Given the actual project, when parsed, then assert the app dependency/settings graph.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("KeyRecord.xcodeproj/project.pbxproj"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let objects = try XCTUnwrap(plist["objects"] as? [String: [String: Any]])
        let app = try XCTUnwrap(objects.values.first { $0["productType"] as? String == "com.apple.product-type.application" })
        let products = try XCTUnwrap(app["packageProductDependencies"] as? [String])
        XCTAssertEqual(Set(products.compactMap { objects[$0]?["productName"] as? String }),
                       ["KeyRecordCore", "KeyRecordCapture", "KeyRecordStore", "KeyRecordAnalysis"])
        XCTAssertEqual(objects.values.filter { $0["isa"] as? String == "XCLocalSwiftPackageReference" }.count, 1)
        XCTAssertFalse(objects.values.contains { $0["isa"] as? String == "XCRemoteSwiftPackageReference" })
        XCTAssertEqual(objects.values.first { $0["isa"] as? String == "XCLocalSwiftPackageReference" }?["relativePath"] as? String, ".")
        let list = try XCTUnwrap(app["buildConfigurationList"] as? String)
        let configurations = try XCTUnwrap(objects[list]?["buildConfigurations"] as? [String])
            .map { id -> (name: String, settings: [String: Any]) in
                let configuration = try XCTUnwrap(objects[id])
                let name = try XCTUnwrap(configuration["name"] as? String)
                let settings = try XCTUnwrap(configuration["buildSettings"] as? [String: Any])
                return (name, settings)
            }
        let settingsByName = Dictionary(uniqueKeysWithValues: configurations.map { ($0.name, $0.settings) })
        XCTAssertEqual(Set(settingsByName.keys), ["Debug", "Release"])
        for settings in settingsByName.values {
            XCTAssertEqual(settings["ENABLE_APP_SANDBOX"] as? String, "NO")
            XCTAssertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String, "com.keyrecord.app")
            XCTAssertNil(settings["CODE_SIGN_ENTITLEMENTS"])
            XCTAssertNil(settings["ENABLE_OUTGOING_NETWORK_CONNECTIONS"])
            XCTAssertNil(settings["ENABLE_INCOMING_NETWORK_CONNECTIONS"])
        }
        let debug = try XCTUnwrap(settingsByName["Debug"])
        // Debug signs automatically with the stable local development team so TCC grants persist.
        XCTAssertEqual(debug["CODE_SIGN_STYLE"] as? String, "Automatic")
        XCTAssertEqual(debug["DEVELOPMENT_TEAM"] as? String, "P3W62C39TN")
        XCTAssertEqual(debug["CODE_SIGN_IDENTITY"] as? String, "Apple Development")
        XCTAssertEqual(debug["ENABLE_HARDENED_RUNTIME"] as? String, "NO")
        let release = try XCTUnwrap(settingsByName["Release"])
        // Release carries no team or signing identity; CI wrappers build it unsigned/ad-hoc.
        XCTAssertNil(release["DEVELOPMENT_TEAM"])
        XCTAssertNil(release["CODE_SIGN_IDENTITY"])
        XCTAssertEqual(release["ENABLE_HARDENED_RUNTIME"] as? String, "YES")
        XCTAssertEqual(objects.values.filter { $0["productType"] as? String == "com.apple.product-type.application" }.count, 1)
        XCTAssertFalse(objects.values.contains { $0["isa"] as? String == "PBXCopyFilesBuildPhase" })
    }

    func testHappyBuiltBundle() throws {
        // Given the adjacent built app, when inspecting its plist, then it is an accessory app.
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let app = try XCTUnwrap(Bundle(url: products.appendingPathComponent("KeyRecordApp.app")))
        XCTAssertEqual(app.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
        XCTAssertEqual(app.bundleIdentifier, "com.keyrecord.app")
        XCTAssertEqual(app.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String, "14.0")
        XCTAssertNil(app.object(forInfoDictionaryKey: "ATSApplicationFontsPath"))
    }

    func testHappyUniversalUnsignedProduct() throws {
        // Given the Release product, when inspecting Mach-O, then both unsigned slices exist.
        let releasePath = try XCTUnwrap(ProcessInfo.processInfo.environment["T23_RELEASE_APP"],
            "Set T23_RELEASE_APP to the universal Release app built for this test run")
        let binary = URL(fileURLWithPath: releasePath)
            .appendingPathComponent("Contents/MacOS/KeyRecordApp")
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-archs", binary.path]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(Set(String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace)), ["arm64", "x86_64"])
        let signing = Process()
        signing.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signing.arguments = ["--verify", binary.path]
        try signing.run()
        signing.waitUntilExit()
        XCTAssertNotEqual(signing.terminationStatus, 0)
    }
}

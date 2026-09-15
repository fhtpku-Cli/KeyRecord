import Foundation
import AppKit
import XCTest
import KeyRecordCore
import KeyRecordCapture

@MainActor
final class Phase1ReleaseIsolationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private let forbiddenReleaseTokens = [
        "KEYRECORD_LOCAL_CAPTURE", "LocalDevelopmentCapture", "SystemSessionLockProvider",
        "LocalKeychainBackend", "LocalKeychainQueries",
    ]

    func testLocalCaptureArmamentRequiresExactEnvValue() {
        // Given / When / Then: only the exact value "1" arms; absent or other values stay disarmed.
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: [:]))
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": ""]))
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": "0"]))
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": "yes"]))
        XCTAssertTrue(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": "1"]))
    }

    func testDefaultLocalCaptureIsUnqualifiedWithoutEnvironment() async {
        // Given: no KEYRECORD_LOCAL_CAPTURE in the hostless environment.
        XCTAssertFalse(LocalDevelopmentCaptureArmament.environmentArmed)
        // When: a default and an explicit-disabled qualification are queried.
        let defaultResult = await LocalDevelopmentCapture().liveCaptureQualified()
        let disabledResult = await LocalDevelopmentCapture(armed: false).liveCaptureQualified()
        let unqualifiedResult = await UnqualifiedCapture().liveCaptureQualified()
        // Then: the live-capture gate is closed, identical to the Release unqualified gate.
        XCTAssertFalse(defaultResult)
        XCTAssertFalse(disabledResult)
        XCTAssertFalse(unqualifiedResult)
    }

    func testLocalCaptureQualificationReflectsMutableArmament() async {
        // Given an env-armed qualification.
        let qualification = LocalDevelopmentCapture(armed: true)
        let initiallyArmed = await qualification.liveCaptureQualified()
        XCTAssertTrue(initiallyArmed)
        // When the developer disarms and rearms it.
        qualification.setArmed(false)
        let disarmed = await qualification.liveCaptureQualified()
        qualification.setArmed(true)
        let rearmed = await qualification.liveCaptureQualified()
        // Then the gate follows the flag.
        XCTAssertFalse(disarmed)
        XCTAssertTrue(rearmed)
    }

    func testSystemSessionLockProviderReportsActualHostSessionLockState() async throws {
        // Given an independent CGSession witness reading the real lock state of this host.
        let expected = try Self.spiSessionLockState()
        // When the product provider queries the same session.
        let state = await SystemSessionLockProvider().sessionLockState()
        // Then: it reports the actual host state (locked or unlocked), never an assumed value.
        XCTAssertEqual(state, expected)
    }

    private static func spiSessionLockState() throws -> SessionLockState {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        let handle = try XCTUnwrap(dlopen(path, RTLD_LAZY | RTLD_LOCAL))
        let symbol = try XCTUnwrap(dlsym(handle, "CGSessionCopyCurrentDictionary"))
        let copy = unsafeBitCast(symbol, to: (@convention(c) () -> Unmanaged<CFDictionary>?).self)
        let dictionary = copy()?.takeRetainedValue() as NSDictionary?
        let locked = (dictionary?["CGSSessionScreenIsLocked"] as? NSNumber)?.intValue == 1
        return locked ? .locked : .unlocked
    }

    func testDeveloperMenuWithoutEnvironmentIsOffAndDisabled() {
        // Given a Debug composition without the arming environment variable.
        let menu = NSMenu()
        let section = LocalDevelopmentCaptureMenu(qualification: nil)
        // When the Developer section is installed.
        section.addItems(to: menu)
        // Then: the toggle is visible, unchecked, disabled — Start stays blocked by qualification.
        let item = try! XCTUnwrap(menu.items.first {
            $0.accessibilityIdentifier() as? String == LocalDevelopmentCaptureMenu.toggleIdentifier
        })
        XCTAssertEqual(item.state, .off)
        XCTAssertFalse(item.isEnabled)
        XCTAssertNotNil(menu.items.first {
            $0.accessibilityIdentifier() as? String == LocalDevelopmentCaptureMenu.sectionIdentifier
        })
    }

    func testDeveloperMenuWithEnvReflectsAndTogglesArmament() {
        // Given an env-armed qualification.
        let qualification = LocalDevelopmentCapture(armed: true)
        let menu = NSMenu()
        let section = LocalDevelopmentCaptureMenu(qualification: qualification)
        section.addItems(to: menu)
        let item = menu.items.first {
            $0.accessibilityIdentifier() as? String == LocalDevelopmentCaptureMenu.toggleIdentifier
        }!
        XCTAssertEqual(item.state, .on)
        XCTAssertTrue(item.isEnabled)
        // When the developer toggles it off and back on.
        section.toggle()
        XCTAssertEqual(item.state, .off)
        XCTAssertFalse(qualification.isArmed)
        section.toggle()
        // Then: the menu checkmark tracks the same flag Start's qualification gate reads.
        XCTAssertEqual(item.state, .on)
        XCTAssertTrue(qualification.isArmed)
    }

    func testReleaseCompilationStripsLocalCaptureTokens() throws {
        // Given every App product source, evaluated as Release compilation (DEBUG undefined).
        let appSources = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("App/KeyRecordApp"),
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        // When / Then: no local-capture token survives DEBUG stripping in any file.
        for file in appSources {
            let code = try releasePreprocessed(file)
            for token in forbiddenReleaseTokens {
                XCTAssertFalse(code.contains(token), "\(token) leaked into Release: \(file.lastPathComponent)")
            }
        }
        let localFile = try releasePreprocessed(root.appendingPathComponent(
            "App/KeyRecordApp/LocalDevelopmentCapture.swift"))
        XCTAssertTrue(localFile.allSatisfy { $0.isWhitespace },
                      "LocalDevelopmentCapture.swift must compile to nothing in Release")
        for name in ["LocalKeychainBackend.swift", "LocalKeychainQueries.swift"] {
            let file = try releasePreprocessed(root.appendingPathComponent("App/KeyRecordApp/\(name)"))
            XCTAssertTrue(file.allSatisfy { $0.isWhitespace }, "\(name) must compile to nothing in Release")
        }
    }

    func testReleaseCompositionKeepsUnqualifiedAssembly() throws {
        // Given ProductComposition.swift with DEBUG undefined.
        let code = try releasePreprocessed(root.appendingPathComponent("App/KeyRecordApp/ProductComposition.swift"))
        // When / Then: the Release assembly is the unqualified path with no environment surface.
        XCTAssertTrue(code.contains("qualification: UnqualifiedCapture()"))
        XCTAssertTrue(code.contains("BlockedLiveKeychain()"))
        XCTAssertFalse(code.contains("ProcessInfo"))
        XCTAssertFalse(code.contains("LocalDevelopmentCapture"))
        XCTAssertFalse(code.contains("SystemSessionLockProvider"))
        XCTAssertFalse(code.contains("LocalKeychainBackend"))
        XCTAssertFalse(code.contains("LocalKeychainQueries"))
        // Given the DEBUG-neutral ProductCapture initializer, its defaults stay unqualified.
        let productCapture = try String(contentsOf: root.appendingPathComponent(
            "App/KeyRecordApp/ProductCapture.swift"), encoding: .utf8)
        XCTAssertTrue(productCapture.contains("any CaptureQualification = UnqualifiedCapture()"))
        XCTAssertTrue(productCapture.contains("any SessionLockProvider = UnqualifiedSessionLockProvider()"))
    }

    func testReleaseAppBinaryHasNoLocalCaptureTokens() throws {
        // Given the unsigned universal Release product, when provided by the QA wrapper.
        let app = ProcessInfo.processInfo.environment["T23_RELEASE_APP"]
            .flatMap { URL(fileURLWithPath: $0) }
        guard let app else { throw XCTSkip("set T23_RELEASE_APP to run the Release binary-string scan") }
        let executable = app.appendingPathComponent("Contents/MacOS/KeyRecordApp")
        let result = try run("/usr/bin/strings", ["-a", executable.path])
        XCTAssertEqual(result.status, 0)
        // Then: neither the arming token nor any local-development symbol is in the binary.
        for token in forbiddenReleaseTokens {
            XCTAssertFalse(result.output.contains(token), "Release binary contains \(token)")
        }
    }

    private struct CommandResult { let status: Int32; let output: String }

    private func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self))
    }

    private func releasePreprocessed(_ file: URL) throws -> String {
        let result = try run("/usr/bin/unifdef", ["-UDEBUG", file.path])
        XCTAssertTrue([0, 1].contains(result.status), file.lastPathComponent)
        return result.output
    }
}

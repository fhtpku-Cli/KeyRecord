import Foundation
import AppKit
import CoreGraphics
import XCTest
import KeyRecordCore
import KeyRecordCapture

@MainActor
final class Phase1ReleaseIsolationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private let forbiddenReleaseTokens = [
        "KEYRECORD_LOCAL_CAPTURE", "LocalDevelopmentCapture", "SystemSessionLockProvider",
        "LocalKeychainBackend", "LocalKeychainQueries", "debug.localCaptureEnabled",
    ]

    func testLocalCaptureArmamentRequiresExactEnvValue() {
        // Given / When / Then: only the exact value "1" arms; absent or other values stay disarmed.
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: [:]))
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": ""]))
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": "0"]))
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": "yes"]))
        XCTAssertTrue(LocalDevelopmentCaptureArmament.isArmed(in: ["KEYRECORD_LOCAL_CAPTURE": "1"]))
    }

    func testLocalCaptureArmamentPersistsAcrossInstancesViaUserDefaults() {
        let key = LocalDevelopmentCaptureArmament.defaultsKey
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        XCTAssertFalse(LocalDevelopmentCaptureArmament.defaultsArmed)
        LocalDevelopmentCaptureArmament.setDefaultsArmed(true)
        XCTAssertTrue(LocalDevelopmentCaptureArmament.defaultsArmed)
        XCTAssertTrue(LocalDevelopmentCaptureArmament.isArmed)
        LocalDevelopmentCaptureArmament.setDefaultsArmed(false)
        XCTAssertFalse(LocalDevelopmentCaptureArmament.defaultsArmed)
    }

    func testDefaultLocalCaptureIsUnqualifiedWithoutEnvironment() async {
        // Given: no env and no persisted toggle.
        UserDefaults.standard.removeObject(forKey: LocalDevelopmentCaptureArmament.defaultsKey)
        XCTAssertFalse(LocalDevelopmentCaptureArmament.isArmed)
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

    func testSystemSessionLockProviderReturnsUnknownWhenSessionWitnessIsUnavailable() async {
        // Given no usable session dictionary and no lock notification.
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: { nil },
                                                 notificationRegistrar: { _ in })
        // When the capture gate asks for the current lock state.
        let state = await provider.sessionLockState()
        // Then the unavailable witness cannot qualify local capture.
        assertSessionLockState(state, is: .unknown)
    }

    func testSystemSessionLockProviderReturnsUnknownForMalformedSessionLockValue() async {
        // Given a session dictionary whose lock field is not a number.
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: {
            ["CGSSessionScreenIsLocked": "0"] as NSDictionary
        }, notificationRegistrar: { _ in })
        // When the capture gate asks for the current lock state.
        let state = await provider.sessionLockState()
        // Then malformed data cannot be interpreted as unlocked.
        assertSessionLockState(state, is: .unknown)
    }

    func testSystemSessionLockProviderReturnsUnknownWhenSessionLockFieldIsMissing() async {
        // Given a session dictionary with no explicit screen-lock value.
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: {
            ["CGSSessionUserID": NSNumber(value: 501)] as NSDictionary
        }, notificationRegistrar: { _ in })
        // When the capture gate asks for the current lock state.
        let state = await provider.sessionLockState()
        // Then the missing field cannot be interpreted as unlocked.
        assertSessionLockState(state, is: .unknown)
    }

    func testSystemSessionLockProviderRequiresAnExplicitUnlockedSessionWitness() async {
        // Given a session dictionary that explicitly states the screen is not locked.
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: {
            ["CGSSessionScreenIsLocked": NSNumber(value: 0), kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())] as NSDictionary
        }, notificationRegistrar: { _ in })
        // When the capture gate asks for the current lock state.
        let state = await provider.sessionLockState()
        // Then that valid, explicit witness qualifies the state as unlocked.
        assertSessionLockState(state, is: .unlocked)
    }

    func testSystemSessionLockProviderDoesNotReuseAnOldUnlockedWitnessAfterQueryFailure() async {
        // Given one explicit unlocked witness followed by an unavailable query.
        var dictionary: NSDictionary? = ["CGSSessionScreenIsLocked": NSNumber(value: 0), kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())] as NSDictionary
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: {
            dictionary
        }, notificationRegistrar: { _ in })
        let initialState = await provider.sessionLockState()
        assertSessionLockState(initialState, is: .unlocked)
        dictionary = nil
        // When the next capture gate refresh cannot read the session.
        let state = await provider.sessionLockState()
        // Then the old unlocked value cannot keep capture qualified.
        assertSessionLockState(state, is: .unknown)
    }

    func testSystemSessionLockProviderLockedNotificationOverridesAnUnlockedQuery() async {
        // Given a currently-unlocked dictionary witness and an injectable lock notification.
        var notify: ((SessionLockState) -> Void)?
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: {
            ["CGSSessionScreenIsLocked": NSNumber(value: 0), kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())] as NSDictionary
        }, notificationRegistrar: { receiver in
            notify = receiver
        })
        // When a screen-lock notification arrives.
        notify?(.locked)
        let state = await provider.sessionLockState()
        // Then the provider reports locked immediately, even before the next SPI reading catches up.
        assertSessionLockState(state, is: .locked)
    }

    func testConsoleWitnessRequiresExplicitBooleanAndCurrentSession() async {
        let eligible: NSDictionary = [kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())]
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: { eligible },
            consoleLockQuery: { kCFBooleanFalse }, notificationRegistrar: { _ in })
        assertSessionLockState(await provider.sessionLockState(), is: .unlocked)
    }

    func testConsoleWitnessRejectsMissingAndNonBooleanValues() async {
        let eligible: NSDictionary = [kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())]
        for value: CFTypeRef? in [nil, NSNumber(value: 0), NSNumber(value: 1), "false" as CFString] {
            let provider = SystemSessionLockProvider(sessionDictionaryQuery: { eligible },
                consoleLockQuery: { value }, notificationRegistrar: { _ in })
            assertSessionLockState(await provider.sessionLockState(), is: .unknown)
        }
    }

    func testConsoleWitnessRejectsIneligibleOrChangingSessions() async {
        let eligible: NSDictionary = [kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())]
        let invalid: [NSDictionary?] = [nil, [:],
            [kCGSessionOnConsoleKey: false, kCGSessionUserIDKey: NSNumber(value: getuid())],
            [kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid() + 1)],
            [kCGSessionOnConsoleKey: NSNumber(value: 1), kCGSessionUserIDKey: NSNumber(value: getuid())],
            [kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: Double(getuid()) + 0.5)]]
        for invalidSession in invalid {
            for invalidFirst in [false, true] {
                var calls = 0
                let provider = SystemSessionLockProvider(sessionDictionaryQuery: {
                    defer { calls += 1 }
                    return (calls == 0) == invalidFirst ? invalidSession : eligible
                }, consoleLockQuery: { kCFBooleanFalse }, notificationRegistrar: { _ in })
                assertSessionLockState(await provider.sessionLockState(), is: .unknown)
            }
        }
    }

    func testConsoleWitnessDoesNotReuseUnlockedAfterFailure() async {
        let eligible: NSDictionary = [kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())]
        var value: CFTypeRef? = kCFBooleanFalse
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: { eligible },
            consoleLockQuery: { value }, notificationRegistrar: { _ in })
        assertSessionLockState(await provider.sessionLockState(), is: .unlocked)
        value = nil
        assertSessionLockState(await provider.sessionLockState(), is: .unknown)
    }

    func testConsoleWitnessCannotOverrideMalformedSessionField() async {
        for value: Any in ["0", NSNumber(value: 2), NSNumber(value: 0.5)] {
            let dictionary: NSDictionary = [kCGSessionOnConsoleKey: true,
                kCGSessionUserIDKey: NSNumber(value: getuid()), "CGSSessionScreenIsLocked": value]
            let provider = SystemSessionLockProvider(sessionDictionaryQuery: { dictionary },
                consoleLockQuery: { kCFBooleanFalse }, notificationRegistrar: { _ in })
            assertSessionLockState(await provider.sessionLockState(), is: .unknown)
        }
    }

    func testExplicitLockedWitnessDominatesConflictingUnlockedWitness() async {
        for sessionLocked in [false, true] {
            let dictionary: NSDictionary = [kCGSessionOnConsoleKey: true,
                kCGSessionUserIDKey: NSNumber(value: getuid()), "CGSSessionScreenIsLocked": NSNumber(value: sessionLocked)]
            let provider = SystemSessionLockProvider(sessionDictionaryQuery: { dictionary },
                consoleLockQuery: { sessionLocked ? kCFBooleanFalse : kCFBooleanTrue },
                notificationRegistrar: { _ in })
            assertSessionLockState(await provider.sessionLockState(), is: .locked)
        }
    }

    func testConsoleWitnessStillHonorsLockedNotificationAndFreshReadAfterUnlock() async {
        let eligible: NSDictionary = [kCGSessionOnConsoleKey: true, kCGSessionUserIDKey: NSNumber(value: getuid())]
        var notify: ((SessionLockState) -> Void)?
        var console: CFTypeRef? = kCFBooleanFalse
        let provider = SystemSessionLockProvider(sessionDictionaryQuery: { eligible },
            consoleLockQuery: { console }, notificationRegistrar: { notify = $0 })
        notify?(.locked)
        assertSessionLockState(await provider.sessionLockState(), is: .locked)
        notify?(.unlocked)
        console = nil
        assertSessionLockState(await provider.sessionLockState(), is: .unknown)
        console = kCFBooleanFalse
        assertSessionLockState(await provider.sessionLockState(), is: .unlocked)
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

    func testDeveloperMenuWithEnvReflectsAndTogglesArmament() async {
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
        await section.applyToggle()
        XCTAssertEqual(item.state, .off)
        XCTAssertFalse(qualification.isArmed)
        await section.applyToggle()
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
        XCTAssertEqual(result.status, 0, result.error)
        // Then: neither the arming token nor any local-development symbol is in the binary.
        for token in forbiddenReleaseTokens {
            XCTAssertFalse(result.output.contains(token), "Release binary contains \(token)")
        }
    }

    private struct CommandResult { let status: Int32; let output: String; let error: String }

    private func assertSessionLockState(_ state: SessionLockState, is expected: SessionLockState,
                                        file: StaticString = #filePath, line: UInt = #line) {
        switch (state, expected) {
        case (.locked, .locked), (.unlocked, .unlocked), (.unknown, .unknown): return
        default: XCTFail("unexpected session lock state", file: file, line: line)
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(decoding: output, as: UTF8.self),
                             error: String(decoding: error, as: UTF8.self))
    }

    private func releasePreprocessed(_ file: URL) throws -> String {
        let result = try run("/usr/bin/unifdef", ["-UDEBUG", file.path])
        XCTAssertTrue([0, 1].contains(result.status), "\(file.lastPathComponent): \(result.error)")
        return result.output
    }
}

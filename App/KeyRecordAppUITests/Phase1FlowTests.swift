import XCTest

// Signed-hosted task 18 product flows. These drive the DEBUG-only
// KEYRECORD_FLOW_FIXTURE composition (in-memory fakes + temp-dir persistence) and need
// an authorized, signed UI-testing host; they cannot run under the unsigned hostless
// lane. Phase1FlowHostlessTests carries the executable assertions in this repository.
final class Phase1FlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureDirectory: URL!
    private var journalURL: URL { fixtureDirectory.appendingPathComponent("results.journal") }

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("t18-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment["KEYRECORD_FLOW_FIXTURE"] = fixtureDirectory.path
        app.launchEnvironment["KEYRECORD_FLOW_FOREGROUND"] = "com.example.editor"
        app.launchEnvironment["KEYRECORD_FLOW_CYCLE"] = "fixed-cycle"
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    private func relaunch(environment: [String: String] = [:]) {
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["KEYRECORD_FLOW_FIXTURE"] = fixtureDirectory.path
        app.launchEnvironment["KEYRECORD_FLOW_FOREGROUND"] = "com.example.editor"
        app.launchEnvironment["KEYRECORD_FLOW_CYCLE"] = "fixed-cycle"
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
    }

    private var journalLines: [String] {
        let text = (try? String(contentsOf: journalURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func openSettings() {
        app.buttons["menu.settings"].firstMatch.click()
    }

    func testConsentRejectionStaysInactive() {
        app.buttons["consent.reject"].click()
        app.terminate()
        let events = journalLines
        XCTAssertFalse(events.contains("keyProvision"))
        XCTAssertFalse(events.contains("captureStart"))
    }

    func testConsentAcceptancePauseResume() {
        app.buttons["consent.accept"].click()
        XCTAssertTrue(app.buttons["menu.pause"].isEnabled)
        app.buttons["menu.pause"].click()
        XCTAssertTrue(app.buttons["menu.resume"].isEnabled)
        app.buttons["menu.resume"].click()
        XCTAssertTrue(app.buttons["menu.pause"].isEnabled)
    }

    func testReopenPersistsCycleAfterRelaunch() {
        app.buttons["consent.accept"].click()
        XCTAssertTrue(app.buttons["menu.pause"].waitForExistence(timeout: 5))
        app.terminate()
        let prefs = fixtureDirectory.appendingPathComponent("preferences.json")
        let data = try? Data(contentsOf: prefs)
        let stored = String(data: data ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(stored.contains("fixed-cycle"))
        relaunch()
        XCTAssertTrue(app.buttons["menu.pause"].waitForExistence(timeout: 5))
    }

    func testExclusionSelectionRevokesGateInstantly() {
        app.buttons["consent.accept"].click()
        openSettings()
        let toggle = app.toggles["settings.exclusions.com.example.editor"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        app.terminate()
        let prefs = fixtureDirectory.appendingPathComponent("preferences.json")
        let stored = String(data: (try? Data(contentsOf: prefs)) ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(stored.contains("com.example.editor"))
    }

    func testLoginToggleRejectionShowsError() {
        relaunch(environment: ["KEYRECORD_FLOW_LOGIN_REJECT": "1"])
        app.buttons["consent.accept"].click()
        openSettings()
        let loginToggle = app.toggles["settings.login"]
        XCTAssertTrue(loginToggle.waitForExistence(timeout: 5))
        loginToggle.click()
        XCTAssertTrue(app.staticTexts["settings.login.error"].waitForExistence(timeout: 5))
    }

    func testResetTwoStageConfirmation() {
        app.buttons["consent.accept"].click()
        openSettings()
        app.buttons["settings.reset"].click()
        let message = app.staticTexts["dialog.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("mappings"))
        app.buttons["dialog.cancel"].click()
        XCTAssertFalse(app.buttons["dialog.confirm"].exists)
        app.buttons["settings.reset"].click()
        app.buttons["dialog.confirm"].click()
        app.terminate()
        XCTAssertEqual(journalLines.filter { $0 == "cycleReset" }, ["cycleReset"])
    }

    func testDeleteDistinctFromConfirmReturnsToFreshConsent() {
        app.buttons["consent.accept"].click()
        openSettings()
        app.buttons["settings.delete"].click()
        XCTAssertTrue(app.staticTexts["dialog.message"].label.contains("cannot be undone"))
        app.buttons["dialog.cancel"].click()
        app.buttons["settings.delete"].click()
        app.buttons["dialog.confirm"].click()
        XCTAssertTrue(app.buttons["consent.accept"].waitForExistence(timeout: 5))
        app.terminate()
        XCTAssertEqual(journalLines.filter { $0 == "eraseAllLocalData" }, ["eraseAllLocalData"])
        relaunch()
        XCTAssertTrue(app.buttons["consent.accept"].waitForExistence(timeout: 5))
    }
}

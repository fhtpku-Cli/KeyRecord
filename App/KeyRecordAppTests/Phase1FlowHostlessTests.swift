import XCTest
import KeyRecordCore

@MainActor
final class Phase1FlowHostlessTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("t18-hostless-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeFixture(_ extra: [String: String] = [:]) throws -> FlowFixture {
        var environment = ["KEYRECORD_FLOW_FIXTURE": tempDirectory.path]
        extra.forEach { environment[$0.key] = $0.value }
        return try FlowFixture(directory: tempDirectory, environment: environment)
    }

    private func collecting(_ fixture: FlowFixture) async {
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
    }

    func testHappyConsentRejectionStaysInactive() async throws {
        let fixture = try makeFixture()
        fixture.showConsentIfNeeded()
        fixture.flow.decline()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertEqual(fixture.orchestrator.state.phase, .unstarted)
        XCTAssertTrue(fixture.flow.menuState.canStart)
        let starts = await fixture.capture.startCount
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(fixture.journalEvents.contains("keyProvision"))
    }

    func testHappyConsentAcceptancePauseResume() async throws {
        let fixture = try makeFixture()
        await collecting(fixture)
        XCTAssertEqual(fixture.orchestrator.state.phase, .collecting)
        XCTAssertTrue(fixture.flow.menuState.canPause)
        XCTAssertTrue(fixture.journalEvents.contains("captureStart"))
        await fixture.flow.pause()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertEqual(fixture.orchestrator.state.phase, .paused)
        XCTAssertTrue(fixture.journalEvents.contains("flushWhileUnlocked"))
        await fixture.flow.resume()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertEqual(fixture.orchestrator.state.phase, .collecting)
    }

    func testHappyReopenPersistsCycle() async throws {
        let fixture = try makeFixture()
        await collecting(fixture)
        let reopened = try makeFixture()
        await reopened.orchestrator.reload()
        XCTAssertEqual(reopened.orchestrator.state.phase, .collecting)
        XCTAssertEqual(reopened.orchestrator.state.preferences?.currentCycleID.rawValue, "fixture-cycle")
        XCTAssertEqual(reopened.orchestrator.state.preferences?.currentCycleID,
                       fixture.orchestrator.state.preferences?.currentCycleID)
    }

    func testHappyExclusionSelectionRevokesGateInstantly() async throws {
        let fixture = try makeFixture()
        await collecting(fixture)
        XCTAssertTrue(fixture.orchestrator.state.gate.isOpen)
        await fixture.flow.setExclusion(bundleID: "com.example.editor", enabled: true)
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertFalse(fixture.orchestrator.state.gate.isOpen)
        XCTAssertEqual(fixture.orchestrator.state.gate.closureReason, .excluded)
        await fixture.flow.setExclusion(bundleID: "com.example.editor", enabled: false)
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertTrue(fixture.orchestrator.state.gate.isOpen)
    }

    func testHappyResetTwoStageConfirmationCancelCallsNothing() async throws {
        let fixture = try makeFixture()
        await collecting(fixture)
        fixture.flow.requestReset()
        guard case .resetConfirmation(let proposal) = fixture.flow.dialog else {
            return XCTFail("reset proposal expected")
        }
        XCTAssertEqual(proposal.messageKey, "dialog.reset.message")
        await fixture.flow.choose(.cancel)
        var resetCalls = await fixture.reset.callCount
        XCTAssertEqual(resetCalls, 0)
        fixture.flow.requestReset()
        await fixture.flow.choose(.confirm)
        resetCalls = await fixture.reset.callCount
        XCTAssertEqual(resetCalls, 1)
        XCTAssertEqual(fixture.flow.dialog, .none)
        XCTAssertEqual(fixture.journalEvents.filter { $0 == "cycleReset" }, ["cycleReset"])
    }

    func testHappyDeleteDistinctFromResetReturnsToFreshConsent() async throws {
        let fixture = try makeFixture()
        await collecting(fixture)
        fixture.flow.requestDeleteLocalData()
        guard case .deleteConfirmation = fixture.flow.dialog else { return XCTFail("delete proposal expected") }
        await fixture.flow.choose(.cancel)
        var eraseCalls = await fixture.eraser.callCount
        XCTAssertEqual(eraseCalls, 0)
        fixture.flow.requestDeleteLocalData()
        await fixture.flow.choose(.confirm)
        eraseCalls = await fixture.eraser.callCount
        XCTAssertEqual(eraseCalls, 1)
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertEqual(fixture.orchestrator.state.phase, .unstarted)
        XCTAssertEqual(fixture.journalEvents.filter { $0 == "eraseAllLocalData" }, ["eraseAllLocalData"])
    }

    func testFailureLoginToggleRejectionShowsError() async throws {
        let fixture = try makeFixture(["KEYRECORD_FLOW_LOGIN_REJECT": "1"])
        await collecting(fixture)
        await fixture.flow.setLoginItem(enabled: true)
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertEqual(fixture.flow.loginItemErrorKey, "settings.login.error")
        if case .rejected(let rejection) = fixture.orchestrator.state.loginItem {
            XCTAssertEqual(rejection, .registrationDenied)
        } else {
            XCTFail("rejected login item status expected")
        }
        XCTAssertTrue(fixture.journalEvents.contains("loginRejected"))
    }

    func testFailureAggregateHiddenWhileLocked() async throws {
        let fixture = try makeFixture()
        await collecting(fixture)
        fixture.flow.snapshot = try AggregateSnapshot(rows: [
            KeyRecordCore.AggregateRow(identity: .bareKey(try KeyCode(1)), total: 3,
                         classification: .discrete, sourceConfidence: .ordinary),
        ])
        XCTAssertNotNil(fixture.flow.snapshot)
        fixture.observeLocked()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertNil(fixture.flow.snapshot)
        XCTAssertFalse(fixture.flow.sensitiveContentVisible)
        fixture.observe(locked: false)
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertNotNil(fixture.flow.snapshot)
    }

    func testFailureResetConfirmUnavailableSurfacesNotice() async {
        final class Driver: LifecycleDriving {
            var state: LifecycleState
            init(state: LifecycleState) { self.state = state }
            func returnToConsentRequired() async { state = .initial }
        }
        var gate = PrivacyGate()
        gate.update(GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
                               secureInput: .disabled, foreground: .attributable(bundleID: "com.ex"),
                               exclusion: .included))
        let model = Phase1FlowModel(lifecycle: Driver(state: LifecycleState(phase: .collecting, gate: gate)))
        let observable = AppFlowObservable(flow: model)
        observable.requestReset()
        await observable.choose(.confirm)
        XCTAssertEqual(observable.noticeKey, "flow.actionUnavailable")
        guard case .resetConfirmation = observable.dialog else { return XCTFail("dialog should remain") }
    }

    func testFailureDialogCopyBilingualAndRetentionDistinct() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func catalog(_ lproj: String) throws -> [String: String] {
            let url = root.appendingPathComponent("App/KeyRecordApp/\(lproj).lproj/Localizable.strings")
            let text = try String(contentsOf: url, encoding: .utf8)
            var result: [String: String] = [:]
            let pattern = /"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";/
            for match in text.matches(of: pattern) { result[String(match.output.1)] = String(match.output.2) }
            return result
        }
        let en = try catalog("en")
        let zh = try catalog("zh-Hans")
        XCTAssertEqual(Set(en.keys), Set(zh.keys))
        for key in ["dialog.reset.title", "dialog.reset.message", "dialog.reset.confirm", "dialog.reset.cancel",
                    "dialog.delete.title", "dialog.delete.message", "dialog.delete.confirm", "dialog.delete.cancel"] {
            XCTAssertFalse(en[key]?.isEmpty ?? true, key)
            XCTAssertNotEqual(en[key], zh[key], key)
        }
        XCTAssertTrue(en["dialog.reset.message"]?.contains("mappings") == true)
        XCTAssertTrue(en["dialog.reset.message"]?.contains("backups") == true)
        XCTAssertTrue(zh["dialog.reset.message"]?.contains("映射") == true)
        XCTAssertTrue(zh["dialog.reset.message"]?.contains("备份") == true)
        XCTAssertTrue(en["dialog.delete.message"]?.contains("cannot be undone") == true)
        XCTAssertTrue(zh["dialog.delete.message"]?.contains("不可撤销") == true)
        XCTAssertNotEqual(en["dialog.reset.message"], en["dialog.delete.message"])
    }

    func testReleaseFixtureIsolationIsDebugCompiledOnly() throws {
        let token = "KEYRECORD_FLOW_FIXTURE"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let appDirectory = root.appendingPathComponent("App/KeyRecordApp")
        let files = try FileManager.default.contentsOfDirectory(at: appDirectory,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var tokenFiles: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(token) else { continue }
            tokenFiles.append(file.lastPathComponent)
            var debugDepth = 0
            var ifDepth = 0
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if") {
                    ifDepth += 1
                    if trimmed.contains("DEBUG") { debugDepth = ifDepth }
                } else if trimmed == "#endif" {
                    if debugDepth == ifDepth { debugDepth = 0 }
                    ifDepth -= 1
                } else if line.contains(token) {
                    XCTAssertTrue(debugDepth > 0, "\(file.lastPathComponent): token outside #if DEBUG")
                }
            }
        }
        XCTAssertEqual(Set(tokenFiles), ["FlowTestComposition.swift"])
        let composition = try String(contentsOf: appDirectory.appendingPathComponent("FlowTestComposition.swift"),
                                     encoding: .utf8)
        let lines = composition.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.first?.trimmingCharacters(in: .whitespaces), "#if DEBUG")
        XCTAssertEqual(lines.last(where: { !$0.isEmpty })?.trimmingCharacters(in: .whitespaces), "#endif")
        let delegate = try String(contentsOf: appDirectory.appendingPathComponent("AppDelegate.swift"),
                                  encoding: .utf8)
        XCTAssertFalse(delegate.contains(token))
    }
}

import XCTest
import AppKit
import KeyRecordCore
import KeyRecordCapture

/// Regressions for the App-layer wiring defects: KR-01 (lock observers never registered),
/// KR-04 (exclusions picker had no production data source and no runtime propagation) and
/// KR-05 (Developer "Local Capture Off" only flipped a flag).
@MainActor
final class ProductWiringTests: XCTestCase {

    // MARK: - KR-04: exclusion candidate merge

    func testMergeDeduplicatesByBundleIDAndSortsByDisplayName() {
        let running = [
            RunningAppDescriptor(bundleID: "com.b", name: "Beta"),
            RunningAppDescriptor(bundleID: "com.a", name: "alpha"),
            RunningAppDescriptor(bundleID: "com.b", name: "Beta duplicate"),
        ]
        let choices = ExclusionChoiceMerge.choices(running: running, excluded: [],
                                                   foregroundBundleID: nil)
        XCTAssertEqual(choices.map(\.bundleID), ["com.a", "com.b"], "duplicates collapse by bundle id")
        XCTAssertEqual(choices.map(\.name), ["alpha", "Beta"], "case-insensitive display-name order")
    }

    func testMergeKeepsSavedExclusionsThatAreNotCurrentlyRunning() {
        let choices = ExclusionChoiceMerge.choices(
            running: [RunningAppDescriptor(bundleID: "com.running", name: "Running")],
            excluded: ["com.saved"], foregroundBundleID: nil)
        let saved = choices.first { $0.bundleID == "com.saved" }
        XCTAssertNotNil(saved, "a saved exclusion must stay listed so it can be removed")
        XCTAssertEqual(saved?.isExcluded, true)
        XCTAssertEqual(saved?.name, "com.saved", "no running instance means no localized name")
    }

    func testMergeFlagsForegroundAndExcludedStates() throws {
        let choices = ExclusionChoiceMerge.choices(
            running: [RunningAppDescriptor(bundleID: "com.front", name: "Front"),
                      RunningAppDescriptor(bundleID: "com.other", name: "Other")],
            excluded: ["com.other"], foregroundBundleID: "com.front")
        let front = try XCTUnwrap(choices.first { $0.bundleID == "com.front" })
        let other = try XCTUnwrap(choices.first { $0.bundleID == "com.other" })
        XCTAssertTrue(front.isForeground)
        XCTAssertFalse(front.isExcluded)
        XCTAssertFalse(other.isForeground)
        XCTAssertTrue(other.isExcluded)
    }

    func testMergeWithNoRunningAppsAndNoExclusionsIsEmptyNotCrashing() {
        XCTAssertTrue(ExclusionChoiceMerge.choices(running: [], excluded: [],
                                                   foregroundBundleID: nil).isEmpty)
    }

    func testEnumerationFailureStillExposesSavedExclusions() {
        // An enumeration failure must not be presented as "there are no applications":
        // saved exclusions remain listed and removable.
        let choices = ExclusionChoiceMerge.choices(running: [], excluded: ["com.saved"],
                                                   foregroundBundleID: nil)
        XCTAssertEqual(choices.map(\.bundleID), ["com.saved"])
        XCTAssertEqual(choices.first?.isExcluded, true)
    }

    func testWorkspaceCandidateSourceReturnsOnlyRegularAppsWithBundleIDs() throws {
        // The real source runs against the live workspace; assert its invariants rather
        // than a fixed list, since the running set varies by machine.
        let apps = try WorkspaceExclusionCandidates().runningApplications()
        for app in apps {
            XCTAssertFalse(app.bundleID.isEmpty, "a candidate must always carry a bundle id")
            XCTAssertFalse(app.name.isEmpty, "a candidate must always carry a display name")
        }
        XCTAssertEqual(Set(apps.map(\.bundleID)).count, apps.count, "source must not repeat a bundle id")
    }

    // MARK: - KR-05: Developer Local Capture Off is a real stop transaction

    private final class RecordingTransaction: LocalCaptureTransacting {
        private(set) var stops = 0
        private(set) var rearms = 0
        /// Captures what the menu was showing at the moment the stop ran, proving the UI
        /// did not switch to "Off" before the stop completed.
        var titleDuringStop: String?
        var titleProvider: (() -> String?)?

        func stopLocalCapture() async {
            titleDuringStop = titleProvider?()
            stops += 1
        }
        func rearmLocalCapture() async { rearms += 1 }
    }

    private func makeMenu(armed: Bool, transaction: RecordingTransaction)
        -> (LocalDevelopmentCaptureMenu, NSMenu, LocalDevelopmentCapture) {
        let qualification = LocalDevelopmentCapture(armed: armed)
        let menu = LocalDevelopmentCaptureMenu(qualification: qualification, transaction: transaction)
        let host = NSMenu()
        menu.addItems(to: host)
        transaction.titleProvider = { [weak menu] in menu?.refresh()?.title }
        return (menu, host, qualification)
    }

    // MARK: - Recovery rebuilds the session (live: coordinator=startFailed forever)

    func testRecoveryRebuildsSessionWithoutReloadingTheAggregate() throws {
        // Live evidence: after the coordinator closed a session, every reopen reported
        // startFailed and the menu sat at "capture not running". Cause: openSession only
        // called reapplyPolicy — which recomputes policy and never starts the source —
        // then asked hasLiveSession, which was necessarily false.
        let source = try String(contentsOf: Self.appSource("ProductComposition.swift"), encoding: .utf8)
        let body = Self.codeOnly(source)
        XCTAssertTrue(body.contains("resumeSession"),
                      "openSession must start a new source session, not just refresh policy")

        // And it must NOT reuse start(), which restores the aggregate from the last
        // durable commit and would silently discard unflushed counts on every recovery.
        let capture = try String(contentsOf: Self.appSource("ProductCapture.swift"), encoding: .utf8)
        let resume = Self.codeOnly(capture)
            .components(separatedBy: "func resumeSession")
            .dropFirst().first ?? ""
        let scope = resume.components(separatedBy: "func hasLiveSession").first ?? ""
        XCTAssertFalse(scope.contains("AggregatePersistence.restore"),
                       "recovery must leave the in-memory aggregate intact")
        XCTAssertFalse(scope.contains("reduction.open"),
                       "recovery must not reopen the reduction with a disk snapshot")
    }

    /// Drops `//` comments so an assertion cannot be satisfied by prose about the rule.
    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let index = line.range(of: "//")?.lowerBound else { return String(line) }
                return String(line[line.startIndex..<index])
            }
            .joined(separator: "\n")
    }

    private static func appSource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KeyRecordApp").appendingPathComponent(name)
    }

    func testTurningLocalCaptureOffStopsCaptureBeforeShowingOff() async throws {
        let transaction = RecordingTransaction()
        let (menu, _, qualification) = makeMenu(armed: true, transaction: transaction)
        XCTAssertTrue(qualification.isArmed)

        await menu.applyToggle()

        XCTAssertEqual(transaction.stops, 1, "Off must run the real stop transaction")
        XCTAssertFalse(qualification.isArmed, "qualification is cleared after the stop")
        XCTAssertNotEqual(transaction.titleDuringStop, "Developer: Local Capture Off",
                          "the menu must not read Off while the stop is still running")
        XCTAssertEqual(menu.refresh()?.title, "Developer: Local Capture Off",
                       "Off is shown only once the stop has completed")
        XCTAssertEqual(menu.refresh()?.state, .off)
        XCTAssertEqual(transaction.rearms, 0)
    }

    func testTurningLocalCaptureBackOnRearmsWithoutStartingCapture() async throws {
        let transaction = RecordingTransaction()
        let (menu, _, qualification) = makeMenu(armed: false, transaction: transaction)

        await menu.applyToggle()

        XCTAssertTrue(qualification.isArmed)
        XCTAssertEqual(transaction.stops, 0, "re-arming must not run a stop")
        XCTAssertEqual(transaction.rearms, 1)
        XCTAssertEqual(menu.refresh()?.title, "Developer: Local Capture On")
        // Re-arming only restores eligibility: it must not itself start collection, so the
        // consent/permission/lock/Secure Input/foreground checks cannot be bypassed.
        XCTAssertFalse(menu.isApplying)
    }

    func testToggleIsNotReentrantWhileAStopIsInFlight() async throws {
        let transaction = RecordingTransaction()
        let (menu, _, _) = makeMenu(armed: true, transaction: transaction)
        async let first: Void = menu.applyToggle()
        async let second: Void = menu.applyToggle()
        _ = await (first, second)
        XCTAssertLessThanOrEqual(transaction.stops, 1, "a second toggle must not double-stop")
    }

    func testMenuWithoutQualificationStaysDisabledAndDoesNothing() async throws {
        let transaction = RecordingTransaction()
        let menu = LocalDevelopmentCaptureMenu(qualification: nil, transaction: transaction)
        menu.addItems(to: NSMenu())
        await menu.applyToggle()
        XCTAssertEqual(transaction.stops, 0)
        XCTAssertEqual(transaction.rearms, 0)
        XCTAssertEqual(menu.refresh()?.isEnabled, false)
    }
}

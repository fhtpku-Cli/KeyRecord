import XCTest
@testable import Phase0Support

final class PrivacyTransitionTests: XCTestCase {
    func testFullContextAndSecureInputCrossProductFailsClosed() {
        let contexts: [FrontmostState] = [.known(bundleID: "app.allowed"), .knownUnattributable, .indeterminate]
        let secureStates: [SecureInputState] = [.disabled, .enabled, .unknown]

        for context in contexts {
            for secure in secureStates {
                var model = PrivacyTransitionModel()
                let before = model.totals
                let result = model.observeTerminalKeyDown(frontmost: context, secureInput: secure, excludedBundleIDs: [])
                let shouldCount = secure == .disabled && context != .indeterminate
                XCTAssertEqual(model.totals.data - before.data, shouldCount ? 1 : 0, "\(context), \(secure)")
                XCTAssertEqual(model.totals.meta - before.meta, shouldCount ? 1 : 0, "\(context), \(secure)")
                XCTAssertEqual(result == .dropped, !shouldCount)
            }
        }
    }

    func testUnknownBucketIsOnlyReliablyUnattributableAndIndeterminateNeverUnknown() {
        var model = PrivacyTransitionModel()
        XCTAssertEqual(model.observeTerminalKeyDown(frontmost: .knownUnattributable, secureInput: .disabled, excludedBundleIDs: []), .counted(bucket: .unknown))
        let before = model.totals
        XCTAssertEqual(model.observeTerminalKeyDown(frontmost: .indeterminate, secureInput: .disabled, excludedBundleIDs: []), .dropped)
        XCTAssertEqual(model.totals, before)
        XCTAssertEqual(model.bucketCounts[.unknown], 1)
    }

    func testKnownBundleAndExcludedApplicationHaveExpectedDeltas() {
        var model = PrivacyTransitionModel()
        XCTAssertEqual(model.observeTerminalKeyDown(frontmost: .known(bundleID: "app.allowed"), secureInput: .disabled, excludedBundleIDs: ["app.excluded"]), .counted(bucket: .bundle("app.allowed")))
        let before = model.totals
        XCTAssertEqual(model.observeTerminalKeyDown(frontmost: .known(bundleID: "app.excluded"), secureInput: .disabled, excludedBundleIDs: ["app.excluded"]), .dropped)
        XCTAssertEqual(model.totals, before, "excluded apps must not produce data or meta-count deltas")
    }

    func testPausedTapResetSleepAndWakeRemainClosedUntilExplicitRecovery() {
        var model = PrivacyTransitionModel()
        model.captureState = .paused
        assertZeroDelta(&model, context: .known(bundleID: "app.allowed"), secure: .disabled)
        model.captureState = .collecting
        _ = model.observeTerminalKeyDown(frontmost: .known(bundleID: "app.allowed"), secureInput: .disabled, excludedBundleIDs: [])
        model.tapReset()
        XCTAssertEqual(model.generation, 1)
        XCTAssertEqual(model.totals, .zero)
        assertZeroDelta(&model, context: .known(bundleID: "app.allowed"), secure: .disabled)
        model.recoverTap()
        model.systemWillSleep()
        assertZeroDelta(&model, context: .known(bundleID: "app.allowed"), secure: .disabled)
        model.systemDidWake()
        assertZeroDelta(&model, context: .known(bundleID: "app.allowed"), secure: .disabled)
        model.recoverAfterWake()
        XCTAssertNotEqual(model.observeTerminalKeyDown(frontmost: .known(bundleID: "app.allowed"), secureInput: .disabled, excludedBundleIDs: []), .dropped)
    }

    func testContradictoryAndUnavailableCacheAreIndeterminate() {
        XCTAssertEqual(FrontmostCache.resolve(notification: .known(bundleID: "a"), workspace: .known(bundleID: "b")), .indeterminate)
        XCTAssertEqual(FrontmostCache.resolve(notification: nil, workspace: .known(bundleID: "a")), .indeterminate)
        XCTAssertEqual(FrontmostCache.resolve(notification: .knownUnattributable, workspace: .knownUnattributable), .knownUnattributable)
        XCTAssertEqual(FrontmostCache.resolve(notification: .known(bundleID: "a"), workspace: .known(bundleID: "a")), .known(bundleID: "a"))
    }

    private func assertZeroDelta(_ model: inout PrivacyTransitionModel, context: FrontmostState, secure: SecureInputState) {
        let before = model.totals
        XCTAssertEqual(model.observeTerminalKeyDown(frontmost: context, secureInput: secure, excludedBundleIDs: []), .dropped)
        XCTAssertEqual(model.totals, before)
    }
}

import AppKit
import XCTest
@testable import LifecyclePreflight

final class ObservedLockSignalsTests: XCTestCase {
    func testHappySDKNamesAndDistributedPair() {
        XCTAssertEqual(ObservedLockSignals.map(NSWorkspace.willSleepNotification, center: .workspace), .willSleep)
        XCTAssertEqual(ObservedLockSignals.map(NSWorkspace.didWakeNotification, center: .workspace), .didWake)
        XCTAssertEqual(ObservedLockSignals.map(NSWorkspace.sessionDidResignActiveNotification, center: .workspace), .sessionResigned)
        XCTAssertEqual(ObservedLockSignals.map(NSWorkspace.sessionDidBecomeActiveNotification, center: .workspace), .sessionBecameActive)
        XCTAssertEqual(ObservedLockSignals.map(.init("com.apple.screenIsLocked"), center: .distributed), .screenLocked)
        XCTAssertEqual(ObservedLockSignals.map(.init("com.apple.screenIsUnlocked"), center: .distributed), .screenUnlocked)
    }
    func testFailureWrongCenterAndFocusNeverRecognized() {
        XCTAssertNil(ObservedLockSignals.map(NSWorkspace.willSleepNotification, center: .distributed))
        XCTAssertNil(ObservedLockSignals.map(.init("com.apple.screenIsUnlocked"), center: .workspace))
        XCTAssertNil(ObservedLockSignals.map(NSApplication.didBecomeActiveNotification, center: .workspace))
        XCTAssertTrue(ObservedLockSignals.qualifiedLiveVersions.isEmpty)
    }
}

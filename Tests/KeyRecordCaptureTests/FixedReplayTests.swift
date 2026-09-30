#if DEBUG
import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

private struct ReplayProviders: FrontmostAppProvider, SecureInputProvider, SessionLockProvider {
    func foregroundState() async -> ForegroundState { .attributable(bundleID: "performance.fixture") }
    func secureInputState() async -> SecureInputState { .disabled }
    func sessionLockState() async -> SessionLockState { .unlocked }
}

private struct ReplayPermission: InputMonitoringPermission {
    let status: InputMonitoringStatus
    func preflight() -> InputMonitoringStatus { status }
    func request() -> InputMonitoringStatus { status }
}

final class FixedReplayTests: XCTestCase {
    func testFixtureBytesMatchTheEventsDrivenByTheController() async throws {
        XCTAssertEqual(try JSONEncoder().encode(FixedReplayController.pattern), FixedReplayController.fixtureJSON)
        let queue = CaptureQueue()
        let providers = ReplayProviders()
        queue.install(GateInputs(collecting: true, keyAvailability: .available,
            sessionLock: .unlocked, secureInput: .disabled,
            foreground: .attributable(bundleID: "performance.fixture"), exclusion: .included),
            for: queue.generation)
        let controller = FixedReplayController()
        let source = ListenOnlyEventSource.fixedReplay(queue: queue, qualification: AllowedCapture(),
            providers: CaptureProviderSet(foreground: providers, secureInput: providers,
                                          sessionLock: providers), controller: controller,
            permission: ReplayPermission(status: .granted))
        let received = CaptureLock([Int]())
        let delivered = expectation(description: "fixed fixture delivered")
        delivered.expectedFulfillmentCount = 16
        try await source.start { event in
            received.withLock { $0.append(event.keyCode.value) }
            delivered.fulfill()
            return .accepted
        }
        let liveBefore = await source.hasLiveSession
        XCTAssertTrue(liveBefore)
        XCTAssertEqual(controller.emit(tick: 0), 16)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(received.withLock { $0 }, [0, 0, 1, 1, 2, 2, 3, 3,
                                                  0, 0, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(controller.acceptedEvents, 16)
        await source.stop()
        let liveAfter = await source.hasLiveSession
        XCTAssertFalse(liveAfter)
        XCTAssertEqual(controller.emit(tick: 1), 0)
        XCTAssertEqual(controller.acceptedEvents, 16)
    }

    func testDeniedPermissionCannotStartReplay() async throws {
        let queue = CaptureQueue()
        let providers = ReplayProviders()
        queue.install(GateInputs(collecting: true, keyAvailability: .available,
            sessionLock: .unlocked, secureInput: .disabled,
            foreground: .attributable(bundleID: "performance.fixture"), exclusion: .included),
            for: queue.generation)
        let controller = FixedReplayController()
        let source = ListenOnlyEventSource.fixedReplay(queue: queue, qualification: AllowedCapture(),
            providers: CaptureProviderSet(foreground: providers, secureInput: providers,
                                          sessionLock: providers), controller: controller,
            permission: ReplayPermission(status: .denied))

        do {
            try await source.start { _ in .accepted }
            XCTFail("Replay started without Input Monitoring authorization")
        } catch CaptureStartError.permissionRequired {}
        let live = await source.hasLiveSession
        XCTAssertFalse(live)
        XCTAssertEqual(controller.emit(tick: 0), 0)
    }
}
#endif

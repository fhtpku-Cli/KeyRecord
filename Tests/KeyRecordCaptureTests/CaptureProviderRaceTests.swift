import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

private struct DelayedProviders: FrontmostAppProvider, SecureInputProvider, SessionLockProvider {
    let barrier: CaptureBarrier
    func foregroundState() async -> ForegroundState {
        await barrier.suspend()
        return .attributable(bundleID: "stale.app")
    }
    func secureInputState() async -> SecureInputState { .disabled }
    func sessionLockState() async -> SessionLockState { .unlocked }
}

extension CaptureProviderTests {
    func testForegroundProviderReadErrorCannotBecomeUnattributable() async {
        enum Failure: Error { case read }
        let provider = FallibleForegroundProvider { throw Failure.read }
        let state = await provider.foregroundState()
        XCTAssertEqual(state, .unknown)
    }

    func testActivationWhileRefreshingCannotPublishStaleSnapshot() async {
        let queue = CaptureQueue()
        let barrier = CaptureBarrier()
        let providers = DelayedProviders(barrier: barrier)
        let control = CaptureControl(queue: queue, providers: CaptureProviderSet(
            foreground: providers, secureInput: providers, sessionLock: providers))
        let refresh = Task { await control.refresh(policy: .collecting) }
        await barrier.waitForArrival()
        queue.revoke()
        await barrier.resume()
        await refresh.value
        XCTAssertFalse(queue.isOpen)
        XCTAssertEqual(queue.snapshot.inputs.foreground, .unknown)
        XCTAssertEqual(queue.snapshot.inputs.secureInput, .unknown)
        XCTAssertEqual(queue.snapshot.inputs.sessionLock, .unknown)
    }

    func testCancelledRefreshRemainsClosed() async {
        let queue = CaptureQueue()
        let barrier = CaptureBarrier()
        let providers = DelayedProviders(barrier: barrier)
        let control = CaptureControl(queue: queue, providers: CaptureProviderSet(
            foreground: providers, secureInput: providers, sessionLock: providers))
        let refresh = Task { await control.refresh(policy: .collecting) }
        await barrier.waitForArrival()
        refresh.cancel()
        await barrier.resume()
        await refresh.value
        XCTAssertFalse(queue.isOpen)
        XCTAssertEqual(queue.snapshot.inputs.secureInput, .unknown)
    }

    func testSecureInputErrorsAndUnavailableRemainUnknown() async {
        enum Failure: Error { case read }
        let failure = FallibleSecureInputProvider { throw Failure.read }
        let unavailable = FallibleSecureInputProvider { nil }
        let enabled = FallibleSecureInputProvider { true }
        let disabled = FallibleSecureInputProvider { false }
        let values = await [failure.secureInputState(), unavailable.secureInputState(),
                            enabled.secureInputState(), disabled.secureInputState()]
        XCTAssertEqual(values, [.unknown, .unknown, .enabled, .disabled])
    }
}

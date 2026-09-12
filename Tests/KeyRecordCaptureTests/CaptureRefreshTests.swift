import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

private struct Providers: FrontmostAppProvider, SecureInputProvider, SessionLockProvider {
    let foreground: ForegroundState
    let secure: SecureInputState
    let lock: SessionLockState
    func foregroundState() async -> ForegroundState { foreground }
    func secureInputState() async -> SecureInputState { secure }
    func sessionLockState() async -> SessionLockState { lock }
}

extension CaptureProviderTests {
    func testNilBundleDiffersFromReadFailure() {
        // Given / When / Then
        XCTAssertEqual(ForegroundReading.observed(bundleID: nil).state, .reliablyUnattributable)
        XCTAssertEqual(ForegroundReading.failed.state, .unknown)
        XCTAssertEqual(ForegroundReading.observed(bundleID: "").state, .reliablyUnattributable)
        XCTAssertEqual(ForegroundReading.observed(bundleID: "app").state, .attributable(bundleID: "app"))
    }

    func testUnsafeProviderStatesCloseGate() async {
        for providers in [
            Providers(foreground: .unknown, secure: .disabled, lock: .unlocked),
            Providers(foreground: .reliablyUnattributable, secure: .enabled, lock: .unlocked),
            Providers(foreground: .reliablyUnattributable, secure: .unknown, lock: .unlocked),
            Providers(foreground: .reliablyUnattributable, secure: .disabled, lock: .locked),
            Providers(foreground: .reliablyUnattributable, secure: .disabled, lock: .unknown)
        ] {
            // Given
            let queue = CaptureQueue()
            queue.install(.safe, for: queue.generation)
            let control = CaptureControl(queue: queue, providers: CaptureProviderSet(
                foreground: providers, secureInput: providers, sessionLock: providers))
            // When
            await control.refresh(policy: .collecting)
            // Then
            XCTAssertFalse(queue.isOpen)
        }
    }

    func testReliableUnattributableCanOpenWithFreshSafeProviders() async {
        // Given
        let queue = CaptureQueue()
        let fake = Providers(foreground: .reliablyUnattributable, secure: .disabled, lock: .unlocked)
        let control = CaptureControl(queue: queue, providers: CaptureProviderSet(
            foreground: fake, secureInput: fake, sessionLock: fake))
        // When
        await control.refresh(policy: .collecting)
        // Then
        XCTAssertTrue(queue.isOpen)
        XCTAssertEqual(queue.snapshot.generation, queue.generation)
    }

    func testUnqualifiedLockRemainsUnknown() async {
        // Given
        let provider = UnqualifiedSessionLockProvider()
        // When
        let state = await provider.sessionLockState()
        // Then
        XCTAssertEqual(state, .unknown)
    }
}

extension CapturePolicy {
    static var collecting: CapturePolicy {
        CapturePolicy(collecting: true, keyAvailability: .available, exclusion: .included)
    }
}

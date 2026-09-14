import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

extension CaptureProviderTests {
    func testForegroundChangeAfterSamplingBeforeSubscriptionRejectsActivation() async {
        // Given: A was sampled before the backend installed any invalidation subscription.
        let queue = CaptureQueue()
        let backend = CaptureTestBackend(queue: queue)
        let control = CaptureControl(queue: queue, providers: CaptureProviderSet(
            foreground: backend, secureInput: backend, sessionLock: backend))
        await control.refresh(policy: .collecting)
        backend.report(.foregroundChanged)
        let source = ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(), backend: backend)
        // When: activate with the now-stale A snapshot, while the current foreground is B.
        do {
            try await source.start { _ in XCTFail("stale foreground event published"); return .accepted }
            XCTFail("stale foreground activation succeeded")
        } catch { XCTAssertEqual(error as? CaptureStartError, .revoked) }
        // Then: no tap activation or event publication is allowed.
        XCTAssertFalse(queue.isOpen)
        XCTAssertEqual(backend.starts, 0)
        XCTAssertEqual(queue.pendingCount, 0)
        await source.stop()
    }

    func testSubscribedForegroundChangeDuringSamplingRejectsActivation() async {
        await assertSamplingChangeRejects(.foregroundChanged)
    }

    func testSubscribedSecureInputChangeDuringSamplingRejectsActivation() async {
        await assertSamplingChangeRejects(.secureInputChanged)
    }

    func testSubscribedLockChangeDuringSamplingRejectsActivation() async {
        await assertSamplingChangeRejects(.sessionChanged)
    }

    func testProviderDriftAtHandoffRejectsWithoutPublication() async {
        for reason in [CaptureInvalidation.foregroundChanged, .secureInputChanged, .sessionChanged] {
            let queue = CaptureQueue()
            queue.install(.safe, for: queue.generation)
            let backend = CaptureTestBackend(queue: queue)
            backend.driftDuringStart(reason)
            let source = ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(), backend: backend)
            do {
                try await source.start { _ in XCTFail("drifted provider published"); return .accepted }
                XCTFail("drifted provider activated")
            } catch { XCTAssertEqual(error as? CaptureStartError, .revoked) }
            XCTAssertEqual(backend.starts, 1)
            XCTAssertEqual(backend.handoffResult, .closed)
            XCTAssertFalse(queue.isOpen)
            XCTAssertEqual(queue.pendingCount, 0)
            await source.stop()
        }
    }

    func testSubscriptionPrecedesEveryAuthoritativeSample() async throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let backend = CaptureTestBackend(queue: queue)
        let source = ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(), backend: backend)
        try await source.start { _ in .accepted }
        XCTAssertEqual(backend.reads, 2)
        XCTAssertEqual(backend.unsubscribedReads, 0)
        XCTAssertEqual(backend.handoffResult, .accepted)
        await source.stop()
    }

    private func assertSamplingChangeRejects(_ reason: CaptureInvalidation) async {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let original = queue.generation
        let backend = CaptureTestBackend(queue: queue)
        backend.changeDuringRead(reason)
        let source = ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(), backend: backend)
        do {
            try await source.start { _ in XCTFail("invalidated sample published"); return .accepted }
            XCTFail("invalidated sample activated")
        } catch { XCTAssertEqual(error as? CaptureStartError, .revoked) }
        XCTAssertEqual(backend.reads, 1)
        XCTAssertEqual(backend.unsubscribedReads, 0)
        XCTAssertEqual(backend.starts, 0)
        XCTAssertFalse(queue.isOpen)
        XCTAssertNotEqual(queue.generation, original)
        XCTAssertEqual(queue.pendingCount, 0)
        await source.stop()
    }
}

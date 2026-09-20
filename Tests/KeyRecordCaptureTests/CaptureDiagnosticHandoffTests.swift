#if DEBUG
import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

final class CaptureDiagnosticHandoffTests: XCTestCase {
    func testAcceptedHandoffIsMeasuredWithoutInventingTapOrDurableEvidence() async throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let backend = CaptureTestBackend(queue: queue)
        let recorder = CaptureDiagnosticsRecorder()
        let source = ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(),
            backend: backend, permission: GrantedPermission())
        await source.setDiagnostics(recorder)
        try await source.start { _ in .accepted }
        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.handoffAccepted, 1)
        XCTAssertEqual(snapshot.handoffClosed, 0)
        XCTAssertEqual(snapshot.totalTapCallbacks, 0)
        XCTAssertEqual(snapshot.flushDurable, 0)
        XCTAssertFalse(snapshot.countersInstrumented)
        await source.stop()
    }

    func testProviderDriftRecordsRejectedHandoff() async {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let backend = CaptureTestBackend(queue: queue)
        backend.driftDuringStart(.secureInputChanged)
        let recorder = CaptureDiagnosticsRecorder()
        let source = ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(),
            backend: backend, permission: GrantedPermission())
        await source.setDiagnostics(recorder)
        do {
            try await source.start { _ in .accepted }
            XCTFail("changed privacy inputs must reject activation")
        } catch {
            XCTAssertEqual(error as? CaptureStartError, .revoked)
        }
        XCTAssertEqual(recorder.snapshot.handoffAccepted, 0)
        XCTAssertEqual(recorder.snapshot.handoffClosed, 1)
        await source.stop()
    }
}
#endif

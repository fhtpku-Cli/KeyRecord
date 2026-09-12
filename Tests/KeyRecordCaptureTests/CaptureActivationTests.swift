import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

actor CaptureBarrier {
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var arrived = false

    func suspend() async {
        await withCheckedContinuation { continuation in
            release = continuation
            arrived = true
            arrival?.resume()
            arrival = nil
        }
    }
    func waitForArrival() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func resume() { release?.resume(); release = nil }
}

private struct Qualification: CaptureQualification {
    let allowed: Bool
    let barrier: CaptureBarrier?
    func liveCaptureQualified() async -> Bool {
        if let barrier { await barrier.suspend() }
        return allowed
    }
}

private actor FakeTap: CaptureTapBackend {
    var starts = 0
    var stops = 0
    let fails: Bool
    let barrier: CaptureBarrier?
    private var handoff: (@Sendable (ObservedKeyEvent) -> EventHandoffResult)?
    init(fails: Bool = false, barrier: CaptureBarrier? = nil) { self.fails = fails; self.barrier = barrier }
    func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws {
        starts += 1
        self.handoff = handoff
        if let barrier { await barrier.suspend() }
        if fails { throw CaptureStartError.unavailable }
    }
    func stop() { stops += 1; handoff = nil }
    func emit(_ event: ObservedKeyEvent) -> EventHandoffResult { handoff?(event) ?? .closed }
}

extension CaptureProviderTests {
    func testSerialRuntimeDeliversOnlyViaBoundedHandoff() async throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let backend = FakeTap()
        let source = ListenOnlyEventSource(queue: queue,
            qualification: Qualification(allowed: true, barrier: nil), backend: backend)
        let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown, isAutoRepeat: false,
            modifiers: ModifierSet(), source: .ordinaryObserved, generation: queue.generation)
        let received: ObservedKeyEvent? = await withCheckedContinuation { continuation in
            Task {
                do {
                    try await source.start { observed in continuation.resume(returning: observed); return .accepted }
                    let result = await backend.emit(event)
                    XCTAssertEqual(result, .accepted)
                } catch { continuation.resume(returning: nil) }
            }
        }
        XCTAssertEqual(received?.generation, event.generation)
        await source.stop()
        let afterStop = await backend.emit(event)
        XCTAssertEqual(afterStop, .closed)
    }

    func testDefaultSystemFactoryCannotActivateLiveBackend() async {
        let queue = CaptureQueue()
        let source = await ListenOnlyEventSource.system(queue: queue)
        do { try await source.start { _ in .accepted }; XCTFail("unqualified") }
        catch { XCTAssertEqual(error as? CaptureStartError, .unqualified) }
        XCTAssertFalse(queue.isOpen)
    }

    func testUnqualifiedStartCreatesZeroTaps() async {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let backend = FakeTap()
        let source = ListenOnlyEventSource(queue: queue, qualification: UnqualifiedCapture(), backend: backend)
        do { try await source.start { _ in .accepted }; XCTFail("must block") }
        catch { XCTAssertEqual(error as? CaptureStartError, .unqualified) }
        let starts = await backend.starts
        XCTAssertEqual(starts, 0)
    }

    func testRevocationDuringQualificationNeverCreatesTap() async {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let barrier = CaptureBarrier()
        let backend = FakeTap()
        let source = ListenOnlyEventSource(queue: queue,
            qualification: Qualification(allowed: true, barrier: barrier), backend: backend)
        let start = Task { try await source.start { _ in .accepted } }
        await barrier.waitForArrival()
        await source.stop()
        queue.install(.safe, for: queue.generation)
        await barrier.resume()
        do { try await start.value; XCTFail("stale qualification") }
        catch { XCTAssertEqual(error as? CaptureStartError, .revoked) }
        let starts = await backend.starts
        XCTAssertEqual(starts, 0)
    }

    func testConcurrentStartAndStopDuringBackendActivation() async {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let barrier = CaptureBarrier()
        let backend = FakeTap(barrier: barrier)
        let source = ListenOnlyEventSource(queue: queue,
            qualification: Qualification(allowed: true, barrier: nil), backend: backend)
        let start = Task { try await source.start { _ in .accepted } }
        await barrier.waitForArrival()
        do { try await source.start { _ in .accepted }; XCTFail("duplicate start") }
        catch { XCTAssertEqual(error as? CaptureStartError, .alreadyStarted) }
        await source.stop()
        await barrier.resume()
        do { try await start.value; XCTFail("revoked start") }
        catch { XCTAssertEqual(error as? CaptureStartError, .revoked) }
        let starts = await backend.starts
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(queue.isOpen)
    }

    func testBackendFailureRevokesGeneration() async {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let original = queue.generation
        let source = ListenOnlyEventSource(queue: queue,
            qualification: Qualification(allowed: true, barrier: nil), backend: FakeTap(fails: true))
        do { try await source.start { _ in .accepted }; XCTFail("unavailable tap") }
        catch { XCTAssertEqual(error as? CaptureStartError, .unavailable) }
        XCTAssertFalse(queue.isOpen)
        XCTAssertNotEqual(queue.generation, original)
    }

    func testSingleBackendStartStopAndReopen() async throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let backend = FakeTap()
        let source = ListenOnlyEventSource(queue: queue,
            qualification: Qualification(allowed: true, barrier: nil), backend: backend)
        try await source.start { _ in .accepted }
        do { try await source.start { _ in .accepted }; XCTFail("duplicate") }
        catch { XCTAssertEqual(error as? CaptureStartError, .alreadyStarted) }
        await source.stop()
        do { try await source.start { _ in .accepted }; XCTFail("fresh providers required") }
        catch { XCTAssertEqual(error as? CaptureStartError, .closed) }
        queue.install(.safe, for: queue.generation)
        try await source.start { _ in .accepted }
        await source.stop()
        let starts = await backend.starts
        XCTAssertEqual(starts, 2)
    }
}

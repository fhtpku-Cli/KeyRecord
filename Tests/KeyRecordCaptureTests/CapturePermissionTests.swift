import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

/// KR-07 regression: in a stable un-granted state the product's start chain could never
/// reach the one production call to `CGRequestListenEventAccess()`.
///
/// The old order was: `prepare()` → `readProviders()` → sees `CGPreflightListenEventAccess()
/// == false` → `invalidate(.permissionRevoked)` → returns `.unknown` → prepare throws
/// `.revoked`. The request lived inside `backend.start()`, which that path never reached.
///
/// The contract asserted here:
/// * the permission request is reachable from a user-initiated start while denied;
/// * it is made exactly once per explicit user action, never in a background loop;
/// * while denied there is no tap and no event delivery (zero tap, zero aggregate);
/// * after the user grants it, an explicit retry establishes a brand-new session.
final class CapturePermissionTests: XCTestCase {

    // MARK: - Controllable permission service

    /// Records every preflight/request so "requested exactly once" is provable.
    private final class FakePermission: InputMonitoringPermission, @unchecked Sendable {
        private let lock = NSLock()
        private var status: InputMonitoringStatus
        private var grantOnRequest: Bool
        private(set) var preflightCount = 0
        private(set) var requestCount = 0

        init(status: InputMonitoringStatus, grantOnRequest: Bool = false) {
            self.status = status
            self.grantOnRequest = grantOnRequest
        }

        func preflight() -> InputMonitoringStatus {
            lock.withLock { preflightCount += 1; return status }
        }

        @discardableResult
        func request() -> InputMonitoringStatus {
            lock.withLock {
                requestCount += 1
                if grantOnRequest { status = .granted }
                return status
            }
        }

        func grantExternally() { lock.withLock { status = .granted } }
        var counts: (preflight: Int, request: Int) {
            lock.withLock { (preflightCount, requestCount) }
        }
    }

    /// Minimal tap backend that refuses to start unless permission is granted, and counts
    /// tap creations so "zero tap while denied" is an actual observation.
    private actor PermissionAwareTap: CaptureTapBackend {
        private let permission: FakePermission
        private(set) var tapCreations = 0
        private(set) var deliveredEvents = 0
        private var handoff: (@Sendable (ObservedKeyEvent) -> EventHandoffResult)?

        init(permission: FakePermission) { self.permission = permission }

        func subscribe(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) {}
        func readProviders() -> CaptureProviderSnapshot { cachedProviders() }
        nonisolated func cachedProviders() -> CaptureProviderSnapshot {
            CaptureProviderSnapshot(.safe)
        }

        func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) throws {
            guard permission.preflight() == .granted else { throw CaptureStartError.revoked }
            tapCreations += 1
            self.handoff = handoff
        }

        func stop() { handoff = nil }

        /// Simulates one physical key arriving at the tap callback.
        func emit(_ event: ObservedKeyEvent) -> EventHandoffResult {
            deliveredEvents += 1
            return handoff?(event) ?? .closed
        }

        var hasTap: Bool { handoff != nil }
    }

    private func makeSource(permission: FakePermission, tap: PermissionAwareTap,
                            queue: CaptureQueue) -> ListenOnlyEventSource {
        ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(),
                              backend: tap, permission: permission)
    }

    private func openQueue(_ queue: CaptureQueue) {
        queue.install(.safe, for: queue.generation)
    }

    // MARK: - denied → request → still denied

    func testDeniedStartRequestsPermissionExactlyOnceAndCreatesNoTap() async throws {
        let permission = FakePermission(status: .denied)
        let queue = CaptureQueue()
        openQueue(queue)
        let tap = PermissionAwareTap(permission: permission)
        let source = makeSource(permission: permission, tap: tap, queue: queue)

        do {
            try await source.start { _ in .accepted }
            XCTFail("start must not succeed while input monitoring is denied")
        } catch let error as CaptureStartError {
            XCTAssertEqual(error, .permissionRequired,
                           "denial must be reported as an actionable permission state")
        }

        // The request is reachable: this is the whole of KR-07.
        XCTAssertEqual(permission.counts.request, 1, "user-initiated start must reach request()")
        let creations = await tap.tapCreations
        XCTAssertEqual(creations, 0, "no tap may be created while denied")
        let hasTap = await tap.hasTap
        XCTAssertFalse(hasTap)
        XCTAssertFalse(queue.isOpen, "queue must fail closed after a denied start")
    }

    func testRepeatedDeniedStartsDoNotLoopThePermissionPrompt() async throws {
        let permission = FakePermission(status: .denied)
        let queue = CaptureQueue()
        let tap = PermissionAwareTap(permission: permission)
        let source = makeSource(permission: permission, tap: tap, queue: queue)

        // Three explicit user actions -> at most one prompt each, never a background loop.
        for _ in 0..<3 {
            openQueue(queue)
            _ = try? await source.start { _ in .accepted }
        }
        XCTAssertEqual(permission.counts.request, 3,
                       "exactly one request per explicit user action, no internal retry loop")
        let creations = await tap.tapCreations
        XCTAssertEqual(creations, 0)
    }

    func testDeniedSessionDeliversZeroEventsAndZeroAggregateDeltas() async throws {
        let permission = FakePermission(status: .denied)
        let queue = CaptureQueue()
        openQueue(queue)
        let tap = PermissionAwareTap(permission: permission)
        let source = makeSource(permission: permission, tap: tap, queue: queue)
        let accepted = Counter()

        _ = try? await source.start { _ in accepted.increment(); return .accepted }

        // Even if the system were to push an event, there is no installed handoff.
        let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown, isAutoRepeat: false,
                                     modifiers: ModifierSet(), source: .ordinaryObserved,
                                     generation: queue.generation)
        let result = await tap.emit(event)
        XCTAssertEqual(result, .closed)
        XCTAssertEqual(accepted.value, 0, "denied session must produce zero aggregate deltas")
    }

    // MARK: - denied → request → granted

    func testRequestThatGrantsAllowsAnExplicitRetryToStartAFreshSession() async throws {
        let permission = FakePermission(status: .denied, grantOnRequest: true)
        let queue = CaptureQueue()
        openQueue(queue)
        let tap = PermissionAwareTap(permission: permission)
        let source = makeSource(permission: permission, tap: tap, queue: queue)

        // First explicit start: prompts, and fails closed without a tap.
        do {
            try await source.start { _ in .accepted }
            XCTFail("the prompting start must not silently continue into a tap")
        } catch let error as CaptureStartError {
            XCTAssertEqual(error, .permissionRequired)
        }
        XCTAssertEqual(permission.counts.request, 1)
        var creations = await tap.tapCreations
        XCTAssertEqual(creations, 0, "the prompting attempt must not create a tap")

        // Explicit user retry after granting: a brand-new session starts.
        let generationBefore = queue.generation
        openQueue(queue)
        try await source.start { _ in .accepted }
        creations = await tap.tapCreations
        XCTAssertEqual(creations, 1, "retry after grant must establish exactly one new session")
        XCTAssertEqual(permission.counts.request, 1, "an already-granted retry must not prompt again")
        XCTAssertNotEqual(queue.generation, generationBefore, "retry must use a new generation")
    }

    func testAlreadyGrantedStartNeverPrompts() async throws {
        let permission = FakePermission(status: .granted)
        let queue = CaptureQueue()
        openQueue(queue)
        let tap = PermissionAwareTap(permission: permission)
        let source = makeSource(permission: permission, tap: tap, queue: queue)

        try await source.start { _ in .accepted }

        XCTAssertEqual(permission.counts.request, 0, "granted state must never show a prompt")
        let creations = await tap.tapCreations
        XCTAssertEqual(creations, 1)
    }

    func testPermissionIsRecheckedBeforeTapCreationNotOnlyAtEntry() async throws {
        // Granted at entry, revoked before the tap is created: must fail closed.
        let permission = FakePermission(status: .granted)
        let queue = CaptureQueue()
        openQueue(queue)
        let tap = RevokingTap(permission: permission)
        let source = ListenOnlyEventSource(queue: queue, qualification: AllowedCapture(),
                                           backend: tap, permission: permission)
        do {
            try await source.start { _ in .accepted }
            XCTFail("a revocation between entry and tap creation must fail closed")
        } catch {
            // expected
        }
        XCTAssertFalse(queue.isOpen)
    }

    /// Revokes permission at the moment the backend would create the tap.
    private actor RevokingTap: CaptureTapBackend {
        private let permission: FakePermission
        init(permission: FakePermission) { self.permission = permission }
        func subscribe(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) {}
        func readProviders() -> CaptureProviderSnapshot { cachedProviders() }
        nonisolated func cachedProviders() -> CaptureProviderSnapshot { CaptureProviderSnapshot(.safe) }
        func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) throws {
            throw CaptureStartError.revoked
        }
        func stop() {}
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}

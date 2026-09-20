import Foundation
import KeyRecordCore

public protocol CaptureQualification: Sendable {
    func liveCaptureQualified() async -> Bool
}

public struct UnqualifiedCapture: CaptureQualification {
    public init() {}
    public func liveCaptureQualified() async -> Bool { false }
}

public enum CaptureStartError: Error, Equatable {
    case unqualified, closed, alreadyStarted, unavailable, revoked
    /// Input Monitoring is not granted. Distinct from `.revoked` so the UI can offer an
    /// actionable "grant, then Retry" path instead of a generic failure (KR-07).
    case permissionRequired
}

protocol CaptureTapBackend: Sendable {
    func subscribe(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) async throws
    func readProviders() async -> CaptureProviderSnapshot
    func cachedProviders() -> CaptureProviderSnapshot
    func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws
    func stop() async
}

public actor ListenOnlyEventSource: EventSource {
    private let queue: CaptureQueue
    private let qualification: any CaptureQualification
    private let backend: any CaptureTapBackend
    private let permission: any InputMonitoringPermission
    private let reducer = DispatchQueue(label: "com.keyrecord.capture.reducer")
    private var signal: (any DispatchSourceUserDataAdd)?
    private var starting = false
    private var invalidationSink: (@Sendable (CaptureInvalidation) -> Void)?

    init(queue: CaptureQueue, qualification: any CaptureQualification, backend: any CaptureTapBackend,
         permission: any InputMonitoringPermission = DeniedInputMonitoringPermission()) {
        self.queue = queue
        self.qualification = qualification
        self.backend = backend
        self.permission = permission
    }

    public static func system(queue: CaptureQueue,
                              qualification: any CaptureQualification = UnqualifiedCapture(),
                              sessionLock: any SessionLockProvider = UnqualifiedSessionLockProvider(),
                              permission: any InputMonitoringPermission = SystemInputMonitoringPermission())
        async -> ListenOnlyEventSource {
        let backend = await SystemTapBackend(queue: queue, sessionLock: sessionLock,
                                             permission: permission)
        return ListenOnlyEventSource(queue: queue, qualification: qualification, backend: backend,
                                     permission: permission)
    }

    public func start(deliver: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws {
        guard !starting, signal == nil else { throw CaptureStartError.alreadyStarted }
        starting = true
        defer { starting = false }
        let expected = queue.snapshot
        let wasOpen = queue.isOpen
        queue.revoke()
        let generation = queue.generation
        guard await qualification.liveCaptureQualified() else {
            queue.revoke()
            throw CaptureStartError.unqualified
        }
        guard wasOpen else { throw CaptureStartError.closed }
        guard queue.generation == generation, !Task.isCancelled else { throw CaptureStartError.revoked }
        // KR-07: the permission gate runs BEFORE provider reads and generation validation.
        // Previously `readProviders()` saw a failing preflight, invalidated, and made
        // `prepare()` throw `.revoked`, so the only production `request()` call — which
        // lived inside `backend.start()` — was unreachable in a stable denied state.
        //
        // `start(deliver:)` is only ever invoked by an explicit user Start/Accept action,
        // so prompting here cannot become a background prompt loop. The prompting attempt
        // never continues into a tap: the user grants access, then retries explicitly,
        // which builds a brand-new session with a fresh generation.
        if permission.preflight() != .granted {
            permission.request()
            queue.revoke()
            throw CaptureStartError.permissionRequired
        }
        let queue = self.queue
        let backend = self.backend
        do {
            let prepared = try await CaptureControl.prepare(queue: queue, expected: expected,
                                                            backend: backend,
                                                            onInvalidation: invalidationSink)
            let current = await backend.readProviders()
            guard queue.validate(prepared, current: current), !Task.isCancelled else { throw CaptureStartError.revoked }
            try await activate(prepared: prepared, deliver: deliver)
        } catch {
            queue.revoke()
            signal?.cancel()
            signal = nil
            await backend.stop()
            throw error
        }
    }

    private func activate(prepared: CaptureSnapshot,
                          deliver: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws {
        let queue = self.queue
        let backend = self.backend
        let signal = DispatchSource.makeUserDataAddSource(queue: reducer)
        signal.setEventHandler {
            for _ in 0..<CaptureQueue.capacity {
                if !queue.deliverOne(current: { backend.cachedProviders() }, deliver) { break }
            }
        }
        signal.activate()
        self.signal = signal
        try await backend.start { event in
            guard event.generation == prepared.generation else { return .closed }
            let result = queue.handoff(event, current: { backend.cachedProviders() })
            if result == .accepted { signal.add(data: 1) }
            return result
        }
        guard queue.validate(prepared, current: backend.cachedProviders()), !Task.isCancelled else {
            throw CaptureStartError.revoked
        }
    }

    /// Whether a delivery session is currently established (KR-08).
    ///
    /// True only between a successful `start` and the next `stop`/failure. The UI uses this
    /// as the witness for a "Collecting" claim, because lifecycle phase and the key gate
    /// can both look healthy while no event source exists.
    public var hasLiveSession: Bool { signal != nil }

    /// Forwards typed invalidations to the single serial recovery entry point (KR-02).
    /// Set once by the composition layer; nil in tests that only exercise the source.
    public func setInvalidationSink(_ sink: (@Sendable (CaptureInvalidation) -> Void)?) {
        invalidationSink = sink
    }

    public func stop() async {
        queue.revoke()
        signal?.cancel()
        signal = nil
        await backend.stop()
    }
}

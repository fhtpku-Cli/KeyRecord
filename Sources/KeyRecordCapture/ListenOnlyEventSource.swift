import Foundation
import KeyRecordCore

public protocol CaptureQualification: Sendable {
    func liveCaptureQualified() async -> Bool
}

public struct UnqualifiedCapture: CaptureQualification {
    public init() {}
    public func liveCaptureQualified() async -> Bool { false }
}

public enum CaptureStartError: Error, Equatable { case unqualified, closed, alreadyStarted, unavailable, revoked }

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
    private let reducer = DispatchQueue(label: "com.keyrecord.capture.reducer")
    private var signal: (any DispatchSourceUserDataAdd)?
    private var starting = false

    init(queue: CaptureQueue, qualification: any CaptureQualification, backend: any CaptureTapBackend) {
        self.queue = queue
        self.qualification = qualification
        self.backend = backend
    }

    public static func system(queue: CaptureQueue,
                              qualification: any CaptureQualification = UnqualifiedCapture(),
                              sessionLock: any SessionLockProvider = UnqualifiedSessionLockProvider()) async -> ListenOnlyEventSource {
        let backend = await SystemTapBackend(queue: queue, sessionLock: sessionLock)
        return ListenOnlyEventSource(queue: queue, qualification: qualification, backend: backend)
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
        let queue = self.queue
        let backend = self.backend
        do {
            let prepared = try await CaptureControl.prepare(queue: queue, expected: expected, backend: backend)
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

    public func stop() async {
        queue.revoke()
        signal?.cancel()
        signal = nil
        await backend.stop()
    }
}

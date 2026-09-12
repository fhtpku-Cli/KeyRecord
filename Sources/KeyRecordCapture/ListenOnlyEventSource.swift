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
                              qualification: any CaptureQualification = UnqualifiedCapture()) async -> ListenOnlyEventSource {
        let backend = await SystemTapBackend(queue: queue)
        return ListenOnlyEventSource(queue: queue, qualification: qualification, backend: backend)
    }

    public func start(deliver: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws {
        guard !starting, signal == nil else { throw CaptureStartError.alreadyStarted }
        starting = true
        defer { starting = false }
        let generation = queue.generation
        guard await qualification.liveCaptureQualified() else {
            queue.revoke()
            throw CaptureStartError.unqualified
        }
        guard queue.isOpen else { throw CaptureStartError.closed }
        guard queue.generation == generation, !Task.isCancelled else { throw CaptureStartError.revoked }
        let queue = self.queue
        let signal = DispatchSource.makeUserDataAddSource(queue: reducer)
        signal.setEventHandler {
            for _ in 0..<CaptureQueue.capacity {
                if !queue.deliverOne(deliver) { break }
            }
        }
        signal.activate()
        self.signal = signal
        do {
            try await backend.start { event in
                let result = queue.handoff(event)
                if result == .accepted { signal.add(data: 1) }
                return result
            }
            guard queue.isOpen, queue.generation == generation, !Task.isCancelled else {
                throw CaptureStartError.revoked
            }
        } catch {
            queue.revoke()
            signal.cancel()
            self.signal = nil
            await backend.stop()
            throw error
        }
    }

    public func stop() async {
        queue.revoke()
        signal?.cancel()
        signal = nil
        await backend.stop()
    }
}

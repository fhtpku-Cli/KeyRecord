import Foundation
import KeyRecordCore

/// Shared by aggregate flushes and preference writes. The store lease is a safety
/// check, not a queue: all product writes must acquire this single FIFO first.
public actor SerialObjectWriter: FlushWriting {
    private let writer: any FlushWriting
    private let clock: any FlushClock
    private var accepting = true
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var drains: [UUID: (CheckedContinuation<FlushCompletion, Never>, Task<Void, Never>)] = [:]

    public init(writer: any FlushWriting, clock: any FlushClock) {
        self.writer = writer; self.clock = clock
    }

    public func write(_ objects: [FlushObject], generation: CaptureGeneration) async throws {
        guard accepting else { throw LifecycleFlushError.locked }
        guard waiters.count < 32 else { throw LifecycleFlushError.failed }
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
        defer { release() }
        guard accepting else { throw LifecycleFlushError.locked }
        try Task.checkCancellation()
        try await writer.write(objects, generation: generation)
    }

    /// No new writes, and no deletion until all already-issued ciphertext I/O has
    /// returned. Timeout leaves the writer suspended; it never pretends to drain.
    public func suspendAndDrain() async -> FlushCompletion {
        accepting = false
        guard busy else { return .saved }
        let id = UUID(), deadline = clock.now() + .seconds(5)
        return await withCheckedContinuation { continuation in
            let timeout = Task {
                do { try await clock.sleep(until: deadline) } catch { return }
                self.drains.removeValue(forKey: id)?.0.resume(returning: .timedOut)
            }
            drains[id] = (continuation, timeout)
        }
    }

    public func resume() throws {
        guard !busy else { throw LifecycleFlushError.timedOut }
        accepting = true
    }

    private func release() {
        if !waiters.isEmpty { waiters.removeFirst().resume(); return }
        busy = false
        let current = drains
        drains.removeAll()
        for (_, drain) in current { drain.1.cancel(); drain.0.resume(returning: .saved) }
    }
}

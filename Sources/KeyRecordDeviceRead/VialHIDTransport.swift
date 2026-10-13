import Foundation
import KeyRecordMappings

public enum VialHIDError: Error, Equatable, Sendable {
    case closed, busy, timeout, invalidReport, disconnected, ioFailure(Int32), wrongInterface
}
public struct VialHIDFrame: Sendable {
    public let reportID: Int
    public let bytes: [UInt8]
    public init(reportID: Int, bytes: [UInt8]) { self.reportID = reportID; self.bytes = bytes }
}
public protocol VialHIDEndpoint: Sendable {
    func start(receive: @escaping @Sendable (Result<VialHIDFrame, VialHIDError>) -> Void)
    func send(_ request: VialReadRequest, timeoutMilliseconds: Int,
              completion: @escaping @Sendable (Result<Void, VialHIDError>) -> Void)
    func close()
}
public protocol VialHIDDeadline: Sendable {
    func schedule(milliseconds: Int, action: @escaping @Sendable () -> Void) -> @Sendable () -> Void
}
public struct DispatchVialHIDDeadline: VialHIDDeadline {
    // DispatchWorkItem.cancel is thread-safe; this immutable wrapper exposes only cancellation.
    private final class Cancellation: @unchecked Sendable {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
    }
    public init() {}
    public func schedule(milliseconds: Int, action: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: item)
        let cancellation = Cancellation(item)
        return { cancellation.item.cancel() }
    }
}
// Lock protects the one outstanding exchange and terminal connection state.
// A timeout/cancellation closes the endpoint: untagged FE responses cannot be
// safely assigned to a later request on the same connection.
public final class VialHIDTransport: VialReadTransport, @unchecked Sendable {
    private struct Pending {
        let id: UUID
        let continuation: CheckedContinuation<[UInt8], any Error>
        var sent = false
        var response: [UInt8]?
        var cancelDeadline: (@Sendable () -> Void)?
    }
    private let lock = NSRecursiveLock()
    private let endpoint: any VialHIDEndpoint
    private let deadline: any VialHIDDeadline
    private var pending: Pending?
    private var closed = false
    public init(endpoint: any VialHIDEndpoint, deadline: any VialHIDDeadline = DispatchVialHIDDeadline()) {
        self.endpoint = endpoint; self.deadline = deadline
        endpoint.start { [weak self] frame in self?.receive(frame) }
    }
    deinit { if !closed { endpoint.close() } }
    public func close() { lock.withLock { fail(.closed) } }
    public func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
        guard timeoutMilliseconds > 0, timeoutMilliseconds <= Int(UInt32.max) else { throw VialReadbackError.invalidRequest }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    guard !closed else { continuation.resume(throwing: VialHIDError.closed); return }
                    guard pending == nil else { continuation.resume(throwing: VialHIDError.busy); return }
                    guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                    pending = Pending(id: id, continuation: continuation)
                    let cancel = deadline.schedule(milliseconds: timeoutMilliseconds) { [weak self] in
                        self?.lock.withLock { if self?.pending?.id == id { self?.fail(.timeout) } }
                    }
                    if pending?.id == id { pending?.cancelDeadline = cancel } else { cancel(); return }
                    endpoint.send(request, timeoutMilliseconds: timeoutMilliseconds) { [weak self] result in
                        self?.sent(result, id: id)
                    }
                }
            }
        } onCancel: {
            self.lock.withLock { if self.pending?.id == id { self.fail(.closed) } }
        }
    }
    private func sent(_ result: Result<Void, VialHIDError>, id: UUID) {
        lock.withLock {
            guard pending?.id == id else { return }
            switch result {
            case .failure(let error): fail(error)
            case .success: pending?.sent = true; finish()
            }
        }
    }
    private func receive(_ result: Result<VialHIDFrame, VialHIDError>) {
        lock.withLock {
            guard !closed else { return }
            switch result {
            case .failure(let error): fail(error)
            case .success(let frame):
                guard pending != nil, pending?.response == nil, frame.reportID == 0, frame.bytes.count == 32 else {
                    fail(.invalidReport); return
                }
                pending?.response = frame.bytes; finish()
            }
        }
    }
    private func finish() {
        guard let current = pending, current.sent, let response = current.response else { return }
        pending = nil; current.cancelDeadline?(); current.continuation.resume(returning: response)
    }
    private func fail(_ error: VialHIDError) {
        guard !closed else { return }
        closed = true
        let current = pending; pending = nil
        current?.cancelDeadline?(); endpoint.close(); current?.continuation.resume(throwing: error)
    }
}

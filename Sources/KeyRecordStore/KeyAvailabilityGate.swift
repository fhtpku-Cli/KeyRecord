import Foundation
import KeyRecordCore

public protocol KeyAvailabilityFencing: Sendable {
    func begin() throws -> CaptureGeneration
    func check(_ candidate: CaptureGeneration) throws
    func use<T>(_ candidate: CaptureGeneration, body: () throws -> T) throws -> T
    func run<T: Sendable>(_ candidate: CaptureGeneration,
                         operation: @escaping @Sendable () async throws -> T) async throws -> T
}

/// Synchronous lock notifications cannot wait for the writer actor. Every field is protected by mutex.
/// Handles carry no material. Swift/Data copies are not claimed to be reliably zeroized.
public final class KeyAvailabilityGate: KeyAvailabilityFencing, @unchecked Sendable {
    private let mutex = NSRecursiveLock()
    private var state: SessionLockState = .unknown
    private var generation: CaptureGeneration
    private var exhausted = false
    private var operations: [UUID: @Sendable () -> Void] = [:]

    public init(generation: CaptureGeneration = CaptureGeneration(rawValue: 0)) { self.generation = generation }

    #if DEBUG
    /// Who last changed the gate, for diagnostics only. A caller-supplied label from a
    /// fixed set of call sites — never user data. DEBUG-only so Release cannot carry it.
    public private(set) var lastUpdateSource: String?
    #endif

    public func update(_ next: SessionLockState, source: StaticString = #function) {
        #if DEBUG
        mutex.withLock { lastUpdateSource = "\(source)->\(next)" }
        #endif
        mutex.withLock {
            guard !exhausted, state != next else { return }
            let (value, overflow) = generation.rawValue.addingReportingOverflow(1)
            exhausted = overflow
            state = overflow ? .unknown : next
            if !overflow { generation = CaptureGeneration(rawValue: value) }
            let cancellations = Array(operations.values)
            operations.removeAll()
            for cancel in cancellations { cancel() }
        }
    }

    public func begin() throws -> CaptureGeneration {
        try mutex.withLock {
            guard state == .unlocked, !exhausted else { throw KeyringError.locked }
            return generation
        }
    }

    public func renewOpenGeneration() throws -> CaptureGeneration {
        try mutex.withLock {
            _ = try begin()
            update(.unknown)
            update(.unlocked)
            return try begin()
        }
    }

    public func check(_ candidate: CaptureGeneration) throws {
        try mutex.withLock { try checkLocked(candidate) }
    }

    public func use<T>(_ candidate: CaptureGeneration, body: () throws -> T) throws -> T {
        try mutex.withLock {
            try checkLocked(candidate)
            let result = try body()
            try checkLocked(candidate)
            return result
        }
    }

    public func run<T: Sendable>(_ candidate: CaptureGeneration,
                          operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let id = UUID()
        let task = try mutex.withLock {
            try checkLocked(candidate)
            let task = Task { try self.check(candidate); try Task.checkCancellation(); return try await operation() }
            operations[id] = { task.cancel() }
            return task
        }
        defer { mutex.withLock { operations[id] = nil } }
        return try await withTaskCancellationHandler {
            do {
                let result = try await task.value
                try check(candidate)
                try Task.checkCancellation()
                return result
            } catch {
                try check(candidate)
                throw error
            }
        } onCancel: { task.cancel() }
    }

    private func checkLocked(_ candidate: CaptureGeneration) throws {
        guard candidate == generation, !exhausted else { throw KeyringError.staleGeneration }
        guard state == .unlocked else { throw KeyringError.locked }
    }
}

public struct KeyMaterialHandle: Sendable {
    public let version: KeyVersion
    let generation: CaptureGeneration
    let owner: UUID
}

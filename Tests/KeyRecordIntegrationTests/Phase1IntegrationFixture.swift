import Foundation
import KeyRecordCore
import KeyRecordStore
@testable import KeyRecordCapture

actor IntegrationKeys: ObjectStoreKeySource {
    private var installed = false
    private var suspended = false
    private var pending: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func install() { installed = true }
    func namespaceKeyVersions() -> Set<KeyVersion> { installed ? [KeyVersion(rawValue: 1)] : [] }
    func material(for version: KeyVersion) async -> Data {
        if suspended {
            await withCheckedContinuation { continuation in
                pending = continuation
                for observer in observers { observer.resume() }
                observers.removeAll()
            }
        }
        return Data(repeating: 0x19, count: 32)
    }
    func suspend() { suspended = true }
    func entered() async {
        if pending != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { suspended = false; pending?.resume(); pending = nil }
}

struct IntegrationClock: LocalClock {
    let calendar = Calendar(identifier: .gregorian)
    let timeZone = TimeZone(secondsFromGMT: 0)!
    func now() -> Date { Date(timeIntervalSince1970: 1_789_344_000) }
}

final class ManualFlushClock: FlushClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Duration = .zero
    private var sleepers: [UUID: (Duration, CheckedContinuation<Void, any Error>)] = [:]
    private var observers: [CheckedContinuation<Void, Never>] = []
    func now() -> Duration { lock.withLock { instant } }
    func sleep(until deadline: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else if instant >= deadline { continuation.resume() }
                    else { sleepers[id] = (deadline, continuation) }
                    for observer in observers { observer.resume() }
                    observers.removeAll()
                }
            }
        } onCancel: {
            self.lock.withLock { self.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
        }
    }
    func waitForSleeper() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if sleepers.isEmpty { observers.append(continuation) }
                else { continuation.resume() }
            }
        }
    }
    func advance(to value: Duration) {
        lock.withLock {
            instant = value
            let due = sleepers.filter { $0.value.0 <= value }
            for (id, sleeper) in due { sleepers[id] = nil; sleeper.1.resume() }
        }
    }
}

actor SuspendedCommitter: CiphertextCommitting {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    func commit(name: String, bytes: Data, root: URL) async throws {
        calls += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for observer in observers { observer.resume() }
            observers.removeAll()
        }
        try AtomicCiphertextCommitter().commit(name: name, bytes: bytes, root: root)
    }
    func entered() async {
        if continuation != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class IntegrationFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-t19-" + UUID().uuidString)
    let keys = IntegrationKeys()
    let gate = KeyAvailabilityGate()
    let queue = CaptureQueue()
    let clock = ManualFlushClock()
    let cycle = CycleID(rawValue: "integration-cycle")
    var store: ObjectStore
    var normalizer = ChordNormalizer()
    var aggregate: AggregationReducer

    init() {
        store = ObjectStore(root: root, keySource: keys)
        aggregate = AggregationReducer(cycleID: cycle)
    }
    func boot() async throws {
        _ = try await store.bootstrap()
        await keys.install()
        try await store.initializeFreshInstallation()
        gate.update(.unlocked)
        let inputs = GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
            secureInput: .disabled, foreground: .attributable(bundleID: "com.example.canary"), exclusion: .included)
        queue.install(inputs, for: queue.generation)
        normalizer.update(inputs)
        aggregate.update(normalizer.gate)
    }
    func key(_ value: Int) throws {
        for kind in [KeyEventKind.keyDown, .keyUp] {
            let event = ObservedKeyEvent(keyCode: try KeyCode(value), kind: kind, isAutoRepeat: false,
                modifiers: ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none),
                source: .ordinaryObserved, generation: queue.generation)
            guard queue.handoff(event) == .accepted, let output = queue.reduceOne() else { continue }
            try aggregate.process(output.output, generation: output.generation, clock: IntegrationClock())
        }
    }
    func reopen() async throws -> AggregationReducer {
        await store.closeProtectedSession()
        store = ObjectStore(root: root, keySource: keys)
        _ = try await store.bootstrap()
        return try await AggregatePersistence.restore(cycleID: cycle, store: store, gate: gate)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

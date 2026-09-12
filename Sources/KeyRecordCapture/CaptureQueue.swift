import Foundation
import KeyRecordCore

public struct CaptureSnapshot: Sendable {
    public let generation: CaptureGeneration
    public let inputs: GateInputs
    public var foreground: ForegroundState { inputs.foreground }
}

struct CaptureReduction: Sendable {
    let generation: CaptureGeneration
    let foreground: ForegroundState
    let output: NormalizationOutput
}

public final class CaptureQueue: Sendable {
    public static let capacity = 4096
    private struct State: Sendable {
        var events = Array<ObservedKeyEvent?>(repeating: nil, count: CaptureQueue.capacity)
        var head = 0
        var count = 0
        var normalizer = ChordNormalizer()
        var foreground: ForegroundState = .unknown
        var inputs = GateInputs()

        mutating func revoke() {
            normalizer.reset()
            foreground = .unknown
            inputs = GateInputs()
            // Logical drain is constant-time; control-side refresh scrubs inaccessible slots.
            head = 0
            count = 0
        }
    }
    private let state = CaptureLock(State())

    public init() {}
    public var generation: CaptureGeneration { state.withLock { $0.normalizer.gate.generation } }
    public var isOpen: Bool { state.withLock { $0.normalizer.gate.isOpen } }
    public var pendingCount: Int { state.withLock { $0.count } }
    var modifiers: ModifierSet { state.withLock { $0.normalizer.gate.modifiers } }
    public var snapshot: CaptureSnapshot {
        state.withLock { CaptureSnapshot(generation: $0.normalizer.gate.generation, inputs: $0.inputs) }
    }

    public func revoke() { state.withLock { $0.revoke() } }

    func install(_ inputs: GateInputs, for generation: CaptureGeneration) {
        state.withLock { state in
            guard state.normalizer.gate.generation == generation else { return }
            if state.normalizer.gate.isOpen && inputs.foreground != state.foreground {
                state.revoke()
                return
            }
            if !state.normalizer.gate.isOpen {
                for index in state.events.indices { state.events[index] = nil }
            }
            state.normalizer.update(inputs)
            state.inputs = inputs
            state.foreground = state.normalizer.gate.isOpen ? inputs.foreground : .unknown
            if !state.normalizer.gate.isOpen { state.head = 0; state.count = 0 }
        }
    }

    public func handoff(_ event: ObservedKeyEvent) -> EventHandoffResult {
        state.withLock { state in
            guard state.normalizer.gate.accepts(event.generation) else { return .closed }
            guard state.count < Self.capacity else {
                state.revoke()
                return .overflow
            }
            state.events[(state.head + state.count) % Self.capacity] = event
            state.count += 1
            return .accepted
        }
    }

    func reduceOne() -> CaptureReduction? {
        state.withLock { state in
            guard state.count > 0, let event = state.events[state.head] else { return nil }
            state.events[state.head] = nil
            state.head = (state.head + 1) % Self.capacity
            state.count -= 1
            guard state.normalizer.gate.accepts(event.generation) else { return nil }
            return CaptureReduction(generation: event.generation, foreground: state.foreground,
                output: state.normalizer.process(event))
        }
    }

    // The serial reducer's sink must be bounded, in-memory and non-reentrant. Holding the fence
    // through delivery prevents a dequeued event from publishing after a concurrent close.
    func deliverOne(_ deliver: @Sendable (ObservedKeyEvent) -> EventHandoffResult) -> Bool {
        state.withLock { state in
            guard state.count > 0, let event = state.events[state.head] else { return false }
            state.events[state.head] = nil
            state.head = (state.head + 1) % Self.capacity
            state.count -= 1
            guard state.normalizer.gate.accepts(event.generation) else { return true }
            if event.source == .productMarked { return true }
            _ = state.normalizer.process(event, activeModifierFamilies: Self.families(event.modifiers))
            let reconstructed = ObservedKeyEvent(keyCode: event.keyCode, kind: event.kind,
                isAutoRepeat: event.isAutoRepeat, modifiers: state.normalizer.gate.modifiers,
                source: event.source, generation: event.generation)
            if deliver(reconstructed) != .accepted { state.revoke() }
            return true
        }
    }

    private static func families(_ modifiers: ModifierSet) -> Set<ModifierFamily> {
        var families: Set<ModifierFamily> = []
        if modifiers.command != .none { families.insert(.command) }
        if modifiers.option != .none { families.insert(.option) }
        if modifiers.control != .none { families.insert(.control) }
        if modifiers.shift != .none { families.insert(.shift) }
        return families
    }
}

import Foundation

/// Pure control state. Closure reasons describe policy, never rejected event activity.
public struct PrivacyGate: Sendable {
    public enum ClosureReason: Equatable, Sendable {
        case notCollecting, keyUnavailable, sessionLocked, secureInput
        case foregroundUnreliable, excluded, reset, generationExhausted
    }

    public private(set) var generation: CaptureGeneration
    public private(set) var closureReason: ClosureReason? = .notCollecting
    public private(set) var heldKeys: Set<KeyCode> = []
    public private(set) var modifiers = ModifierSet()
    public var isOpen: Bool { closureReason == nil }

    public init(generation: CaptureGeneration = CaptureGeneration(rawValue: 0)) {
        self.generation = generation
    }

    public mutating func update(_ inputs: GateInputs) {
        guard closureReason != .generationExhausted else { return }
        let reason = Self.reason(inputs)
        let changesOpenness = isOpen != (reason == nil)
        closureReason = reason
        if changesOpenness { advanceGeneration() }
        if !isOpen { clearHeldState() }
    }

    public mutating func reset() {
        closureReason = .reset
        advanceGeneration()
        clearHeldState()
    }

    public func accepts(_ candidate: CaptureGeneration) -> Bool {
        isOpen && candidate == generation
    }

    mutating func observe(_ event: ObservedKeyEvent, modifiers: ModifierSet) {
        self.modifiers = modifiers
        switch event.kind {
        case .keyDown: heldKeys.insert(event.keyCode)
        case .keyUp: heldKeys.remove(event.keyCode)
        case .flagsChanged: break
        }
    }

    private mutating func clearHeldState() {
        heldKeys.removeAll(keepingCapacity: false)
        modifiers = ModifierSet()
    }

    private mutating func advanceGeneration() {
        let (next, overflow) = generation.rawValue.addingReportingOverflow(1)
        if overflow { closureReason = .generationExhausted }
        else { generation = CaptureGeneration(rawValue: next) }
    }

    private static func reason(_ inputs: GateInputs) -> ClosureReason? {
        guard inputs.collecting else { return .notCollecting }
        guard inputs.keyAvailability == .available else { return .keyUnavailable }
        guard inputs.sessionLock == .unlocked else { return .sessionLocked }
        guard inputs.secureInput == .disabled else { return .secureInput }
        guard inputs.foreground != .unknown else { return .foregroundUnreliable }
        if case .attributable(let bundleID) = inputs.foreground, bundleID.isEmpty {
            return .foregroundUnreliable
        }
        guard inputs.exclusion == .included else { return .excluded }
        return nil
    }
}

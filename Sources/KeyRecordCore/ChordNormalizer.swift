import Foundation

/// Serial, deterministic in-memory reducer. Control updates must precede processing their events.
/// Recheck providers at the adapter boundary; Core does not obtain or infer platform state.
public struct ChordNormalizer: Sendable {
    public private(set) var gate: PrivacyGate
    private var reconstruction = ModifierReconstructor()
    private var foreground: ForegroundState = .unknown
    public let rules: ChordRuleTable

    public init(generation: CaptureGeneration = CaptureGeneration(rawValue: 0), rules: ChordRuleTable = .v1) {
        gate = PrivacyGate(generation: generation)
        self.rules = rules
    }

    public mutating func update(_ inputs: GateInputs) {
        let previous = gate.generation
        gate.update(inputs)
        foreground = gate.isOpen ? inputs.foreground : .unknown
        if !gate.isOpen || previous != gate.generation { reconstruction.reset() }
    }

    public mutating func reset() {
        gate.reset()
        foreground = .unknown
        reconstruction.reset()
    }

    /// With decoded family flags, reconstruct sides from flagsChanged sequences and use the event's
    /// explicit Fn confidence. Otherwise the event carries an authoritative observed side snapshot.
    public mutating func process(
        _ event: ObservedKeyEvent, activeModifierFamilies: Set<ModifierFamily>? = nil
    ) -> NormalizationOutput {
        guard gate.accepts(event.generation) else { return .none }
        let source: NormalizedSource
        switch event.source {
        case .productMarked: return .none
        case .ordinaryObserved: source = .ordinaryObserved
        case .suspectedInjection: source = .suspectedInjection
        }
        if let activeModifierFamilies {
            reconstruction.observeFlags(active: activeModifierFamilies, fn: event.modifiers.fn,
                changedKey: event.kind == .flagsChanged ? event.keyCode : nil)
        } else {
            reconstruction.apply(event.modifiers)
        }
        let modifiers = reconstruction.snapshot
        gate.observe(event, modifiers: modifiers)
        switch event.kind {
        case .flagsChanged: return .none
        case .keyUp: return .keyUp(event.keyCode)
        case .keyDown: break
        }
        if event.isAutoRepeat { return .repeatedKeyDown(event.keyCode) }
        // Fn unknown is transient (SP2 ModifierReconstruction.swift:32), never a counted chord.
        guard modifiers.fn != .unknown else { return .none }
        let bare = modifiers.command == .none && modifiers.option == .none
            && modifiers.control == .none && modifiers.shift == .none && modifiers.fn == .none
        if bare { return .keyDown(.bare(event.keyCode), source) }
        let bucket: AppBucket
        switch foreground {
        case .attributable(let bundleID): bucket = .bundleID(bundleID)
        case .reliablyUnattributable: bucket = .unknown
        case .unknown: return .none
        }
        let chord = Chord(keyCode: event.keyCode, modifiers: modifiers)
        return .keyDown(.chord(ChordBucket(chord: chord, appBucket: bucket), rules.classify(chord)), source)
    }
}

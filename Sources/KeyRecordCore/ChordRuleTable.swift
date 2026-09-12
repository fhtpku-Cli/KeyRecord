import Foundation

public enum ChordRuleTable: Sendable {
    case v1

    public var version: UInt32 { 1 }

    public func classify(_ chord: Chord) -> ShortcutClassification {
        let modifiers = chord.modifiers
        let command = modifiers.command != .none
        let option = modifiers.option != .none
        let control = modifiers.control != .none
        let shift = modifiers.shift != .none
        if chord.keyCode.value == 48 && command && !option && !control {
            // Plan task 8 / architecture 4.7: Cmd-Tab and Cmd-Shift-Tab, not app semantics.
            return ShortcutClassification(kind: .stateful, scope: .normal)
        }
        // G0 controlled classifier: Spikes/Sources/Phase0Probe/SP1Probe.swift:368-372.
        // evidence/phase0/sp1/evidence.json:56-71 binds this systemShortcut leg.
        // Exact four-family matches: Shift-Cmd-3 and Ctrl-Up; Fn is outside that mask.
        let screenshot = chord.keyCode.value == 20 && shift && command && !control && !option
        let missionControl = chord.keyCode.value == 126 && control && !shift && !command && !option
        return ShortcutClassification(kind: .discrete, scope: screenshot || missionControl ? .system : .normal)
    }
}

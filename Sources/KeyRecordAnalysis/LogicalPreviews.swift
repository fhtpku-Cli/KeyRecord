import Foundation
import KeyRecordCore

public enum LogicalPreviews {
    public static func keyCount(_ chord: Chord) -> Int {
        let m = chord.modifiers
        let sides = [m.command, m.option, m.control, m.shift]
        return 1 + sides.reduce(0) { sum, side in
            sum + (side == .none ? 0 : side == .both ? 2 : 1)
        } + (m.fn == .active ? 1 : 0)
    }

    public static func canonicalID(_ chord: Chord) -> String {
        let m = chord.modifiers
        return ([String(format: "%03d", chord.keyCode.value)] +
            [m.command.rawValue, m.option.rawValue, m.control.rawValue, m.shift.rawValue, m.fn.rawValue]).joined(separator: ":")
    }

    static func generate(_ chord: Chord, confirmed: Set<KeyCode>) -> [TriggerPreview] {
        let original = keyCount(chord)
        let m = chord.modifiers
        // Unknown Fn cannot establish a reduction; side-unknown still means one active modifier.
        guard m.fn != .unknown else { return [] }
        var options: [Chord] = []
        let families = [m.command, m.option, m.control, m.shift]
        for index in families.indices where families[index] != .none {
            var values = families
            values[index] = .none
            // Require a command/control/option modifier. Shift-only printable keys are not safe sketches.
            guard values.prefix(3).contains(where: { $0 != .none }) else { continue }
            options.append(Chord(keyCode: chord.keyCode, modifiers: ModifierSet(command: values[0],
                option: values[1], control: values[2], shift: values[3], fn: m.fn)))
        }
        // Confirmed function keys only; other confirmed keys may be printable on an unknown layout.
        let functionCodes: Set<Int> = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
        for key in confirmed where functionCodes.contains(key.value) {
            options.append(Chord(keyCode: key, modifiers: ModifierSet(command: .none, option: .none,
                control: .none, shift: .none, fn: .none)))
        }
        return options.filter { keyCount($0) < original && ChordRuleTable.v1.classify($0).kind == .discrete }
            .sorted { keyCount($0) == keyCount($1) ? canonicalID($0) < canonicalID($1) : keyCount($0) < keyCount($1) }
            .prefix(3).map { TriggerPreview(chord: $0, logicalKeysSaved: original - keyCount($0)) }
    }
}

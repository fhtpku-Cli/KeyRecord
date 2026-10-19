import Foundation
import KeyRecordCore

public struct MenuShortcutEvidence: Equatable, Sendable {
    public let application: String
    public let shortcuts: Set<Chord>
    public init(application: String, shortcuts: Set<Chord>) {
        self.application = application; self.shortcuts = shortcuts
    }

    public static func chord(virtualKey: Int, modifiers: Int) -> Chord? {
        guard (0...15).contains(modifiers), let key = try? KeyCode(virtualKey) else { return nil }
        return Chord(keyCode: key, modifiers: ModifierSet(
            command: modifiers & 8 == 0 ? .activeSideUnknown : .none,
            option: modifiers & 2 != 0 ? .activeSideUnknown : .none,
            control: modifiers & 4 != 0 ? .activeSideUnknown : .none,
            shift: modifiers & 1 != 0 ? .activeSideUnknown : .none, fn: .unknown))
    }
}

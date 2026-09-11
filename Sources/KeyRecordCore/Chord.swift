import Foundation

public enum ModifierSideState: String, Codable, CaseIterable, Sendable {
    case none, left, right, both, activeSideUnknown
}

public enum FnState: String, Codable, CaseIterable, Sendable {
    case none, active, unknown
}

/// Architecture §§4.5–4.6, plan contract 5: unknown survives startup/reset until authoritative recovery.
public struct ModifierSet: Hashable, Codable, Sendable {
    public let command: ModifierSideState
    public let option: ModifierSideState
    public let control: ModifierSideState
    public let shift: ModifierSideState
    public let fn: FnState

    public init(
        command: ModifierSideState = .activeSideUnknown,
        option: ModifierSideState = .activeSideUnknown,
        control: ModifierSideState = .activeSideUnknown,
        shift: ModifierSideState = .activeSideUnknown,
        fn: FnState = .unknown
    ) {
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.fn = fn
    }
}

public struct Chord: Hashable, Codable, Sendable {
    public let keyCode: KeyCode
    public let modifiers: ModifierSet
    public init(keyCode: KeyCode, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum AppBucket: Hashable, Codable, Sendable {
    case bundleID(String)
    case unknown
}

public struct ChordBucket: Hashable, Codable, Sendable {
    public let chord: Chord
    public let appBucket: AppBucket
    public init(chord: Chord, appBucket: AppBucket) {
        self.chord = chord
        self.appBucket = appBucket
    }
}

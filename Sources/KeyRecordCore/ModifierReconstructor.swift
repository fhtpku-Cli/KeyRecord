import Foundation

public enum ModifierFamily: CaseIterable, Sendable {
    case command, option, control, shift
}

/// Behavior port: Spikes/Sources/Phase0Support/ModifierReconstruction.swift:23-53.
/// The adapter must supply observed snapshots, not default missing Fn evidence to `.none`.
public struct ModifierReconstructor: Equatable, Sendable {
    private var states: [ModifierFamily: ModifierSideState] = [:]
    private var fn: FnState = .unknown

    public init() {}

    public subscript(family: ModifierFamily) -> ModifierSideState {
        states[family] ?? .activeSideUnknown
    }

    public var snapshot: ModifierSet {
        ModifierSet(command: self[.command], option: self[.option], control: self[.control],
            shift: self[.shift], fn: fn)
    }

    public mutating func recover(family: ModifierFamily, left: Bool, right: Bool) {
        states[family] = switch (left, right) {
        case (false, false): ModifierSideState.none
        case (true, false): .left
        case (false, true): .right
        case (true, true): .both
        }
    }

    public mutating func recoverFn(active: Bool) { fn = active ? .active : .none }

    public mutating func markLoss(affected: Set<ModifierFamily>) {
        for family in affected { states[family] = .activeSideUnknown }
        fn = .unknown
    }

    public mutating func reset() {
        states.removeAll(keepingCapacity: false)
        fn = .unknown
    }

    public mutating func apply(_ observed: ModifierSet) {
        states = [.command: observed.command, .option: observed.option,
            .control: observed.control, .shift: observed.shift]
        fn = observed.fn
    }

    /// Family flags alone cannot identify sides after loss. A coherent flagsChanged key sequence
    /// can toggle known sides; explicit side snapshots recover unknown sides without guessing.
    /// `active` is an adapter-decoded set, not an OS bitmask; invalid flag bits cannot enter this API.
    public mutating func observeFlags(active: Set<ModifierFamily>, fn: FnState, changedKey: KeyCode?) {
        for family in ModifierFamily.allCases {
            guard active.contains(family) else {
                states[family] = ModifierSideState.none
                continue
            }
            guard let key = changedKey, let (changedFamily, isLeft) = Self.sideKey(key),
                  changedFamily == family else {
                if self[family] == .none { states[family] = .activeSideUnknown }
                continue
            }
            states[family] = switch (self[family], isLeft) {
            case (.none, true): .left
            case (.none, false): .right
            case (.left, false), (.right, true): .both
            case (.both, true): .right
            case (.both, false): .left
            case (.left, true), (.right, false), (.activeSideUnknown, _): .activeSideUnknown
            }
        }
        self.fn = fn
    }

    private static func sideKey(_ key: KeyCode) -> (ModifierFamily, Bool)? {
        switch key.value {
        case 55: (.command, true)
        case 54: (.command, false)
        case 58: (.option, true)
        case 61: (.option, false)
        case 59: (.control, true)
        case 62: (.control, false)
        case 56: (.shift, true)
        case 60: (.shift, false)
        default: nil
        }
    }
}

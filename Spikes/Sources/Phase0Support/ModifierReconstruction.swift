import Foundation

public enum ModifierFamily: String, Codable, CaseIterable, Sendable {
    case command, option, control, shift
}

public enum ModifierSideState: String, Codable, CaseIterable, Sendable {
    case none, left, right, both, activeSideUnknown
}

public enum FnConfidence: String, Codable, CaseIterable, Sendable {
    case knownNone, knownActive, unknown
}

public enum RecoveryTransition: String, Codable, CaseIterable, Sendable {
    case eventLoss, tapReset, wake
}

public struct ModifierReconstructionModel: Equatable, Sendable {
    private var states: [ModifierFamily: ModifierSideState]
    public private(set) var fn: FnConfidence

    public init() {
        states = Dictionary(uniqueKeysWithValues: ModifierFamily.allCases.map { ($0, .activeSideUnknown) })
        fn = .unknown
    }

    public subscript(family: ModifierFamily) -> ModifierSideState {
        states[family] ?? .activeSideUnknown
    }

    public var canCountFnSensitiveChord: Bool { fn != .unknown }

    public mutating func apply(family: ModifierFamily, left: Bool, right: Bool) {
        states[family] = switch (left, right) {
        case (false, false): ModifierSideState.none
        case (true, false): .left
        case (false, true): .right
        case (true, true): .both
        }
    }

    public mutating func applyFn(active: Bool) { fn = active ? .knownActive : .knownNone }

    public mutating func markLoss(affected: Set<ModifierFamily>) {
        for family in affected { states[family] = .activeSideUnknown }
        fn = .unknown
    }

    public mutating func invalidate(for transition: RecoveryTransition) {
        for family in ModifierFamily.allCases { states[family] = .activeSideUnknown }
        fn = .unknown
    }
}

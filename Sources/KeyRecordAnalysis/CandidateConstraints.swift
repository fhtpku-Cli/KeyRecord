import Foundation
import KeyRecordCore

public enum RecommendationBackend: String, CaseIterable, Sendable {
    case karabiner, via, vial
}

public struct BackendCapabilities: Equatable, Sendable {
    public let backend: RecommendationBackend
    public let keyCodes: Set<KeyCode>
    public let applicationScope: Bool
    public let fnModifier: Bool

    public init(backend: RecommendationBackend, keyCodes: Set<KeyCode>,
                applicationScope: Bool, fnModifier: Bool) {
        self.backend = backend
        self.keyCodes = keyCodes
        self.applicationScope = applicationScope
        self.fnModifier = fnModifier
    }
}

public enum BackendConnection: Equatable, Sendable {
    case disconnected(RecommendationBackend)
    case unsupported(RecommendationBackend)
    case connected(BackendCapabilities)
}

public struct CandidateCheckInput: Equatable, Sendable {
    public let source: Chord
    public let trigger: Chord
    public let scope: RecommendationScope
    public let backend: BackendConnection
    public let layout: LayoutPreference
    public let keyboardPool: Set<KeyCode>
    public let ruleVersion: String
    public let physicalEvidence: PhysicalEvidence?

    public init(source: Chord, trigger: Chord, scope: RecommendationScope,
                backend: BackendConnection, layout: LayoutPreference = LayoutPreference(),
                keyboardPool: Set<KeyCode> = [], ruleVersion: String = AnalysisSnapshot.ruleVersion,
                physicalEvidence: PhysicalEvidence? = nil) {
        self.source = source
        self.trigger = trigger
        self.scope = scope
        self.backend = backend
        self.layout = layout
        self.keyboardPool = keyboardPool
        self.ruleVersion = ruleVersion
        self.physicalEvidence = physicalEvidence
    }
}

public enum CandidateConflict: String, Equatable, Sendable {
    case observedShortcut, knownSystemRisk, existingRuleOverlap, mappingCycle, protectedLayerEntry
}

public enum CandidateUnsupportedReason: String, Equatable, Sendable {
    case backend, keyCode, applicationScope, fnModifier, stateful, sameChord, unknownModifiers
}

public struct CandidateConflictCheck: Equatable, Sendable {
    public let input: CandidateCheckInput
    public let conflicts: [CandidateConflict]
    public let evidenceKinds: Set<String>

    public init(input: CandidateCheckInput, conflicts: [CandidateConflict], evidenceKinds: Set<String>) {
        self.input = input
        self.conflicts = conflicts
        self.evidenceKinds = evidenceKinds
    }
}

public enum CandidateReadiness: Equatable, Sendable {
    case disconnected
    case unsupported(CandidateUnsupportedReason)
    case unchecked
    case conflict([CandidateConflict])
    case checked(evidenceKinds: Set<String>)
}

public enum CandidateConstraints {
    public static func assess(_ input: CandidateCheckInput, check: CandidateConflictCheck? = nil) -> CandidateReadiness {
        guard ChordRuleTable.v1.classify(input.source).kind == .discrete,
              ChordRuleTable.v1.classify(input.trigger).kind == .discrete else { return .unsupported(.stateful) }
        guard input.source != input.trigger else { return .unsupported(.sameChord) }
        let modifiers = input.trigger.modifiers
        guard [input.source.modifiers, modifiers].allSatisfy({ m in
            m.fn != .unknown && ![m.command, m.option, m.control, m.shift].contains(.activeSideUnknown)
        })
        else { return .unsupported(.unknownModifiers) }
        switch input.backend {
        case .disconnected: return .disconnected
        case .unsupported: return .unsupported(.backend)
        case .connected(let capabilities):
            guard capabilities.keyCodes.contains(input.trigger.keyCode),
                  capabilities.keyCodes.contains(input.source.keyCode) else { return .unsupported(.keyCode) }
            if case .application = input.scope, !capabilities.applicationScope { return .unsupported(.applicationScope) }
            if [input.source.modifiers.fn, modifiers.fn].contains(.active), !capabilities.fnModifier { return .unsupported(.fnModifier) }
        }
        guard let check, check.input == input, !check.evidenceKinds.isEmpty else { return .unchecked }
        if !check.conflicts.isEmpty { return .conflict(check.conflicts) }
        return .checked(evidenceKinds: check.evidenceKinds)
    }
}

public enum ManualCandidateError: Error, Equatable, Sendable {
    case invalidKeyCode, modifierAsTerminal, unknownModifiers, stateful
}

public enum ManualCandidateState: Equatable, Sendable {
    case editing
    case awaitingRiskConfirmation(Chord)
    case accepted(Chord)
}

public struct ManualCandidateDraft: Equatable, Sendable {
    public private(set) var state: ManualCandidateState = .editing

    public init() {}

    public mutating func invalidate() { state = .editing }

    public mutating func propose(keyCode: String, modifiers: ModifierSet) throws {
        state = .editing
        guard let value = Int(keyCode.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? KeyCode(value) else { throw ManualCandidateError.invalidKeyCode }
        guard ![54, 55, 56, 58, 59, 60, 61, 62, 63].contains(value) else { throw ManualCandidateError.modifierAsTerminal }
        guard modifiers.fn != .unknown,
              ![modifiers.command, modifiers.option, modifiers.control, modifiers.shift].contains(.activeSideUnknown)
        else { throw ManualCandidateError.unknownModifiers }
        let chord = Chord(keyCode: key, modifiers: modifiers)
        guard ChordRuleTable.v1.classify(chord).kind == .discrete else { throw ManualCandidateError.stateful }
        state = Self.needsRiskConfirmation(chord) ? .awaitingRiskConfirmation(chord) : .accepted(chord)
    }

    public mutating func confirmRisk() {
        if case .awaitingRiskConfirmation(let chord) = state { state = .accepted(chord) }
    }

    public static func needsRiskConfirmation(_ chord: Chord) -> Bool {
        let modifiers = chord.modifiers
        if [modifiers.command, modifiers.option, modifiers.control].contains(where: { $0 != .none }) { return false }
        let nonprinting = Set(LogicalPreviews.functionKeyValues + [36, 48, 51, 53, 57, 71, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126])
        return !nonprinting.contains(chord.keyCode.value)
    }
}

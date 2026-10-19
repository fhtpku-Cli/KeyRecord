import Foundation
import KeyRecordCore

public enum ConflictSeverity: String, Sendable { case warning, blocking }

public struct ConflictFinding: Equatable, Sendable {
    public let kind: CandidateConflict
    public var severity: ConflictSeverity {
        switch kind {
        case .observedShortcut, .knownSystemRisk, .applicationMenuShortcut: return .warning
        case .existingRuleOverlap, .mappingCycle, .protectedLayerEntry: return .blocking
        }
    }
}

public enum ConflictLimitation: String, CaseIterable, Hashable, Sendable {
    case observationsUnavailable, unknownApplication, backendRulesUnavailable
    case referenceOnly, unsupportedRules, profileMismatch, backendVersionUnknown, menuUnavailable, menuPartial, traversalLimit
}

public struct BackendRule: Equatable, Sendable {
    public let trigger: Chord
    public let output: Chord?
    public let scope: RecommendationScope
    public let devices: Set<String>?
    public let profile: String
    public let anyModifiers: Bool

    public init(trigger: Chord, output: Chord?, scope: RecommendationScope = .global,
                devices: Set<String>? = nil, profile: String, anyModifiers: Bool = false) {
        self.trigger = trigger; self.output = output; self.scope = scope
        self.devices = devices; self.profile = profile; self.anyModifiers = anyModifiers
    }
}

public enum BackendEvidenceOrigin: Equatable, Sendable { case selectedCopy, currentAdapter }

public struct BackendRuleEvidence: Equatable, Sendable {
    public let backend: RecommendationBackend
    public let profile: String
    public let rules: [BackendRule]
    public let unsupportedRuleCount: Int
    public let origin: BackendEvidenceOrigin
    public let backendVersion: String?
    public let protectedTriggers: Set<Chord>

    public init(backend: RecommendationBackend, profile: String, rules: [BackendRule],
                unsupportedRuleCount: Int = 0, origin: BackendEvidenceOrigin,
                protectedTriggers: Set<Chord> = [], backendVersion: String? = nil) {
        self.backend = backend; self.profile = profile; self.rules = rules
        self.unsupportedRuleCount = unsupportedRuleCount; self.origin = origin
        self.protectedTriggers = protectedTriggers
        self.backendVersion = backendVersion
    }
}

public struct CandidateConflictEvidence: Equatable, Sendable {
    /// nil means unavailable; an empty array means the visible cycle has no observations.
    public let observations: [ChordBucket]?
    public let backendRules: BackendRuleEvidence?
    public let profile: String?
    public let devices: Set<String>?
    public let menu: MenuShortcutEvidence?

    public init(observations: [ChordBucket]?, backendRules: BackendRuleEvidence? = nil,
                profile: String? = nil, devices: Set<String>? = nil, menu: MenuShortcutEvidence? = nil) {
        self.observations = observations; self.backendRules = backendRules
        self.profile = profile; self.devices = devices
        self.menu = menu
    }
}

public struct CandidateConflictReport: Equatable, Sendable {
    public let check: CandidateConflictCheck
    public let findings: [ConflictFinding]
    public let limitations: Set<ConflictLimitation>
    public var readiness: CandidateReadiness { CandidateConstraints.assess(check.input, check: check) }
}

enum ChordOverlap {
    static func matches(_ lhs: Chord, _ rhs: Chord) -> Bool {
        guard lhs.keyCode == rhs.keyCode else { return false }
        let a = lhs.modifiers, b = rhs.modifiers
        let left: [ModifierSideState] = [a.command, a.option, a.control, a.shift]
        let right: [ModifierSideState] = [b.command, b.option, b.control, b.shift]
        let sidesMatch = zip(left, right).allSatisfy { pair in
            pair.0 == pair.1 || (pair.0 == .activeSideUnknown && pair.1 != .none)
                || (pair.1 == .activeSideUnknown && pair.0 != .none)
        }
        return sidesMatch && (a.fn == b.fn || a.fn == .unknown || b.fn == .unknown)
    }
}

import Foundation
import KeyRecordCore

public struct AnalysisInput: Sendable {
    public let cycleID: CycleID
    public let shortcuts: [DailyShortcutAggregate]
    public let bareKeys: [DailyBareKeyAggregate]
    /// Reducer encounter order, including days with only bare-key activity.
    public let activeDays: [LocalDay]
    public let layout: LayoutPreference
    public let ignoredRecommendationKeys: Set<String>
    public let keyboardPoolConfirmed: Set<KeyCode>
    public let backendCapabilities: BackendCapabilities?

    public init(cycleID: CycleID, shortcuts: [DailyShortcutAggregate], bareKeys: [DailyBareKeyAggregate],
                activeDays: [LocalDay], layout: LayoutPreference = LayoutPreference(),
                ignoredRecommendationKeys: Set<String> = [], keyboardPoolConfirmed: Set<KeyCode> = [],
                backendCapabilities: BackendCapabilities? = nil) {
        self.cycleID = cycleID; self.shortcuts = shortcuts; self.bareKeys = bareKeys
        self.activeDays = activeDays; self.layout = layout
        self.ignoredRecommendationKeys = ignoredRecommendationKeys
        self.keyboardPoolConfirmed = keyboardPoolConfirmed
        self.backendCapabilities = backendCapabilities
    }
}

public enum AnalysisError: Error, Equatable { case cycleMismatch, duplicateRow, invalidActiveDays, classificationMismatch, countOverflow }
public enum RecommendationScope: Equatable, Sendable { case global, application(String) }
public enum CandidateStatus: String, Sendable { case observation, eligible, statefulExcluded }

/// Sample eligibility, a simplification plan, and applicability stay separate.
/// Increment A never reports a physical score or a verified mapping.
public enum SimplificationPlan: Equatable, Sendable {
    case positivePreview
    case noShorterCombination
    case functionStateUnknown
    case statefulExcluded
}
public struct ApplicationStatistic: Equatable, Sendable {
    public let app: AppBucket
    public let sourceCounts: SourceCounts
}
public struct BareKeyStatistic: Equatable, Sendable {
    public let keyCode: KeyCode
    public let sourceCounts: SourceCounts
}
public struct ShortcutStatistic: Equatable, Sendable {
    public let chord: Chord
    public let sourceCounts: SourceCounts
    public let distinctDays: Int
}
public struct RecommendationFactors: Equatable, Sendable {
    public let weightedFrequency: Double
    public let sourceLogicalKeyCount: Int
    public let triggerLogicalKeyCount: Int?
    public let savedPerUse: Int
    public let sourceReliability: Double
    public let layoutCompleteness: Double
    public var confidence: Double { sourceReliability * layoutCompleteness }
    public var score: Double { weightedFrequency * Double(savedPerUse) * confidence }
}
/// A logical sketch only: no backend support, conflict safety or application is asserted.
public struct TriggerPreview: Equatable, Sendable {
    public let chord: Chord
    public let logicalKeysSaved: Int
}
public struct RecommendationCandidate: Equatable, Sendable, Identifiable {
    public let id: String
    public let chord: Chord
    public let sourceCounts: SourceCounts
    public var rawCount: Int64 { sourceCounts.total.value }
    public let distinctDays: Int
    public let status: CandidateStatus
    public let defaultScope: RecommendationScope
    public let topApplication: String?
    public let topApplicationShare: Double
    public let factors: RecommendationFactors
    public let triggers: [TriggerPreview]
    public let isIgnored: Bool

    public var simplificationPlan: SimplificationPlan {
        if status == .statefulExcluded { return .statefulExcluded }
        if chord.modifiers.fn == .unknown { return .functionStateUnknown }
        if triggers.contains(where: { $0.logicalKeysSaved > 0 }) { return .positivePreview }
        return .noShorterCombination
    }

    /// Home ranking only. Eligibility, raw counts, and candidate order are unchanged.
    public var qualifiesForTopRecommendations: Bool {
        status == .eligible && !isIgnored && simplificationPlan == .positivePreview
    }
}

public struct IgnoredRecommendationEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let chord: Chord?
    public let hasCurrentObservation: Bool
}

public enum IgnoredRecommendationList {
    public static func entries(persisted: Set<String>, candidates: [RecommendationCandidate]) -> [IgnoredRecommendationEntry] {
        let observed = Set(candidates.map(\.id))
        return persisted.sorted().map { id in
            IgnoredRecommendationEntry(id: id, chord: LogicalPreviews.chord(fromCanonicalID: id),
                                       hasCurrentObservation: observed.contains(id))
        }
    }
}

public struct AnalysisSnapshot: Equatable, Sendable {
    public let cycleID: CycleID
    public let activeDayCount: Int
    public let shortcutStatistics: [ShortcutStatistic]
    public let applications: [ApplicationStatistic]
    public let bareKeys: [BareKeyStatistic]
    public let candidates: [RecommendationCandidate]
    public let shouldAskLayout: Bool
    public var topRecommendations: [RecommendationCandidate] {
        Array(candidates.filter(\.qualifiesForTopRecommendations).prefix(5))
    }
    public static let ruleVersion = "phase2-logical-v1+backend-capabilities-v1"
}

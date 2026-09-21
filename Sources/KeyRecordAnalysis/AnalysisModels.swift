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

    public init(cycleID: CycleID, shortcuts: [DailyShortcutAggregate], bareKeys: [DailyBareKeyAggregate],
                activeDays: [LocalDay], layout: LayoutPreference = LayoutPreference(),
                ignoredRecommendationKeys: Set<String> = [], keyboardPoolConfirmed: Set<KeyCode> = []) {
        self.cycleID = cycleID; self.shortcuts = shortcuts; self.bareKeys = bareKeys
        self.activeDays = activeDays; self.layout = layout
        self.ignoredRecommendationKeys = ignoredRecommendationKeys
        self.keyboardPoolConfirmed = keyboardPoolConfirmed
    }
}

public enum AnalysisError: Error, Equatable { case cycleMismatch, duplicateRow, invalidActiveDays, classificationMismatch, countOverflow }
public enum RecommendationScope: Equatable, Sendable { case global, application(String) }
public enum CandidateStatus: String, Sendable { case observation, eligible, statefulExcluded }
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
}
public struct AnalysisSnapshot: Equatable, Sendable {
    public let shortcutStatistics: [ShortcutStatistic]
    public let applications: [ApplicationStatistic]
    public let bareKeys: [BareKeyStatistic]
    public let candidates: [RecommendationCandidate]
    public let shouldAskLayout: Bool
    public var topRecommendations: [RecommendationCandidate] {
        Array(candidates.filter { $0.status == .eligible && !$0.isIgnored }.prefix(5))
    }
    public static let ruleVersion = "phase2-logical-v1"
}

import Foundation
import KeyRecordCore

public enum AnalysisEngine {
    public static func analyze(_ input: AnalysisInput) throws -> AnalysisSnapshot {
        try validate(input)
        let ordinal = Dictionary(uniqueKeysWithValues: input.activeDays.enumerated().map { ($0.element, $0.offset) })
        let rows = input.shortcuts.sorted {
            if $0.day != $1.day { return (ordinal[$0.day] ?? -1) < (ordinal[$1.day] ?? -1) }
            let lhs = LogicalPreviews.canonicalID($0.identity.chord) + appID($0.identity.appBucket)
            let rhs = LogicalPreviews.canonicalID($1.identity.chord) + appID($1.identity.appBucket)
            return lhs < rhs
        }
        var groups: [Chord: [DailyShortcutAggregate]] = [:]
        var applications: [AppBucket: SourceCounts] = [:]
        for row in rows where row.sourceCounts.total.value > 0 {
            groups[row.identity.chord, default: []].append(row)
            applications[row.identity.appBucket] = try add(applications[row.identity.appBucket], row.sourceCounts)
        }
        var candidates: [RecommendationCandidate] = []
        for chord in groups.keys.sorted(by: { LogicalPreviews.canonicalID($0) < LogicalPreviews.canonicalID($1) }) {
            guard let group = groups[chord], let first = group.first else { continue }
            let counts = try group.reduce(nil as SourceCounts?) { try add($0, $1.sourceCounts) }
            guard let counts else { continue }
            var weighted = 0.0
            var perApp: [String: Double] = [:]
            for row in group {
                guard let index = ordinal[row.day] else { throw AnalysisError.invalidActiveDays }
                let weight = pow(2, -Double(input.activeDays.count - 1 - index) / 14)
                let frequency = Double(row.sourceCounts.total.value) * weight
                weighted += frequency
                if case .bundleID(let id) = row.identity.appBucket { perApp[id, default: 0] += frequency }
            }
            let top = perApp.filter { $0.value > 0 }.sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }.first
            let share = weighted > 0 ? (top?.value ?? 0) / weighted : 0
            let scope: RecommendationScope
            if first.classification.scope != .system, share >= 0.70, let top {
                scope = .application(top.key)
            } else {
                scope = .global
            }
            let days = Set(group.map(\.day)).count
            let status: CandidateStatus = first.classification.kind == .stateful ? .statefulExcluded
                : counts.total.value >= 20 && days >= 2 ? .eligible : .observation
            let triggers = status == .statefulExcluded ? [] : LogicalPreviews.generate(chord, confirmed: input.keyboardPoolConfirmed)
            let ratio = Double(counts.ordinary.value) / Double(counts.total.value)
            // Versioned conservative table: ordinary is not proof of authenticity.
            let reliability = ratio >= 0.95 ? 1.0 : ratio >= 0.5 ? 0.75 : 0.5
            // No physical evidence chain is accepted by this logical-only engine.
            let completeness = input.layout.preset == .none ? 0.5 : 0.75
            let factors = RecommendationFactors(weightedFrequency: weighted, sourceLogicalKeyCount: LogicalPreviews.keyCount(chord),
                triggerLogicalKeyCount: triggers.first.map { LogicalPreviews.keyCount($0.chord) },
                savedPerUse: triggers.first?.logicalKeysSaved ?? 0, sourceReliability: reliability, layoutCompleteness: completeness)
            let id = LogicalPreviews.canonicalID(chord)
            candidates.append(RecommendationCandidate(id: id, chord: chord, sourceCounts: counts, distinctDays: days,
                status: status, defaultScope: scope, topApplication: top?.key, topApplicationShare: share,
                factors: factors, triggers: triggers, isIgnored: input.ignoredRecommendationKeys.contains(id)))
        }
        candidates.sort { $0.factors.score == $1.factors.score ? $0.id < $1.id : $0.factors.score > $1.factors.score }
        let statistics = candidates.map { ShortcutStatistic(chord: $0.chord, sourceCounts: $0.sourceCounts, distinctDays: $0.distinctDays) }
            .sorted { $0.sourceCounts.total == $1.sourceCounts.total
                ? LogicalPreviews.canonicalID($0.chord) < LogicalPreviews.canonicalID($1.chord)
                : $0.sourceCounts.total.value > $1.sourceCounts.total.value }
        var bare: [KeyCode: SourceCounts] = [:]
        for row in input.bareKeys where row.sourceCounts.total.value > 0 { bare[row.keyCode] = try add(bare[row.keyCode], row.sourceCounts) }
        return AnalysisSnapshot(shortcutStatistics: statistics,
            applications: applications.map { ApplicationStatistic(app: $0.key, sourceCounts: $0.value) }.sorted {
                $0.sourceCounts.total == $1.sourceCounts.total ? appID($0.app) < appID($1.app)
                    : $0.sourceCounts.total.value > $1.sourceCounts.total.value
            }, bareKeys: bare.map { BareKeyStatistic(keyCode: $0.key, sourceCounts: $0.value) }.sorted {
                $0.sourceCounts.total == $1.sourceCounts.total ? $0.keyCode.value < $1.keyCode.value
                    : $0.sourceCounts.total.value > $1.sourceCounts.total.value
            }, candidates: candidates, shouldAskLayout: !input.layout.hasAsked && candidates.contains { $0.status == .eligible })
    }

    private static func appID(_ app: AppBucket) -> String {
        switch app { case .unknown: return "0"; case .bundleID(let id): return "1" + id }
    }

    private static func add(_ lhs: SourceCounts?, _ rhs: SourceCounts) throws -> SourceCounts {
        guard let lhs else { return rhs }
        let (ordinary, o) = lhs.ordinary.value.addingReportingOverflow(rhs.ordinary.value)
        let (suspected, s) = lhs.suspectedInjection.value.addingReportingOverflow(rhs.suspectedInjection.value)
        let (_, t) = lhs.total.value.addingReportingOverflow(rhs.total.value)
        guard !o && !s && !t else { throw AnalysisError.countOverflow }
        return try SourceCounts(ordinary: Count(ordinary), suspectedInjection: Count(suspected))
    }

    private struct RowKey: Hashable { let day: LocalDay; let bucket: ChordBucket }
    private struct BareRowKey: Hashable { let day: LocalDay; let key: KeyCode }
    private static func validate(_ input: AnalysisInput) throws {
        guard Set(input.activeDays).count == input.activeDays.count else { throw AnalysisError.invalidActiveDays }
        var days: Set<LocalDay> = []
        var seen: Set<RowKey> = []
        var bareSeen: Set<BareRowKey> = []
        var total: SourceCounts?
        for row in input.shortcuts {
            guard row.cycleID == input.cycleID else { throw AnalysisError.cycleMismatch }
            guard seen.insert(RowKey(day: row.day, bucket: row.identity)).inserted else { throw AnalysisError.duplicateRow }
            guard row.classification == ChordRuleTable.v1.classify(row.identity.chord) else { throw AnalysisError.classificationMismatch }
            total = try add(total, row.sourceCounts)
            if row.sourceCounts.total.value > 0 { days.insert(row.day) }
        }
        for row in input.bareKeys {
            guard row.cycleID == input.cycleID else { throw AnalysisError.cycleMismatch }
            guard bareSeen.insert(BareRowKey(day: row.day, key: row.keyCode)).inserted else { throw AnalysisError.duplicateRow }
            total = try add(total, row.sourceCounts)
            if row.sourceCounts.total.value > 0 { days.insert(row.day) }
        }
        guard days == Set(input.activeDays) else { throw AnalysisError.invalidActiveDays }
    }
}

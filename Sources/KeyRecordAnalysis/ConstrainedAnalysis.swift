import KeyRecordCore

public extension AnalysisSnapshot {
    func constrained(to capabilities: BackendCapabilities?, confirmed: Set<KeyCode>) -> AnalysisSnapshot {
        guard let capabilities else { return self }
        var updated: [RecommendationCandidate] = candidates.map { candidate -> RecommendationCandidate in
            let triggers: [TriggerPreview] = candidate.status == .statefulExcluded ? [] : LogicalPreviews.generate(candidate.chord, confirmed: confirmed, capabilities: capabilities)
            let original = candidate.factors
            let factors = RecommendationFactors(weightedFrequency: original.weightedFrequency,
                sourceLogicalKeyCount: original.sourceLogicalKeyCount,
                triggerLogicalKeyCount: triggers.first.map { LogicalPreviews.keyCount($0.chord) },
                savedPerUse: triggers.first?.logicalKeysSaved ?? 0, sourceReliability: original.sourceReliability,
                layoutCompleteness: original.layoutCompleteness)
            return RecommendationCandidate(id: candidate.id, chord: candidate.chord, sourceCounts: candidate.sourceCounts,
                distinctDays: candidate.distinctDays, status: candidate.status, defaultScope: candidate.defaultScope,
                topApplication: candidate.topApplication, topApplicationShare: candidate.topApplicationShare,
                factors: factors, triggers: triggers, isIgnored: candidate.isIgnored)
        }
        updated.sort { $0.factors.score == $1.factors.score ? $0.id < $1.id : $0.factors.score > $1.factors.score }
        return AnalysisSnapshot(cycleID: cycleID, activeDayCount: activeDayCount, shortcutStatistics: shortcutStatistics,
            applications: applications, bareKeys: bareKeys, candidates: updated, shouldAskLayout: shouldAskLayout)
    }
}

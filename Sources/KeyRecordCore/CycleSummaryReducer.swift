import Foundation

public enum CycleSummaryReducer: Sendable {
    public static func reduce(
        cycleID: CycleID, shortcuts: [DailyShortcutAggregate], bareKeys: [DailyBareKeyAggregate]
    ) throws -> CycleSummary {
        var chords: [ChordBucket: Count] = [:]
        var keys: [KeyCode: Count] = [:]
        var days: Set<LocalDay> = []
        var sources = try SourceCounts(ordinary: Count(0), suspectedInjection: Count(0))
        for row in shortcuts {
            guard row.cycleID == cycleID else { throw AggregationError.cycleMismatch }
            sources = try sources.adding(row.sourceCounts)
            chords[row.identity] = try (chords[row.identity] ?? Count(0)).adding(row.sourceCounts.total)
            if row.sourceCounts.total.value > 0 { days.insert(row.day) }
        }
        for row in bareKeys {
            guard row.cycleID == cycleID else { throw AggregationError.cycleMismatch }
            sources = try sources.adding(row.sourceCounts)
            keys[row.keyCode] = try (keys[row.keyCode] ?? Count(0)).adding(row.sourceCounts.total)
            if row.sourceCounts.total.value > 0 { days.insert(row.day) }
        }
        let chordTotal = try chords.values.reduce(Count(0)) { try $0.adding($1) }
        let retainedTotal = try keys.values.reduce(chordTotal) { try $0.adding($1) }
        guard retainedTotal == sources.total else { throw AggregationError.inconsistentTotal }
        return try CycleSummary(cycleID: cycleID, perChordTotals: chords, perBareKeyTotals: keys,
            distinctActiveDays: ActiveDayOrdinal(Int64(days.count)))
    }
}

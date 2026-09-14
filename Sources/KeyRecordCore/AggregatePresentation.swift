import Foundation

// MARK: - Task 18 aggregate presentation DTOs (pure Foundation, no SwiftUI)

/// Three-way presentation class. Pure mapping from task 8's stored
/// `ShortcutClassification` (`ShortcutKind` + `ScopeClass`, produced by
/// `ChordRuleTable.v1`): system scope wins; otherwise the kind maps one-to-one.
public enum ChordPresentationClass: String, Equatable, Sendable {
    case discrete, stateful, system

    public init(_ classification: ShortcutClassification) {
        switch classification.scope {
        case .system:
            self = .system
        case .normal:
            switch classification.kind {
            case .stateful: self = .stateful
            case .discrete: self = .discrete
            }
        }
    }
}

/// Side marker for a row's provenance. Derived from task 9's `SourceCounts`:
/// any suspected-injection count marks the whole row; a positive total is ordinary;
/// a zero-total row (no retained observations) carries the unknown side marker.
/// Ordinary observation is never proof of authenticity (architecture §4.4).
public enum SourceConfidence: String, Equatable, Sendable {
    case ordinary, suspectedInjection, unknown

    public init(_ counts: SourceCounts) {
        if counts.suspectedInjection.value > 0 {
            self = .suspectedInjection
        } else if counts.total.value > 0 {
            self = .ordinary
        } else {
            self = .unknown
        }
    }
}

/// Row identity. Task 8's `ChordBucket` already composes `Chord` (keyCode + modifiers)
/// with `AppBucket` (a concrete bundle id or `.unknown`), so it is reused directly as
/// the shortcut identity instead of introducing a new ChordID name. Bare keys are a
/// separate case with no associated application value — the no-attribution rule is
/// enforced by the type, matching `CycleSummary.perBareKeyTotals` keyed by KeyCode alone.
public enum AggregateRowIdentity: Equatable, Sendable {
    case shortcut(ChordBucket)
    case bareKey(KeyCode)
}

/// One cycle-total line on the task 18 aggregate screen.
public struct AggregateRow: Equatable, Sendable {
    public let identity: AggregateRowIdentity
    public let total: Int64
    public let classification: ChordPresentationClass
    public let sourceConfidence: SourceConfidence

    public init(identity: AggregateRowIdentity, total: Int64,
                classification: ChordPresentationClass, sourceConfidence: SourceConfidence) {
        self.identity = identity
        self.total = total
        self.classification = classification
        self.sourceConfidence = sourceConfidence
    }
}

/// Cycle-wide view DTO. Unlike the task 9 daily records, no day field exists on a row:
/// records for the same (chord, app bucket) / bare key are summed across active days,
/// matching the retained-totals shape of `CycleSummary` (architecture §5.1).
public struct AggregateSnapshot: Equatable, Sendable {
    public let rows: [AggregateRow]
    public var shortcutTotal: Int64
    public var bareKeyTotal: Int64

    public init(rows: [AggregateRow]) throws {
        self.rows = rows
        var shortcuts = try Count(0)
        var bareKeys = try Count(0)
        for row in rows {
            switch row.identity {
            case .shortcut: shortcuts = try shortcuts.adding(Count(row.total))
            case .bareKey: bareKeys = try bareKeys.adding(Count(row.total))
            }
        }
        shortcutTotal = shortcuts.value
        bareKeyTotal = bareKeys.value
    }

    /// Build from the task 9 reducer's daily records. Checked count arithmetic precedes
    /// the presentation mapping, so an overflowing sum throws the same `CountError` as
    /// `CycleSummaryReducer`; ordering follows `AggregateOrdering` (shortcuts via
    /// `ChordBucket.ordered`, then bare keys ascending by keyCode).
    public init(shortcuts dailyShortcuts: [DailyShortcutAggregate],
                bareKeys dailyBareKeys: [DailyBareKeyAggregate]) throws {
        struct ShortcutGroup {
            let classification: ShortcutClassification
            var counts: SourceCounts
        }
        let zero = try SourceCounts(ordinary: Count(0), suspectedInjection: Count(0))
        var groups: [ChordBucket: ShortcutGroup] = [:]
        for row in dailyShortcuts {
            if let existing = groups[row.identity] {
                groups[row.identity] = ShortcutGroup(
                    classification: existing.classification,
                    counts: try existing.counts.adding(row.sourceCounts))
            } else {
                // Classification is a pure function of the chord (ChordRuleTable.v1),
                // so every daily row for one bucket carries the identical value.
                groups[row.identity] = ShortcutGroup(classification: row.classification, counts: row.sourceCounts)
            }
        }
        var keyCounts: [KeyCode: SourceCounts] = [:]
        for row in dailyBareKeys {
            keyCounts[row.keyCode] = try (keyCounts[row.keyCode] ?? zero).adding(row.sourceCounts)
        }
        var rows: [AggregateRow] = []
        rows.reserveCapacity(groups.count + keyCounts.count)
        for (bucket, group) in groups.sorted(by: { ChordBucket.ordered($0.key, $1.key) }) {
            rows.append(AggregateRow(identity: .shortcut(bucket), total: group.counts.total.value,
                                     classification: ChordPresentationClass(group.classification),
                                     sourceConfidence: SourceConfidence(group.counts)))
        }
        // An unattributed bare keypress is never stateful/system; the identity case is
        // what tells the screen to render it without a chord or app attribution.
        for (keyCode, counts) in keyCounts.sorted(by: { $0.key.value < $1.key.value }) {
            rows.append(AggregateRow(identity: .bareKey(keyCode), total: counts.total.value,
                                     classification: .discrete, sourceConfidence: SourceConfidence(counts)))
        }
        try self.init(rows: rows)
    }
}

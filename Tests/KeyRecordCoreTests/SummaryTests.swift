import Foundation
import XCTest
import KeyRecordCore

final class SummaryTests: XCTestCase {
    private let cycle = CycleID(rawValue: "cycle")

    func testSummaryRetainsExactApprovedJSONFields() throws {
        // Given: daily app-attributed shortcuts and unattributed bare keys.
        let reducer = try sequence()
        // When: compacting the cycle.
        let summary = try CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: reducer.shortcuts, bareKeys: reducer.bareKeys)
        let data = try canonical(summary)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Then: only contract-9 fields remain, including recursively nested fields.
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "cycleID", "perChordTotals", "perBareKeyTotals", "distinctActiveDays"])
        let chordEntries = try XCTUnwrap(object["perChordTotals"] as? [Any])
        let identity = try XCTUnwrap(chordEntries.first as? [String: Any])
        XCTAssertEqual(Set(identity.keys), ["chord", "appBucket"])
        let chord = try XCTUnwrap(identity["chord"] as? [String: Any])
        XCTAssertEqual(Set(chord.keys), ["keyCode", "modifiers"])
        let modifiers = try XCTUnwrap(chord["modifiers"] as? [String: Any])
        XCTAssertEqual(Set(modifiers.keys), ["command", "option", "control", "shift", "fn"])
        let keys = allKeys(object)
        XCTAssertTrue(keys.isDisjoint(with: ["day", "sourceCounts", "ordinary", "suspectedInjection", "classification", "kind", "scope", "scopeClass"]))
        XCTAssertEqual(try JSONDecoder().decode(CycleSummary.self, from: data), summary)
        XCTAssertEqual(summary.distinctActiveDays.value.value, 1)
    }

    func testSourceConservationBeforeResetAndNineteenTwentyCounts() throws {
        // Given: 19 ordinary and one suspected press of a stateful Cmd-Tab chord.
        var reducer = try sequence()
        // When: reducing without recommendation/scoring logic.
        let summary = try CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: reducer.shortcuts, bareKeys: reducer.bareKeys)
        let sourceTotal = reducer.shortcuts.reduce(Int64(0)) { $0 + $1.sourceCounts.ordinary.value + $1.sourceCounts.suspectedInjection.value }
            + reducer.bareKeys.reduce(Int64(0)) { $0 + $1.sourceCounts.ordinary.value + $1.sourceCounts.suspectedInjection.value }
        let retainedTotal = summary.perChordTotals.values.reduce(Int64(0)) { $0 + $1.value }
            + summary.perBareKeyTotals.values.reduce(Int64(0)) { $0 + $1.value }
        // Then: 19/20 is source accounting only; all counted classifications survive as totals.
        XCTAssertEqual(reducer.shortcuts.first?.sourceCounts.ordinary.value, 19)
        XCTAssertEqual(reducer.shortcuts.first?.sourceCounts.total.value, 20)
        XCTAssertEqual(reducer.shortcuts.first?.classification.kind, .stateful)
        XCTAssertEqual(sourceTotal, retainedTotal)
        XCTAssertEqual(retainedTotal, 21)
        reducer.reset(cycleID: CycleID(rawValue: "next"))
        XCTAssertEqual(summary.perChordTotals.values.first?.value, 20)
    }

    func testUnknownForegroundProducesNoAttributedShard() throws {
        // Given: detector uncertainty closes the existing normalization gate.
        var normalizer = ChordNormalizer()
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
            secureInput: .disabled, foreground: .unknown, exclusion: .included))
        var reducer = AggregationReducer(cycleID: cycle)
        reducer.update(normalizer.gate)
        let event = try NormalizationFixtures.event(generation: normalizer.gate.generation)
        // When: the pipeline receives an event with unknown foreground.
        try reducer.process(normalizer.process(event), generation: event.generation,
            clock: AggregationClock("2026-01-01T12:00:00Z"))
        // Then: neither attributed nor bare records nor active days are emitted.
        XCTAssertTrue(reducer.shortcuts.isEmpty)
        XCTAssertTrue(reducer.bareKeys.isEmpty)
        XCTAssertEqual(try reducer.distinctActiveDays.value.value, 0)
    }

    func testSummaryOverflowAcrossDistinctBucketsFails() throws {
        // Given: individually valid rows whose cycle-wide sum overflows.
        let rows = try [Int64.max, 1].enumerated().map { index, count in
            DailyBareKeyAggregate(cycleID: cycle, day: LocalDay("2026-01-01"), keyCode: try KeyCode(index),
                sourceCounts: try SourceCounts(ordinary: Count(count), suspectedInjection: Count(0)))
        }
        // When / Then: reducing must fail even though each bucket fits.
        XCTAssertThrowsError(try CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: [], bareKeys: rows)) {
            XCTAssertEqual($0 as? CountError, .overflow)
        }
    }

    func testSummaryOverflowWithinBucketFails() throws {
        // Given: the same key over two days exceeds a count.
        let rows = try [Int64.max, 1].enumerated().map { index, count in
            DailyBareKeyAggregate(cycleID: cycle, day: LocalDay("2026-01-0\(index + 1)"), keyCode: try KeyCode(0),
                sourceCounts: try SourceCounts(ordinary: Count(count), suspectedInjection: Count(0)))
        }
        // When / Then: checked reduction cannot wrap.
        XCTAssertThrowsError(try CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: [], bareKeys: rows)) {
            XCTAssertEqual($0 as? CountError, .overflow)
        }
    }

    func testReplayAndPermutedRowsAreByteIdentical() throws {
        // Given: independent replays plus a different dictionary insertion order.
        let first = try sequence()
        let second = try sequence()
        // When: encoding the daily outputs and retained totals deterministically.
        XCTAssertEqual(try canonical(first.shortcuts), try canonical(second.shortcuts))
        XCTAssertEqual(try canonical(first.bareKeys), try canonical(second.bareKeys))
        let keys = try [0, 1, 2, 3].map { try KeyCode($0) }
        let pairs = try keys.map { ($0, try Count(Int64($0.value + 1))) }
        let left = try CycleSummary(cycleID: cycle, perChordTotals: [:],
            perBareKeyTotals: Dictionary(uniqueKeysWithValues: pairs), distinctActiveDays: ActiveDayOrdinal(1))
        let right = try CycleSummary(cycleID: cycle, perChordTotals: [:],
            perBareKeyTotals: Dictionary(uniqueKeysWithValues: pairs.reversed()), distinctActiveDays: ActiveDayOrdinal(1))
        // Then: encoded dictionary arrays are canonical too, not just sorted JSON object keys.
        XCTAssertEqual(try canonical(left), try canonical(right))
        let chordPairs = try keys.map { key in
            (ChordBucket(chord: Chord(keyCode: key, modifiers: NormalizationFixtures.empty),
                appBucket: .bundleID("app.\(key.value)")), try Count(1))
        }
        let chordLeft = try CycleSummary(cycleID: cycle, perChordTotals: Dictionary(uniqueKeysWithValues: chordPairs),
            perBareKeyTotals: [:], distinctActiveDays: ActiveDayOrdinal(1))
        let chordRight = try CycleSummary(cycleID: cycle, perChordTotals: Dictionary(uniqueKeysWithValues: chordPairs.reversed()),
            perBareKeyTotals: [:], distinctActiveDays: ActiveDayOrdinal(1))
        XCTAssertEqual(try canonical(chordLeft), try canonical(chordRight))
        XCTAssertEqual(try canonical(CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: first.shortcuts, bareKeys: first.bareKeys)),
            try canonical(CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: second.shortcuts.reversed(), bareKeys: second.bareKeys.reversed())))
    }

    func testSummaryRejectsForeignCycleAndIgnoresZeroRowsForActiveDays() throws {
        let zero = try SourceCounts(ordinary: Count(0), suspectedInjection: Count(0))
        let emptyRow = DailyBareKeyAggregate(cycleID: cycle, day: LocalDay("2026-01-01"),
            keyCode: try KeyCode(0), sourceCounts: zero)
        let summary = try CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: [], bareKeys: [emptyRow])
        XCTAssertEqual(summary.distinctActiveDays.value.value, 0)
        XCTAssertThrowsError(try CycleSummaryReducer.reduce(cycleID: CycleID(rawValue: "other"), shortcuts: [], bareKeys: [emptyRow])) {
            XCTAssertEqual($0 as? AggregationError, .cycleMismatch)
        }
    }

    func testSummaryUnionsDaysAcrossShardTypesAndMergesChordTotals() throws {
        let counts = try SourceCounts(ordinary: Count(1), suspectedInjection: Count(1))
        let identity = ChordBucket(chord: Chord(keyCode: try KeyCode(48), modifiers: NormalizationFixtures.empty), appBucket: .unknown)
        let shortcuts = ["2026-01-02", "2026-01-01"].map {
            DailyShortcutAggregate(cycleID: cycle, day: LocalDay($0), identity: identity,
                classification: ShortcutClassification(kind: .stateful, scope: .normal), sourceCounts: counts)
        }
        let bare = DailyBareKeyAggregate(cycleID: cycle, day: LocalDay("2026-01-01"), keyCode: try KeyCode(0), sourceCounts: counts)
        let summary = try CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: shortcuts, bareKeys: [bare])
        XCTAssertEqual(summary.distinctActiveDays.value.value, 2)
        XCTAssertEqual(summary.perChordTotals[identity]?.value, 4)
        XCTAssertEqual(summary.perBareKeyTotals[try KeyCode(0)]?.value, 2)
    }

    func testNineteenThenTwentyPressesCountWithoutRecommendationThresholds() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        var reducer = AggregationReducer(cycleID: cycle)
        reducer.update(normalizer.gate)
        let modifiers = ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none)
        for index in 0..<21 {
            let clock = try AggregationClock(index == 20 ? "2026-01-02T00:00:00Z" : "2026-01-01T00:00:00Z")
            for kind in [KeyEventKind.keyDown, .keyUp] {
                let event = ObservedKeyEvent(keyCode: try KeyCode(8), kind: kind, isAutoRepeat: false,
                    modifiers: modifiers, source: index == 19 ? .productMarked : .ordinaryObserved,
                    generation: normalizer.gate.generation)
                try reducer.process(normalizer.process(event), generation: event.generation, clock: clock)
            }
            if index >= 18 {
                let summary = try CycleSummaryReducer.reduce(cycleID: cycle, shortcuts: reducer.shortcuts, bareKeys: reducer.bareKeys)
                XCTAssertEqual(summary.perChordTotals.values.first?.value, index == 20 ? 20 : 19)
                XCTAssertEqual(summary.distinctActiveDays.value.value, index == 20 ? 2 : 1)
            }
        }
    }

    private func sequence() throws -> AggregationReducer {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        var reducer = AggregationReducer(cycleID: cycle)
        reducer.update(normalizer.gate)
        let clock = try AggregationClock("2026-01-01T12:00:00Z")
        let modifiers = ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none)
        for index in 0..<20 {
            for kind in [KeyEventKind.keyDown, .keyUp] {
                let event = ObservedKeyEvent(keyCode: try KeyCode(48), kind: kind, isAutoRepeat: false,
                    modifiers: modifiers, source: index == 19 ? .suspectedInjection : .ordinaryObserved,
                    generation: normalizer.gate.generation)
                try reducer.process(normalizer.process(event), generation: event.generation, clock: clock)
            }
        }
        let bare = try NormalizationFixtures.event(generation: normalizer.gate.generation)
        try reducer.process(normalizer.process(bare), generation: bare.generation, clock: clock)
        return reducer
    }

    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func allKeys(_ object: Any) -> Set<String> {
        if let dictionary = object as? [String: Any] {
            return dictionary.values.reduce(Set(dictionary.keys)) { $0.union(allKeys($1)) }
        }
        if let array = object as? [Any] { return array.reduce([]) { $0.union(allKeys($1)) } }
        return []
    }
}

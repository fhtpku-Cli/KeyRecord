import Foundation
import XCTest
@testable import KeyRecordCore

struct AggregationClock: LocalClock {
    let instant: Date
    let timeZone: TimeZone
    var calendar: Calendar { Calendar(identifier: .gregorian) }
    func now() -> Date { instant }

    init(_ instant: String, zone: String = "UTC") throws {
        self.instant = try XCTUnwrap(ISO8601DateFormatter().date(from: instant))
        timeZone = try XCTUnwrap(TimeZone(identifier: zone))
    }
}

final class AggregationTests: XCTestCase {
    func testThreeSecondHeldRepeatAndMultiKeySequence() throws {
        // Given: a fixed three-second stream, including duplicate unflagged downs.
        var reducer = AggregationReducer(cycleID: CycleID(rawValue: "cycle"))
        var gate = PrivacyGate()
        gate.update(NormalizationFixtures.open)
        reducer.update(gate)
        let key = try KeyCode(0)
        let other = try KeyCode(1)
        let sequence: [(Int, NormalizationOutput)] = [
            (0, .keyDown(.bare(key), .ordinaryObserved)),
            (200, .keyDown(.bare(key), .ordinaryObserved)),
            (400, .repeatedKeyDown(key)),
            (600, .keyDown(.bare(other), .suspectedInjection)),
            (1000, .keyUp(key)), (1500, .keyDown(.bare(key), .suspectedInjection)),
            (2000, .keyUp(other)), (2500, .keyUp(key)), (3000, .repeatedKeyDown(key))
        ]
        let start = try AggregationClock("2026-01-01T12:00:00Z")
        // When: replaying events with an injected timestamp, never sleeping.
        for (milliseconds, output) in sequence {
            let clock = FixedAggregationClock(instant: start.instant.addingTimeInterval(Double(milliseconds) / 1000),
                timeZone: start.timeZone)
            try reducer.process(output, generation: gate.generation, clock: clock)
        }
        // Then: two physical presses of key 0, one of key 1, split by source.
        XCTAssertEqual(reducer.bareKeys.map(\.sourceCounts.total.value), [2, 1])
        XCTAssertEqual(reducer.bareKeys.map(\.sourceCounts.ordinary.value), [1, 0])
        XCTAssertEqual(try reducer.distinctActiveDays.value.value, 1)
    }

    func testMissingKeyUpClearsOnClosureGenerationAndReset() throws {
        // Given: a held key with no keyUp.
        var reducer = AggregationReducer(cycleID: CycleID(rawValue: "old"))
        var gate = PrivacyGate()
        gate.update(NormalizationFixtures.open)
        reducer.update(gate)
        let old = gate.generation
        let down = NormalizationOutput.keyDown(.bare(try KeyCode(0)), .ordinaryObserved)
        let clock = try AggregationClock("2026-01-01T00:00:00Z")
        try reducer.process(down, generation: old, clock: clock)
        // When: closing, reopening, rejecting a stale up, and resetting the cycle.
        gate.update(GateInputs())
        reducer.update(gate)
        try reducer.process(down, generation: old, clock: clock)
        gate.update(NormalizationFixtures.open)
        reducer.update(gate)
        try reducer.process(down, generation: gate.generation, clock: clock)
        try reducer.process(.keyUp(try KeyCode(0)), generation: old, clock: clock)
        try reducer.process(down, generation: gate.generation, clock: clock)
        // Then: closure released the first hold; stale up did not release the second.
        XCTAssertEqual(reducer.bareKeys.first?.sourceCounts.total.value, 2)
        reducer.reset(cycleID: CycleID(rawValue: "new"))
        XCTAssertTrue(reducer.bareKeys.isEmpty)
        XCTAssertEqual(try reducer.distinctActiveDays.value.value, 0)
        try reducer.process(down, generation: gate.generation, clock: clock)
        XCTAssertTrue(reducer.bareKeys.isEmpty)
        reducer.update(gate)
        try reducer.process(down, generation: gate.generation, clock: clock)
        XCTAssertEqual(reducer.bareKeys.first?.cycleID, CycleID(rawValue: "new"))
        XCTAssertEqual(reducer.bareKeys.first?.sourceCounts.total.value, 1)
    }

    func testActiveDayEncounterOrderAcrossTimezoneRollbackAndRevisit() throws {
        // Given: local Jan 2, then timezone rollback to Jan 1, then Jan 2 revisited.
        let clocks = try [AggregationClock("2026-01-02T01:00:00Z"),
            AggregationClock("2026-01-02T01:00:01Z", zone: "America/Los_Angeles"),
            AggregationClock("2026-01-02T01:00:02Z"), AggregationClock("2026-01-03T01:00:00Z")]
        // When: each distinct press is attributed using its injected clock.
        let reducer = try replay(clocks)
        // Then: ordinal follows first encounter, not lexicographic calendar order.
        XCTAssertEqual(reducer.activeDays.map(\.label), ["2026-01-02", "2026-01-01", "2026-01-03"])
        XCTAssertEqual(try reducer.distinctActiveDays.value.value, 3)
        XCTAssertEqual(reducer.bareKeys.map(\.day.label), ["2026-01-01", "2026-01-02", "2026-01-03"])
        XCTAssertEqual(reducer.bareKeys.map(\.sourceCounts.total.value), [1, 2, 1])
    }

    func testUTCAndLocalMidnightAttribution() throws {
        // Given: UTC midnight does not coincide with Los Angeles midnight.
        let clocks = try [AggregationClock("2026-01-02T00:00:00Z", zone: "America/Los_Angeles"),
            AggregationClock("2026-01-02T07:59:59Z", zone: "America/Los_Angeles"),
            AggregationClock("2026-01-02T08:00:00Z", zone: "America/Los_Angeles")]
        // When: reducing the local-midnight boundary.
        let reducer = try replay(clocks)
        // Then: UTC midnight remains in Jan 1; local midnight starts Jan 2.
        XCTAssertEqual(reducer.bareKeys.map(\.day.label), ["2026-01-01", "2026-01-02"])
        XCTAssertEqual(reducer.bareKeys.map(\.sourceCounts.total.value), [2, 1])
    }

    func testDSTRepeatedAndSkippedHourDoNotAddDays() throws {
        // Given: spring-forward and fall-back boundaries in New York.
        let clocks = try ["2026-03-08T06:59:59Z", "2026-03-08T07:00:00Z",
            "2026-11-01T05:59:59Z", "2026-11-01T06:00:00Z"].map {
                try AggregationClock($0, zone: "America/New_York")
            }
        // When: reducing the four presses.
        let reducer = try replay(clocks)
        // Then: hour discontinuities do not become new active days.
        XCTAssertEqual(try reducer.distinctActiveDays.value.value, 2)
        XCTAssertEqual(reducer.bareKeys.map(\.sourceCounts.total.value), [2, 2])
    }

    func testCountAdditionOverflowFailsClosed() throws {
        // Given: the largest valid count.
        let maximum = try Count(Int64.max)
        // When / Then: adding another event must report a typed error, never wrap.
        XCTAssertThrowsError(try maximum.adding(Count(1))) { error in
            XCTAssertEqual(error as? CountError, .overflow)
        }
        let sources = try SourceCounts(ordinary: maximum, suspectedInjection: Count(0))
        XCTAssertThrowsError(try sources.adding(SourceCounts(ordinary: Count(0), suspectedInjection: Count(1)))) {
            XCTAssertEqual($0 as? CountError, .overflow)
        }
    }

    func testOpenGenerationReplacementClearsHeldKeys() throws {
        var reducer = AggregationReducer(cycleID: CycleID(rawValue: "cycle"))
        var first = PrivacyGate()
        first.update(NormalizationFixtures.open)
        reducer.update(first)
        let clock = try AggregationClock("2026-01-01T00:00:00Z")
        let down = NormalizationOutput.keyDown(.bare(try KeyCode(0)), .ordinaryObserved)
        try reducer.process(down, generation: first.generation, clock: clock)
        var replacement = PrivacyGate(generation: CaptureGeneration(rawValue: 100))
        replacement.update(NormalizationFixtures.open)
        reducer.update(replacement)
        try reducer.process(down, generation: first.generation, clock: clock)
        try reducer.process(down, generation: replacement.generation, clock: clock)
        XCTAssertEqual(reducer.bareKeys.first?.sourceCounts.total.value, 2)
    }

    func testInvalidClockLeavesStateUnchangedAndSamePressCanRetry() throws {
        var reducer = AggregationReducer(cycleID: CycleID(rawValue: "cycle"))
        var gate = PrivacyGate()
        gate.update(NormalizationFixtures.open)
        reducer.update(gate)
        let valid = try AggregationClock("2026-01-01T00:00:00Z")
        let invalid = FixedAggregationClock(instant: Date(timeIntervalSinceReferenceDate: .infinity), timeZone: valid.timeZone)
        let down = NormalizationOutput.keyDown(.bare(try KeyCode(0)), .ordinaryObserved)
        XCTAssertThrowsError(try reducer.process(down, generation: gate.generation, clock: invalid)) {
            XCTAssertEqual($0 as? AggregationError, .invalidLocalDate)
        }
        XCTAssertTrue(reducer.activeDays.isEmpty)
        XCTAssertTrue(reducer.bareKeys.isEmpty)
        try reducer.process(down, generation: gate.generation, clock: valid)
        XCTAssertEqual(reducer.bareKeys.first?.sourceCounts.total.value, 1)
    }

    func testAppBucketsSystemClassificationAndBareKeysStaySeparate() throws {
        var reducer = AggregationReducer(cycleID: CycleID(rawValue: "cycle"))
        var normalizer = ChordNormalizer()
        let clock = try AggregationClock("2026-01-01T00:00:00Z")
        let modifiers = ModifierSet(command: .left, option: .none, control: .none, shift: .left, fn: .none)
        for foreground in [ForegroundState.attributable(bundleID: "z.app"), .attributable(bundleID: "a.app"), .reliablyUnattributable] {
            normalizer.update(GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
                secureInput: .disabled, foreground: foreground, exclusion: .included))
            reducer.update(normalizer.gate)
            for kind in [KeyEventKind.keyDown, .keyUp] {
                let event = ObservedKeyEvent(keyCode: try KeyCode(20), kind: kind, isAutoRepeat: false,
                    modifiers: modifiers, source: .ordinaryObserved, generation: normalizer.gate.generation)
                try reducer.process(normalizer.process(event), generation: event.generation, clock: clock)
                let bare = ObservedKeyEvent(keyCode: try KeyCode(0), kind: kind, isAutoRepeat: false,
                    modifiers: NormalizationFixtures.empty, source: .ordinaryObserved, generation: normalizer.gate.generation)
                try reducer.process(normalizer.process(bare), generation: bare.generation, clock: clock)
            }
        }
        XCTAssertEqual(reducer.shortcuts.map(\.identity.appBucket), [.unknown, .bundleID("a.app"), .bundleID("z.app")])
        XCTAssertEqual(reducer.shortcuts.map(\.classification.scope), [.system, .system, .system])
        XCTAssertEqual(reducer.bareKeys.count, 1)
        XCTAssertEqual(reducer.bareKeys.first?.sourceCounts.total.value, 3)
    }

    func testInjectedCalendarIsUsedInsteadOfGlobalCalendar() throws {
        let base = try AggregationClock("2026-01-01T00:00:00Z")
        let clock = FixedAggregationClock(instant: base.instant, timeZone: base.timeZone,
            calendar: Calendar(identifier: .buddhist))
        var reducer = AggregationReducer(cycleID: CycleID(rawValue: "cycle"))
        var gate = PrivacyGate()
        gate.update(NormalizationFixtures.open)
        reducer.update(gate)
        try reducer.process(.keyDown(.bare(try KeyCode(0)), .ordinaryObserved), generation: gate.generation, clock: clock)
        XCTAssertEqual(reducer.bareKeys.first?.day.label, "2569-01-01")
    }

    private func replay(_ clocks: [AggregationClock]) throws -> AggregationReducer {
        var reducer = AggregationReducer(cycleID: CycleID(rawValue: "cycle"))
        var gate = PrivacyGate()
        gate.update(NormalizationFixtures.open)
        reducer.update(gate)
        let key = try KeyCode(0)
        for clock in clocks {
            try reducer.process(.keyDown(.bare(key), .ordinaryObserved), generation: gate.generation, clock: clock)
            try reducer.process(.keyUp(key), generation: gate.generation, clock: clock)
        }
        return reducer
    }
}

private struct FixedAggregationClock: LocalClock {
    let instant: Date
    let timeZone: TimeZone
    var calendar: Calendar = Calendar(identifier: .gregorian)
    func now() -> Date { instant }
}

import XCTest
import KeyRecordCore
@testable import KeyRecordAnalysis

final class AnalysisTests: XCTestCase {
    let cycle = CycleID(rawValue: "synthetic")
    let d1 = LocalDay("2026-09-01")
    let d2 = LocalDay("2026-09-02")

    func row(_ count: Int64, day: LocalDay, app: AppBucket = .unknown,
             code: Int = 8, side: ModifierSideState = .left, fn: FnState = .none,
             suspected: Int64 = 0) throws -> DailyShortcutAggregate {
        let chord = Chord(keyCode: try KeyCode(code), modifiers: ModifierSet(command: side,
            option: .none, control: .none, shift: .left, fn: fn))
        return try DailyShortcutAggregate(cycleID: cycle, day: day,
            identity: ChordBucket(chord: chord, appBucket: app), classification: ChordRuleTable.v1.classify(chord),
            sourceCounts: SourceCounts(ordinary: Count(count), suspectedInjection: Count(suspected)))
    }
    func analyze(_ rows: [DailyShortcutAggregate], days: [LocalDay]? = nil,
                 bare: [DailyBareKeyAggregate] = [], layout: LayoutPreference = LayoutPreference()) throws -> AnalysisSnapshot {
        try AnalysisEngine.analyze(AnalysisInput(cycleID: cycle, shortcuts: rows, bareKeys: bare,
            activeDays: days ?? [d1, d2], layout: layout))
    }

    func testRawThresholdAndDistinctDays() throws {
        XCTAssertEqual(try analyze([row(10, day: d1), row(9, day: d2)]).candidates[0].status, .observation)
        XCTAssertEqual(try analyze([row(20, day: d1)], days: [d1]).candidates[0].status, .observation)
        let eligible = try analyze([row(10, day: d1), row(10, day: d2)])
        XCTAssertEqual(eligible.candidates[0].status, .eligible)
        XCTAssertTrue(eligible.shouldAskLayout)
        XCTAssertFalse(try analyze([row(10, day: d1), row(10, day: d2)], layout: LayoutPreference(hasAsked: true)).shouldAskLayout)
    }

    func testFourteenActiveDaysHalvesOldCountsIncludingBareOnlyDays() throws {
        let days = (1...15).map { LocalDay(String(format: "2026-09-%02d", $0)) }
        let bare = try days.dropFirst().map {
            try DailyBareKeyAggregate(cycleID: cycle, day: $0, keyCode: KeyCode(0),
                sourceCounts: SourceCounts(ordinary: Count(1), suspectedInjection: Count(0)))
        }
        let result = try analyze([row(20, day: days[0])], days: days, bare: bare)
        XCTAssertEqual(result.candidates[0].factors.weightedFrequency, 10, accuracy: 0.000001)
        XCTAssertEqual(result.candidates[0].status, .observation)
        XCTAssertEqual(result.applications.count, 1)
        XCTAssertEqual(result.applications[0].sourceCounts.total.value, 20)
    }

    func testSeventyPercentBoundaryUnknownDenominatorAndTies() throws {
        let boundary = try analyze([row(70, day: d1, app: .bundleID("app.a")), row(30, day: d1)], days: [d1]).candidates[0]
        XCTAssertEqual(boundary.defaultScope, .application("app.a"))
        let below = try analyze([row(69, day: d1, app: .bundleID("app.a")), row(31, day: d1)], days: [d1]).candidates[0]
        XCTAssertEqual(below.defaultScope, .global)
        let tie = try analyze([row(50, day: d1, app: .bundleID("z")), row(50, day: d1, app: .bundleID("a"))], days: [d1]).candidates[0]
        XCTAssertEqual(tie.topApplication, "a")
        XCTAssertEqual(tie.defaultScope, .global)
        XCTAssertNil(try analyze([row(10, day: d1)], days: [d1]).candidates[0].topApplication)
    }

    func testPermutationStabilityAndSidePreservation() throws {
        let rows = try [row(10, day: d1), row(10, day: d2), row(8, day: d2, side: .right), row(9, day: d1, app: .bundleID("x"))]
        let expected = try analyze(rows)
        XCTAssertEqual(expected.shortcutStatistics.count, 2)
        for offset in rows.indices {
            let permutation = Array(rows[offset...]) + Array(rows[..<offset])
            XCTAssertEqual(try analyze(permutation), expected)
            XCTAssertEqual(try analyze(permutation.reversed()), expected)
        }
    }

    func testStatefulAndUnknownFnNeverGenerateTriggers() throws {
        XCTAssertEqual(try analyze([row(20, day: d1, code: 48), row(20, day: d2, code: 48)]).candidates[0].status, .statefulExcluded)
        XCTAssertTrue(try analyze([row(20, day: d1, fn: .unknown)], days: [d1]).candidates[0].triggers.isEmpty)
    }

    func testTriggerCapSafetyAndScoreFactors() throws {
        let rows = try [row(20, day: d1), row(20, day: d2)]
        let result = try AnalysisEngine.analyze(AnalysisInput(cycleID: cycle, shortcuts: rows, bareKeys: [], activeDays: [d1,d2],
            keyboardPoolConfirmed: Set([try KeyCode(0), try KeyCode(122), try KeyCode(120), try KeyCode(99)])))
        let candidate = result.candidates[0]
        XCTAssertEqual(candidate.triggers.count, 3)
        XCTAssertFalse(candidate.triggers.contains { $0.chord.keyCode.value == 0 })
        XCTAssertEqual(candidate.factors.savedPerUse, 2)
        XCTAssertEqual(candidate.factors.score, candidate.factors.weightedFrequency * 2 * 0.5)
    }

    func testValidationRejectsDuplicateCycleAndOrdinalErrorsAndOverflow() throws {
        let first = try row(1, day: d1)
        XCTAssertThrowsError(try analyze([first, first], days: [d1]))
        XCTAssertThrowsError(try analyze([first], days: [d1,d1]))
        XCTAssertThrowsError(try analyze([first], days: [d2]))
        XCTAssertThrowsError(try AnalysisEngine.analyze(AnalysisInput(cycleID: CycleID(rawValue: "other"), shortcuts: [first], bareKeys: [], activeDays: [d1])))
        XCTAssertThrowsError(try analyze([row(Int64.max, day: d1), row(1, day: d2)]))
    }

    func testEncounterOrderRatherThanCalendarOrderAndDecayDoesNotDisqualify() throws {
        let days = (1...30).map { LocalDay("synthetic-\($0)") }
        let bare = try days.dropFirst(2).map {
            try DailyBareKeyAggregate(cycleID: cycle, day: $0, keyCode: KeyCode(0),
                sourceCounts: SourceCounts(ordinary: Count(1), suspectedInjection: Count(0)))
        }
        let snapshot = try analyze([row(10, day: days[0]), row(10, day: days[1])], days: days, bare: bare)
        XCTAssertEqual(snapshot.candidates[0].status, .eligible)
        XCTAssertLessThan(snapshot.candidates[0].factors.weightedFrequency, 6)
    }

    func testSystemScopeIgnoresApplicationMajority() throws {
        let result = try analyze([row(20, day: d1, app: .bundleID("app"), code: 20)], days: [d1])
        XCTAssertEqual(result.candidates[0].topApplication, "app")
        XCTAssertEqual(result.candidates[0].defaultScope, .global)
    }

    func testTopFiveAndIgnoredCandidatesRemainInspectable() throws {
        let rows = try (0...6).flatMap { code in
            try [row(10, day: d1, code: code), row(10, day: d2, code: code)]
        }
        let initial = try analyze(rows)
        let ignored = initial.candidates[0].id
        let result = try AnalysisEngine.analyze(AnalysisInput(cycleID: cycle, shortcuts: rows,
            bareKeys: [], activeDays: [d1,d2], ignoredRecommendationKeys: [ignored]))
        XCTAssertEqual(result.topRecommendations.count, 5)
        XCTAssertEqual(result.candidates.count, 7)
        XCTAssertFalse(result.topRecommendations.contains { $0.id == ignored })
        XCTAssertTrue(result.candidates.contains { $0.id == ignored && $0.isIgnored })
    }

    func testSourceCountsAndConfidenceArePreserved() throws {
        let result = try analyze([row(5, day: d1, suspected: 15)], days: [d1])
        XCTAssertEqual(result.candidates[0].rawCount, 20)
        XCTAssertEqual(result.candidates[0].sourceCounts.suspectedInjection.value, 15)
        XCTAssertEqual(result.candidates[0].factors.sourceReliability, 0.5)
        XCTAssertEqual(result.candidates[0].factors.confidence, 0.25)
    }

    func testScopeUsesWeightedCountsAndExplicitBackwardCalendarOrder() throws {
        let rows = try [row(70, day: d2, app: .bundleID("known")), row(30, day: d1)]
        let result = try analyze(rows, days: [d2, d1]).candidates[0]
        XCTAssertLessThan(result.topApplicationShare, 0.70)
        XCTAssertEqual(result.defaultScope, .global)
    }
}

import XCTest
import KeyRecordCore

// MARK: - In-file builders

private let cycle = CycleID(rawValue: "t18-slice2")
private let day1 = LocalDay("2026-09-12")
private let day2 = LocalDay("2026-09-13")

private func counts(_ ordinary: Int64, _ suspected: Int64 = 0) throws -> SourceCounts {
    try SourceCounts(ordinary: Count(ordinary), suspectedInjection: Count(suspected))
}

private func modifiers(command: Bool = false, shift: Bool = false,
                       option: Bool = false, control: Bool = false) -> ModifierSet {
    ModifierSet(command: command ? .both : .none, option: option ? .both : .none,
                control: control ? .both : .none, shift: shift ? .both : .none, fn: .none)
}

private func bucket(_ keyCode: Int, _ modifiers: ModifierSet, _ app: AppBucket) throws -> ChordBucket {
    ChordBucket(chord: Chord(keyCode: try KeyCode(keyCode), modifiers: modifiers), appBucket: app)
}

private func shortcut(_ day: LocalDay, _ bucket: ChordBucket, _ counts: SourceCounts) throws -> DailyShortcutAggregate {
    try DailyShortcutAggregate(cycleID: cycle, day: day, identity: bucket,
                               classification: ChordRuleTable.v1.classify(bucket.chord),
                               sourceCounts: counts)
}

private func bare(_ day: LocalDay, _ keyCode: Int, _ counts: SourceCounts) throws -> DailyBareKeyAggregate {
    try DailyBareKeyAggregate(cycleID: cycle, day: day, keyCode: KeyCode(keyCode), sourceCounts: counts)
}

private func keyCode(of identity: AggregateRowIdentity) -> Int {
    switch identity {
    case .shortcut(let bucket): bucket.chord.keyCode.value
    case .bareKey(let key): key.value
    }
}

// MARK: - Tests

final class AggregatePresentationTests: XCTestCase {
    func testSameChordAndBucketSumsAcrossDays() throws {
        // Given: the same Cmd-S in the same app on two active days; When: presented;
        // Then: one cycle row with summed total and the suspected-injection marker.
        let b = try bucket(1, modifiers(command: true), .bundleID("com.ex"))
        let snapshot = try AggregateSnapshot(
            shortcuts: [try shortcut(day1, b, counts(3)), try shortcut(day2, b, counts(2, 1))],
            bareKeys: [])
        XCTAssertEqual(snapshot.rows.count, 1)
        let row = try XCTUnwrap(snapshot.rows.first)
        XCTAssertEqual(row.identity, .shortcut(b))
        XCTAssertEqual(row.total, 6)
        XCTAssertEqual(row.sourceConfidence, .suspectedInjection)
        XCTAssertEqual(snapshot.shortcutTotal, 6)
        XCTAssertEqual(snapshot.bareKeyTotal, 0)
    }

    func testSameBareKeySumsAcrossDays() throws {
        // Given: unattributed presses of one bare key on two days; When: presented;
        // Then: one bare row with summed total and no app attribution possible.
        let snapshot = try AggregateSnapshot(
            shortcuts: [],
            bareKeys: [try bare(day1, 99, counts(4)), try bare(day2, 99, counts(5))])
        XCTAssertEqual(snapshot.rows.count, 1)
        let row = try XCTUnwrap(snapshot.rows.first)
        XCTAssertEqual(row.identity, .bareKey(try KeyCode(99)))
        XCTAssertEqual(row.total, 9)
        XCTAssertEqual(row.sourceConfidence, .ordinary)
        XCTAssertEqual(snapshot.bareKeyTotal, 9)
    }

    func testDailyRecordsCollapseToCycleRows() throws {
        // Given: two days of one shortcut bucket and one bare key (4 daily records);
        // When: presented; Then: exactly two cycle rows — no day breakdown survives.
        let b = try bucket(1, modifiers(command: true), .unknown)
        let snapshot = try AggregateSnapshot(
            shortcuts: [try shortcut(day1, b, counts(1)), try shortcut(day2, b, counts(1))],
            bareKeys: [try bare(day1, 5, counts(1)), try bare(day2, 5, counts(1))])
        XCTAssertEqual(snapshot.rows.map(\.identity), [.shortcut(b), .bareKey(try KeyCode(5))])
    }

    func testRowsFollowAggregationOrdering() throws {
        // Given: shortcut/bare rows inserted out of order; When: presented;
        // Then: shortcuts are ordered by ChordBucket.ordered (keyCode, modifiers,
        // unknown bucket before concrete bundle) and bare keys ascend by keyCode.
        let k1Unknown = try bucket(1, modifiers(command: true), .unknown)
        let k1Bundle = try bucket(1, modifiers(command: true), .bundleID("com.b"))
        let k48 = try bucket(48, modifiers(command: true), .unknown)
        let snapshot = try AggregateSnapshot(
            shortcuts: [try shortcut(day1, k48, counts(1)), try shortcut(day1, k1Bundle, counts(1)),
                        try shortcut(day1, k1Unknown, counts(1))],
            bareKeys: [try bare(day1, 50, counts(1)), try bare(day1, 2, counts(1))])
        XCTAssertEqual(snapshot.rows.map(\.identity),
                       [.shortcut(k1Unknown), .shortcut(k1Bundle), .shortcut(k48),
                        .bareKey(try KeyCode(2)), .bareKey(try KeyCode(50))])
    }

    func testClassificationMapsStatefulSystemAndDiscrete() throws {
        // Given: the G0-classifier families from ChordRuleTable plus an ordinary chord;
        // When: presented; Then: Cmd-Tab is stateful, Shift-Cmd-3 is system, Cmd-C discrete.
        let cmdTab = try bucket(48, modifiers(command: true), .unknown)
        let screenshot = try bucket(20, modifiers(command: true, shift: true), .unknown)
        let cmdC = try bucket(8, modifiers(command: true), .unknown)
        let snapshot = try AggregateSnapshot(
            shortcuts: [try shortcut(day1, cmdTab, counts(1)), try shortcut(day1, screenshot, counts(1)),
                        try shortcut(day1, cmdC, counts(1))],
            bareKeys: [])
        func row(_ code: Int) throws -> AggregateRow {
            try XCTUnwrap(snapshot.rows.first { keyCode(of: $0.identity) == code })
        }
        XCTAssertEqual(try row(48).classification, .stateful)
        XCTAssertEqual(try row(20).classification, .system)
        XCTAssertEqual(try row(8).classification, .discrete)
    }

    func testSourceConfidenceMarkers() throws {
        // Given: rows with ordinary-only, suspected-only, and zero counts; When: presented;
        // Then: each gets its side marker, with a zero-total row marked unknown.
        let ordinary = try bucket(10, modifiers(command: true), .unknown)
        let suspected = try bucket(11, modifiers(command: true), .unknown)
        let empty = try bucket(12, modifiers(command: true), .unknown)
        let snapshot = try AggregateSnapshot(
            shortcuts: [try shortcut(day1, ordinary, counts(5)),
                        try shortcut(day1, suspected, counts(0, 2)),
                        try shortcut(day1, empty, counts(0))],
            bareKeys: [])
        func confidence(_ code: Int) throws -> SourceConfidence {
            try XCTUnwrap(snapshot.rows.first { keyCode(of: $0.identity) == code }).sourceConfidence
        }
        XCTAssertEqual(try confidence(10), .ordinary)
        XCTAssertEqual(try confidence(11), .suspectedInjection)
        XCTAssertEqual(try confidence(12), .unknown)
    }

    func testBareKeyRowCannotCarryAppBucketAndShortcutKeepsItsBucket() throws {
        // Given: one attributed shortcut and one bare key; When: identities are switched on;
        // Then: the bare case has NO associated application value by construction
        // (compile-time proof: `.bareKey(KeyCode)` carries no AppBucket), while the
        // shortcut row retains its concrete bundle.
        let b = try bucket(1, modifiers(command: true), .bundleID("com.ex"))
        let snapshot = try AggregateSnapshot(
            shortcuts: [try shortcut(day1, b, counts(3))],
            bareKeys: [try bare(day1, 4, counts(7))])
        for row in snapshot.rows {
            switch row.identity {
            case .shortcut(let bucket):
                XCTAssertEqual(bucket.appBucket, .bundleID("com.ex"))
            case .bareKey(let keyCode):
                XCTAssertEqual(keyCode, try KeyCode(4))
                // No appBucket exists on this case: unattributed totals can never leak a bundle.
            }
        }
    }

    func testSnapshotTotalsAreSumsOfRows() throws {
        // Given: hand-built shortcut and bare rows; When: AggregateSnapshot(rows:);
        // Then: the two totals are the per-kind sums regardless of input ordering.
        func shortcutRow(_ code: Int, _ total: Int64) throws -> AggregateRow {
            AggregateRow(identity: .shortcut(try bucket(code, modifiers(command: true), .unknown)),
                         total: total, classification: .discrete, sourceConfidence: .ordinary)
        }
        let rows: [AggregateRow] = [
            try shortcutRow(3, 4),
            AggregateRow(identity: .bareKey(try KeyCode(2)), total: 7,
                         classification: .discrete, sourceConfidence: .ordinary),
            try shortcutRow(1, 3),
            AggregateRow(identity: .bareKey(try KeyCode(1)), total: 2,
                         classification: .discrete, sourceConfidence: .ordinary),
        ]
        let snapshot = AggregateSnapshot(rows: rows)
        XCTAssertEqual(snapshot.shortcutTotal, 7)
        XCTAssertEqual(snapshot.bareKeyTotal, 9)
    }
}

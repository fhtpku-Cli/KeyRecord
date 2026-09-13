import Foundation

public enum AggregationError: Error, Equatable, Sendable {
    case invalidLocalDate
    case cycleMismatch
    case inconsistentTotal
}

/// Feed control updates before normalized events, including closures that produce no event output.
public struct AggregationReducer: Sendable {
    private struct HeldKey: Hashable, Sendable {
        let generation: CaptureGeneration
        let keyCode: KeyCode
    }

    private struct ShortcutDay: Hashable, Sendable {
        let day: LocalDay
        let identity: ChordBucket
    }

    private struct BareDay: Hashable, Sendable {
        let day: LocalDay
        let keyCode: KeyCode
    }

    public private(set) var cycleID: CycleID
    public private(set) var activeDays: [LocalDay] = []
    private var encounteredDays: Set<LocalDay> = []
    private var shortcutRows: [ShortcutDay: DailyShortcutAggregate] = [:]
    private var bareRows: [BareDay: DailyBareKeyAggregate] = [:]
    private var held: Set<HeldKey> = []
    private var generation: CaptureGeneration?
    private var cycleTotal: Int64 = 0

    public init(cycleID: CycleID) { self.cycleID = cycleID }

    public init(cycleID: CycleID, shortcuts: [DailyShortcutAggregate],
                bareKeys: [DailyBareKeyAggregate]) throws {
        self.init(cycleID: cycleID)
        for row in shortcuts {
            guard row.cycleID == cycleID else { throw AggregationError.cycleMismatch }
            let key = ShortcutDay(day: row.day, identity: row.identity)
            guard shortcutRows[key] == nil else { throw AggregationError.inconsistentTotal }
            cycleTotal = try Count(cycleTotal).adding(row.sourceCounts.total).value
            shortcutRows[key] = row
            encounteredDays.insert(row.day)
        }
        for row in bareKeys {
            guard row.cycleID == cycleID else { throw AggregationError.cycleMismatch }
            let key = BareDay(day: row.day, keyCode: row.keyCode)
            guard bareRows[key] == nil else { throw AggregationError.inconsistentTotal }
            cycleTotal = try Count(cycleTotal).adding(row.sourceCounts.total).value
            bareRows[key] = row
            encounteredDays.insert(row.day)
        }
        activeDays = encounteredDays.sorted { $0.label < $1.label }
    }

    public var distinctActiveDays: ActiveDayOrdinal {
        get throws { try ActiveDayOrdinal(Int64(activeDays.count)) }
    }

    public var shortcuts: [DailyShortcutAggregate] {
        shortcutRows.values.sorted {
            if $0.day != $1.day { return $0.day.label < $1.day.label }
            return ChordBucket.ordered($0.identity, $1.identity)
        }
    }

    public var bareKeys: [DailyBareKeyAggregate] {
        bareRows.values.sorted {
            if $0.day != $1.day { return $0.day.label < $1.day.label }
            return $0.keyCode.value < $1.keyCode.value
        }
    }

    public mutating func update(_ gate: PrivacyGate) {
        if !gate.isOpen || generation != gate.generation { held.removeAll() }
        generation = gate.isOpen ? gate.generation : nil
    }

    /// In-memory reset only. Caller must reduce/retain the old cycle before invoking this boundary.
    public mutating func reset(cycleID: CycleID) {
        self = Self(cycleID: cycleID)
    }

    public mutating func process(
        _ output: NormalizationOutput, generation candidate: CaptureGeneration, clock: any LocalClock
    ) throws {
        guard generation == candidate else { return }
        let key: NormalizedKey
        switch output {
        case .none: return
        case .keyUp(let code):
            held.remove(HeldKey(generation: candidate, keyCode: code))
            return
        case .repeatedKeyDown(let code):
            held.insert(HeldKey(generation: candidate, keyCode: code))
            return
        case .keyDown(let normalized, _): key = normalized
        }
        let code: KeyCode
        switch key {
        case .bare(let bare): code = bare
        case .chord(let bucket, _): code = bucket.chord.keyCode
        }
        let heldKey = HeldKey(generation: candidate, keyCode: code)
        guard !held.contains(heldKey) else { return }
        let day = try Self.localDay(clock)
        let delta = try output.sourceDelta
        let total = try Count(cycleTotal).adding(delta.total)
        // All throwing arithmetic precedes mutation, so rejected input leaves counts and holds intact.
        switch key {
        case .bare(let code):
            let identity = BareDay(day: day, keyCode: code)
            let counts = try bareRows[identity]?.sourceCounts.adding(delta) ?? delta
            bareRows[identity] = DailyBareKeyAggregate(cycleID: cycleID, day: day, keyCode: code, sourceCounts: counts)
        case .chord(let bucket, let classification):
            let identity = ShortcutDay(day: day, identity: bucket)
            let counts = try shortcutRows[identity]?.sourceCounts.adding(delta) ?? delta
            shortcutRows[identity] = DailyShortcutAggregate(cycleID: cycleID, day: day, identity: bucket,
                classification: classification, sourceCounts: counts)
        }
        cycleTotal = total.value
        held.insert(heldKey)
        if encounteredDays.insert(day).inserted { activeDays.append(day) }
    }

    private static func localDay(_ clock: any LocalClock) throws -> LocalDay {
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone
        let instant = clock.now()
        guard instant.timeIntervalSinceReferenceDate.isFinite else { throw AggregationError.invalidLocalDate }
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = components.year, let month = components.month, let day = components.day,
            (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day)
        else { throw AggregationError.invalidLocalDate }
        func padded(_ value: Int, width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return LocalDay("\(padded(year, width: 4))-\(padded(month, width: 2))-\(padded(day, width: 2))")
    }
}

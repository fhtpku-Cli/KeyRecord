import Foundation
import KeyRecordCore

public enum DomainFixtures {
    public static let cycleID = CycleID(rawValue: "fixture-cycle")

    public static func sources() throws -> SourceCounts {
        try SourceCounts(ordinary: Count(3), suspectedInjection: Count(2))
    }

    public static func summary() throws -> CycleSummary {
        let key = try KeyCode(0)
        let chord = Chord(keyCode: key, modifiers: ModifierSet())
        return CycleSummary(
            cycleID: cycleID,
            perChordTotals: [ChordBucket(chord: chord, appBucket: .unknown): try Count(5)],
            perBareKeyTotals: [key: try Count(7)],
            distinctActiveDays: try ActiveDayOrdinal(2)
        )
    }
}

public struct FixedClock: LocalClock {
    public let instant: Date
    public let calendar: Calendar
    public let timeZone: TimeZone

    public init(instant: Date, calendar: Calendar, timeZone: TimeZone) {
        self.instant = instant
        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func now() -> Date { instant }
}

public struct FixedIDGenerator: CycleIDGenerator {
    public let value: CycleID
    public init(value: CycleID) { self.value = value }
    public func nextCycleID() async -> CycleID { value }
}

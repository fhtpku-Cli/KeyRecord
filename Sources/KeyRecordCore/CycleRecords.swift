import Foundation

public struct CycleRecord: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = SchemaVersion.v1
    public let schemaVersion: SchemaVersion
    public let cycleID: CycleID
    public let index: Count
    public let createdDay: LocalDay
    public let closedDay: LocalDay?
    public let isCurrent: Bool

    public init(cycleID: CycleID, index: Count, createdDay: LocalDay, closedDay: LocalDay?, isCurrent: Bool) {
        schemaVersion = Self.currentSchemaVersion
        self.cycleID = cycleID
        self.index = index
        self.createdDay = createdDay
        self.closedDay = closedDay
        self.isCurrent = isCurrent
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, cycleID, index, createdDay, closedDay, isCurrent }

    public init(from decoder: any Decoder) throws {
        let values = try strictContainer(decoder, keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(SchemaVersion.self, forKey: .schemaVersion)
        cycleID = try values.decode(CycleID.self, forKey: .cycleID)
        index = try values.decode(Count.self, forKey: .index)
        createdDay = try values.decode(LocalDay.self, forKey: .createdDay)
        closedDay = try values.decodeIfPresent(LocalDay.self, forKey: .closedDay)
        isCurrent = try values.decode(Bool.self, forKey: .isCurrent)
    }
}

/// Architecture §5.1 and plan contract 9: retained totals only; no daily/source/kind/scope details.
/// Dictionary identity prevents duplicate totals; bare keys cannot carry an application bucket.
public struct CycleSummary: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = SchemaVersion.v1
    public let schemaVersion: SchemaVersion
    public let cycleID: CycleID
    public let perChordTotals: [ChordBucket: Count]
    public let perBareKeyTotals: [KeyCode: Count]
    public let distinctActiveDays: ActiveDayOrdinal

    public init(cycleID: CycleID, perChordTotals: [ChordBucket: Count], perBareKeyTotals: [KeyCode: Count], distinctActiveDays: ActiveDayOrdinal) {
        schemaVersion = Self.currentSchemaVersion
        self.cycleID = cycleID
        self.perChordTotals = perChordTotals
        self.perBareKeyTotals = perBareKeyTotals
        self.distinctActiveDays = distinctActiveDays
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, cycleID, perChordTotals, perBareKeyTotals, distinctActiveDays }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(cycleID, forKey: .cycleID)
        try values.encode(distinctActiveDays, forKey: .distinctActiveDays)
        // Preserve Swift's non-string-key dictionary wire format, but order its alternating entries.
        var chords = values.nestedUnkeyedContainer(forKey: .perChordTotals)
        for (identity, count) in perChordTotals.sorted(by: { ChordBucket.ordered($0.key, $1.key) }) {
            try chords.encode(identity)
            try chords.encode(count)
        }
        var keys = values.nestedUnkeyedContainer(forKey: .perBareKeyTotals)
        for (key, count) in perBareKeyTotals.sorted(by: { $0.key.value < $1.key.value }) {
            try keys.encode(key)
            try keys.encode(count)
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try strictContainer(decoder, keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(SchemaVersion.self, forKey: .schemaVersion)
        cycleID = try values.decode(CycleID.self, forKey: .cycleID)
        perChordTotals = try values.decode([ChordBucket: Count].self, forKey: .perChordTotals)
        perBareKeyTotals = try values.decode([KeyCode: Count].self, forKey: .perBareKeyTotals)
        distinctActiveDays = try values.decode(ActiveDayOrdinal.self, forKey: .distinctActiveDays)
    }
}

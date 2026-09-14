import Foundation

public enum ShortcutKind: String, Codable, Sendable { case discrete, stateful }
public enum ScopeClass: String, Codable, Sendable { case normal, system }

public struct ShortcutClassification: Equatable, Codable, Sendable {
    public let kind: ShortcutKind
    public let scope: ScopeClass
    public init(kind: ShortcutKind, scope: ScopeClass) { self.kind = kind; self.scope = scope }
}

public struct DailyShortcutAggregate: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = SchemaVersion.v1
    public let schemaVersion: SchemaVersion
    public let cycleID: CycleID
    public let day: LocalDay
    public let identity: ChordBucket
    public let classification: ShortcutClassification
    public let sourceCounts: SourceCounts

    public init(cycleID: CycleID, day: LocalDay, identity: ChordBucket, classification: ShortcutClassification, sourceCounts: SourceCounts) {
        schemaVersion = Self.currentSchemaVersion
        self.cycleID = cycleID
        self.day = day
        self.identity = identity
        self.classification = classification
        self.sourceCounts = sourceCounts
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, cycleID, day, identity, classification, sourceCounts }

    public init(from decoder: any Decoder) throws {
        let values = try strictContainer(decoder, keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(SchemaVersion.self, forKey: .schemaVersion)
        cycleID = try values.decode(CycleID.self, forKey: .cycleID)
        day = try values.decode(LocalDay.self, forKey: .day)
        identity = try values.decode(ChordBucket.self, forKey: .identity)
        classification = try values.decode(ShortcutClassification.self, forKey: .classification)
        sourceCounts = try values.decode(SourceCounts.self, forKey: .sourceCounts)
    }
}

/// Architecture §5.1 / FR-P3: separate concrete record, no attributed superclass or metadata dictionary.
public struct DailyBareKeyAggregate: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = SchemaVersion.v1
    public let schemaVersion: SchemaVersion
    public let cycleID: CycleID
    public let day: LocalDay
    public let keyCode: KeyCode
    public let sourceCounts: SourceCounts

    public init(cycleID: CycleID, day: LocalDay, keyCode: KeyCode, sourceCounts: SourceCounts) {
        schemaVersion = Self.currentSchemaVersion
        self.cycleID = cycleID
        self.day = day
        self.keyCode = keyCode
        self.sourceCounts = sourceCounts
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, cycleID, day, keyCode, sourceCounts }

    public init(from decoder: any Decoder) throws {
        let values = try strictContainer(decoder, keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(SchemaVersion.self, forKey: .schemaVersion)
        cycleID = try values.decode(CycleID.self, forKey: .cycleID)
        day = try values.decode(LocalDay.self, forKey: .day)
        keyCode = try values.decode(KeyCode.self, forKey: .keyCode)
        sourceCounts = try values.decode(SourceCounts.self, forKey: .sourceCounts)
    }
}

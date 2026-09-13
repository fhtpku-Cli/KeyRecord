import Foundation
import KeyRecordCore

enum ResetJournalPhase: String, Codable, Sendable {
    case prepared
    case summaryWritten
    case detailsRemoved
    case cycleCommitted

    var rank: Int {
        switch self {
        case .prepared: 0
        case .summaryWritten: 1
        case .detailsRemoved: 2
        case .cycleCommitted: 3
        }
    }
}

/// Logical (plaintext) retention proof: payload SHA-256 survives key rotation even though
/// the on-disk envelope bytes change, so post-rotation recovery can still verify retention.
struct RetainedObjectHash: Codable, Equatable, Sendable {
    let identity: String
    let sha256: String
}

/// Encrypted reset-journal content. The journal is the sole post-crash authority for the
/// approved summary once daily details are gone, so decoding is strict like every record.
struct ResetJournalPayload: Codable, Equatable, Sendable {
    let schemaVersion: UInt32
    let operationID: UUID
    let oldCycleID: CycleID
    let newCycleID: CycleID
    let newCycleIndex: Int64
    let expectedCollecting: Bool
    let summary: CycleSummary
    let retainedHashes: [RetainedObjectHash]
    let phase: ResetJournalPhase

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, operationID, oldCycleID, newCycleID, newCycleIndex
        case expectedCollecting, summary, retainedHashes, phase
    }

    init(
        schemaVersion: UInt32 = 1,
        operationID: UUID,
        oldCycleID: CycleID,
        newCycleID: CycleID,
        newCycleIndex: Int64,
        expectedCollecting: Bool,
        summary: CycleSummary,
        retainedHashes: [RetainedObjectHash],
        phase: ResetJournalPhase
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.oldCycleID = oldCycleID
        self.newCycleID = newCycleID
        self.newCycleIndex = newCycleIndex
        self.expectedCollecting = expectedCollecting
        self.summary = summary
        self.retainedHashes = retainedHashes
        self.phase = phase
    }

    init(from decoder: any Decoder) throws {
        let all = try decoder.container(keyedBy: AnyFieldKey.self)
        guard Set(all.allKeys.map(\.stringValue)).isSubset(of: CodingKeys.allCases.map(\.rawValue)) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "unexpected journal fields"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(UInt32.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw SchemaError.unsupportedVersion(Int(schemaVersion)) }
        operationID = try values.decode(UUID.self, forKey: .operationID)
        oldCycleID = try values.decode(CycleID.self, forKey: .oldCycleID)
        newCycleID = try values.decode(CycleID.self, forKey: .newCycleID)
        newCycleIndex = try values.decode(Int64.self, forKey: .newCycleIndex)
        guard newCycleIndex > 0 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "newCycleIndex must be positive"))
        }
        expectedCollecting = try values.decode(Bool.self, forKey: .expectedCollecting)
        summary = try values.decode(CycleSummary.self, forKey: .summary)
        retainedHashes = try values.decode([RetainedObjectHash].self, forKey: .retainedHashes)
        phase = try values.decode(ResetJournalPhase.self, forKey: .phase)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(operationID, forKey: .operationID)
        try values.encode(oldCycleID, forKey: .oldCycleID)
        try values.encode(newCycleID, forKey: .newCycleID)
        try values.encode(newCycleIndex, forKey: .newCycleIndex)
        try values.encode(expectedCollecting, forKey: .expectedCollecting)
        try values.encode(summary, forKey: .summary)
        try values.encode(retainedHashes.sorted { $0.identity < $1.identity }, forKey: .retainedHashes)
        try values.encode(phase, forKey: .phase)
    }

    func advancing(to next: ResetJournalPhase) -> ResetJournalPayload {
        ResetJournalPayload(
            operationID: operationID, oldCycleID: oldCycleID, newCycleID: newCycleID,
            newCycleIndex: newCycleIndex, expectedCollecting: expectedCollecting,
            summary: summary, retainedHashes: retainedHashes, phase: next)
    }
}

private struct AnyFieldKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

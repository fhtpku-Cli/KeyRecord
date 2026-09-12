import Foundation
import KeyRecordCore

public struct KeyringMetadata: Equatable, Sendable {
    public let current: KeyVersion
    public let versions: Set<KeyVersion>
    public let retirementPending: Set<KeyVersion>
    public let rotation: KeyRotation?

    init(current: KeyVersion, versions: Set<KeyVersion>, retirementPending: Set<KeyVersion> = [], rotation: KeyRotation? = nil) {
        self.current = current; self.versions = versions
        self.retirementPending = retirementPending; self.rotation = rotation
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw KeyringError.corruptMetadata }
        do {
            let wire = try JSONDecoder().decode(Wire.self, from: data)
            let versions = Set(wire.versions.map { KeyVersion(rawValue: $0) })
            let pending = Set(wire.retirementPending.map { KeyVersion(rawValue: $0) })
            let current = KeyVersion(rawValue: wire.current)
            guard wire.schema == 1, current.rawValue > 0, versions.contains(current),
                  versions.count == wire.versions.count, pending.count == wire.retirementPending.count,
                  !versions.contains(KeyVersion(rawValue: 0)), !pending.contains(current), pending.isSubset(of: versions)
            else { throw KeyringError.corruptMetadata }
            let rotation: KeyRotation?
            switch (wire.rotationFrom, wire.rotationTo) {
            case (nil, nil):
                guard versions == [current], pending.isEmpty else { throw KeyringError.corruptMetadata }
                rotation = nil
            case (.some(let from), .some(let to)):
                let old = KeyVersion(rawValue: from)
                guard from > 0, from < to, to == current.rawValue, versions == [old, current], pending.isSubset(of: [old])
                else { throw KeyringError.corruptMetadata }
                rotation = KeyRotation(from: old, to: current)
            default: throw KeyringError.corruptMetadata
            }
            let metadata = Self(current: current, versions: versions, retirementPending: pending, rotation: rotation)
            // Canonical v1 bytes reject duplicate fields and ambiguous numeric/JSON representations.
            guard try metadata.encoded() == data else { throw KeyringError.corruptMetadata }
            return metadata
        } catch { throw KeyringError.corruptMetadata }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Wire(schema: 1, current: current.rawValue,
            versions: versions.map(\.rawValue).sorted(), retirementPending: retirementPending.map(\.rawValue).sorted(),
            rotationFrom: rotation?.from.rawValue, rotationTo: rotation?.to.rawValue))
    }

    private struct Wire: Codable {
        let schema: UInt32
        let current: UInt32
        let versions: [UInt32]
        let retirementPending: [UInt32]
        let rotationFrom: UInt32?
        let rotationTo: UInt32?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schema, current, versions, retirementPending, rotationFrom, rotationTo
        }
        struct AnyKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(schema: UInt32, current: UInt32, versions: [UInt32], retirementPending: [UInt32],
             rotationFrom: UInt32?, rotationTo: UInt32?) {
            self.schema = schema; self.current = current; self.versions = versions
            self.retirementPending = retirementPending; self.rotationFrom = rotationFrom; self.rotationTo = rotationTo
        }

        init(from decoder: any Decoder) throws {
            let all = try decoder.container(keyedBy: AnyKey.self)
            guard Set(all.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue)))
            else { throw KeyringError.corruptMetadata }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decode(UInt32.self, forKey: .schema)
            current = try c.decode(UInt32.self, forKey: .current)
            versions = try c.decode([UInt32].self, forKey: .versions)
            retirementPending = try c.decode([UInt32].self, forKey: .retirementPending)
            rotationFrom = try c.decodeIfPresent(UInt32.self, forKey: .rotationFrom)
            rotationTo = try c.decodeIfPresent(UInt32.self, forKey: .rotationTo)
        }
    }
}

public struct KeyringRecoveryState: Sendable {
    public let metadata: KeyringMetadata
    public let pendingCandidates: Set<KeyVersion>
}

import Foundation
import KeyRecordCore
import KeyRecordStore

public struct KarabinerTargetReference: Codable, Equatable, Sendable {
    public let namespace: UUID
    public let bookmark: Data
    public let location: String
    public let profile: String
    public init(namespace: UUID = UUID(), bookmark: Data, location: String, profile: String) {
        self.namespace = namespace; self.bookmark = bookmark; self.location = location; self.profile = profile
    }
}

public actor EncryptedKarabinerTargetStore {
    private let store: ObjectStore
    private let identity: CanonicalLogicalIdentity
    public init(store: ObjectStore) throws {
        self.store = store
        identity = try CanonicalLogicalIdentity(objectType: "com.keyrecord.mapping-target", schemaVersion: 1, logicalIDText: "karabiner")
    }
    public func load() async throws -> KarabinerTargetReference? {
        guard try await store.entries().contains(where: { $0.identity == identity }) else { return nil }
        return try JSONDecoder().decode(KarabinerTargetReference.self, from: await store.read(identity))
    }
    public func save(_ reference: KarabinerTargetReference) async throws {
        _ = try await store.put(identity: identity, payload: JSONEncoder().encode(reference))
    }
}

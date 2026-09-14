import Foundation

public enum ManifestError: Error, Equatable, Sendable {
    case malformed
    case unknownSchemaVersion(UInt32)
    case tooLarge
    case duplicateEntry
    case invalidEntry
}

/// Fixed discovery filename inside the private store root. It is itself an authenticated
/// envelope under `CanonicalLogicalIdentity.manifest`; there is no directory index.
public enum ManifestDiscovery {
    public static let fileName = "manifest.krenc"
    public static let maximumPayloadBytes = 4 * 1_024 * 1_024
    static let schemaVersion: UInt32 = 1
}

public struct ManifestEntry: Equatable, Sendable {
    public let identity: CanonicalLogicalIdentity
    public let locator: ObjectLocator
    public let keyVersion: UInt32

    public init(identity: CanonicalLogicalIdentity, locator: ObjectLocator, keyVersion: UInt32) {
        self.identity = identity; self.locator = locator; self.keyVersion = keyVersion
    }
}

/// In-memory, single-writer manifest. Entries are kept sorted by canonical identity bytes,
/// so every sealing is deterministic. The envelope header records the key that encrypts
/// the manifest; `currentKeyVersion` is the writer version, which can differ only while a
/// key rotation migration is resuming.
public struct EncryptedManifest: Equatable, Sendable {
    public var currentKeyVersion: UInt32
    public private(set) var entries: [ManifestEntry]

    public init(currentKeyVersion: UInt32, entries: [ManifestEntry] = []) throws {
        guard currentKeyVersion > 0 else { throw ManifestError.invalidEntry }
        self.currentKeyVersion = currentKeyVersion
        self.entries = []
        try setEntries(entries)
    }

    public func entry(for identity: CanonicalLogicalIdentity) -> ManifestEntry? {
        entries.first { $0.identity == identity }
    }

    public func entry(at locator: ObjectLocator) -> ManifestEntry? {
        entries.first { $0.locator == locator }
    }

    public var locators: Set<ObjectLocator> { Set(entries.map(\.locator)) }

    public mutating func upsert(_ entry: ManifestEntry) throws {
        var next = entries.filter { $0.identity != entry.identity }
        next.append(entry)
        try setEntries(next)
    }

    public mutating func remove(_ identity: CanonicalLogicalIdentity) {
        entries.removeAll { $0.identity == identity }
        entries.sort { Self.ordered($0.identity, before: $1.identity) }
    }

    public mutating func setCurrentKeyVersion(_ version: UInt32) throws {
        guard version > 0 else { throw ManifestError.invalidEntry }
        currentKeyVersion = version
    }

    private mutating func setEntries(_ entries: [ManifestEntry]) throws {
        var identities = Set<Data>()
        for entry in entries {
            guard entry.keyVersion > 0,
                  identities.insert(entry.identity.canonicalBytes).inserted
            else { throw entry.keyVersion == 0 ? ManifestError.invalidEntry : ManifestError.duplicateEntry }
        }
        self.entries = entries.sorted { Self.ordered($0.identity, before: $1.identity) }
    }

    static func ordered(_ lhs: CanonicalLogicalIdentity, before rhs: CanonicalLogicalIdentity) -> Bool {
        lhs.canonicalBytes.lexicographicallyPrecedes(rhs.canonicalBytes)
    }

    func payloadData() throws -> Data {
        try ManifestCoding.encode(self)
    }

    static func from(payload: Data) throws -> EncryptedManifest {
        try ManifestCoding.decode(payload)
    }

    public static func seal(_ manifest: EncryptedManifest, material: Data) throws -> Data {
        let sealed = try LocatorCodec.seal(identity: CanonicalLogicalIdentity.manifest,
                                          payload: try manifest.payloadData(),
                                          keyVersion: manifest.currentKeyVersion, material: material)
        return sealed.envelope
    }

    public static func open(envelope: Data, materialByVersion: [UInt32: Data]) throws
        -> (manifest: EncryptedManifest, encryptionKeyVersion: UInt32) {
        let opened = try LocatorCodec.open(envelope: envelope, requested: CanonicalLogicalIdentity.manifest,
                                          materialByVersion: materialByVersion)
        let manifest = try from(payload: opened.payload)
        return (manifest, opened.keyVersion)
    }
}

enum ManifestCoding {
    static func encode(_ manifest: EncryptedManifest) throws -> Data {
        let wire = Wire(current: manifest.currentKeyVersion,
                        entries: manifest.entries.map(Entry.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(wire)
    }

    static func decode(_ data: Data) throws -> EncryptedManifest {
        guard data.count <= ManifestDiscovery.maximumPayloadBytes else { throw ManifestError.tooLarge }
        let wire: Wire
        do { wire = try JSONDecoder().decode(Wire.self, from: data) }
        catch { throw ManifestError.malformed }
        guard wire.schema == ManifestDiscovery.schemaVersion, wire.current > 0 else {
            throw wire.schema == ManifestDiscovery.schemaVersion
                ? ManifestError.invalidEntry
                : ManifestError.unknownSchemaVersion(wire.schema)
        }
        let entries = try wire.entries.map { try $0.entry() }
        let manifest = try EncryptedManifest(currentKeyVersion: wire.current, entries: entries)
        guard let canonical = try? encode(manifest), canonical == data else {
            throw ManifestError.malformed
        }
        return manifest
    }

    private struct Wire: Codable {
        let schema: UInt32
        let current: UInt32
        let entries: [Entry]

        enum CodingKeys: String, CodingKey, CaseIterable { case schema, current, entries }

        struct AnyKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(current: UInt32, entries: [Entry]) {
            schema = ManifestDiscovery.schemaVersion; self.current = current; self.entries = entries
        }

        init(from decoder: any Decoder) throws {
            let all = try decoder.container(keyedBy: AnyKey.self)
            guard Set(all.allKeys.map(\.stringValue))
                .isSubset(of: Set(CodingKeys.allCases.map(\.rawValue)))
            else { throw ManifestError.malformed }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schema = try container.decode(UInt32.self, forKey: .schema)
            current = try container.decode(UInt32.self, forKey: .current)
            entries = try container.decode([Entry].self, forKey: .entries)
        }
    }

    private struct Entry: Codable {
        let objectType: String
        let schemaVersion: UInt32
        let logicalID: String
        let locator: String
        let keyVersion: UInt32

        enum CodingKeys: String, CodingKey, CaseIterable {
            case objectType, schemaVersion, logicalID, locator, keyVersion
        }

        struct AnyKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(_ entry: ManifestEntry) {
            objectType = entry.identity.objectType
            schemaVersion = entry.identity.schemaVersion
            logicalID = entry.identity.logicalID.hex
            locator = entry.locator.value.hex
            keyVersion = entry.keyVersion
        }

        init(from decoder: any Decoder) throws {
            let all = try decoder.container(keyedBy: AnyKey.self)
            guard Set(all.allKeys.map(\.stringValue))
                .isSubset(of: Set(CodingKeys.allCases.map(\.rawValue)))
            else { throw ManifestError.malformed }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            objectType = try container.decode(String.self, forKey: .objectType)
            schemaVersion = try container.decode(UInt32.self, forKey: .schemaVersion)
            logicalID = try container.decode(String.self, forKey: .logicalID)
            locator = try container.decode(String.self, forKey: .locator)
            keyVersion = try container.decode(UInt32.self, forKey: .keyVersion)
        }

        func entry() throws -> ManifestEntry {
            guard let idBytes = Data.parseHex(logicalID),
                  let locatorValue = Data.parseHex(locator)
            else { throw ManifestError.invalidEntry }
            let identity = try CanonicalLogicalIdentity(objectType: objectType,
                                                        schemaVersion: schemaVersion, logicalID: idBytes)
            return ManifestEntry(identity: identity, locator: try ObjectLocator(locatorValue),
                                 keyVersion: keyVersion)
        }
    }
}

import Foundation

/// Failures while building or parsing the canonical authenticated identity.
public enum LogicalIdentityError: Error, Equatable, Sendable {
    case emptyComponent
    case unsupportedSchemaVersion(UInt32)
    case tooLong
    case malformedEncoding
}

/// Canonical logical identity bound into both the locator and the decrypted plaintext.
///
/// Contract 6: the identity is a length-prefixed UTF-8 tuple
/// `(objectType, schemaVersion, logicalID)`. Numeric schema version is encoded as its
/// canonical ASCII decimal form, so the tuple has one unambiguous byte serialization.
/// A shard's `logicalID` is itself a length-prefixed `(cycleId, dayKey, aggregateType)`
/// byte triple (which is not UTF-8 text because of its length prefixes), so logical IDs
/// are stored as `Data`; ordinary objects use the UTF-8 string initializer.
public struct CanonicalLogicalIdentity: Hashable, Sendable {
    /// Maximum serialized identity size: generous for every planned record, bounded so a
    /// malformed authenticated payload can never force unbounded allocation.
    public static let maximumEncodedByteCount = 65_535
    /// Only record schema version 1 is known. Adding a version is an explicit contract
    /// change; unknown values fail closed here and at decode time.
    public static let supportedSchemaVersions: Set<UInt32> = [1]

    public static let recordObjectTypePrefix = "com.keyrecord."
    public static let shardObjectType = "com.keyrecord.shard"
    public static let manifestObjectType = "com.keyrecord.manifest"
    /// Fixed discovery identity of `manifest.krenc`, known before any decryption.
    public static let manifest = CanonicalLogicalIdentity(
        validatedObjectType: manifestObjectType, schemaVersion: 1,
        logicalID: Data("manifest".utf8))

    public let objectType: String
    public let schemaVersion: UInt32
    public let logicalID: Data

    internal init(validatedObjectType objectType: String, schemaVersion: UInt32, logicalID: Data) {
        self.objectType = objectType
        self.schemaVersion = schemaVersion
        self.logicalID = logicalID
    }

    public init(objectType: String, schemaVersion: UInt32, logicalIDText: String) throws {
        try self.init(objectType: objectType, schemaVersion: schemaVersion,
                      logicalID: Data(logicalIDText.utf8))
    }

    public init(objectType: String, schemaVersion: UInt32, logicalID: Data) throws {
        guard objectType.hasPrefix(Self.recordObjectTypePrefix),
              objectType.utf8.count > Self.recordObjectTypePrefix.utf8.count,
              !logicalID.isEmpty
        else { throw LogicalIdentityError.emptyComponent }
        guard Self.supportedSchemaVersions.contains(schemaVersion) else {
            throw LogicalIdentityError.unsupportedSchemaVersion(schemaVersion)
        }
        let encoded = Self.encode(objectType: objectType, schemaVersion: schemaVersion, logicalID: logicalID)
        guard encoded.count <= Self.maximumEncodedByteCount else { throw LogicalIdentityError.tooLong }
        self.objectType = objectType
        self.schemaVersion = schemaVersion
        self.logicalID = logicalID
    }

    /// Shard identity for physical storage of `(cycleId, dayKey, aggregateType)` arrays.
    public static func shard(cycleID: String, dayKey: String, aggregateType: String,
                             schemaVersion: UInt32 = 1) throws -> CanonicalLogicalIdentity {
        try CanonicalLogicalIdentity(objectType: shardObjectType, schemaVersion: schemaVersion,
                                     logicalID: encodeTriple(cycleID, dayKey, aggregateType))
    }

    /// Recover the `(cycleId, dayKey, aggregateType)` triple of a shard identity. Fails on
    /// non-shard objects, trailing bytes, or non-UTF-8 components.
    public func shardComponents() throws -> (cycleID: String, dayKey: String, aggregateType: String) {
        guard objectType == Self.shardObjectType else { throw LogicalIdentityError.malformedEncoding }
        var reader = LengthPrefixedReader(logicalID)
        let cycleBytes = try reader.nextField()
        let dayBytes = try reader.nextField()
        let typeBytes = try reader.nextField()
        guard reader.isExhausted,
              let cycleID = String(bytes: cycleBytes, encoding: .utf8),
              let dayKey = String(bytes: dayBytes, encoding: .utf8),
              let aggregateType = String(bytes: typeBytes, encoding: .utf8),
              !cycleID.isEmpty, !dayKey.isEmpty, !aggregateType.isEmpty
        else { throw LogicalIdentityError.malformedEncoding }
        return (cycleID, dayKey, aggregateType)
    }

    /// UTF-8 text form for ordinary (non-shard) objects; nil for binary shard composites.
    public var logicalIDText: String? { String(bytes: logicalID, encoding: .utf8) }

    public var canonicalBytes: Data {
        Self.encode(objectType: objectType, schemaVersion: schemaVersion, logicalID: logicalID)
    }

    /// Split an authenticated plaintext into its leading identity tuple and the payload.
    public static func split(_ plaintext: Data) throws -> (identity: CanonicalLogicalIdentity, payload: Data) {
        var reader = LengthPrefixedReader(plaintext)
        let typeBytes = try reader.nextField()
        let versionBytes = try reader.nextField()
        let idBytes = try reader.nextField()
        let consumed = reader.consumed
        guard let objectType = String(bytes: typeBytes, encoding: .utf8),
              let versionText = String(bytes: versionBytes, encoding: .utf8),
              let schemaVersion = UInt32(versionText), !versionText.hasPrefix("+")
        else { throw LogicalIdentityError.malformedEncoding }
        let identity = try CanonicalLogicalIdentity(objectType: objectType,
                                                    schemaVersion: schemaVersion, logicalID: idBytes)
        return (identity, plaintext.subdata(in: consumed..<plaintext.count))
    }

    /// Parse exactly one length-prefixed tuple with no trailing bytes.
    public static func parse(_ bytes: Data) throws -> CanonicalLogicalIdentity {
        let split = try split(bytes)
        guard split.payload.isEmpty else { throw LogicalIdentityError.malformedEncoding }
        return split.identity
    }

    static func encode(objectType: String, schemaVersion: UInt32, logicalID: Data) -> Data {
        var result = Data()
        result.append(lengthPrefixed(Data(objectType.utf8)))
        result.append(lengthPrefixed(Data(String(schemaVersion).utf8)))
        result.append(lengthPrefixed(logicalID))
        return result
    }

    static func encodeTriple(_ first: String, _ second: String, _ third: String) -> Data {
        lengthPrefixed(Data(first.utf8))
            + lengthPrefixed(Data(second.utf8))
            + lengthPrefixed(Data(third.utf8))
    }

    private static func lengthPrefixed(_ bytes: Data) -> Data {
        var result = Data(UInt32(bytes.count).bigEndianBytes)
        result.append(bytes)
        return result
    }
}

private struct LengthPrefixedReader {
    private let data: Data
    private var offset = 0
    init(_ data: Data) { self.data = data }

    var consumed: Int { offset }
    var isExhausted: Bool { offset == data.count }

    mutating func nextField() throws -> Data {
        guard offset + 4 <= data.count else { throw LogicalIdentityError.malformedEncoding }
        let length = data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        offset += 4
        guard length <= UInt32(CanonicalLogicalIdentity.maximumEncodedByteCount),
              offset + Int(length) <= data.count
        else { throw LogicalIdentityError.malformedEncoding }
        let field = data.subdata(in: offset..<(offset + Int(length)))
        offset += Int(length)
        return field
    }
}

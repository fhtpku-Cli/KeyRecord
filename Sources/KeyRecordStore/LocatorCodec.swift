import CryptoKit
import Foundation

/// Errors specific to authenticated object binding (distinct from raw wire parse errors).
public enum LocatorCodecError: Error, Equatable, Sendable {
    /// The 64-byte header locator does not equal the locator recomputed for the requested
    /// identity under the selected version key.
    case locatorMismatch
    /// The decrypted identity tuple does not equal the requested identity.
    case identityMismatch
    /// The plaintext carries no payload after the identity tuple.
    case emptyPayload
    /// A stored filename is not the flat opaque shape the contract requires.
    case invalidLocatorFileName
    /// The payload would push the envelope past the 8 MiB authenticated-plaintext bound.
    case payloadTooLarge
}

/// A 32-byte HMAC-SHA256 locator. Product filenames are exactly `<lowerhex>.krenc`,
/// flat inside the private store root. There is no semantic or sharded directory level.
public struct ObjectLocator: Hashable, Sendable {
    public static let byteCount = 32
    public static let fileNameSuffix = ".krenc"

    public let value: Data

    public init(_ value: Data) throws {
        guard value.count == Self.byteCount else { throw LocatorCodecError.invalidLocatorFileName }
        self.value = value
    }

    public var fileName: String { value.hex + Self.fileNameSuffix }

    /// Parse only the strict flat `<64-lowerhex>.krenc>` form.
    public static func parse(fileName: String) throws -> ObjectLocator {
        let expectedSuffixLength = Self.fileNameSuffix.utf8.count
        guard fileName.utf8.count == Self.byteCount * 2 + expectedSuffixLength,
              fileName.hasSuffix(Self.fileNameSuffix)
        else { throw LocatorCodecError.invalidLocatorFileName }
        let hexPart = String(fileName.dropLast(expectedSuffixLength))
        guard hexPart.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let value = Data.parseHex(hexPart)
        else { throw LocatorCodecError.invalidLocatorFileName }
        return try ObjectLocator(value)
    }
}

/// Authenticated object content. The encrypted plaintext is `identity || payload`:
/// GCM authenticates the header (including locator), and the plaintext identity is
/// compared against the caller's requested identity after decryption, so swapping one
/// complete valid envelope for another is rejected even though both are valid ciphertexts.
public struct SealedObject: Equatable, Sendable {
    public let locator: ObjectLocator
    public let keyVersion: UInt32
    public let envelope: Data
}

public struct OpenedObject: Equatable, Sendable {
    public let identity: CanonicalLogicalIdentity
    public let payload: Data
    public let keyVersion: UInt32
}

public enum LocatorCodec {
    public static func seal(
        identity: CanonicalLogicalIdentity,
        payload: Data,
        keyVersion: UInt32,
        material: Data
    ) throws -> SealedObject {
        let inner = identity.canonicalBytes + payload
        guard !payload.isEmpty,
              inner.count <= AuthenticatedStorageEnvelope.maximumCiphertextBytes
        else {
            throw payload.isEmpty ? LocatorCodecError.emptyPayload : LocatorCodecError.payloadTooLarge
        }
        let locatorValue = StorageKeySchedule.locator(material: material, objectID: identity.canonicalBytes)
        let locator = try ObjectLocator(locatorValue)
        let envelope = try AuthenticatedStorageEnvelope.seal(
            inner, material: material, keyVersion: keyVersion, locator: locator.value)
        return SealedObject(locator: locator, keyVersion: keyVersion, envelope: envelope)
    }

    /// Authenticate an envelope with no requested identity. Recovery uses this ONLY to
    /// establish provenance of unreferenced files: GCM verifies the header (including its
    /// locator), the recovered identity is parsed, and the header locator must equal the
    /// locator recomputed from that recovered identity under the selected key.
    public static func authenticate(
        envelope: Data,
        materialByVersion: [UInt32: Data]
    ) throws -> OpenedObject {
        let parsed = try AuthenticatedStorageEnvelope.parse(envelope)
        let keyVersion = parsed.header.keyVersion
        guard let material = materialByVersion[keyVersion] else {
            throw StorageEnvelopeError.missingKeyVersion
        }
        var keys: [UInt32: SymmetricKey] = [:]
        keys[keyVersion] = StorageKeySchedule.key(material)
        let plaintext = try AuthenticatedStorageEnvelope.open(envelope, keys: keys)
        let split = try CanonicalLogicalIdentity.split(plaintext)
        guard !split.payload.isEmpty else { throw LocatorCodecError.emptyPayload }
        let expectedLocator = StorageKeySchedule.locator(material: material,
                                                         objectID: split.identity.canonicalBytes)
        guard parsed.header.locator == expectedLocator else { throw LocatorCodecError.locatorMismatch }
        return OpenedObject(identity: split.identity, payload: split.payload, keyVersion: keyVersion)
    }

    /// Open an envelope for an explicitly requested identity. Fails closed unless:
    /// 1. the wire parses and the header key version selects available material;
    /// 2. the header locator equals HMAC(locatorKey(v), requestedIdentity);
    /// 3. GCM verifies against the authenticated header;
    /// 4. the decrypted identity tuple equals the requested identity exactly.
    public static func open(
        envelope: Data,
        requested identity: CanonicalLogicalIdentity,
        materialByVersion: [UInt32: Data]
    ) throws -> OpenedObject {
        let parsed = try AuthenticatedStorageEnvelope.parse(envelope)
        let keyVersion = parsed.header.keyVersion
        guard let material = materialByVersion[keyVersion] else {
            throw StorageEnvelopeError.missingKeyVersion
        }
        let expectedLocator = StorageKeySchedule.locator(material: material,
                                                         objectID: identity.canonicalBytes)
        guard parsed.header.locator == expectedLocator else { throw LocatorCodecError.locatorMismatch }
        var keys: [UInt32: SymmetricKey] = [:]
        keys[keyVersion] = StorageKeySchedule.key(material)
        let plaintext = try AuthenticatedStorageEnvelope.open(envelope, keys: keys)
        let split = try CanonicalLogicalIdentity.split(plaintext)
        guard split.identity == identity else { throw LocatorCodecError.identityMismatch }
        guard !split.payload.isEmpty else { throw LocatorCodecError.emptyPayload }
        return OpenedObject(identity: split.identity, payload: split.payload, keyVersion: keyVersion)
    }
}

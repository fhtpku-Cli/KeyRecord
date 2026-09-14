import CryptoKit
import Foundation

public enum StorageEnvelopeError: Error, Equatable, Sendable {
    case duplicateNonce, invalidAlgorithm, invalidFormat, invalidKeyVersion, invalidLength
    case invalidVersion, missingKeyVersion
}

public struct StorageEnvelopeHeader: Equatable, Sendable {
    public let keyVersion: UInt32
    public let locator: Data
    public let nonce: Data
    public let ciphertextLength: UInt64
}

public struct ParsedStorageEnvelope: Equatable, Sendable {
    public let header: StorageEnvelopeHeader
    public let authenticatedHeader: Data
    public let ciphertext: Data
    public let tag: Data
}

/// HKDF labels and salt ported from the measured SP6A primitive. Frozen wire contract;
/// StorageCryptoVectorTests locks derived bytes against the spike's measured output.
/// The probe's sharded path helper is intentionally not ported: product storage is flat.
public enum StorageKeySchedule {
    public static let salt = Data("KeyRecord/SP-6A/HKDF-SHA256/v1".utf8)
    public static let encryptionInfo = Data("KeyRecord/SP-6A/object-encryption/v1".utf8)
    public static let locatorInfo = Data("KeyRecord/SP-6A/opaque-locator/v1".utf8)

    public static func key(_ material: Data) -> SymmetricKey { SymmetricKey(data: material) }
    public static func encryptionKey(material: Data) -> SymmetricKey { encryptionKey(masterKey: key(material)) }
    public static func locatorKey(material: Data) -> SymmetricKey { locatorKey(masterKey: key(material)) }

    public static func encryptionKey(masterKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: encryptionInfo, outputByteCount: 32)
    }

    public static func locatorKey(masterKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: locatorInfo, outputByteCount: 32)
    }

    public static func locator(material: Data, objectID: Data) -> Data {
        locator(masterKey: key(material), objectID: objectID)
    }

    public static func locator(masterKey: SymmetricKey, objectID: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: objectID, using: locatorKey(masterKey: masterKey)))
    }
}

/// v1 authenticated envelope, byte-for-byte compatible with the measured SP6A wire:
/// magic `KR6A`, version 1, AES-256-GCM algorithm byte, two reserved zeroes, UInt32 BE key
/// version, 32-byte locator, 12-byte nonce, UInt64 BE length, ciphertext, 16-byte tag.
/// The 8 MiB bound is enforced at seal AND parse, so a declared length cannot over-allocate.
public enum AuthenticatedStorageEnvelope {
    public static let headerByteCount = 64
    public static let lengthOffset = 56
    public static let maximumCiphertextBytes = 8 * 1_024 * 1_024
    static let magic = Data([0x4b, 0x52, 0x36, 0x41])
    static let formatVersion: UInt8 = 1
    static let algorithmAESGCM256: UInt8 = 1
    static let tagByteCount = 16

    public static func fixedNonce(_ bytes: Data) throws -> AES.GCM.Nonce {
        try AES.GCM.Nonce(data: bytes)
    }

    public static func seal(_ plaintext: Data, material: Data, keyVersion: UInt32,
                            locator: Data, nonce: AES.GCM.Nonce? = nil) throws -> Data {        try seal(plaintext, masterKey: StorageKeySchedule.key(material),
                 keyVersion: keyVersion, locator: locator, nonce: nonce)
    }

    public static func seal(_ plaintext: Data, masterKey: SymmetricKey, keyVersion: UInt32,
                            locator: Data, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        guard keyVersion > 0 else { throw StorageEnvelopeError.invalidKeyVersion }
        guard locator.count == SHA256.byteCount, plaintext.count <= maximumCiphertextBytes else {
            throw StorageEnvelopeError.invalidLength
        }
        let selectedNonce = nonce ?? AES.GCM.Nonce()
        let nonceData = selectedNonce.withUnsafeBytes { Data($0) }
        guard nonceData.count == 12 else { throw StorageEnvelopeError.invalidLength }
        let header = encodedHeader(keyVersion: keyVersion, locator: locator, nonce: nonceData,
                                   ciphertextLength: UInt64(plaintext.count))
        let box = try AES.GCM.seal(plaintext,
                                   using: StorageKeySchedule.encryptionKey(masterKey: masterKey),
                                   nonce: selectedNonce, authenticating: header)
        return header + box.ciphertext + box.tag
    }

    public static func parse<D: DataProtocol>(_ bytes: D) throws -> ParsedStorageEnvelope {
        let data = Data(bytes)
        guard data.count >= headerByteCount + tagByteCount else { throw StorageEnvelopeError.invalidLength }
        guard data.prefix(4) == magic else { throw StorageEnvelopeError.invalidFormat }
        guard data[4] == formatVersion else { throw StorageEnvelopeError.invalidVersion }
        guard data[5] == algorithmAESGCM256, data[6] == 0, data[7] == 0 else {
            throw StorageEnvelopeError.invalidAlgorithm
        }
        let keyVersion = readUInt32(data, at: 8)
        guard keyVersion > 0 else { throw StorageEnvelopeError.invalidKeyVersion }
        let length = readUInt64(data, at: lengthOffset)
        guard length <= maximumCiphertextBytes, length <= UInt64(Int.max),
              data.count == headerByteCount + Int(length) + tagByteCount else {
            throw StorageEnvelopeError.invalidLength
        }
        let end = headerByteCount + Int(length)
        return ParsedStorageEnvelope(
            header: StorageEnvelopeHeader(keyVersion: keyVersion, locator: data.subdata(in: 12..<44),
                                          nonce: data.subdata(in: 44..<56), ciphertextLength: length),
            authenticatedHeader: data.prefix(headerByteCount),
            ciphertext: data.subdata(in: headerByteCount..<end), tag: data.suffix(tagByteCount))
    }

    public static func open<D: DataProtocol>(_ bytes: D, materials: [UInt32: Data]) throws -> Data {
        try open(bytes, keys: materials.mapValues { StorageKeySchedule.key($0) })
    }

    public static func open<D: DataProtocol>(_ bytes: D, keys: [UInt32: SymmetricKey]) throws -> Data {
        let parsed = try parse(bytes)
        guard let masterKey = keys[parsed.header.keyVersion] else {
            throw StorageEnvelopeError.missingKeyVersion
        }
        let nonce = try AES.GCM.Nonce(data: parsed.header.nonce)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: parsed.ciphertext, tag: parsed.tag)
        return try AES.GCM.open(box,
                                using: StorageKeySchedule.encryptionKey(masterKey: masterKey),
                                authenticating: parsed.authenticatedHeader)
    }

    static func encodedHeader(keyVersion: UInt32, locator: Data, nonce: Data, ciphertextLength: UInt64) -> Data {
        var result = magic
        result.append(contentsOf: [formatVersion, algorithmAESGCM256, 0, 0])
        result.append(contentsOf: keyVersion.bigEndianBytes)
        result.append(locator); result.append(nonce)
        result.append(contentsOf: ciphertextLength.bigEndianBytes)
        return result
    }

    static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

public struct NonceReuseDetector: Sendable {
    // Random 96-bit nonces are the primary collision defense. This bounded replay
    // window is only a secondary session-local check, not lifetime nonce history.
    static let capacity = 4096
    private var observed = Set<String>()
    private var ring: [String] = []
    private var oldest = 0
    var retainedCount: Int { observed.count }
    public init() {}
    public mutating func record(_ nonce: Data, keyVersion: UInt32) throws {
        guard nonce.count == 12 else { throw StorageEnvelopeError.invalidLength }
        let entry = "\(keyVersion):\(nonce.hex)"
        guard !observed.contains(entry) else {
            throw StorageEnvelopeError.duplicateNonce
        }
        if ring.count == Self.capacity {
            observed.remove(ring[oldest])
            ring[oldest] = entry
            oldest = (oldest + 1) % Self.capacity
        } else {
            ring.append(entry)
        }
        observed.insert(entry)
    }
}

extension Data {
    public var hex: String { map { String(format: "%02x", $0) }.joined() }

    static func parseHex(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let value = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(value); index = next
        }
        return bytes
    }
}

extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] { withUnsafeBytes(of: bigEndian) { Array($0) } }
}

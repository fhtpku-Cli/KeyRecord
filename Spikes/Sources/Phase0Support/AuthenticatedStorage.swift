import CryptoKit
import Foundation

public enum StorageEnvelopeError: Error, Equatable, Sendable {
    case duplicateNonce
    case invalidAlgorithm
    case invalidFormat
    case invalidKeyVersion
    case invalidLength
    case invalidVersion
    case missingKeyVersion
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

public enum StorageKeySchedule {
    public static let salt = Data("KeyRecord/SP-6A/HKDF-SHA256/v1".utf8)
    public static let encryptionInfo = Data("KeyRecord/SP-6A/object-encryption/v1".utf8)
    public static let locatorInfo = Data("KeyRecord/SP-6A/opaque-locator/v1".utf8)

    public static func encryptionKey(masterKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: encryptionInfo, outputByteCount: 32)
    }

    public static func locatorKey(masterKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: locatorInfo, outputByteCount: 32)
    }

    public static func locator(masterKey: SymmetricKey, objectID: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: objectID, using: locatorKey(masterKey: masterKey)))
    }

    public static func opaquePath(locator: Data) -> String {
        let value = locator.hex
        return "\(value.prefix(2))/\(value.dropFirst(2)).krenc"
    }
}

public enum AuthenticatedStorageEnvelope {
    public static let headerByteCount = 64
    public static let lengthOffset = 56
    public static let maximumCiphertextBytes = 8 * 1_024 * 1_024
    private static let magic = Data([0x4b, 0x52, 0x36, 0x41])
    private static let formatVersion: UInt8 = 1
    private static let algorithmAESGCM256: UInt8 = 1
    private static let tagByteCount = 16

    public static func seal(
        _ plaintext: Data,
        masterKey: SymmetricKey,
        keyVersion: UInt32,
        locator: Data,
        nonce: AES.GCM.Nonce? = nil
    ) throws -> Data {
        guard keyVersion > 0 else { throw StorageEnvelopeError.invalidKeyVersion }
        guard locator.count == SHA256.byteCount, plaintext.count <= maximumCiphertextBytes else {
            throw StorageEnvelopeError.invalidLength
        }
        let selectedNonce = nonce ?? AES.GCM.Nonce()
        let nonceData = selectedNonce.withUnsafeBytes { Data($0) }
        guard nonceData.count == 12 else { throw StorageEnvelopeError.invalidLength }
        let header = encodedHeader(keyVersion: keyVersion, locator: locator, nonce: nonceData, ciphertextLength: UInt64(plaintext.count))
        let box = try AES.GCM.seal(plaintext, using: StorageKeySchedule.encryptionKey(masterKey: masterKey), nonce: selectedNonce, authenticating: header)
        return header + box.ciphertext + box.tag
    }

    public static func parse<D: DataProtocol>(_ bytes: D) throws -> ParsedStorageEnvelope {
        let data = Data(bytes)
        guard data.count >= headerByteCount + tagByteCount else { throw StorageEnvelopeError.invalidLength }
        guard data.prefix(4) == magic else { throw StorageEnvelopeError.invalidFormat }
        guard data[4] == formatVersion else { throw StorageEnvelopeError.invalidVersion }
        guard data[5] == algorithmAESGCM256, data[6] == 0, data[7] == 0 else { throw StorageEnvelopeError.invalidAlgorithm }
        let keyVersion = readUInt32(data, at: 8)
        guard keyVersion > 0 else { throw StorageEnvelopeError.invalidKeyVersion }
        let locator = data.subdata(in: 12..<44)
        let nonce = data.subdata(in: 44..<56)
        let length = readUInt64(data, at: lengthOffset)
        guard length <= maximumCiphertextBytes,
              length <= UInt64(Int.max),
              data.count == headerByteCount + Int(length) + tagByteCount else {
            throw StorageEnvelopeError.invalidLength
        }
        let ciphertextEnd = headerByteCount + Int(length)
        return ParsedStorageEnvelope(
            header: StorageEnvelopeHeader(keyVersion: keyVersion, locator: locator, nonce: nonce, ciphertextLength: length),
            authenticatedHeader: data.prefix(headerByteCount),
            ciphertext: data.subdata(in: headerByteCount..<ciphertextEnd),
            tag: data.suffix(tagByteCount)
        )
    }

    public static func open<D: DataProtocol>(_ bytes: D, keys: [UInt32: SymmetricKey]) throws -> Data {
        let parsed = try parse(bytes)
        guard let masterKey = keys[parsed.header.keyVersion] else { throw StorageEnvelopeError.missingKeyVersion }
        let nonce = try AES.GCM.Nonce(data: parsed.header.nonce)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: parsed.ciphertext, tag: parsed.tag)
        return try AES.GCM.open(box, using: StorageKeySchedule.encryptionKey(masterKey: masterKey), authenticating: parsed.authenticatedHeader)
    }

    private static func encodedHeader(keyVersion: UInt32, locator: Data, nonce: Data, ciphertextLength: UInt64) -> Data {
        var result = magic
        result.append(contentsOf: [formatVersion, algorithmAESGCM256, 0, 0])
        result.append(contentsOf: keyVersion.bigEndianBytes)
        result.append(locator)
        result.append(nonce)
        result.append(contentsOf: ciphertextLength.bigEndianBytes)
        return result
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

public struct NonceReuseDetector: Sendable {
    private var observed = Set<String>()
    public init() {}
    public mutating func record(_ nonce: Data, keyVersion: UInt32) throws {
        guard nonce.count == 12 else { throw StorageEnvelopeError.invalidLength }
        guard observed.insert("\(keyVersion):\(nonce.hex)").inserted else { throw StorageEnvelopeError.duplicateNonce }
    }
}

public enum StorageCanaryError: Error, Equatable, Sendable { case plaintextFound, semanticPath }

public enum StorageCanary {
    public static func validate(relativePaths: [String], files: [Data], plaintextCanary: Data) throws {
        guard !plaintextCanary.isEmpty else { throw StorageCanaryError.plaintextFound }
        guard relativePaths.allSatisfy(isOpaquePath) else { throw StorageCanaryError.semanticPath }
        guard files.allSatisfy({ $0.range(of: plaintextCanary) == nil }) else { throw StorageCanaryError.plaintextFound }
    }

    public static func isOpaquePath(_ value: String) -> Bool {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, components[0].count == 2, components[1].count == 68,
              components[1].hasSuffix(".krenc") else { return false }
        return (components[0] + components[1].dropLast(6)).utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

public enum EncryptedArtifactWriteFault: Sendable { case beforeRename }

public enum EncryptedArtifactWriter {
    public static func write(_ envelope: Data, to target: URL, failAt: EncryptedArtifactWriteFault? = nil) throws {
        let injection = AtomicReplacementInjection(failureAt: failAt == .beforeRename ? .rename : nil)
        _ = try POSIXAtomicReplacement().replace(target: target, bytes: envelope, injection: injection)
    }
}

extension Data {
    public var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}

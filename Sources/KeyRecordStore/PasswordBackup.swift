import Foundation
import CryptoKit
import argon2

public enum PasswordBackupError: Error, Equatable, Sendable {
    case invalidPassword, invalidArchive, unsupportedFormat, derivationFailed
    case authenticationFailed, limitExceeded, destinationNotEmpty, maintenancePending
}

/// A portable logical snapshot. Local key material, machine paths and file names are
/// never needed to decrypt it. Every manifest object is included without a type filter.
public struct BackupObject: Sendable, Equatable {
    public let identity: CanonicalLogicalIdentity
    public let payload: Data
    public init(identity: CanonicalLogicalIdentity, payload: Data) {
        self.identity = identity; self.payload = payload
    }
}

public enum PasswordBackup {
    public static let maximumArchiveBytes = 128 * 1_024 * 1_024
    public static let maximumObjects = 50_000
    // The previously measured SP-6B Apple Silicon profile, not an Intel timing claim.
    static let memoryKiB: UInt32 = 524_288
    static let iterations: UInt32 = 5
    static let parallelism: UInt32 = 4
    private static let magic = Data("KRBACKUP".utf8)
    private static let headerSize = 8 + 5 * 4 + 16

    public static func seal(_ objects: [BackupObject], password: String) throws -> Data {
        try validate(password: password)
        let plain = try encode(objects)
        let salt = Data(try SystemMasterMaterial().generate().prefix(16))
        var header = magic
        for value: UInt32 in [1, 0x13, memoryKiB, iterations, parallelism] { append(value, to: &header) }
        header.append(salt)
        var key = try derive(password: Data(password.utf8), salt: salt,
                             memory: memoryKiB, iterations: iterations, lanes: parallelism)
        defer { key.resetBytes(in: 0..<key.count) }
        let sealed = try AES.GCM.seal(plain, using: SymmetricKey(data: key), authenticating: header)
        guard let combined = sealed.combined else { throw PasswordBackupError.invalidArchive }
        return header + combined
    }

    public static func open(_ archive: Data, password: String) throws -> [BackupObject] {
        try validate(password: password)
        guard archive.count <= maximumArchiveBytes,
              archive.count >= headerSize + 28, archive.prefix(8) == magic
        else { throw PasswordBackupError.invalidArchive }
        var reader = BackupReader(data: Data(archive.dropFirst(8)))
        // Accept only the v1 profile before allocating Argon2 memory. Future profiles
        // need an explicit reader version; attacker-supplied costs never reach C.
        guard try reader.integer() == 1, try reader.integer() == 0x13,
              try reader.integer() == memoryKiB, try reader.integer() == iterations,
              try reader.integer() == parallelism else { throw PasswordBackupError.unsupportedFormat }
        let salt = try reader.bytes(16)
        var key = try derive(password: Data(password.utf8), salt: salt,
                             memory: memoryKiB, iterations: iterations, lanes: parallelism)
        defer { key.resetBytes(in: 0..<key.count) }
        let plain: Data
        do {
            plain = try AES.GCM.open(AES.GCM.SealedBox(combined: archive.dropFirst(headerSize)),
                                    using: SymmetricKey(data: key), authenticating: archive.prefix(headerSize))
        } catch { throw PasswordBackupError.authenticationFailed }
        return try decode(plain)
    }

    static func derive(password: Data, salt: Data, memory: UInt32,
                       iterations: UInt32, lanes: UInt32) throws -> Data {
        var key = Data(count: 32)
        let result = key.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    argon2id_hash_raw(iterations, memory, lanes, passwordBytes.baseAddress, passwordBytes.count,
                                      saltBytes.baseAddress, saltBytes.count, out.baseAddress, out.count)
                }
            }
        }
        guard result == ARGON2_OK.rawValue else { throw PasswordBackupError.derivationFailed }
        return key
    }

    static func validate(password: String) throws {
        guard !password.isEmpty, password.utf8.count <= 1_024 else { throw PasswordBackupError.invalidPassword }
    }

    static func encode(_ objects: [BackupObject]) throws -> Data {
        guard objects.count <= maximumObjects else { throw PasswordBackupError.limitExceeded }
        var result = Data(); append(UInt32(objects.count), to: &result)
        var identities = Set<CanonicalLogicalIdentity>()
        for object in objects {
            guard object.identity != .manifest, identities.insert(object.identity).inserted,
                  !object.payload.isEmpty,
                  object.payload.count + object.identity.canonicalBytes.count <= AuthenticatedStorageEnvelope.maximumCiphertextBytes
            else { throw PasswordBackupError.invalidArchive }
            let identity = object.identity.canonicalBytes
            guard result.count + identity.count + object.payload.count + 8 <= maximumArchiveBytes - headerSize - 28
            else { throw PasswordBackupError.limitExceeded }
            append(UInt32(identity.count), to: &result); result.append(identity)
            append(UInt32(object.payload.count), to: &result); result.append(object.payload)
        }
        return result
    }

    static func decode(_ plain: Data) throws -> [BackupObject] {
        var reader = BackupReader(data: plain)
        let count = try reader.integer()
        guard count <= maximumObjects else { throw PasswordBackupError.limitExceeded }
        var objects: [BackupObject] = []
        for _ in 0..<count {
            let identitySize = try reader.integer()
            guard identitySize <= CanonicalLogicalIdentity.maximumEncodedByteCount else { throw PasswordBackupError.invalidArchive }
            let identity = try CanonicalLogicalIdentity.parse(reader.bytes(Int(identitySize)))
            let size = try reader.integer()
            guard size <= AuthenticatedStorageEnvelope.maximumCiphertextBytes else { throw PasswordBackupError.invalidArchive }
            objects.append(BackupObject(identity: identity, payload: try reader.bytes(Int(size))))
        }
        guard reader.exhausted else { throw PasswordBackupError.invalidArchive }
        _ = try encode(objects)
        return objects
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

private struct BackupReader {
    let data: Data
    var offset = 0
    var exhausted: Bool { offset == data.count }
    mutating func integer() throws -> UInt32 {
        try bytes(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw PasswordBackupError.invalidArchive }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

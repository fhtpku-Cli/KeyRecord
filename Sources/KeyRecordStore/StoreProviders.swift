import Foundation
import KeyRecordCore

public enum StoreError: Error, Equatable, Sendable {
    case keyUnavailable(KeyVersion)
    case protectedDataUnavailable
    case filesystemFailure
}

/// Architecture §3.2, plan contracts 7–8: async actor seam; missing keys never authorize replacement.
/// Material remains transient. Future implementations must fence reads by fresh lock/key generation.
public protocol KeyMaterialSource: Sendable {
    func keyMaterial(for version: KeyVersion) async throws -> Data
}

/// Architecture §5.2: ciphertext-only storage port; no record/event serializer or engine in this task.
/// Future single-writer actor must enforce permissions, symlink policy and durable rename ordering.
public protocol FileSystem: Sendable {
    func readCiphertext(at location: URL) async throws -> Data
    func replaceCiphertext(_ bytes: Data, at location: URL) async throws
    func removeCiphertext(at location: URL) async throws
    func synchronizeDirectory(at location: URL) async throws
}

import Foundation
import KeyRecordCore

/// Deliberately no live effect adapter until task 7's signed, environment-bound qualification passes.
/// Fake success cannot unlock this backend; a future authorized adapter must validate before EVERY effect.
public struct BlockedLiveKeychain: KeychainBackend {
    public init() {}
    public func read(_ id: KeychainItemID) async throws -> Data? { throw KeyringError.liveQualificationBlocked }
    public func versions(in namespace: KeychainNamespace) async throws -> Set<KeyVersion> { throw KeyringError.liveQualificationBlocked }
    public func add(_ item: KeychainItem) async throws { throw KeyringError.liveQualificationBlocked }
    public func publish(_ update: KeychainMetadataUpdate) async throws { throw KeyringError.liveQualificationBlocked }
    public func delete(_ id: KeychainItemID) async throws { throw KeyringError.liveQualificationBlocked }
}

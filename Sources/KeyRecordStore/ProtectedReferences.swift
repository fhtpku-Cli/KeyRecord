import Foundation
import KeyRecordCore

public enum ProtectedReferenceKind: String, CaseIterable, Sendable {
    case liveManifestEntry, fixedManifest, unfinishedJournal, journalRecoveryObject, ownedTemporaryOrOrphan
}

public enum ProtectedReference: Sendable {
    case known(ProtectedReferenceKind, KeyVersion)
    case unreadable(ProtectedReferenceKind)
}

public struct ProtectedReferenceSnapshot: Sendable {
    public let coverage: Set<ProtectedReferenceKind>
    public let references: [ProtectedReference]
    public init(coverage: Set<ProtectedReferenceKind>, references: [ProtectedReference]) {
        self.coverage = coverage; self.references = references
    }

    func requiredVersions() throws -> Set<KeyVersion> {
        guard coverage == Set(ProtectedReferenceKind.allCases) else { throw KeyringError.unknownReferences }
        var versions: Set<KeyVersion> = []
        for reference in references {
            switch reference {
            case .known(_, let version):
                guard version.rawValue > 0 else { throw KeyringError.unknownReferences }
                versions.insert(version)
            case .unreadable: throw KeyringError.unknownReferences
            }
        }
        return versions
    }
}

public struct KeyRotation: Codable, Equatable, Sendable {
    public let from: KeyVersion
    public let to: KeyVersion
    public init(from: KeyVersion, to: KeyVersion) { self.from = from; self.to = to }
}

/// The store actor must exclude ALL reset/rotation/reference writers until release, including across awaits.
/// A session's migration and recovery steps are durable and idempotent. Implementations fence their own
/// async protected completions with the shared availability gate; they must not publish stale plaintext.
public protocol ProtectedReferenceProviding: Sendable {
    func acquireExclusiveAccess() async throws -> any ProtectedReferenceSession
}

public protocol ProtectedReferenceSession: Sendable {
    func migrateData(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws
    func reencryptManifestAndJournals(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws
    func recoverAndReconcile(access: KeyringProtectedAccess) async throws
    func scan(access: KeyringProtectedAccess) async throws -> ProtectedReferenceSnapshot
    func release() async
}

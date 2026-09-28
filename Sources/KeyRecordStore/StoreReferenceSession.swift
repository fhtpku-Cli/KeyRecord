import Foundation
import KeyRecordCore

extension ObjectStore: ProtectedReferenceProviding {
    public func acquireExclusiveAccess() async throws -> any ProtectedReferenceSession {
        StoreSession(store: self, lease: try beginLease(), sessionToken: protectedSessionToken)
    }
}

private final class StoreSession: ProtectedReferenceSession, @unchecked Sendable {
    private let store: ObjectStore
    private let lease: UUID
    private let sessionToken: UUID
    private var released = false

    init(store: ObjectStore, lease: UUID, sessionToken: UUID) {
        self.store = store; self.lease = lease; self.sessionToken = sessionToken
    }

    func migrateData(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        try await store.migrateObjects(lease: lease, rotation: rotation, access: access,
                                       sessionToken: sessionToken)
    }

    func reencryptManifestAndJournals(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        try await store.reencryptFixedManifest(lease: lease, rotation: rotation, access: access,
                                               sessionToken: sessionToken)
    }

    func recoverAndReconcile(access: KeyringProtectedAccess) async throws {
        try await store.reconcileAfterRecovery(lease: lease, access: access, sessionToken: sessionToken)
    }

    func scan(access: KeyringProtectedAccess) async throws -> ProtectedReferenceSnapshot {
        try await store.protectedScan(lease: lease, access: access, sessionToken: sessionToken)
    }

    func release() async {
        guard !released else { return }
        released = true
        await store.endLease(lease)
    }
}

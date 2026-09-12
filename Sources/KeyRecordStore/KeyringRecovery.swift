import Foundation
import KeyRecordCore

extension KeychainKeyring {
    struct Loaded: Sendable {
        let state: KeyringRecoveryState
        let bytes: Data
    }

    func load(_ generation: CaptureGeneration, _ session: any ProtectedReferenceSession) async throws -> Loaded {
        let bytes = try await readMetadata(generation)
        let inventory = try await inventory(generation)
        guard let bytes else {
            if !inventory.isEmpty { throw KeyringError.unpublishedCandidates(inventory) }
            throw KeyringError.corruptMetadata
        }
        let metadata = try KeyringMetadata.decode(bytes)
        let candidates = inventory.subtracting(metadata.versions)
        guard candidates.allSatisfy({ $0.rawValue > metadata.current.rawValue }) else { throw KeyringError.corruptMetadata }
        if !metadata.retirementPending.isEmpty {
            let required = try await scan(session, generation, versions: metadata.versions.subtracting(metadata.retirementPending))
            for version in metadata.retirementPending {
                guard !required.contains(version) else { throw KeyringError.versionReferenced(version) }
            }
            guard required.isSubset(of: metadata.versions) else { throw KeyringError.unknownReferences }
        }
        for version in metadata.versions.sorted(by: { $0.rawValue < $1.rawValue }) {
            do { _ = try await material(version, generation) }
            catch KeyringError.missingKey(let missing) where metadata.retirementPending.contains(missing) {
                // Only the just-completed, complete scan above permits a deleted pending item.
            }
        }
        for candidate in candidates { _ = try await material(candidate, generation) }
        return Loaded(state: KeyringRecoveryState(metadata: metadata, pendingCandidates: candidates), bytes: bytes)
    }

    func scan(_ session: any ProtectedReferenceSession, _ generation: CaptureGeneration,
              versions: Set<KeyVersion>) async throws -> Set<KeyVersion> {
        let access = access(generation, versions: versions)
        defer { access.invalidate() }
        let snapshot = try await gate.run(generation) { try await session.scan(access: access) }
        return try snapshot.requiredVersions()
    }

    public func removePendingCandidate(_ version: KeyVersion) async throws {
        try await serialized { ring, generation, session in
            let loaded = try await ring.load(generation, session)
            guard loaded.state.pendingCandidates.contains(version) else { throw KeyringError.invalidVersion }
            let access = ring.access(generation, versions: loaded.state.metadata.versions)
            defer { access.invalidate() }
            try await ring.gate.run(generation) { try await session.recoverAndReconcile(access: access) }
            let required = try await ring.scan(session, generation, versions: loaded.state.metadata.versions)
            guard !required.contains(version) else { throw KeyringError.versionReferenced(version) }
            guard required.isSubset(of: loaded.state.metadata.versions) else { throw KeyringError.unknownReferences }
            try await ring.delete(version, generation)
        }
    }
}

import Foundation
import KeyRecordCore

extension KeychainKeyring {
    public func rotate(to version: KeyVersion) async throws {
        try await serialized { ring, generation, session in
            let loaded = try await ring.load(generation, session)
            let previous = loaded.state.metadata
            guard previous.rotation == nil else { throw KeyringError.busy }
            guard version.rawValue > previous.current.rawValue else { throw KeyringError.invalidVersion }
            guard loaded.state.pendingCandidates.isSubset(of: [version])
            else { throw KeyringError.unpublishedCandidates(loaded.state.pendingCandidates) }
            if !loaded.state.pendingCandidates.contains(version) { try await ring.add(version, generation) }
            let rotation = KeyRotation(from: previous.current, to: version)
            let next = KeyringMetadata(current: version, versions: [previous.current, version], rotation: rotation)
            try await ring.publish(next, expected: loaded.bytes, generation)
            // Read the exact durable bytes for subsequent CAS; never roll back a possibly committed publication.
            let published = try await ring.load(generation, session)
            try await ring.finishRotation(published, generation, session)
        }
    }

    public func resumeRotation() async throws {
        try await serialized { ring, generation, session in
            let loaded = try await ring.load(generation, session)
            try await ring.finishRotation(loaded, generation, session)
        }
    }

    func finishRotation(_ loaded: Loaded, _ generation: CaptureGeneration,
                        _ session: any ProtectedReferenceSession) async throws {
        let metadata = loaded.state.metadata
        guard let rotation = metadata.rotation else { return }
        let access = access(generation, versions: metadata.versions)
        defer { access.invalidate() }
        var expected = loaded.bytes
        if metadata.retirementPending.isEmpty {
            try await gate.run(generation) { try await session.migrateData(rotation, access: access) }
            try await gate.run(generation) { try await session.reencryptManifestAndJournals(rotation, access: access) }
            try await gate.run(generation) { try await session.recoverAndReconcile(access: access) }
            try await proveRetirable(rotation.from, versions: metadata.versions, session, generation)
            let pending = KeyringMetadata(current: metadata.current, versions: metadata.versions,
                                          retirementPending: [rotation.from], rotation: rotation)
            try await publish(pending, expected: expected, generation)
            guard let bytes = try await readMetadata(generation), try KeyringMetadata.decode(bytes) == pending
            else { throw KeyringError.metadataConflict }
            expected = bytes
        } else {
            // Recovery never trusts a pre-crash scan, even if exact deletion already happened.
            try await proveRetirable(rotation.from, versions: metadata.versions, session, generation)
        }
        try await delete(rotation.from, generation)
        let final = KeyringMetadata(current: metadata.current, versions: [metadata.current])
        try await publish(final, expected: expected, generation)
    }

    func proveRetirable(_ version: KeyVersion, versions: Set<KeyVersion>,
                        _ session: any ProtectedReferenceSession, _ generation: CaptureGeneration) async throws {
        let required = try await scan(session, generation, versions: versions.subtracting([version]))
        guard !required.contains(version) else { throw KeyringError.versionReferenced(version) }
        guard required.isSubset(of: versions) else { throw KeyringError.unknownReferences }
        for retained in versions.subtracting([version]) { _ = try await material(retained, generation) }
    }
}

import Foundation
import KeyRecordCore

extension ObjectStore {
    func recoverManifest(requiredVersions versions: Set<KeyVersion>) async throws
        -> (manifest: EncryptedManifest, encryptionKeyVersion: UInt32) {
        let bytes: Data
        do {
            bytes = try fileSystem.readWholeFile(name: ManifestDiscovery.fileName, in: root)
        } catch {
            throw ObjectStoreError.corruption(.manifestMissing)
        }
        let parsed: ParsedStorageEnvelope
        do { parsed = try AuthenticatedStorageEnvelope.parse(bytes) }
        catch { throw ObjectStoreError.corruption(.manifestUnreadable) }
        guard versions.contains(KeyVersion(rawValue: parsed.header.keyVersion)) else {
            throw ObjectStoreError.corruption(.envelopeKeyMissing)
        }
        let material: Data
        do { material = try await keySource.material(for: KeyVersion(rawValue: parsed.header.keyVersion)) }
        catch { throw ObjectStoreError.corruption(.envelopeKeyMissing) }
        do {
            return try EncryptedManifest.open(envelope: bytes,
                                              materialByVersion: [parsed.header.keyVersion: material])
        } catch ManifestError.unknownSchemaVersion {
            throw ObjectStoreError.corruption(.unknownManifestSchemaVersion)
        } catch let error as ManifestError {
            throw ObjectStoreError.manifest(error)
        } catch {
            throw ObjectStoreError.corruption(.manifestUnreadable)
        }
    }

    func validateReferencedFiles(_ manifest: EncryptedManifest) throws {
        for entry in manifest.entries {
            let bytes: Data
            do {
                bytes = try fileSystem.readWholeFile(name: entry.locator.fileName, in: root)
            } catch FileSystemError.notRegularFile, FileSystemError.posix(operation: "open(no-follow)", code: ELOOP) {
                throw ObjectStoreError.corruption(.symlinkEncountered)
            } catch FileSystemError.posix(operation: "open(no-follow)", code: ENOENT) {
                throw ObjectStoreError.corruption(.referencedObjectMissing)
            } catch {
                throw ObjectStoreError.corruption(.manifestUnreadable)
            }
            guard let material = materialCache[entry.keyVersion] else {
                throw ObjectStoreError.corruption(.envelopeKeyMissing)
            }
            do {
                _ = try LocatorCodec.open(envelope: bytes, requested: entry.identity,
                                          materialByVersion: [entry.keyVersion: material])
            } catch {
                throw ObjectStoreError.corruption(.manifestUnreadable)
            }
        }
    }

    func loadMaterial(_ versions: Set<UInt32>, known: Set<KeyVersion>) async throws {
        for raw in versions {
            if materialCache[raw] != nil { continue }
            let version = KeyVersion(rawValue: raw)
            guard known.contains(version) else { throw ObjectStoreError.corruption(.envelopeKeyMissing) }
            materialCache[raw] = try await keySource.material(for: version)
        }
    }

    func reconcileUnreferenced(_ entries: [(RootEntry, RootEntryClassification)],
                               referenced: Set<ObjectLocator>,
                               known: Set<KeyVersion>) async throws {
        var materials = [UInt32: Data]()
        for version in known {
            if let material = try? await keySource.material(for: version) {
                materials[version.rawValue] = material
            }
        }
        for (entry, classification) in entries {
            if case .locator(let locator) = classification, referenced.contains(locator) { continue }
            let proven = try isProvenOwned(entry.name, materials: materials)
            if proven {
                try fileSystem.removeFile(name: entry.name, in: root)
            } else {
                unresolvedArtifacts.append(entry.name)
            }
        }
    }

    private func isProvenOwned(_ name: String, materials: [UInt32: Data]) throws -> Bool {
        guard let bytes = try? fileSystem.readWholeFile(name: name, in: root),
              let parsed = try? AuthenticatedStorageEnvelope.parse(bytes),
              materials[parsed.header.keyVersion] != nil,
              (try? LocatorCodec.authenticate(envelope: bytes, materialByVersion: materials)) != nil
        else { return false }
        return true
    }
}

import Foundation
import KeyRecordCore

/// Real filesystem adapter for explicit destruction. Foundation/POSIX only: lstat-based
/// enumeration reuses `AtomicFileSystem`, removals are no-follow unlink/rmdir and never
/// recurse. Symlinks and non-directory specials block planning instead of being removed.
public struct FileSystemDeletionAdapter: DeletionFileSystem {
    private let fileSystem = AtomicFileSystem()

    public init() {}

    public func listOwnedEntries(ownedRoot: String) throws -> [DeletionEntry] {
        let root = URL(fileURLWithPath: ownedRoot)
        var rootStatus = stat()
        guard lstat(root.path, &rootStatus) == 0 else {
            if errno == ENOENT { return [] }
            throw FileSystemError.posix(operation: "lstat(root)", code: errno)
        }
        switch rootStatus.st_mode & S_IFMT {
        case S_IFLNK: throw FileSystemError.rootSymlink
        case S_IFDIR: break
        default: throw FileSystemError.rootNotDirectory
        }
        return try fileSystem.listEntries(in: root).map { Self.classify($0, root: root) }
    }

    public func removeOwnedEntry(_ entry: DeletionEntry) throws {
        var status = stat()
        guard lstat(entry.path, &status) == 0 else {
            if errno == ENOENT { return }
            throw DeletionError.ioFailure("lstat failed: \(entry.path)")
        }
        switch status.st_mode & S_IFMT {
        case S_IFLNK:
            // Planning already refuses symlinks; this guards a race-planted replacement.
            throw DeletionError.ioFailure("refusing symlink removal: \(entry.path)")
        case S_IFDIR:
            // rmdir only succeeds when empty, so foreign contents can never be recursively removed.
            if rmdir(entry.path) != 0, errno != ENOENT {
                throw DeletionError.ioFailure("rmdir failed: \(entry.path)")
            }
        default:
            let url = URL(fileURLWithPath: entry.path)
            try fileSystem.removeFile(
                name: url.lastPathComponent, in: url.deletingLastPathComponent())
        }
    }

    public func ownedRootExists(_ root: String) -> Bool {
        fileSystem.rootExists(URL(fileURLWithPath: root))
    }

    public func removeOwnedRootIfEmpty(_ root: String) throws {
        if rmdir(root) != 0, errno != ENOENT {
            throw DeletionError.ioFailure("rmdir root failed: \(root)")
        }
    }

    private static func classify(_ entry: RootEntry, root: URL) -> DeletionEntry {
        let path = root.appendingPathComponent(entry.name).path
        switch entry.kind {
        case .regular:
            // manifest.krenc, strict <64hex>.krenc locators and owned crash-safe temp
            // names are recognized; every other regular file is reported as unrecognized.
            let isKnown = RootEntryClassifier.classify(entry) != .foreign
            return DeletionEntry(path: path,
                                 kind: isKnown ? .ownedFile : .unrecognizedOwnedFile)
        case .symlink:
            return DeletionEntry(path: path, kind: .symlink)
        case .other:
            var status = stat()
            let isDirectory = lstat(path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFDIR
            return DeletionEntry(path: path, kind: isDirectory ? .directory : .foreignEntry)
        }
    }
}

/// Bridges the keyring's explicit-destruction API to the per-item `DeletionKeychain`
/// port. Item identifiers are `KeychainItemID.account` strings (`master-v<version>`);
/// the namespace metadata item is removed once every planned version is gone.
public actor KeychainDeletionAdapter: DeletionKeychain {
    private let keyring: KeychainKeyring
    private var plannedVersions: [String: KeyVersion] = [:]

    public init(keyring: KeychainKeyring) {
        self.keyring = keyring
    }

    public func ownedVersionedItemIDs() async throws -> [String] {
        let namespace = keyring.configuration.namespace
        let versions = try await keyring.destructionInventory()
        plannedVersions = .init(uniqueKeysWithValues: versions.map {
            (KeychainItemID.key(namespace, $0).account, $0)
        })
        return versions.map { KeychainItemID.key(namespace, $0).account }
    }

    public func deleteOwnedItem(_ id: String) async throws {
        guard let version = plannedVersions[id] else {
            throw DeletionError.ioFailure("unowned keychain item: \(id)")
        }
        let outcome = try await keyring.deleteOwnedVersionForDestruction(version)
        plannedVersions[id] = nil
        if plannedVersions.isEmpty {
            try await keyring.deleteOwnedMetadataForDestruction()
        }
        if case .missingKeyDuringDeletion = outcome {
            throw DeletionError.missingOwnedKey(id)
        }
    }
}

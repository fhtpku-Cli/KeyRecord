import Foundation
import KeyRecordCore

/// Typed corruption causes. Recovery never guesses or rebuilds: callers surface a generic
/// failure and only the explicit deletion flow (task 17) may consume these states.
public enum StoreCorruption: String, Error, Equatable, Sendable {
    case rootReplacedBySymlink
    case rootNotDirectory
    case insecureRoot
    case manifestMissing
    case manifestUnreadable
    case unknownManifestSchemaVersion
    case unexpectedEntry
    case symlinkEncountered
    case referencedObjectMissing
    case envelopeKeyMissing
    case unindexedDataWithNamespaceKey
}

public enum ObjectStoreError: Error, Equatable, Sendable {
    case storeNotInitialized
    case alreadyInitialized
    case unknownObject
    case corruption(StoreCorruption)
    case keyMissing(KeyVersion)
    case envelope(StorageEnvelopeError)
    case locator(LocatorCodecError)
    case manifest(ManifestError)
    case identity(LogicalIdentityError)
    case filesystem(FileSystemError)
}

public enum StoreBootstrapState: Equatable, Sendable {
    /// Private root is empty AND the namespace contains no key versions. No manifest is
    /// written until the caller proves consent and initializes a fresh installation.
    case freshInstall
    /// Manifest authenticated and reconciled; the store is ready.
    case opened
}

/// Namespace-key boundary the store consumes. Task 11's keyring owns SecItem access and
/// key lifecycle; the store never touches Keychain directly. Tests wire an in-memory fake;
/// production composition (task 14) bridges the keyring's protected material callbacks.
public protocol ObjectStoreKeySource: Sendable {
    /// Every key version currently visible in the namespace, including unpublished
    /// pending candidates. An empty set is the fresh-install witness.
    func namespaceKeyVersions() async throws -> Set<KeyVersion>
    func material(for version: KeyVersion) async throws -> Data
}

/// Reset/rotation journals are task 16. The store owns manifest and data-object references;
/// journals contribute their protected references through this seam so a complete
/// pre-retirement scan can block on an unreadable journal envelope.
public protocol StoreJournalRecoverySource: Sendable {
    /// Re-encrypt every unfinished journal envelope under the new key.
    func reencryptJournals(rotation: KeyRotation, access: KeyringProtectedAccess) async throws
    /// Protected references contributed by journals. `.unreadable` entries block retirement.
    func journalProtectedReferences(access: KeyringProtectedAccess) async throws -> [ProtectedReference]
}

/// A no-op journal source for the pre-task-16 store. An empty unfinished-journal set is
/// itself complete coverage; task 16 replaces this with the real journal enumeration.
public struct EmptyJournalRecoverySource: StoreJournalRecoverySource {
    public init() {}
    public func reencryptJournals(rotation: KeyRotation, access: KeyringProtectedAccess) async throws {}
    public func journalProtectedReferences(access: KeyringProtectedAccess) async throws -> [ProtectedReference] { [] }
}

/// Name classification for flat-private-root entries. Only the fixed manifest name, strict
/// `<64-lowerhex>.krenc` locator names and owned opaque temporary names are recognized.
public enum RootEntryClassification: Equatable, Sendable {
    case manifest
    case locator(ObjectLocator)
    case ownedTemporary
    case foreign
}

public enum RootEntryClassifier {
    public static func classify(_ entry: RootEntry) -> RootEntryClassification {
        switch entry.kind {
        case .symlink, .other:
            return .foreign
        case .regular:
            if entry.name == ManifestDiscovery.fileName { return .manifest }
            if let locator = try? ObjectLocator.parse(fileName: entry.name) { return .locator(locator) }
            if isOwnedTemporaryName(entry.name) { return .ownedTemporary }
            return .foreign
        }
    }

    static func isOwnedTemporaryName(_ name: String) -> Bool {
        let prefix = AtomicFileSystem.tempPrefix
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.utf8.count)
        return suffix.count == 10 && suffix.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
}

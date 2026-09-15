import Foundation
import KeyRecordCore

public enum KeyringError: Error, Equatable, Sendable {
    case locked, staleGeneration, busy, creationDenied, entropyDenied, duplicateItem
    case corruptMetadata, metadataConflict, invalidNamespace, invalidVersion, unknownReferences
    case liveQualificationBlocked
    /// Live backend rejected an operation for a non-enumerated infrastructure reason
    /// (e.g. an unmapped SecItem OSStatus). Carries no status or material payload.
    case backendUnavailable
    case missingKey(KeyVersion), corruptKey(KeyVersion), versionReferenced(KeyVersion)
    case unpublishedCandidates(Set<KeyVersion>)
}

public struct KeychainNamespace: Hashable, Sendable {
    public let service: String
    public init(_ service: String) throws {
        guard !service.isEmpty, service.utf8.count <= 128,
              service.utf8.allSatisfy({ $0 == 45 || $0 == 46 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) })
        else { throw KeyringError.invalidNamespace }
        self.service = service
    }
}

public struct KeychainItemID: Hashable, Sendable {
    public let namespace: KeychainNamespace
    public let version: KeyVersion?
    public var account: String { version.map { "master-v\($0.rawValue)" } ?? "metadata" }
    public static func key(_ namespace: KeychainNamespace, _ version: KeyVersion) -> Self {
        Self(namespace: namespace, version: version)
    }
    public static func metadata(_ namespace: KeychainNamespace) -> Self { Self(namespace: namespace, version: nil) }
}

public enum KeychainAccessibilityPolicy: Sendable {
    // Candidate only: task 7 must qualify the exact macOS environment before this can be frozen.
    case candidateWhenUnlockedThisDeviceOnly
}

public struct KeychainItem: Sendable {
    public let id: KeychainItemID
    public let material: Data
    public let policy: KeychainAccessibilityPolicy
    public let synchronizable = false
    public let dataProtection = true
}

public struct KeychainMetadataUpdate: Sendable {
    public let id: KeychainItemID
    public let expected: Data?
    public let replacement: Data
    public let policy: KeychainAccessibilityPolicy
    public let synchronizable = false
    public let dataProtection = true
}

/// Implementations must use exact service/account identities, no auth UI and no synchronizable fallback.
/// Publish is atomic compare-and-replace (nil means add-only); delete is exact and idempotent.
/// One backend/store writer owns a namespace. Unknown inventory accounts must throw, never be ignored.
public protocol KeychainBackend: Sendable {
    func read(_ id: KeychainItemID) async throws -> Data?
    func versions(in namespace: KeychainNamespace) async throws -> Set<KeyVersion>
    func add(_ item: KeychainItem) async throws
    func publish(_ update: KeychainMetadataUpdate) async throws
    func delete(_ id: KeychainItemID) async throws
}

public protocol MasterMaterialGenerating: Sendable { func generate() throws -> Data }
public protocol KeyringClock: Sendable { func now() -> Date }

public enum KeyringStoreState: Sendable { case fresh, existing, unknown }
public struct KeyringCreationState: Sendable {
    public let consent: Bool
    public let store: KeyringStoreState
    public let validUntil: Date
    public init(consent: Bool, store: KeyringStoreState, validUntil: Date = .distantFuture) {
        self.consent = consent; self.store = store; self.validUntil = validUntil
    }
}

/// Fresh means independently proven empty storage, not a missing or corrupt manifest.
public protocol KeyringCreationAuthorizing: Sendable {
    func creationState() async throws -> KeyringCreationState
}

public struct KeyringConfiguration: Sendable {
    public let namespace: KeychainNamespace
    public let accessibility: KeychainAccessibilityPolicy
    public init(namespace: KeychainNamespace, accessibility: KeychainAccessibilityPolicy = .candidateWhenUnlockedThisDeviceOnly) {
        self.namespace = namespace; self.accessibility = accessibility
    }
}

public struct KeyringPorts: Sendable {
    public let backend: any KeychainBackend
    public let entropy: any MasterMaterialGenerating
    public let creation: any KeyringCreationAuthorizing
    public let references: any ProtectedReferenceProviding
    public let clock: any KeyringClock

    public init(backend: any KeychainBackend, entropy: any MasterMaterialGenerating,
                creation: any KeyringCreationAuthorizing, references: any ProtectedReferenceProviding,
                clock: any KeyringClock) {
        self.backend = backend; self.entropy = entropy; self.creation = creation
        self.references = references; self.clock = clock
    }
}

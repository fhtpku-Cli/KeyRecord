import Foundation
import Security
import KeyRecordCore
import KeyRecordStore

struct LocalKeychainMatch {
    let status: OSStatus
    let value: CFTypeRef?
}

protocol LocalKeychainClient: Sendable {
    func copyMatching(_ query: [String: Any]) throws -> LocalKeychainMatch
    func add(_ attributes: [String: Any]) throws -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) throws -> OSStatus
    func delete(_ query: [String: Any]) throws -> OSStatus
}

struct SystemLocalKeychainClient: LocalKeychainClient {
    func copyMatching(_ query: [String: Any]) -> LocalKeychainMatch {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return LocalKeychainMatch(status: status, value: result)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

// Security invariants: exact service+account generic-password items in the data-protection
// keychain, kSecAttrSynchronizable false (no iCloud), this-device-only accessibility,
// kSecMatchLimitOne reads, no enumeration or prefix deletion, and key bytes are never
// logged. An unavailable data-protection keychain fails closed. Selection is
// controlled by the product's platform qualification or DEBUG developer armament.
struct LocalKeychainBackend: KeychainBackend {
    private let client: any LocalKeychainClient

    init(client: any LocalKeychainClient = SystemLocalKeychainClient()) {
        self.client = client
    }

    func read(_ id: KeychainItemID) async throws -> Data? {
        let identity = Self.identity(id)
        #if DEBUG
        let result = try ProtectedReadActivity.process.observe(.keychain) {
            try client.copyMatching(LocalKeychainQueries.queryForReadingData(identity: identity))
        }
        #else
        let result = try client.copyMatching(LocalKeychainQueries.queryForReadingData(identity: identity))
        #endif
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess else { throw Self.statusError(result.status) }
        guard let bytes = result.value as? Data else { throw Self.contentError(for: id) }
        return bytes
    }

    func versions(in namespace: KeychainNamespace) async throws -> Set<KeyVersion> {
        // Enumeration is forbidden. The exact metadata item is the inventory record;
        // strictly-incremental rotation strands at most one deterministically-named
        // candidate account, probed by exact query.
        guard let bytes = try await read(.metadata(namespace)) else {
            let first = KeyVersion(rawValue: 1)
            return (try await read(.key(namespace, first))) != nil ? [first] : []
        }
        let metadata = try KeyringMetadata.decode(bytes)
        var versions = metadata.versions
        if metadata.current.rawValue < UInt32.max {
            let candidate = KeyVersion(rawValue: metadata.current.rawValue + 1)
            if (try await read(.key(namespace, candidate))) != nil { versions.insert(candidate) }
        }
        return versions
    }

    func add(_ item: KeychainItem) async throws {
        try await add(id: item.id, data: item.material, policy: item.policy)
    }

    func publish(_ update: KeychainMetadataUpdate) async throws {
        guard let expected = update.expected else {
            try await add(id: update.id, data: update.replacement, policy: update.policy)
            return
        }
        // Compare-and-replace: verify the exact current bytes before replacing. One
        // writer owns the namespace, so the window is uncontended; any drift is a conflict.
        guard let current = try await read(update.id), current == expected
        else { throw KeyringError.metadataConflict }
        let identity = Self.identity(update.id)
        let attributes = LocalKeychainQueries.attributesForUpdate(
            data: update.replacement, accessible: Self.accessible(update.policy))
        let status = try client.update(identity, attributes: attributes)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeyringError.metadataConflict }
            throw Self.statusError(status)
        }
    }

    func delete(_ id: KeychainItemID) async throws {
        let status = try client.delete(Self.identity(id))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.statusError(status)
        }
    }

    private func add(id: KeychainItemID, data: Data, policy: KeychainAccessibilityPolicy) async throws {
        let identity = Self.identity(id)
        let attributes = LocalKeychainQueries.attributesForAdd(
            identity: identity, data: data, accessible: Self.accessible(policy))
        let status = try client.add(attributes)
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem { throw KeyringError.duplicateItem }
            throw Self.statusError(status)
        }
    }

    private static func identity(_ id: KeychainItemID) -> [String: Any] {
        LocalKeychainQueries.productIdentity(service: id.namespace.service, account: id.account)
    }

    private static func accessible(_ policy: KeychainAccessibilityPolicy) -> CFString {
        switch policy {
        case .candidateWhenUnlockedThisDeviceOnly:
            return LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly
        }
    }

    private static func statusError(_ status: OSStatus) -> KeyringError {
        status == errSecInteractionNotAllowed ? .locked : .backendUnavailable
    }

    private static func contentError(for id: KeychainItemID) -> KeyringError {
        id.version.map(KeyringError.corruptKey) ?? .corruptMetadata
    }
}

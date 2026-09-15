#if DEBUG
import Foundation
import Security
import KeyRecordCore
import KeyRecordStore

// REAL Security.framework backend, compiled only into DEBUG builds and selected only
// when KEYRECORD_LOCAL_CAPTURE=1 arms the local developer capture path. Security
// invariants: exact service+account generic-password items in the TRADITIONAL file
// keychain (data-protection keychain requires a paid provisioned access-group
// entitlement and returns errSecMissingEntitlement -34018 on a free account; local
// dev uses the file keychain under the same exact service namespace),
// kSecAttrSynchronizable false (no iCloud), this-device-only accessibility,
// kSecMatchLimitOne reads, no enumeration or prefix deletion, and key bytes are never
// logged. Release and non-armed Debug builds keep BlockedLiveKeychain.
struct LocalKeychainBackend: KeychainBackend {
    // DEBUG local dev always uses the traditional file keychain; ignore the
    // root-package dataProtection preference (which targets a paid entitlement).
    private static let usesDataProtectionKeychain = false

    func read(_ id: KeychainItemID) async throws -> Data? {
        let identity = Self.identity(id, dataProtection: Self.usesDataProtectionKeychain)
        var result: CFTypeRef?
        let status = SecItemCopyMatching(LocalKeychainQueries.queryForReadingData(identity: identity) as CFDictionary,
                                         &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Self.statusError(status) }
        guard let bytes = result as? Data else { throw Self.contentError(for: id) }
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
        let identity = Self.identity(update.id, dataProtection: Self.usesDataProtectionKeychain)
        let attributes = LocalKeychainQueries.attributesForUpdate(
            data: update.replacement, accessible: Self.accessible(update.policy))
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeyringError.metadataConflict }
            throw Self.statusError(status)
        }
    }

    func delete(_ id: KeychainItemID) async throws {
        let status = SecItemDelete(Self.identity(id, dataProtection: Self.usesDataProtectionKeychain) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.statusError(status)
        }
    }

    private func add(id: KeychainItemID, data: Data, policy: KeychainAccessibilityPolicy) async throws {
        let identity = Self.identity(id, dataProtection: Self.usesDataProtectionKeychain)
        let attributes = LocalKeychainQueries.attributesForAdd(
            identity: identity, data: data, accessible: Self.accessible(policy))
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem { throw KeyringError.duplicateItem }
            throw Self.statusError(status)
        }
    }

    private static func identity(_ id: KeychainItemID, dataProtection: Bool) -> [String: Any] {
        LocalKeychainQueries.identityQuery(service: id.namespace.service,
                                           account: id.account, dataProtection: dataProtection)
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
#endif

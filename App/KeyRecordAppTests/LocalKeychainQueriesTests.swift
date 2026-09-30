import Foundation
import Security
import XCTest
#if DEBUG
import KeyRecordCore
@testable import KeyRecordStore

final class MemoryLocalKeychainClient: LocalKeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private let forcedStatus: OSStatus?
    private var items: [String: Data] = [:]
    private var recordedQueries: [[String: Any]] = []
    var queries: [[String: Any]] { lock.withLock { recordedQueries } }

    init(forcedStatus: OSStatus? = nil) { self.forcedStatus = forcedStatus }

    private func identity(_ query: [String: Any]) -> String? {
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String else { return nil }
        return service + "/" + account
    }

    func copyMatching(_ query: [String: Any]) -> LocalKeychainMatch {
        lock.withLock {
            recordedQueries.append(query)
            if let forcedStatus { return .init(status: forcedStatus, value: nil) }
            guard let id = identity(query) else { return .init(status: errSecParam, value: nil) }
            guard let data = items[id] else { return .init(status: errSecItemNotFound, value: nil) }
            return .init(status: errSecSuccess, value: data as CFData)
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            recordedQueries.append(attributes)
            guard let id = identity(attributes), let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
            guard items[id] == nil else { return errSecDuplicateItem }
            items[id] = data
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            recordedQueries.append(query)
            guard let id = identity(query), let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
            guard items[id] != nil else { return errSecItemNotFound }
            items[id] = data
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            recordedQueries.append(query)
            guard let id = identity(query) else { return errSecParam }
            return items.removeValue(forKey: id) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}
#endif

@MainActor
final class LocalKeychainQueriesTests: XCTestCase {
    private let service = "com.keyrecord.app"

    #if DEBUG
    func testProductBackendCRUDInventoryAndConflictUseExactItems() async throws {
        let client = MemoryLocalKeychainClient()
        let backend = LocalKeychainBackend(client: client)
        let namespace = try KeychainNamespace("com.keyrecord.synthetic.backend")
        let other = try KeychainNamespace("com.keyrecord.synthetic.other")
        let first = KeyVersion(rawValue: 1), second = KeyVersion(rawValue: 2)
        let policy = KeychainAccessibilityPolicy.candidateWhenUnlockedThisDeviceOnly
        let material = Data(repeating: 0x42, count: 32)
        for id in [KeychainItemID.key(namespace, first), .key(namespace, second), .key(other, first)] {
            try await backend.add(KeychainItem(id: id, material: material, policy: policy))
        }
        let before = try KeyringMetadata(current: first, versions: [first]).encoded()
        let after = try KeyringMetadata(current: second, versions: [first, second],
                                        rotation: KeyRotation(from: first, to: second)).encoded()
        try await backend.publish(.init(id: .metadata(namespace), expected: nil, replacement: before, policy: policy))
        try await backend.publish(.init(id: .metadata(namespace), expected: before, replacement: after, policy: policy))
        do {
            try await backend.publish(.init(id: .metadata(namespace), expected: before, replacement: before, policy: policy))
            XCTFail("Stale metadata update succeeded")
        } catch { XCTAssertEqual(error as? KeyringError, .metadataConflict) }
        let metadata = try await backend.read(.metadata(namespace))
        XCTAssertTrue(metadata == after)
        let inventory = try await backend.versions(in: namespace)
        XCTAssertEqual(inventory, [first, second])
        XCTAssertTrue(client.queries.contains { $0[kSecAttrAccount as String] as? String == "master-v3" })
        for id in [KeychainItemID.key(namespace, first), .key(namespace, second), .metadata(namespace)] {
            try await backend.delete(id)
            try await backend.delete(id)
            let missing = try await backend.read(id)
            XCTAssertNil(missing)
        }
        let retained = try await backend.read(.key(other, first))
        XCTAssertTrue(retained == material)
        for query in client.queries {
            XCTAssertNotNil(query[kSecAttrAccount as String] as? String)
            XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
            XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String, kSecUseAuthenticationUIFail as String)
        }
    }

    func testProductBackendMapsUnavailableAndLockedReadsWithoutFallback() async throws {
        let namespace = try KeychainNamespace("com.keyrecord.synthetic.denied")
        for (status, expected) in [(errSecInteractionNotAllowed, KeyringError.locked),
                                   (errSecAuthFailed, KeyringError.backendUnavailable)] {
            let client = MemoryLocalKeychainClient(forcedStatus: status)
            let backend = LocalKeychainBackend(client: client)
            do {
                _ = try await backend.read(.metadata(namespace))
                XCTFail("Unavailable keychain read succeeded")
            } catch { XCTAssertEqual(error as? KeyringError, expected) }
            XCTAssertEqual(client.queries.count, 1)
        }
    }
    #endif

    func testIdentityQueryTargetsExactGenericPasswordItem() {
        // Given an exact service/account identity.
        let query = LocalKeychainQueries.identityQuery(service: service, account: "master-v7",
                                                       dataProtection: true)
        // When / Then: it matches one exact generic-password item, never a prefix or wildcard.
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, service)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "master-v7")
        XCTAssertFalse(query.values.contains { ($0 as? String) == "*" })
        XCTAssertFalse(query.keys.contains(kSecMatchLimitAll as String))
    }

    func testIdentityQueryDisablesSynchronizationAndSelectsKeychainByFlag() {
        for account in ["metadata", "master-v1"] {
            let dp = LocalKeychainQueries.identityQuery(service: service, account: account, dataProtection: true)
            XCTAssertEqual(dp[kSecAttrSynchronizable as String] as? Bool, false, account)
            XCTAssertEqual(dp[kSecUseDataProtectionKeychain as String] as? Bool, true, account)
            let file = LocalKeychainQueries.identityQuery(service: service, account: account, dataProtection: false)
            XCTAssertEqual(file[kSecAttrSynchronizable as String] as? Bool, false, account)
            XCTAssertNil(file[kSecUseDataProtectionKeychain as String], account)
        }
        let product = LocalKeychainQueries.productIdentity(service: service, account: "metadata")
        XCTAssertEqual(product[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertEqual(product[kSecAttrSynchronizable as String] as? Bool, false)
    }

    func testReadQueryReturnsDataForExactlyOneMatch() {
        // Given an identity.
        let identity = LocalKeychainQueries.identityQuery(service: service, account: "metadata",
                                                          dataProtection: true)
        // When building a read query.
        let query = LocalKeychainQueries.queryForReadingData(identity: identity)
        // Then: data return is requested with a one-item limit, never match-all.
        XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
        XCTAssertNotEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitAll as String)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "metadata")
    }

    func testProductOperationsFailInsteadOfOpeningAuthenticationUI() {
        let identity = LocalKeychainQueries.productIdentity(service: service, account: "master-v1")
        let queries = [identity,
            LocalKeychainQueries.queryForReadingData(identity: identity),
            LocalKeychainQueries.queryForReadingAttributes(identity: identity),
            LocalKeychainQueries.attributesForAdd(identity: identity, data: Data(count: 32),
                accessible: LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly)]
        for query in queries {
            XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String,
                kSecUseAuthenticationUIFail as String)
        }
    }

    func testAttributeInspectionDoesNotFilterOutIncorrectAccessibilityOrReadMaterial() {
        let identity = LocalKeychainQueries.productIdentity(service: service, account: "metadata")
        let query = LocalKeychainQueries.queryForReadingAttributes(identity: identity)
        XCTAssertEqual(query[kSecReturnAttributes as String] as? Bool, true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
        XCTAssertNil(query[kSecAttrAccessible as String])
        XCTAssertNil(query[kSecReturnData as String])
        XCTAssertEqual(query[kSecAttrService as String] as? String, service)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "metadata")
    }

    func testAddAttributesCarryExactMaterialAndDeviceOnlyAccessibility() throws {
        // Given 32 bytes of material (never asserted in body or logged here).
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        XCTAssertEqual(status, errSecSuccess)
        let identity = LocalKeychainQueries.identityQuery(service: service, account: "master-v1",
                                                          dataProtection: true)
        // When building add attributes.
        let attributes = LocalKeychainQueries.attributesForAdd(
            identity: identity, data: bytes,
            accessible: LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly)
        // Then: the exact item identity, material and this-device-only accessibility are present.
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, bytes)
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(attributes[kSecAttrService as String] as? String, service)
        XCTAssertEqual(attributes[kSecAttrAccount as String] as? String, "master-v1")
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(attributes[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }

    func testUpdateAttributesContainOnlyDataAndAccessibility() {
        // Given replacement metadata bytes.
        let replacement = Data([0x7b, 0x7d])
        // When building SecItemUpdate attributes.
        let attributes = LocalKeychainQueries.attributesForUpdate(
            data: replacement, accessible: LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly)
        // Then: only value and accessibility are updated; identity/class keys never ride along.
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, replacement)
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertNil(attributes[kSecClass as String])
        XCTAssertNil(attributes[kSecAttrService as String])
        XCTAssertNil(attributes[kSecAttrAccount as String])
    }

    func testAllBuildersRemainExactItemAndMatchLimitOneShaped() {
        // Given every exported builder.
        let identity = LocalKeychainQueries.identityQuery(service: service, account: "metadata",
                                                          dataProtection: true)
        let dictionaries = [
            identity,
            LocalKeychainQueries.queryForReadingData(identity: identity),
            LocalKeychainQueries.attributesForAdd(identity: identity, data: Data(count: 1),
                                                  accessible: LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly),
            LocalKeychainQueries.attributesForUpdate(data: Data(count: 1),
                                                     accessible: LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly),
        ]
        // When / Then: none can enumerate or wildcard-match keychain items.
        for dictionary in dictionaries {
            XCTAssertFalse(dictionary.keys.contains(kSecMatchLimitAll as String))
            XCTAssertFalse(dictionary.values.contains { ($0 as? String)?.contains("*") == true })
            XCTAssertFalse(dictionary.keys.contains("r_Attributes"))
        }
        let read = LocalKeychainQueries.queryForReadingData(identity: identity)
        XCTAssertEqual(read[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
    }
}

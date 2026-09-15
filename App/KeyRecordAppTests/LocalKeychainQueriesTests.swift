import Foundation
import Security
import XCTest

// Hostless tests for the pure SecItem query/attribute construction of the DEBUG-only
// LocalKeychainBackend. No SecItem function is called here; the real CRUD path is
// verified interactively in a signed Debug build.
final class LocalKeychainQueriesTests: XCTestCase {
    private let service = "com.keyrecord.app"

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
        // The pure builder supports both; the DEBUG LocalKeychainBackend uses the
        // traditional file keychain (false) because data-protection requires a paid
        // access-group entitlement (errSecMissingEntitlement -34018 on free accounts).
        for account in ["metadata", "master-v1"] {
            let dp = LocalKeychainQueries.identityQuery(service: service, account: account, dataProtection: true)
            XCTAssertEqual(dp[kSecAttrSynchronizable as String] as? Bool, false, account)
            XCTAssertEqual(dp[kSecUseDataProtectionKeychain as String] as? Bool, true, account)
            let file = LocalKeychainQueries.identityQuery(service: service, account: account, dataProtection: false)
            XCTAssertEqual(file[kSecAttrSynchronizable as String] as? Bool, false, account)
            XCTAssertNil(file[kSecUseDataProtectionKeychain as String], account)
        }
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

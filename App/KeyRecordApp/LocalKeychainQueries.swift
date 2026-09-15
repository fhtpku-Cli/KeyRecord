#if DEBUG
import Foundation
import Security

// Pure SecItem dictionary construction for LocalKeychainBackend. Every dictionary
// identifies one exact generic-password item (exact service + exact account); no
// match-all/wildcard/prefix builder exists. Material appears only as v_Data and is
// never logged. This file imports no KeyRecordStore type so the builders can be
// unit-tested in the hostless App test bundle.
enum LocalKeychainQueries {
    static var accessibleWhenUnlockedThisDeviceOnly: CFString {
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }

    static func identityQuery(service: String, account: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue }
        return query
    }

    static func attributesForAdd(identity: [String: Any], data: Data, accessible: CFString) -> [String: Any] {
        var attributes = identity
        attributes[kSecAttrAccessible as String] = accessible
        attributes[kSecValueData as String] = data
        return attributes
    }

    static func queryForReadingData(identity: [String: Any]) -> [String: Any] {
        var query = identity
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    static func attributesForUpdate(data: Data, accessible: CFString) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
    }
}
#endif

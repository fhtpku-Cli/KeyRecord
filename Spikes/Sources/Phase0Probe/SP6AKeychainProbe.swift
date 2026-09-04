import Darwin
import Foundation
import Phase0Support
import Security

enum SP6AKeychainProbe {
    static let servicePrefix = "com.keyrecord.phase0.sp6a."
    static let candidateAccounts = ["after-first-unlock", "when-unlocked"]

    static func command(arguments: [String]) throws {
        guard arguments.count == 4, arguments[0] == "sp6a-keychain", arguments[2] == "--service",
              arguments[3].hasPrefix(servicePrefix), arguments[3].count == servicePrefix.count + 36 else {
            throw ProbeError.usage
        }
        switch arguments[1] {
        case "cleanup":
            let status = deleteNamespace(arguments[3])
            guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else { throw SP6AKeychainError.lifecycleFailure }
            print("SP6A_KEYCHAIN_CLEANUP=PASS status=\(status) entitlementAvailable=\(status != errSecMissingEntitlement)")
        case "residue":
            let result = residueQuery(arguments[3])
            guard result.status == errSecItemNotFound, result.count == 0 else { throw SP6AKeychainError.lifecycleFailure }
            print("SP6A_KEYCHAIN_RESIDUE=PASS status=\(result.status) count=0")
        default: throw ProbeError.usage
        }
    }

    static func run(service: String = servicePrefix + UUID().uuidString.lowercased()) throws -> SP6AKeychainArtifact {
        guard service.hasPrefix(servicePrefix), service.count == servicePrefix.count + 36 else { throw SP6AKeychainError.invalidNamespace }
        let cleanup = SP6AKeychainSignalCleanup(service: service)
        let preCleanup = deleteNamespace(service)
        defer { _ = deleteNamespace(service); cleanup.complete() }
        if preCleanup == errSecMissingEntitlement {
            if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP6A_TEST_DELAY_WITH_KEYS"], let delay = Double(value) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            let residue = residueQuery(service)
            return SP6AKeychainArtifact(
                service: service, dataProtectionKeychain: true, preCleanupStatus: preCleanup, candidates: [],
                selection: nil, selectionVerdict: .blocked,
                selectionReason: "D9 is unavailable: the isolated data-protection Keychain namespace requires an application identifier entitlement not present on this SwiftPM runner.",
                hostLockAttempted: false, restartAttempted: false, crossDeviceRestoreVerdict: .blocked,
                crossDeviceRestoreReason: "No separately approved second-device backup/restore environment is available.",
                postCleanupStatus: errSecMissingEntitlement, residueQueryStatus: residue.status, residueCount: residue.count,
                keyBytesPersistedOutsideKeychain: false
            )
        }
        let configurations: [(String, String, CFString)] = [
            ("sp6a.keychainAfterFirstUnlock", candidateAccounts[0], kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly),
            ("sp6a.keychainWhenUnlocked", candidateAccounts[1], kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
        ]
        var candidates: [SP6AKeychainCandidate] = []
        for configuration in configurations {
            candidates.append(try exercise(service: service, legID: configuration.0, account: configuration.1, accessibility: configuration.2))
        }
        let postCleanup = deleteNamespace(service)
        let residue = residueQuery(service)
        guard candidates.allSatisfy({ candidatePassed($0) }), residue.status == errSecItemNotFound, residue.count == 0 else {
            throw SP6AKeychainError.lifecycleFailure
        }
        return SP6AKeychainArtifact(
            service: service, dataProtectionKeychain: true, preCleanupStatus: preCleanup, candidates: candidates,
            selection: nil, selectionVerdict: .inconclusive,
            selectionReason: "Unlocked add/read/attribute/delete observations cannot establish locked or background-after-first-unlock lifecycle behavior; host lock, logout, and restart are forbidden.",
            hostLockAttempted: false, restartAttempted: false, crossDeviceRestoreVerdict: .blocked,
            crossDeviceRestoreReason: "No separately approved second-device backup/restore environment is available.",
            postCleanupStatus: postCleanup, residueQueryStatus: residue.status, residueCount: residue.count,
            keyBytesPersistedOutsideKeychain: false
        )
    }

    static func deleteNamespace(_ service: String) -> OSStatus {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }

    static func residueQuery(_ service: String) -> (status: OSStatus, count: Int) {
        var query = baseQuery(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return (status, 0) }
        guard status == errSecSuccess else { return (status, -1) }
        if let values = result as? [[String: Any]] { return (status, values.count) }
        return (status, result == nil ? 0 : 1)
    }

    static func candidatePassed(_ value: SP6AKeychainCandidate) -> Bool {
        value.addStatus == errSecSuccess && value.readStatus == errSecSuccess && value.attributesStatus == errSecSuccess
            && value.deleteStatus == errSecSuccess && value.valueMatched && value.accessibilityMatched
            && value.synchronizableMatched && !value.synchronizable && !value.lifecycleEstablished
    }

    private static func exercise(service: String, legID: String, account: String, accessibility: CFString) throws -> SP6AKeychainCandidate {
        let key = randomBytes(count: 32)
        var add = baseQuery(service: service)
        add[kSecAttrAccount as String] = account
        add[kSecAttrAccessible as String] = accessibility
        add[kSecValueData as String] = key
        let addStatus = SecItemAdd(add as CFDictionary, nil)

        var read = baseQuery(service: service)
        read[kSecAttrAccount as String] = account
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        read[kSecReturnData as String] = true
        var readResult: CFTypeRef?
        let readStatus = SecItemCopyMatching(read as CFDictionary, &readResult)
        let valueMatched = (readResult as? Data) == key

        var attributes = baseQuery(service: service)
        attributes[kSecAttrAccount as String] = account
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        attributes[kSecReturnAttributes as String] = true
        var attributesResult: CFTypeRef?
        let attributesStatus = SecItemCopyMatching(attributes as CFDictionary, &attributesResult)
        let dictionary = attributesResult as? [String: Any]
        let observedAccessibility = dictionary?[kSecAttrAccessible as String] as? String
        let observedSynchronizable = dictionary?[kSecAttrSynchronizable as String] as? Bool

        if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP6A_TEST_DELAY_WITH_KEYS"], let delay = Double(value) {
            Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
        }
        var deletion = baseQuery(service: service)
        deletion[kSecAttrAccount as String] = account
        let deleteStatus = SecItemDelete(deletion as CFDictionary)
        return SP6AKeychainCandidate(
            legID: legID, account: account, accessibility: accessibility as String, synchronizable: false,
            addStatus: addStatus, readStatus: readStatus, attributesStatus: attributesStatus, deleteStatus: deleteStatus,
            valueMatched: valueMatched, accessibilityMatched: observedAccessibility == accessibility as String,
            synchronizableMatched: observedSynchronizable == false,
            lifecycleBehavior: "unlocked-add-read-attributes-delete-only; locked/background behavior not safely exercised",
            lifecycleEstablished: false
        )
    }

    private static func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess)
        return bytes
    }
}

enum SP6AKeychainError: Error { case invalidNamespace, lifecycleFailure }

private let errSecMissingEntitlement = OSStatus(-34018)

private final class SP6AKeychainSignalCleanup: @unchecked Sendable {
    private var sources: [DispatchSourceSignal] = []
    init(service: String) {
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler {
                _ = SP6AKeychainProbe.deleteNamespace(service)
                Foundation.exit(Int32(item.1))
            }
            source.resume(); sources.append(source)
        }
    }
    func complete() {
        sources.forEach { $0.cancel() }; sources.removeAll()
        signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL)
    }
}

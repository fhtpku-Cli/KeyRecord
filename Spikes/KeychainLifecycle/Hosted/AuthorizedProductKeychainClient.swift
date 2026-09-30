#if DEBUG
import Foundation
import Security
import LifecyclePreflight

struct AuthorizedProductKeychainClient: LocalKeychainClient {
    let namespace: ProbeNamespace
    let accounts: Set<String>
    let evidence: @Sendable () -> SignedEffectEvidence
    let client: any LocalKeychainClient

    init(attempt: URL, namespace: ProbeNamespace, accounts: Set<String>) {
        self.namespace = namespace
        self.accounts = accounts
        self.evidence = { SignedCandidateBackend.evidence(attempt: attempt) }
        self.client = SystemLocalKeychainClient()
    }

    init(namespace: ProbeNamespace, accounts: Set<String>, client: any LocalKeychainClient,
         evidence: @escaping @Sendable () -> SignedEffectEvidence) {
        self.namespace = namespace
        self.accounts = accounts
        self.client = client
        self.evidence = evidence
    }

    private func authorize(_ query: [String: Any]) throws {
        guard query[kSecClass as String] as? String == kSecClassGenericPassword as String,
              query[kSecAttrService as String] as? String == namespace.service,
              let account = query[kSecAttrAccount as String] as? String, accounts.contains(account),
              query[kSecUseDataProtectionKeychain as String] as? Bool == true,
              query[kSecAttrSynchronizable as String] as? Bool == false,
              query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String
        else { throw PreflightBlock.namespaceMismatch }
        switch SignedEffectGate.authorizeKeychain(namespace: namespace, evidence: evidence(), expectedNamespace: namespace) {
        case .ready: return
        case .blocked(let reason): throw reason
        }
    }

    func copyMatching(_ query: [String: Any]) throws -> LocalKeychainMatch {
        try authorize(query)
        return try client.copyMatching(query)
    }

    func add(_ attributes: [String: Any]) throws -> OSStatus {
        try authorize(attributes)
        guard attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        else { throw PreflightBlock.namespaceMismatch }
        return try client.add(attributes)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) throws -> OSStatus {
        try authorize(query)
        guard Set(attributes.keys) == [kSecValueData as String, kSecAttrAccessible as String],
              attributes[kSecValueData as String] is Data,
              attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        else { throw PreflightBlock.namespaceMismatch }
        return try client.update(query, attributes: attributes)
    }

    func delete(_ query: [String: Any]) throws -> OSStatus {
        try authorize(query)
        return try client.delete(query)
    }
}
#endif

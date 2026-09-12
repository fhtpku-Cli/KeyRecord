import CryptoKit
import Foundation
import LifecyclePreflight
import Security

// Compiled only into the hosted test bundle. No Q6 executable calls this adapter.
final class SignedCandidateBackend: CandidateBackend {
    private let attempt: URL
    private let namespace: ProbeNamespace
    private var value = Data()
    private(set) var calls = 0

    init(attempt: URL, seed: UUID) {
        self.attempt = attempt
        self.namespace = ProbeNamespace(attempt: attempt.lastPathComponent, seed: seed)
    }

    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        guard namespace == self.namespace else { throw PreflightBlock.namespace }
        let host = attempt.appendingPathComponent("build/lifecycle/Build/Products/Debug/KeychainLifecycleProbe.app")
        guard Bundle.main.bundleURL.resolvingSymlinksInPath() == host.resolvingSymlinksInPath(),
              Bundle(for: Self.self).bundleURL.resolvingSymlinksInPath() == host.appendingPathComponent("Contents/PlugIns/KeychainLifecycleTests.xctest").resolvingSymlinksInPath()
        else { throw PreflightBlock.signature }
        var runningCode: SecCode?
        guard SecCodeCopySelf([], &runningCode) == errSecSuccess, let runningCode,
              SecCodeCheckValidity(runningCode, [], nil) == errSecSuccess else { throw PreflightBlock.signature }
        var runningInfo: CFDictionary?
        var runningStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(runningCode, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopySigningInformation(runningStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &runningInfo) == errSecSuccess,
              let info = runningInfo as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first,
              let manifestBytes = try? Data(contentsOf: attempt.appendingPathComponent("host.json")),
              let manifest = try? JSONDecoder().decode(HostManifest.self, from: manifestBytes),
              info[kSecCodeInfoTeamIdentifier as String] as? String == manifest.teamID,
              info[kSecCodeInfoIdentifier as String] as? String == "com.keyrecord.phase1.probe.host",
              SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map({ String(format: "%02x", $0) }).joined() == manifest.certificateSHA256
        else { throw PreflightBlock.signature }
        switch LivePreflight.evaluate(manifestURL: attempt.appendingPathComponent("host.json"), attempt: attempt) {
        case .blocked(let reason): throw reason
        case .ready: break
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: namespace.service,
            kSecAttrAccount as String: "when-unlocked",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var result: CFTypeRef?
        let status: OSStatus
        var matched: Bool?
        switch operation {
        case .add:
            value = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
            query[kSecValueData as String] = value
            calls += 1
            status = SecItemAdd(query as CFDictionary, nil)
        case .read:
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            calls += 1
            status = SecItemCopyMatching(query as CFDictionary, &result)
            matched = (result as? Data) == value
        case .attributes:
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            calls += 1
            status = SecItemCopyMatching(query as CFDictionary, &result)
        case .delete:
            calls += 1
            status = SecItemDelete(query as CFDictionary)
            value.resetBytes(in: value.startIndex..<value.endIndex)
            value.removeAll()
        }
        let attributes = result as? [String: Any]
        return CandidateObservation(status: status, accessibility: attributes?[kSecAttrAccessible as String] as? String,
                                    synchronizable: attributes?[kSecAttrSynchronizable as String] as? Bool, valueMatched: matched)
    }
}

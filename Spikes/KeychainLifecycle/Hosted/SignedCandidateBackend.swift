import CryptoKit
import Foundation
import LifecyclePreflight
import Security

// Compiled only into the hosted test bundle. No Q6 executable calls this adapter.
final class SignedCandidateBackend: CandidateBackend {
    private let executor: SignedEffectExecutor
    var calls: Int { executor.calls }
    var denials: Int { executor.denials }
    var lastDenial: PreflightBlock? { executor.lastDenial }

    init(attempt: URL, seed: UUID) {
        executor = SignedEffectExecutor(namespace: ProbeNamespace(attempt: attempt.lastPathComponent, seed: seed),
                                        store: SecurityCandidateEffectStore()) { Self.evidence(attempt: attempt) }
    }

    init(namespace: ProbeNamespace, store: any CandidateEffectStore, evidence: @escaping () -> SignedEffectEvidence) {
        executor = SignedEffectExecutor(namespace: namespace, store: store, evidence: evidence)
    }

    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        try executor.perform(operation, namespace: namespace)
    }

    private static func evidence(attempt: URL) -> SignedEffectEvidence {
        let host = attempt.appendingPathComponent("build/lifecycle/Build/Products/Debug/KeychainLifecycleProbe.app")
        let tests = host.appendingPathComponent("Contents/PlugIns/KeychainLifecycleTests.xctest")
        let bundles = BundlePathMatch(host: Bundle.main.bundleURL.resolvingSymlinksInPath() == host.resolvingSymlinksInPath(),
                                      tests: Bundle(for: Self.self).bundleURL.resolvingSymlinksInPath() == tests.resolvingSymlinksInPath())
        let manifestURL = attempt.appendingPathComponent("host.json")
        let manifest: Result<HostManifest, PreflightBlock>
        if let bytes = try? Data(contentsOf: manifestURL) {
            if let decoded = try? JSONDecoder().decode(HostManifest.self, from: bytes) {
                manifest = .success(decoded)
            } else { manifest = .failure(.malformedManifest) }
        } else { manifest = .failure(.missingManifest) }
        return SignedEffectEvidence(identity: SignedEffectIdentity(bundles: bundles, runningCode: runningIdentity()),
                                    manifest: manifest, preflight: LivePreflight.evaluate(manifestURL: manifestURL, attempt: attempt))
    }

    private static func runningIdentity() -> RunningCodeIdentity {
        var runningCode: SecCode?
        guard SecCodeCopySelf([], &runningCode) == errSecSuccess, let runningCode,
              SecCodeCheckValidity(runningCode, [], nil) == errSecSuccess else { return .invalid }
        var runningInfo: CFDictionary?
        var runningStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(runningCode, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopySigningInformation(runningStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &runningInfo) == errSecSuccess,
              let info = runningInfo as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              let identifier = info[kSecCodeInfoIdentifier as String] as? String else { return .invalid }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        return .valid(RunningSigningIdentity(teamID: team, certificateSHA256: fingerprint, identifier: identifier))
    }
}

private final class SecurityCandidateEffectStore: CandidateEffectStore {
    func perform(_ request: CandidateEffectRequest) throws -> CandidateObservation {
        let query = request.foundationQuery as CFDictionary
        var result: CFTypeRef?
        let status: OSStatus
        var matched: Bool?
        switch request.operation {
        case .add:
            status = SecItemAdd(query, nil)
        case .read:
            status = SecItemCopyMatching(query, &result)
            matched = (result as? Data) == request.expectedValue
        case .attributes:
            status = SecItemCopyMatching(query, &result)
        case .delete:
            status = SecItemDelete(query)
        }
        let attributes = result as? [String: Any]
        return CandidateObservation(status: status, accessibility: attributes?[kSecAttrAccessible as String] as? String,
                                    synchronizable: attributes?[kSecAttrSynchronizable as String] as? Bool, valueMatched: matched)
    }
}

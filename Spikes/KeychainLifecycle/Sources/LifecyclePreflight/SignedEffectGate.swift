import Foundation

public struct BundlePathMatch: Sendable {
    public let host: Bool
    public let tests: Bool
    public init(host: Bool, tests: Bool) { self.host = host; self.tests = tests }
}

public struct RunningSigningIdentity: Sendable {
    public let teamID: String
    public let certificateSHA256: String
    public let identifier: String
    public init(teamID: String, certificateSHA256: String, identifier: String) {
        self.teamID = teamID; self.certificateSHA256 = certificateSHA256; self.identifier = identifier
    }
}

public enum RunningCodeIdentity: Sendable {
    case invalid
    case valid(RunningSigningIdentity)
}

public struct SignedEffectIdentity: Sendable {
    public let bundles: BundlePathMatch
    public let runningCode: RunningCodeIdentity
    public init(bundles: BundlePathMatch, runningCode: RunningCodeIdentity) {
        self.bundles = bundles; self.runningCode = runningCode
    }
}

public struct SignedEffectEvidence: Sendable {
    public let identity: SignedEffectIdentity
    public let manifest: Result<HostManifest, PreflightBlock>
    public let preflight: PreflightVerdict
    public init(identity: SignedEffectIdentity, manifest: Result<HostManifest, PreflightBlock>, preflight: PreflightVerdict) {
        self.identity = identity; self.manifest = manifest; self.preflight = preflight
    }
}

public struct SignedEffectIntent: Equatable, Sendable {
    public let operation: CandidateOperation
    public let namespace: ProbeNamespace
    public init(operation: CandidateOperation, namespace: ProbeNamespace) {
        self.operation = operation; self.namespace = namespace
    }
}

public enum SignedEffectDecision: Equatable, Sendable {
    case allow(SignedEffectIntent)
    case deny(PreflightBlock)
}

public enum SignedEffectGate {
    public static func evaluate(_ intent: SignedEffectIntent, evidence: SignedEffectEvidence,
                                expectedNamespace: ProbeNamespace) -> SignedEffectDecision {
        switch authorizeKeychain(namespace: intent.namespace, evidence: evidence, expectedNamespace: expectedNamespace) {
        case .ready: return .allow(intent)
        case .blocked(let reason): return .deny(reason)
        }
    }

    public static func authorizeKeychain(namespace: ProbeNamespace, evidence: SignedEffectEvidence,
                                         expectedNamespace: ProbeNamespace) -> PreflightVerdict {
        guard namespace == expectedNamespace else { return .blocked(.namespaceMismatch) }
        guard evidence.identity.bundles.host else { return .blocked(.bundleIDsMismatch) }
        guard evidence.identity.bundles.tests else { return .blocked(.bundleIDsMismatch) }
        let identity: RunningSigningIdentity
        switch evidence.identity.runningCode {
        case .invalid: return .blocked(.unavailableIdentity)
        case .valid(let value): identity = value
        }
        let manifest: HostManifest
        switch evidence.manifest {
        case .failure(let reason): return .blocked(reason)
        case .success(let value): manifest = value
        }
        guard identity.teamID == manifest.teamID else { return .blocked(.teamIDMismatch) }
        guard identity.certificateSHA256 == manifest.certificateSHA256 else { return .blocked(.certificateFingerprintMismatch) }
        guard identity.identifier == "com.keyrecord.phase1.probe.host" else { return .blocked(.bundleIDsMismatch) }
        switch evidence.preflight {
        case .blocked(let reason): return .blocked(reason)
        case .ready: break
        }
        guard manifest.operations.contains(.keychain) else { return .blocked(.operationAllowlistMismatch) }
        return .ready
    }
}

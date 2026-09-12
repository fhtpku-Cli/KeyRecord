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
        guard intent.namespace == expectedNamespace else { return .deny(.namespaceMismatch) }
        guard evidence.identity.bundles.host else { return .deny(.bundleIDsMismatch) }
        guard evidence.identity.bundles.tests else { return .deny(.bundleIDsMismatch) }
        let identity: RunningSigningIdentity
        switch evidence.identity.runningCode {
        case .invalid: return .deny(.unavailableIdentity)
        case .valid(let value): identity = value
        }
        let manifest: HostManifest
        switch evidence.manifest {
        case .failure(let reason): return .deny(reason)
        case .success(let value): manifest = value
        }
        guard identity.teamID == manifest.teamID else { return .deny(.teamIDMismatch) }
        guard identity.certificateSHA256 == manifest.certificateSHA256 else { return .deny(.certificateFingerprintMismatch) }
        guard identity.identifier == "com.keyrecord.phase1.probe.host" else { return .deny(.bundleIDsMismatch) }
        switch evidence.preflight {
        case .blocked(let reason): return .deny(reason)
        case .ready: break
        }
        switch intent.operation {
        case .add, .read, .attributes, .delete:
            guard manifest.operations.contains(.keychain) else { return .deny(.operationAllowlistMismatch) }
        }
        return .allow(intent)
    }
}

import Foundation
@testable import LifecyclePreflight

final class CandidateEffectRecorder: CandidateEffectStore {
    private(set) var requests: [CandidateEffectRequest] = []

    func perform(_ request: CandidateEffectRequest) throws -> CandidateObservation {
        requests.append(request)
        return CandidateObservation(status: 0, accessibility: nil, synchronizable: false, valueMatched: nil)
    }
}

struct SignedEffectFixture {
    var hostMatches = true
    var testsMatch = true
    var runningCode: RunningCodeIdentity = .valid(RunningSigningIdentity(
        teamID: "FIXTURETEAM", certificateSHA256: String(repeating: "a", count: 64),
        identifier: "com.keyrecord.phase1.probe.host"))
    var manifest: Result<HostManifest, PreflightBlock>
    var preflight: PreflightVerdict
    let expectedNamespace: ProbeNamespace
    var namespace: ProbeNamespace

    init() throws {
        let fixture = PreflightFixture()
        let data = try fixture.data()
        manifest = .success(try JSONDecoder().decode(HostManifest.self, from: data))
        preflight = Preflight.evaluate(data: data, context: fixture.context, now: Date(timeIntervalSince1970: 2_000_000_000))
        expectedNamespace = ProbeNamespace(attempt: fixture.context.attemptID, seed: UUID())
        namespace = expectedNamespace
    }

    var evidence: SignedEffectEvidence {
        SignedEffectEvidence(identity: SignedEffectIdentity(
            bundles: BundlePathMatch(host: hostMatches, tests: testsMatch), runningCode: runningCode),
            manifest: manifest, preflight: preflight)
    }
}

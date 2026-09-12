import Foundation
@testable import LifecyclePreflight

final class EffectCounter: CandidateBackend {
    var keychain = 0
    var controller = 0
    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        keychain += 1
        return CandidateObservation(status: 0, accessibility: nil, synchronizable: false, valueMatched: true)
    }
}

struct PreflightFixture {
    static func identity(entitled: Bool = true, signed: Bool = true) -> HostIdentity {
        HostIdentity(hostID: "fixture-host", architecture: "arm64", macOS: "26.6",
                     certificateSHA256: String(repeating: "a", count: 64), teamID: "FIXTURETEAM",
                     bundleIDs: ["com.keyrecord.phase1.probe.host", "com.keyrecord.phase1.probe.tests"],
                     signatureValid: signed, entitlementsValid: entitled)
    }
    var context: PreflightContext {
        PreflightContext(identity: Self.identity(), attemptID: "attempt-one", scratchRoot: "/fixture/attempt-one",
                         controllerSHA256: String(repeating: "d", count: 64), controllerExecutable: true)
    }
    func data(changing field: String? = nil, to value: String = "") throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": 1, "hostID": "fixture-host", "architecture": "arm64", "macOS": "26.6",
            "certificateSHA256": String(repeating: "a", count: 64), "teamID": "FIXTURETEAM",
            "bundleIDs": ["com.keyrecord.phase1.probe.host", "com.keyrecord.phase1.probe.tests"],
            "namespacePrefix": "com.keyrecord.phase1.probe.", "scratchRoot": "/fixture/attempt-one",
            "operations": HostOperation.allCases.map(\.rawValue), "expiresAt": "2034-01-01T00:00:00Z",
            "controllerPath": "/fixture/controller", "controllerSHA256": String(repeating: "d", count: 64),
            "attemptID": "attempt-one",
        ]
        if let field { object[field] = value }
        return try JSONSerialization.data(withJSONObject: object)
    }
    static func gatedEffects(data: Data?, context: PreflightContext, counter: EffectCounter, now: Date) throws -> PreflightVerdict {
        do {
            _ = try KeychainLifecycleProbe.exercise(backend: counter, namespace: ProbeNamespace(attempt: context.attemptID, seed: UUID())) {
                Preflight.evaluate(data: data, context: context, now: now)
            }
            return .ready
        } catch let reason as PreflightBlock { return .blocked(reason) }
    }
}

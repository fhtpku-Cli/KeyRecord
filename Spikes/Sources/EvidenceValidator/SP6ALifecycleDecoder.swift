import Foundation

enum SP6ALifecycleDecoder {
    static let sourcePaths: Set<String> = [
        "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/LifecycleScenario.swift",
        "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/LifecycleReceipt.swift",
        "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/SessionLockQualification.swift",
        "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/ObservedLockSignals.swift",
        "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/KeychainLifecycleProbe.swift",
        "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/SignedEffectGate.swift",
        "Spikes/KeychainLifecycle/Sources/LifecyclePreflight/SignedEffectExecutor.swift",
        "Spikes/KeychainLifecycle/Hosted/SignedCandidateBackend.swift",
        "Spikes/KeychainLifecycle/Hosted/HostedLifecycleScenarioController.swift",
        "Spikes/KeychainLifecycle/Hosted/KeychainLifecycleScenarioTests.swift",
    ]

    static func decode(_ bytes: Data, expectedSHA256: String? = nil) throws -> ReadinessReceipt {
        if let expectedSHA256, Canonical.sha256(bytes) != expectedSHA256 {
            throw ValidatorError("sp6a_receipt_hash_mismatch")
        }
        let r = try ReadinessDecoding.decode(ReadinessReceipt.self, from: bytes)
        let isSP6A = r.sourceFiles.contains { sourcePaths.contains($0.path) }
        guard isSP6A else { return r }
        guard ReadinessReceiptID.lifecycle.contains(r.id), !r.hostManifestPath.isEmpty,
              Set(r.sourceFiles.map(\.path)).isSubset(of: sourcePaths),
              r.sourceFiles.contains { sourcePaths.contains($0.path) },
              Set(r.assertions.map(\.id)) == Set(r.id.requiredAssertions), r.assertions.count == r.id.requiredAssertions.count,
              r.status == CurrentReadinessDeriver.aggregate(r.assertions.map(\.status)),
              r.executed == r.assertions.filter({ $0.status != .blocked }).count,
              r.failed == r.assertions.filter({ $0.status == .fail }).count, r.skipped == 0,
              ([r.producerControllerSHA256] + r.assertions.map(\.artifactSHA256) + r.sourceFiles.map(\.sha256)).allSatisfy({
                  $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
              }) else { throw ValidatorError("sp6a_invalid_lifecycle_contract") }
        return r
    }
}

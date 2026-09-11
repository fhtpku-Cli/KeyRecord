import Foundation
import Phase0Support

enum CurrentReadinessDeriver {
    static func aggregate(_ statuses: [ReadinessStatus]) -> ReadinessStatus {
        if statuses.contains(.fail) { return .fail }
        if statuses.isEmpty || statuses.contains(.blocked) { return .blocked }
        return .pass
    }

    static func derive(_ input: ReadinessInputs) throws -> CurrentReadiness {
        let g0 = try historicalG0(input)
        let lifecycle = receiptGate(ReadinessReceiptID.lifecycle, input.receipts)
        let implementation = receiptGate(ReadinessReceiptID.implementation, input.receipts)
        let g1 = aggregate([g0, lifecycle.status, implementation.status])
        let causes = (g0 == .pass ? [] : [ReadinessGateID.g0.rawValue])
            + (lifecycle.status == .pass ? [] : [ReadinessGateID.lifecycle.rawValue]) + implementation.causes
        let gates: [ReadinessGate] = [
            .init(id: .g0, title: "Verified historical G0 proof", status: g0, unresolvedCauses: g0 == .pass ? [] : ["historical.g0.proof"]),
            .init(id: .lifecycle, title: "SP6A local lifecycle qualification", status: lifecycle.status, unresolvedCauses: lifecycle.causes),
            .init(id: .implementation, title: "G1 implementation receipts", status: g1, unresolvedCauses: causes),
        ]
        return CurrentReadiness(schemaVersion: 1, historicalRoot: input.historicalRoot, lifecyclePath: input.lifecyclePath, bindings: input.bindings, historicalAssessment: input.historical, localLifecycleAssessment: lifecycle.status, gates: gates, retainedReleaseBlockers: input.historical?.downstreamBlocks.filter { $0.id != "G1" } ?? [])
    }

    private static func historicalG0(_ input: ReadinessInputs) throws -> ReadinessStatus {
        guard let history = input.historical else { return .blocked }
        guard history.schemaVersion == 1, history.spikes.map(\.id) == ConclusionContract.spikeIDs else {
            throw ValidatorError("readiness_invalid_history")
        }
        let blockerIDs = history.downstreamBlocks.map(\.id)
        guard Set(blockerIDs).count == blockerIDs.count,
              Set(ConclusionContract.downstreamBlockIDs).isSubset(of: blockerIDs) else {
            throw ValidatorError("readiness_invalid_retained_blockers")
        }
        let required = history.spikes.filter { $0.id == "SP-1" || $0.id == "SP-2" }
        for spike in required {
            guard spike.passCount >= 0, spike.failCount >= 0, spike.blockedCount >= 0, spike.inconclusiveCount >= 0,
                  spike.passCount + spike.failCount + spike.blockedCount + spike.inconclusiveCount > 0 else {
                throw ValidatorError("readiness_invalid_historical_counts")
            }
        }
        switch history.g0.status {
        case .passed:
            guard history.g0.reasons.isEmpty, history.g0.blockingLegIDs.isEmpty,
                  ["session", "annotated"].contains(history.g0.candidateSelection),
                  required.allSatisfy({ $0.verdict == .pass && $0.passCount > 0 }) else {
                throw ValidatorError("readiness_unearned_g0")
            }
        case .open:
            guard history.g0.candidateSelection == nil, !history.g0.blockingLegIDs.isEmpty else {
                throw ValidatorError("readiness_invalid_open_g0")
            }
        }
        // Missing expected bytes are incomplete proof (BLOCKED). Present failures
        // are FAIL; malformed identities and bindings are rejected at the boundary.
        let proofPaths = required.flatMap { ["\(input.historicalRoot)/\($0.evidence.path)", "\(input.historicalRoot)/\($0.evidence.manifestPath)"] }
        if !Set(proofPaths).isDisjoint(with: input.bindings.missingPaths) { return .blocked }
        guard let sp1 = input.sp1, let sp2 = input.sp2 else { return .blocked }
        try sp1.validate(); try sp2.validate()
        guard (history.g0.status == .open || sp1.selectedTapIdentity?.tapType == history.g0.candidateSelection),
              required.first(where: { $0.id == "SP-1" })?.verdict == sp1.verdict,
              required.first(where: { $0.id == "SP-2" })?.verdict == sp2.verdict else {
            throw ValidatorError("readiness_historical_proof_mismatch")
        }
        if required.contains(where: { $0.verdict == .fail }) { return .fail }
        switch history.g0.status { case .passed: return .pass; case .open: return .blocked }
    }

    private static func receiptGate(_ required: [ReadinessReceiptID], _ receipts: [ReadinessReceipt]) -> (status: ReadinessStatus, causes: [String]) {
        let statuses = required.map { id in receipts.first { $0.id == id }?.status ?? .blocked }
        let causes = zip(required, statuses).compactMap { $0.1 == .pass ? nil : "receipt.\($0.0.rawValue)" }
        return (aggregate(statuses), causes)
    }
}

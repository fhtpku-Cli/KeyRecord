import Foundation
import Phase0Support

public struct GateValidationReport: Equatable, Sendable {
    public let legCount: Int
    public let o4RowCount: Int
    public let g0Status: G0Status
}

public enum GateValidator {
    public static func validate(directory: URL) throws -> GateValidationReport {
        let documentURL = directory.appendingPathComponent("evidence.json")
        try requireRegularFile(documentURL, code: "missing_evidence_document")
        let document = try ValidatorDecoding.decode(
            GateEvidenceDocument.self,
            from: Data(contentsOf: documentURL),
            malformedCode: "malformed_evidence"
        )
        let environmentURL = directory.appendingPathComponent("environment.json")
        try requireRegularFile(environmentURL, code: "missing_environment_manifest")
        let environmentData = try Data(contentsOf: environmentURL)
        let detectors = try ValidatorDecoding.decode(DetectorManifest.self, from: environmentData, malformedCode: "malformed_environment_manifest")
        guard document.schemaVersion == 1 else { throw ValidatorError("unsupported_schema") }
        try validateLegs(document, detectors: detectors, environmentSha256: Canonical.sha256(environmentData))
        try validateO4(document.o4Rows)
        let aggregate = try validateSpikeResults(document)
        try validateDownstream(document, aggregate: aggregate)
        try validateDispositions(document.dispositions, sp2: aggregate["SP-2"])
        try validateG0(document, aggregate: aggregate)
        return GateValidationReport(legCount: document.legs.count, o4RowCount: document.o4Rows.count, g0Status: document.g0.status)
    }

    private static func validateLegs(_ document: GateEvidenceDocument, detectors: DetectorManifest, environmentSha256: String) throws {
        let detectorGroups = Dictionary(grouping: detectors.detectors, by: \DetectorResult.id)
        let detectorIDs = Set((0...12).map { "D\($0)" })
        guard !detectorGroups.contains(where: { $0.value.count > 1 }), Set(detectorGroups.keys) == detectorIDs else {
            throw ValidatorError("detector_set_mismatch")
        }
        let detectorValues = Dictionary(uniqueKeysWithValues: detectors.detectors.map { ($0.id, $0.available) })
        let grouped = Dictionary(grouping: document.legs, by: \GateLeg.legID)
        if let duplicate = grouped.first(where: { $0.value.count > 1 })?.key {
            throw ValidatorError("duplicate_leg_id", duplicate)
        }
        let actual = Set(grouped.keys)
        if let unknown = actual.subtracting(Phase0Registry.legIDs).sorted().first {
            throw ValidatorError("unknown_leg_id", unknown)
        }
        if let missing = Phase0Registry.legIDs.subtracting(actual).sorted().first {
            throw ValidatorError("missing_leg_id", missing)
        }
        guard Phase0Registry.legRules.count == 57, Phase0Registry.legIDs == Set(Phase0Registry.legRules.keys) else {
            throw ValidatorError("internal_registry_invalid")
        }
        for leg in document.legs {
            guard let rule = Phase0Registry.legRules[leg.legID] else { throw ValidatorError("unknown_leg_id", leg.legID) }
            guard leg.evidenceKind == rule.evidenceKind else { throw ValidatorError("wrong_evidence_kind", leg.legID) }
            guard leg.detectorID == rule.detectorID else { throw ValidatorError("wrong_detector_id", leg.legID) }
            try validateProvenance(leg)
            guard leg.environmentSha256 == environmentSha256 else { throw ValidatorError("environment_binding_mismatch", leg.legID) }
            guard detectorValues[leg.detectorID] == leg.detectorAvailable else { throw ValidatorError("detector_state_mismatch", leg.legID) }
            try validateVerdict(leg, allowsInconclusive: rule.allowsInconclusive)
            if leg.containsEventLevelData && (leg.evidenceKind != .synthetic || !leg.productStampedSynthetic) {
                throw ValidatorError(leg.evidenceKind == .live ? "live_event_data_forbidden" : "event_data_not_product_stamped", leg.legID)
            }
            if leg.productStampedSynthetic && leg.evidenceKind != .synthetic {
                throw ValidatorError("event_data_not_product_stamped", leg.legID)
            }
        }
        try validateSP1(document)
    }

    private static func validateProvenance(_ leg: GateLeg) throws {
        guard leg.environmentSha256.isLowercaseSHA256,
              leg.runnerCommitSha.isLowercaseGitSHA1,
              leg.runnerTreeSha.isLowercaseGitSHA1 else {
            throw ValidatorError("invalid_provenance", leg.legID)
        }
        var seen = Set<String>()
        for artifact in leg.artifacts {
            guard isSafeRelativePath(artifact.path), seen.insert(artifact.path).inserted else {
                throw ValidatorError("invalid_provenance", leg.legID)
            }
        }
    }

    private static func validateVerdict(_ leg: GateLeg, allowsInconclusive: Bool) throws {
        switch leg.verdict {
        case .blocked:
            guard !leg.detectorAvailable, leg.blocker != nil, leg.exitStatus == nil,
                  leg.command.isEmpty, leg.artifacts.isEmpty else {
                throw ValidatorError("invalid_verdict_semantics", leg.legID)
            }
        case .pass, .fail, .inconclusive:
            guard leg.detectorAvailable, leg.blocker == nil, leg.exitStatus != nil,
                  !leg.command.isEmpty, leg.command.allSatisfy({ !$0.isEmpty }), !leg.artifacts.isEmpty else {
                throw ValidatorError(leg.verdict == .pass ? "unsupported_pass" : "invalid_verdict_semantics", leg.legID)
            }
            if leg.verdict == .pass && leg.exitStatus != 0 { throw ValidatorError("unsupported_pass", leg.legID) }
            if leg.verdict == .inconclusive && !allowsInconclusive { throw ValidatorError("inconclusive_not_allowed", leg.legID) }
        }
    }

    private static func validateSP1(_ document: GateEvidenceDocument) throws {
        let identity = document.selectedTapIdentity
        guard [identity.tapType, identity.attemptID].allSatisfy({ !$0.isEmpty }),
              identity.runnerCommitSha.isLowercaseGitSHA1,
              identity.runnerTreeSha.isLowercaseGitSHA1,
              identity.environmentSha256.isLowercaseSHA256,
              identity.tapConfigSha256.isLowercaseSHA256 else {
            throw ValidatorError("mixed_sp1_identity")
        }
        let byID = Dictionary(uniqueKeysWithValues: document.legs.map { ($0.legID, $0) })
        let passingTaps = Phase0Registry.selectedTapLegIDs.compactMap { id in byID[id]?.verdict == .pass ? byID[id] : nil }
        guard passingTaps.count == 1, let selected = passingTaps.first else { throw ValidatorError("invalid_sp1_selection") }
        guard selected.tapIdentity == document.selectedTapIdentity,
              selected.legID.contains(document.selectedTapIdentity.tapType) else {
            throw ValidatorError("mixed_sp1_identity", selected.legID)
        }
        let identityIDs = Phase0Registry.identityBoundSP1LegIDs.union([selected.legID])
        var artifactPaths = Set<String>()
        var artifactHashes = Set<String>()
        for id in identityIDs.sorted() {
            guard let leg = byID[id], leg.verdict == .pass, leg.tapIdentity == document.selectedTapIdentity else {
                throw ValidatorError("mixed_sp1_identity", id)
            }
            guard leg.runnerCommitSha == document.selectedTapIdentity.runnerCommitSha,
                  leg.runnerTreeSha == document.selectedTapIdentity.runnerTreeSha,
                  leg.environmentSha256 == document.selectedTapIdentity.environmentSha256 else {
                throw ValidatorError("mixed_sp1_identity", id)
            }
            for artifact in leg.artifacts {
                guard artifactPaths.insert(artifact.path).inserted,
                      artifactHashes.insert(artifact.sha256).inserted else {
                    throw ValidatorError("reused_sp1_evidence", artifact.path)
                }
            }
        }
    }

    private static func validateO4(_ rows: [O4ValidationRow]) throws {
        let grouped = Dictionary(grouping: rows, by: \O4ValidationRow.id)
        if grouped.contains(where: { $0.value.count > 1 }) { throw ValidatorError("duplicate_o4_id") }
        let actual = Set(grouped.keys)
        if !actual.subtracting(Phase0Registry.o4IDs).isEmpty { throw ValidatorError("unknown_o4_id") }
        if actual != Phase0Registry.o4IDs { throw ValidatorError("missing_o4_id") }
        for row in rows {
            let hasEvidence = !row.evidencePaths.isEmpty
            let hasBlocker = row.blocker != nil
            guard hasEvidence != hasBlocker,
                  row.evidencePaths.allSatisfy(isSafeRelativePath) else { throw ValidatorError("invalid_o4_semantics", row.id) }
        }
    }

    private static func validateSpikeResults(_ document: GateEvidenceDocument) throws -> [String: Verdict] {
        let grouped = Dictionary(grouping: document.spikeResults, by: \SpikeResult.spikeID)
        if grouped.contains(where: { $0.value.count > 1 }) { throw ValidatorError("duplicate_spike_result") }
        guard Set(grouped.keys) == Phase0Registry.spikeIDs else { throw ValidatorError("spike_result_set_mismatch") }
        var calculated: [String: Verdict] = [:]
        for spike in Phase0Registry.spikeIDs {
            let legs = document.legs.filter { spikeID(for: $0.legID) == spike }
            let relevant: [GateLeg]
            if spike == "SP-1" {
                relevant = legs.filter { Phase0Registry.identityBoundSP1LegIDs.contains($0.legID) || $0.tapIdentity == document.selectedTapIdentity }
            } else {
                relevant = legs
            }
            let verdict = relevant.map(\.verdict).max(by: { precedence($0) < precedence($1) }) ?? .blocked
            calculated[spike] = verdict
            guard grouped[spike]?.first?.verdict == verdict else { throw ValidatorError("spike_aggregate_mismatch", spike) }
        }
        return calculated
    }

    private static func validateDownstream(_ document: GateEvidenceDocument, aggregate: [String: Verdict]) throws {
        let blocks = Dictionary(grouping: document.downstreamBlocks, by: \DownstreamBlock.id)
        guard !blocks.contains(where: { $0.value.count > 1 }) else { throw ValidatorError("duplicate_downstream_block") }
        let results = Dictionary(uniqueKeysWithValues: document.spikeResults.map { ($0.spikeID, $0) })
        var referenced = Set<String>()
        for (spike, verdict) in aggregate {
            guard let result = results[spike] else { throw ValidatorError("spike_result_set_mismatch") }
            if verdict == .pass {
                guard result.downstreamBlockIDs.isEmpty else { throw ValidatorError("unexpected_downstream_block", spike) }
            } else {
                guard !result.downstreamBlockIDs.isEmpty else { throw ValidatorError("missing_downstream_block", spike) }
                referenced.formUnion(result.downstreamBlockIDs)
            }
        }
        for disposition in document.dispositions { referenced.formUnion(disposition.blockerIDs) }
        guard referenced == Set(blocks.keys) else { throw ValidatorError("downstream_block_set_mismatch") }
        for block in document.downstreamBlocks {
            guard !block.id.isEmpty, !block.blockedCapability.isEmpty, !block.causedBy.isEmpty,
                  !block.unblockAction.isEmpty else { throw ValidatorError("incomplete_downstream_block", block.id) }
        }
    }

    private static func validateDispositions(_ values: [OItemDisposition], sp2: Verdict?) throws {
        let grouped = Dictionary(grouping: values, by: \OItemDisposition.id)
        guard !grouped.contains(where: { $0.value.count > 1 }), Set(grouped.keys) == Phase0Registry.oDispositionIDs else {
            throw ValidatorError("disposition_set_mismatch")
        }
        let expected = ["O1": "DEFERRED", "O2": "NO_PUBLIC_ACTION", "O3": "FUTURE_REAL_DEVICE", "O4": "EVIDENCE_OR_BLOCKED", "O5": "REPRESENTED", "O6": sp2 == .pass ? "RESOLVED" : "OPEN", "O7": "CONSERVATIVE"]
        for value in values {
            guard value.status == expected[value.id],
                  !value.evidencePaths.isEmpty || !value.blockerIDs.isEmpty,
                  value.evidencePaths.allSatisfy(isSafeRelativePath) else { throw ValidatorError("invalid_disposition", value.id) }
        }
    }

    private static func validateG0(_ document: GateEvidenceDocument, aggregate: [String: Verdict]) throws {
        guard let sp1 = aggregate["SP-1"], let sp2 = aggregate["SP-2"] else { throw ValidatorError("g0_mismatch") }
        let expectedStatus: G0Status = sp1 == .pass && sp2 == .pass ? .passed : .open
        let blocking = document.legs.filter { spikeID(for: $0.legID) == "SP-1" || spikeID(for: $0.legID) == "SP-2" }
            .filter { $0.verdict != .pass && !Phase0Registry.selectedTapLegIDs.contains($0.legID) }
            .map(\.legID).sorted()
        guard document.g0.status == expectedStatus, document.g0.sp1Verdict == sp1,
              document.g0.sp2Verdict == sp2, document.g0.blockingLegIDs == blocking else {
            throw ValidatorError("g0_mismatch")
        }
    }

    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }

    private static func spikeID(for legID: String) -> String {
        let prefix = legID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        switch prefix { case "sp4a": return "SP-4A"; case "sp4b": return "SP-4B"; case "sp5a": return "SP-5A"; case "sp5b": return "SP-5B"; case "sp6a": return "SP-6A"; case "sp6b": return "SP-6B"; default: return prefix.uppercased().replacingOccurrences(of: "SP", with: "SP-") }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") && !path.contains("\u{0}")
    }

    private static func requireRegularFile(_ url: URL, code: String) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { throw ValidatorError(code, url.path) }
    }
}

private extension String {
    var isLowercaseSHA256: Bool { utf8.count == 64 && utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    var isLowercaseGitSHA1: Bool { utf8.count == 40 && utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}

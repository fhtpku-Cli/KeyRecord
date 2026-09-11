import Foundation
import Phase0Support

enum SP1DirectoryValidator {
    private static let canonicalV1SyntheticSHA256 = "7238044654fbd6c081b5531f50ba8a095fd90e89e80edf9c6cb48a52f94ba518"
    private static let artifactNames: Set<String> = [
        "O7-ADDENDUM.md", "SP-1-CONCLUSION.md", "evidence.json",
        "live-aggregate-counts.json", "product-stamped-synthetic.json",
    ]

    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> GateValidationReport {
        let evidenceURL = directory.appendingPathComponent("evidence.json")
        guard isRegularFile(evidenceURL) else { throw ValidatorError("missing_evidence_document") }
        let evidence: SP1Evidence
        do { evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: evidenceURL)) }
        catch { throw ValidatorError("malformed_sp1_evidence", String(describing: error)) }
        let environmentURL = directory.deletingLastPathComponent().appendingPathComponent("environment.json")
        let environmentData = isRegularFile(environmentURL) ? try Data(contentsOf: environmentURL) : nil
        let candidateEnvironmentSha256 = environmentData.map(Canonical.sha256)
        var environmentEvidence: EnvironmentEvidence?
        if let environmentData {
            do { environmentEvidence = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData) }
            catch { throw ValidatorError("sp1_environment_malformed", String(describing: error)) }
        } else if evidence.schemaVersion == 2 || evidence.schemaVersion == 3 {
            throw ValidatorError("sp1_environment_missing")
        }
        if evidence.schemaVersion == 2 || evidence.schemaVersion == 3 {
            guard environmentEvidence?.guiSession.status == .available,
                  environmentEvidence?.listenEventAccess == .available,
                  environmentEvidence?.guiSession.tapCreate == .available else {
                throw ValidatorError(evidence.schemaVersion == 3 ? "sp1_v3_requires_d1" : "sp1_v2_requires_d1")
            }
        }
        do { try evidence.validate(candidateEnvironmentSha256: candidateEnvironmentSha256) }
        catch let error as SP1ValidationError { throw ValidatorError("sp1_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory, evidence: evidence)
        try validateArtifactBindings(evidence, directory: directory)
        if evidence.schemaVersion == 2, let environmentEvidence {
            try validateV2ArtifactSemantics(directory, evidence: evidence)
            try validateV2EnvironmentSemantics(evidence, environment: environmentEvidence)
        }
        if evidence.schemaVersion == 3, let environmentEvidence {
            try validateV3ArtifactSemantics(directory, evidence: evidence)
            try validateV3EnvironmentSemantics(evidence, environment: environmentEvidence)
        }
        try validateBlockerSemantics(evidence, environment: environmentEvidence)
        try validateNarratives(directory, evidence: evidence)
        try validateRunnerBinding(evidence, repository: repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: evidence.g0Status)
    }

    static func validateRunnerBinding(_ evidence: SP1Evidence, repository: URL) throws {
        guard let first = evidence.legs.first else { throw ValidatorError("sp1_runner_identity_missing") }
        let commitSha = evidence.selectedTapIdentity?.runnerCommitSha ?? first.runnerCommitSha
        let treeSha = evidence.selectedTapIdentity?.runnerTreeSha ?? first.runnerTreeSha
        guard Set(evidence.runnerSourceSha256.keys) == SP1RunnerBinding.sourcePaths else {
            throw ValidatorError("sp1_runner_source_set_mismatch")
        }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let commitCheck = try git.run(["cat-file", "-e", "\(commitSha)^{commit}"], acceptedStatuses: [0, 1, 128])
        guard commitCheck.status == 0 else { throw ValidatorError("sp1_runner_commit_missing") }
        let actualTree = try git.text(["rev-parse", "\(commitSha)^{tree}"])
        guard actualTree == treeSha else { throw ValidatorError("sp1_runner_tree_mismatch") }
        let ancestor = try git.run(["merge-base", "--is-ancestor", commitSha, "HEAD"], acceptedStatuses: [0, 1])
        guard ancestor.status == 0 else { throw ValidatorError("sp1_runner_not_ancestor") }

        for path in SP1RunnerBinding.sourcePaths.sorted() {
            let object = try git.run(["cat-file", "-e", "\(commitSha):\(path)"], acceptedStatuses: [0, 1, 128])
            guard object.status == 0 else { throw ValidatorError("sp1_runner_source_missing", path) }
            let committed = try git.run(["cat-file", "blob", "\(commitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else {
                throw ValidatorError("sp1_runner_source_hash_mismatch", path)
            }
            let workingURL = repository.appendingPathComponent(path)
            guard isRegularFile(workingURL) else { throw ValidatorError("sp1_runner_source_dirty", path) }
            if evidence.schemaVersion == 2 || evidence.schemaVersion == 3,
               Canonical.sha256(try Data(contentsOf: workingURL)) != evidence.runnerSourceSha256[path] {
                throw ValidatorError("sp1_runner_source_dirty", path)
            }
            let status = try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path])
            guard status.isEmpty else { throw ValidatorError("sp1_runner_source_dirty", path) }
        }
    }

    static func validateArtifacts(_ directory: URL, evidence: SP1Evidence) throws {
        let syntheticURL = directory.appendingPathComponent("product-stamped-synthetic.json")
        switch evidence.schemaVersion {
        case 1:
            try validateV1SyntheticArtifact(syntheticURL)
            if let leg = evidence.legs.first(where: { $0.verdict != .blocked }) {
                throw ValidatorError("sp1_synthetic_pass_unsupported", leg.legID)
            }
        case 2, 3:
            let actual = try bytes(syntheticURL, code: "sp1_synthetic_recompute_mismatch")
            let recomputed = try SP1SyntheticScenarios.run()
            guard actual == (try recomputed.canonicalJSON()) else {
                throw ValidatorError("sp1_synthetic_recompute_mismatch")
            }
        default:
            throw ValidatorError("sp1_unsupported_schema_version")
        }
        let live = try validateLiveArtifact(directory.appendingPathComponent("live-aggregate-counts.json"))
        if evidence.schemaVersion == 1 || evidence.schemaVersion == 2,
           live.systemShortcutObservedCount != 0 || live.unmarkedObservedCount != 0 {
            throw ValidatorError("sp1_live_semantics_invalid")
        }
    }

    static func validateArtifactBindings(_ evidence: SP1Evidence, directory: URL) throws {
        var liveHashes = Set<String>()
        for leg in evidence.legs where leg.verdict != .blocked {
            let synthetic = syntheticLegIDs.contains(leg.legID)
            let url = directory.appendingPathComponent(synthetic ? "product-stamped-synthetic.json" : "live-aggregate-counts.json")
            guard isRegularFile(url), let data = try? Data(contentsOf: url) else {
                throw ValidatorError("sp1_artifact_missing", leg.legID)
            }
            let actual = Canonical.sha256(data)
            guard leg.artifactSha256 == actual else { throw ValidatorError("sp1_artifact_hash_mismatch", leg.legID) }
            if !synthetic {
                if evidence.schemaVersion < 3, !liveHashes.insert(actual).inserted {
                    throw ValidatorError("sp1_reused_artifact_hash", leg.legID)
                }
            }
        }
    }

    private static let syntheticLegIDs: Set<String> = ["sp1.autoRepeat", "sp1.o7Boundary", "sp1.productStampedDrop", "sp1.tapReset"]

    private static func validateV1SyntheticArtifact(_ url: URL) throws {
        let actual = try bytes(url, code: "sp1_malformed_product_marker")
        guard Canonical.sha256(actual) == canonicalV1SyntheticSHA256, actual == SP1CanonicalArtifacts.v1Synthetic else {
            throw ValidatorError("sp1_malformed_product_marker")
        }
        let synthetic = try jsonObject(url, code: "sp1_malformed_product_marker")
        guard let object = synthetic as? [String: Any], Set(object.keys) == ["evidenceKind", "productStampedSynthetic", "records"],
              object["evidenceKind"] as? String == EvidenceKind.synthetic.rawValue,
              object["productStampedSynthetic"] as? Bool == true,
              let records = object["records"] as? [[String: Any]], records.count == InputEventKind.allCases.count else {
            throw ValidatorError("sp1_malformed_product_marker")
        }
        var kinds = Set<String>()
        for record in records {
            guard Set(record.keys) == ["dropped", "isAutoRepeat", "keyCode", "kind", "marker"],
                  record["dropped"] as? Bool == true,
                  record["isAutoRepeat"] is Bool,
                  record["keyCode"] is NSNumber,
                  let marker = record["marker"] as? NSNumber, marker.uint64Value == ProductSyntheticMarker.value,
                  let kind = record["kind"] as? String, InputEventKind(rawValue: kind) != nil,
                  kinds.insert(kind).inserted else { throw ValidatorError("sp1_malformed_product_marker") }
        }
    }

    private static func validateLiveArtifact(_ url: URL) throws -> SP1LiveAggregateArtifact {
        let data = try bytes(url, code: "sp1_live_event_detail_forbidden")
        guard let live = try? JSONDecoder().decode(SP1LiveAggregateArtifact.self, from: data),
              live.evidenceKind == .live,
              live.systemShortcutObservedCount >= 0,
              live.unmarkedObservedCount >= 0 else {
            throw ValidatorError("sp1_live_event_detail_forbidden")
        }
        return live
    }

    private static func validateV2SyntheticSemantics(_ evidence: SP1Evidence, assertions: [SP1SyntheticAssertion], artifactHash: String) throws {
        let assertionByID = Dictionary(uniqueKeysWithValues: assertions.map { ($0.legID, $0.passed) })
        guard Set(assertionByID.keys) == syntheticLegIDs else { throw ValidatorError("sp1_synthetic_recompute_mismatch") }
        for leg in evidence.legs where syntheticLegIDs.contains(leg.legID) {
            let identityOK = evidence.schemaVersion < 3 || evidence.selectedTapIdentity == nil
                ? leg.identity == nil
                : leg.identity == evidence.selectedTapIdentity
            guard let passed = assertionByID[leg.legID],
                  leg.verdict == (passed ? .pass : .fail), leg.detectorAvailable,
                  leg.blocker == nil, identityOK, leg.matrix == nil, leg.aggregateCount == nil,
                  leg.artifactSha256 == artifactHash else {
                throw ValidatorError("sp1_synthetic_assertion_leg_mismatch", leg.legID)
            }
        }
    }

    private static func validateV2ArtifactSemantics(_ directory: URL, evidence: SP1Evidence) throws {
        let synthetic = try SP1SyntheticScenarios.run()
        let syntheticData = try bytes(directory.appendingPathComponent("product-stamped-synthetic.json"), code: "sp1_synthetic_recompute_mismatch")
        try validateV2SyntheticSemantics(evidence, assertions: synthetic.assertions, artifactHash: Canonical.sha256(syntheticData))
        let live = try validateLiveArtifact(directory.appendingPathComponent("live-aggregate-counts.json"))
        try validateV2LiveSemantics(evidence, live: live)
    }

    private static func validateV2LiveSemantics(_ evidence: SP1Evidence, live: SP1LiveAggregateArtifact) throws {
        guard live.systemShortcutObservedCount == 0, live.unmarkedObservedCount == 0,
              let shortcut = evidence.legs.first(where: { $0.legID == "sp1.systemShortcut" }),
              shortcut.verdict == .blocked, !shortcut.detectorAvailable,
              shortcut.blocker == SP1CanonicalBlockers.systemShortcutExecutionNotImplemented,
              shortcut.identity == nil, shortcut.artifactSha256 == nil,
              shortcut.matrix == nil, shortcut.aggregateCount == nil else {
            throw ValidatorError("sp1_live_semantics_invalid")
        }
        for leg in evidence.legs where matrixLegIDs.contains(leg.legID) {
            guard leg.verdict == .blocked, !leg.detectorAvailable, leg.blocker?.complete == true,
                  leg.identity == nil, leg.artifactSha256 == nil, leg.matrix == nil, leg.aggregateCount == nil else {
                throw ValidatorError("sp1_matrix_semantics_invalid", leg.legID)
            }
        }
    }

    private static func validateV2EnvironmentSemantics(_ evidence: SP1Evidence, environment: EnvironmentEvidence) throws {
        let karabinerInstalled = environment.applications.contains { $0.name == "Karabiner-Elements" && $0.status == .installed }
        let expected = karabinerInstalled ? SP1CanonicalBlockers.v2MatrixExecutionNotImplemented : SP1CanonicalBlockers.v2KarabinerAbsent
        for leg in evidence.legs where matrixLegIDs.contains(leg.legID) {
            guard leg.blocker == expected else { throw ValidatorError("sp1_matrix_blocker_invalid", leg.legID) }
        }
    }

    private static func validateBlockerSemantics(_ evidence: SP1Evidence, environment: EnvironmentEvidence?) throws {
        switch evidence.schemaVersion {
        case 1:
            let d1Failure = environment.flatMap(SP1CanonicalBlockers.d1Failure(for:)) ?? (environment == nil ? SP1CanonicalBlockers.d1 : nil)
            let karabinerAbsent = environment.map {
                !$0.applications.contains { $0.name == "Karabiner-Elements" && $0.status == .installed }
            } ?? true
            let matrix = environment.map { SP1CanonicalBlockers.legacyV1Matrix(environment: $0, karabinerAbsent: karabinerAbsent) }
                ?? SP1CanonicalBlockers.legacyV1Matrix(inputMonitoringUnavailable: true, karabinerAbsent: karabinerAbsent)
            for leg in evidence.legs where leg.verdict == .blocked {
                guard let expected = matrixLegIDs.contains(leg.legID) ? matrix : d1Failure,
                      leg.blocker == expected else { throw ValidatorError("sp1_blocker_invalid", leg.legID) }
            }
        case 2:
            guard let environment else { throw ValidatorError("sp1_environment_missing") }
            let matrix = environment.applications.contains { $0.name == "Karabiner-Elements" && $0.status == .installed }
                ? SP1CanonicalBlockers.v2MatrixExecutionNotImplemented
                : SP1CanonicalBlockers.v2KarabinerAbsent
            for leg in evidence.legs where leg.verdict == .blocked {
                let expected = leg.legID == "sp1.systemShortcut" ? SP1CanonicalBlockers.systemShortcutExecutionNotImplemented
                    : matrixLegIDs.contains(leg.legID) ? matrix : nil
                guard let expected, leg.blocker == expected else {
                    throw ValidatorError("sp1_blocker_invalid", leg.legID)
                }
            }
        case 3:
            guard let environment else { throw ValidatorError("sp1_environment_missing") }
            let karabinerInstalled = environment.applications.contains { $0.name == "Karabiner-Elements" && $0.status == .installed }
            for leg in evidence.legs where leg.verdict == .blocked {
                let expected: SP1Blocker?
                if leg.legID == "sp1.systemShortcut" {
                    expected = SP1CanonicalBlockers.liveExecutionNotArmed
                } else if matrixLegIDs.contains(leg.legID) {
                    expected = karabinerInstalled ? SP1CanonicalBlockers.liveExecutionNotArmed : SP1CanonicalBlockers.v2KarabinerAbsent
                } else {
                    expected = nil
                }
                guard let expected, leg.blocker == expected else {
                    throw ValidatorError("sp1_blocker_invalid", leg.legID)
                }
            }
        default:
            throw ValidatorError("sp1_unsupported_schema_version")
        }
    }

    private static func validateV3ArtifactSemantics(_ directory: URL, evidence: SP1Evidence) throws {
        let synthetic = try SP1SyntheticScenarios.run()
        let syntheticData = try bytes(directory.appendingPathComponent("product-stamped-synthetic.json"), code: "sp1_synthetic_recompute_mismatch")
        try validateV2SyntheticSemantics(evidence, assertions: synthetic.assertions, artifactHash: Canonical.sha256(syntheticData))
        let live = try validateLiveArtifact(directory.appendingPathComponent("live-aggregate-counts.json"))
        guard let shortcut = evidence.legs.first(where: { $0.legID == "sp1.systemShortcut" }) else {
            throw ValidatorError("sp1_live_semantics_invalid")
        }
        if shortcut.verdict == .blocked {
            guard live.systemShortcutObservedCount == 0, live.unmarkedObservedCount == 0,
                  shortcut.blocker == SP1CanonicalBlockers.liveExecutionNotArmed,
                  shortcut.identity == nil, shortcut.artifactSha256 == nil else {
                throw ValidatorError("sp1_live_semantics_invalid")
            }
        } else if shortcut.verdict == .pass {
            guard shortcut.detectorAvailable, shortcut.blocker == nil,
                  shortcut.artifactSha256 != nil,
                  live.systemShortcutObservedCount >= 0,
                  live.unmarkedObservedCount >= 0 else {
                throw ValidatorError("sp1_live_semantics_invalid")
            }
        } else if shortcut.verdict == .inconclusive {
            guard shortcut.detectorAvailable, shortcut.blocker == nil, shortcut.artifactSha256 != nil else {
                throw ValidatorError("sp1_live_semantics_invalid")
            }
        }
        if let selected = evidence.selectedTapIdentity {
            let selectedLegID = "sp1.tap.\(selected.tapType).matrix"
            guard let selectedLeg = evidence.legs.first(where: { $0.legID == selectedLegID }),
                  selectedLeg.verdict == .pass, selectedLeg.matrix?.passes == true else {
                throw ValidatorError("sp1_matrix_semantics_invalid")
            }
        }
    }

    private static func validateV3EnvironmentSemantics(_ evidence: SP1Evidence, environment: EnvironmentEvidence) throws {
        let karabinerInstalled = environment.applications.contains { $0.name == "Karabiner-Elements" && $0.status == .installed }
        for leg in evidence.legs where matrixLegIDs.contains(leg.legID) && leg.verdict == .blocked {
            let expected = karabinerInstalled ? SP1CanonicalBlockers.liveExecutionNotArmed : SP1CanonicalBlockers.v2KarabinerAbsent
            guard leg.blocker == expected else { throw ValidatorError("sp1_matrix_blocker_invalid", leg.legID) }
        }
    }

    private static func validateNarratives(_ directory: URL, evidence: SP1Evidence) throws {
        guard try bytes(directory.appendingPathComponent("O7-ADDENDUM.md"), code: "sp1_narrative_mismatch") == SP1CanonicalNarratives.o7(),
              try bytes(directory.appendingPathComponent("SP-1-CONCLUSION.md"), code: "sp1_narrative_mismatch") == SP1CanonicalNarratives.conclusion(for: evidence) else {
            throw ValidatorError("sp1_narrative_mismatch")
        }
    }

    private static let matrixLegIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]

    static func verifyManifest(_ directory: URL) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        guard isRegularFile(manifest), let text = try? String(contentsOf: manifest, encoding: .utf8) else { throw ValidatorError("missing_manifest") }
        var expected = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { throw ValidatorError("malformed_manifest") }
            let name = String(parts[1])
            guard artifactNames.contains(name), expected.insert(name).inserted else { throw ValidatorError("manifest_membership_mismatch") }
            let file = directory.appendingPathComponent(name)
            guard isRegularFile(file), let data = try? Data(contentsOf: file), Canonical.sha256(data) == String(parts[0]) else {
                throw ValidatorError("manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard expected == artifactNames, actual == artifactNames else { throw ValidatorError("manifest_membership_mismatch") }
    }

    private static func bytes(_ url: URL, code: String) throws -> Data {
        guard isRegularFile(url), let data = try? Data(contentsOf: url) else { throw ValidatorError(code) }
        return data
    }

    private static func jsonObject(_ url: URL, code: String) throws -> Any {
        guard isRegularFile(url), let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else { throw ValidatorError(code) }
        return object
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 1_048_576
    }
}

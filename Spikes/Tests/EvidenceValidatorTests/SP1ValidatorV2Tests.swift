import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP1ValidatorV2Tests: XCTestCase {
    private static let syntheticIDs: Set<String> = ["sp1.autoRepeat", "sp1.o7Boundary", "sp1.productStampedDrop", "sp1.tapReset"]
    private static let matrixLegIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]
    func testCheckedInCanonicalV1AllBlockedDirectoryRemainsAccepted() throws {
        let directory = try repositoryRoot().appendingPathComponent("evidence/phase0/sp1")
        let evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: directory.appendingPathComponent("evidence.json")))
        guard evidence.schemaVersion == 1 else {
            throw XCTSkip("checked-in canonical SP-1 evidence is no longer schema v1")
        }
        XCTAssertEqual(evidence.verdict, .blocked)
        XCTAssertTrue(evidence.legs.allSatisfy { $0.verdict == .blocked && $0.artifactSha256 == nil })
        for leg in evidence.legs {
            let expected = Self.matrixLegIDs.contains(leg.legID)
                ? SP1CanonicalBlockers.legacyV1Matrix(inputMonitoringUnavailable: true, karabinerAbsent: true)
                : SP1CanonicalBlockers.d1
            XCTAssertEqual(leg.blocker, expected, leg.legID)
        }
        XCTAssertNoThrow(try evidence.validate())
        XCTAssertNoThrow(try SP1DirectoryValidator.verifyManifest(directory))
        XCTAssertNoThrow(try SP1DirectoryValidator.validateArtifacts(directory, evidence: evidence))
        XCTAssertNoThrow(try SP1DirectoryValidator.validateArtifactBindings(evidence, directory: directory))
    }

    func testV1AllBlockedFixturePassesFullValidation() throws {
        var spec = FixtureSpec()
        spec.schemaVersion = 1
        spec.passLegs = []
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
    }

    func testV1RemanifestedPositiveLiveCountsReject() throws {
        for counts in [(1, 0), (0, 1)] {
            var spec = FixtureSpec()
            spec.schemaVersion = 1
            spec.passLegs = []
            spec.withRepository = true
            spec.liveArtifact = try JSONEncoder().encode(
                SP1LiveAggregateArtifact(systemShortcutObservedCount: counts.0, unmarkedObservedCount: counts.1)
            )
            let fixture = try makeFixture(spec)
            defer { fixture.remove() }
            XCTAssertEqual(
                code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository) },
                "sp1_live_semantics_invalid"
            )
        }
    }

    func testFullDirectoryRejectsMissingOrNullSchemaVersionAfterRemanifesting() throws {
        for replacement: Any? in [nil, NSNull()] {
            var spec = FixtureSpec()
            spec.withRepository = true
            let fixture = try makeFixture(spec)
            defer { fixture.remove() }
            let evidenceURL = fixture.directory.appendingPathComponent("evidence.json")
            var object = try jsonObject(at: evidenceURL)
            object["schemaVersion"] = replacement
            try writeJSONObject(object, to: evidenceURL)
            try fixture.remanifest()
            XCTAssertEqual(
                code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository) },
                "malformed_sp1_evidence"
            )
        }
    }

    func testV2AllBlockedFixtureContradictsPassingSyntheticAssertions() throws {
        var spec = FixtureSpec()
        spec.passLegs = []
        spec.inconclusiveLegs = []
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertThrowsError(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
    }

    func testV1NonblockedSyntheticLegRejects() throws {
        for (legID, verdict) in [("sp1.autoRepeat", Verdict.pass), ("sp1.o7Boundary", .pass), ("sp1.productStampedDrop", .pass), ("sp1.tapReset", .pass), ("sp1.tapReset", Verdict.fail)] {
            var spec = FixtureSpec()
            spec.schemaVersion = 1
            spec.passLegs = verdict == .pass ? [legID] : []
            spec.failLegs = verdict == .fail ? [legID] : []
            let fixture = try makeFixture(spec)
            defer { fixture.remove() }
            XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_synthetic_pass_unsupported", "\(legID) \(verdict)")
        }
    }

    func testValidV2DirectoryPassesFullValidationWithRecomputedArtifactAndByteBindings() throws {
        var spec = FixtureSpec()
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        let report = try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository)
        XCTAssertEqual(report.legCount, SP1Evidence.requiredLegIDs.count)
        XCTAssertEqual(report.g0Status, .open)
    }

    func testV2MissingAssertionRejects() throws {
        try assertSyntheticMutationRejects { $0.removeLast() }
    }

    func testV2DuplicateAssertionRejects() throws {
        try assertSyntheticMutationRejects { assertions in assertions.append(assertions[0]) }
    }

    func testV2ExtraAssertionRejects() throws {
        try assertSyntheticMutationRejects { $0.append(SP1SyntheticAssertion(legID: "sp1.systemShortcut", passed: true)) }
    }

    func testV2FlippedAssertionResultRejects() throws {
        try assertSyntheticMutationRejects { assertions in
            assertions[1] = SP1SyntheticAssertion(legID: assertions[1].legID, passed: false)
        }
    }

    func testV2PassingAssertionCannotBeReportedAsFail() throws {
        var spec = FixtureSpec()
        spec.passLegs.remove("sp1.autoRepeat")
        spec.failLegs.insert("sp1.autoRepeat")
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertThrowsError(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
    }

    func testV2ReorderedAssertionsReject() throws {
        try assertSyntheticMutationRejects { $0.swapAt(0, 3) }
    }

    func testV2EventRecordLayoutArtifactRejects() throws {
        var spec = FixtureSpec()
        spec.syntheticArtifact = try v1RecordsArtifact()
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_synthetic_recompute_mismatch")
    }

    func testV2StaleLegArtifactHashesReject() throws {
        for legID in ["sp1.autoRepeat"] {
            var spec = FixtureSpec()
            spec.declaredHashes = [legID: String(repeating: "e", count: 64)]
            let fixture = try makeFixture(spec)
            defer { fixture.remove() }
            XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_artifact_hash_mismatch", legID)
        }
    }

    func testV2RemanifestedLiveForgeryRejects() throws {
        let fixture = try makeFixture(FixtureSpec())
        defer { fixture.remove() }
        let forged = try JSONEncoder().encode(SP1LiveAggregateArtifact(systemShortcutObservedCount: 0, unmarkedObservedCount: 7))
        try forged.write(to: fixture.directory.appendingPathComponent("live-aggregate-counts.json"))
        try fixture.remanifest()
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_live_semantics_invalid")
    }

    func testV2RemanifestedRawPayloadInsertionRejects() throws {
        let fixture = try makeFixture(FixtureSpec())
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("live-aggregate-counts.json")
        var object = try jsonObject(at: url)
        object["rawPayload"] = ["keyCode": 4, "text": "temporary-test-only"]
        try writeJSONObject(object, to: url)
        try fixture.remanifest()
        XCTAssertThrowsError(try SP1DirectoryValidator.validateArtifacts(fixture.directory, evidence: fixture.evidence()))
    }

    func testV2LiveCountsRejectBooleansFractionsNegativesAndOverflow() throws {
        for value in ["true", "0.5", "-1", "1e100"] {
            let fixture = try makeFixture(FixtureSpec())
            defer { fixture.remove() }
            let payload = "{\"evidenceKind\":\"live\",\"systemShortcutObservedCount\":\(value),\"unmarkedObservedCount\":0}\n"
            try Data(payload.utf8).write(to: fixture.directory.appendingPathComponent("live-aggregate-counts.json"))
            try fixture.remanifest()
            XCTAssertThrowsError(try SP1DirectoryValidator.validateArtifacts(fixture.directory, evidence: fixture.evidence()), "count \(value) must be a nonnegative, losslessly decoded integer")
        }
    }

    func testV2ShortcutCannotBeRepresentedAsExecuted() throws {
        var spec = FixtureSpec()
        spec.passLegs.insert("sp1.systemShortcut")
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertThrowsError(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
    }

    func testV2LiveArtifactCountsMustRemainStrictlyZero() throws {
        for counts in [(1, 0), (0, 1)] {
            var spec = FixtureSpec()
            spec.liveArtifact = try JSONEncoder().encode(SP1LiveAggregateArtifact(systemShortcutObservedCount: counts.0, unmarkedObservedCount: counts.1))
            let fixture = try makeFixture(spec)
            defer { fixture.remove() }
            XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_live_semantics_invalid")
        }
    }

    func testV2RequiresSiblingEnvironmentArtifact() throws {
        var spec = FixtureSpec()
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("environment.json"))
        XCTAssertThrowsError(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
    }

    func testV2RejectsRemanifestedO7AndConclusionByteMutations() throws {
        for name in ["O7-ADDENDUM.md", "SP-1-CONCLUSION.md"] {
            var spec = FixtureSpec()
            spec.withRepository = true
            let fixture = try makeFixture(spec)
            defer { fixture.remove() }
            let url = fixture.directory.appendingPathComponent(name)
            var bytes = try Data(contentsOf: url)
            bytes.append(Data("\nreview-time byte injection\n".utf8))
            try bytes.write(to: url)
            try fixture.remanifest()
            XCTAssertThrowsError(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository), "remanifesting must not legitimize altered \(name)")
        }
    }

    func testV1AndV2RejectEveryRemanifestedBlockerFieldInjectionWithRegeneratedNarrative() throws {
        for schemaVersion in [1, 2] {
            for field in ["blocked_by", "detect_command", "prerequisite", "unblock_action"] {
                var spec = FixtureSpec()
                spec.schemaVersion = schemaVersion
                spec.passLegs = schemaVersion == 2 ? Self.syntheticIDs : []
                spec.inconclusiveLegs = []
                spec.withRepository = true
                let fixture = try makeFixture(spec)
                defer { fixture.remove() }

                let evidenceURL = fixture.directory.appendingPathComponent("evidence.json")
                var root = try jsonObject(at: evidenceURL)
                var legs = root["legs"] as! [[String: Any]]
                let index = legs.firstIndex { $0["legID"] as? String == "sp1.tap.session.matrix" }!
                var blocker = legs[index]["blocker"] as! [String: Any]
                blocker[field] = field == "detect_command" ? ["preflight", "temporary raw payload"] : "temporary raw payload"
                legs[index]["blocker"] = blocker
                root["legs"] = legs
                try writeJSONObject(root, to: evidenceURL)

                let forged = try fixture.evidence()
                try SP1CanonicalNarratives.conclusion(for: forged).write(to: fixture.directory.appendingPathComponent("SP-1-CONCLUSION.md"))
                try fixture.remanifest()
                XCTAssertThrowsError(
                    try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository),
                    "schema v\(schemaVersion) must reject injected \(field) even after canonical narrative regeneration"
                )
            }
        }
    }

    func testV2RejectsEveryRemanifestedShortcutBlockerFieldMutation() throws {
        for field in ["blocked_by", "detect_command", "prerequisite", "unblock_action"] {
            let fixture = try makeFixture(FixtureSpec())
            defer { fixture.remove() }
            let evidenceURL = fixture.directory.appendingPathComponent("evidence.json")
            var root = try jsonObject(at: evidenceURL)
            var legs = root["legs"] as! [[String: Any]]
            let index = legs.firstIndex { $0["legID"] as? String == "sp1.systemShortcut" }!
            var blocker = legs[index]["blocker"] as! [String: Any]
            blocker[field] = field == "detect_command" ? ["temporary raw payload"] : "temporary raw payload"
            legs[index]["blocker"] = blocker
            root["legs"] = legs
            try writeJSONObject(root, to: evidenceURL)
            try SP1CanonicalNarratives.conclusion(for: fixture.evidence()).write(to: fixture.directory.appendingPathComponent("SP-1-CONCLUSION.md"))
            try fixture.remanifest()
            XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_live_semantics_invalid", field)
        }
    }

    func testV1ValidatorRecomputesNonlegacyD1AndMatrixBlockersFromEnvironment() throws {
        var spec = FixtureSpec()
        spec.schemaVersion = 1
        spec.passLegs = []
        spec.guiStatus = "available"
        spec.listenEventAccess = "unknown"
        spec.tapCreate = "denied"
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertNil(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository) })

        let evidenceURL = fixture.directory.appendingPathComponent("evidence.json")
        var evidence = try fixture.evidence()
        let index = evidence.legs.firstIndex { $0.legID == "sp1.autoRepeat" }!
        evidence.legs[index].blocker = SP1CanonicalBlockers.d1
        try JSONEncoder().encode(evidence).write(to: evidenceURL)
        try SP1CanonicalNarratives.conclusion(for: evidence).write(to: fixture.directory.appendingPathComponent("SP-1-CONCLUSION.md"))
        try fixture.remanifest()
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository) }, "sp1_blocker_invalid")
    }

    func testV1SemanticallyEquivalentButByteMutatedProductArtifactRejects() throws {
        var spec = FixtureSpec()
        spec.schemaVersion = 1
        spec.passLegs = []
        spec.inconclusiveLegs = []
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("product-stamped-synthetic.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
        try fixture.remanifest()
        XCTAssertNotEqual(Canonical.sha256(try Data(contentsOf: url)), "7238044654fbd6c081b5531f50ba8a095fd90e89e80edf9c6cb48a52f94ba518")
        XCTAssertThrowsError(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
    }

    func testV2RunnerAncestorOfHeadValidatesAfterDescendantOnlySeal() throws {
        var spec = FixtureSpec()
        spec.withRepository = true
        spec.runnerIsAncestor = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
    }

    func testV2RunnerNonAncestorRejects() throws {
        var spec = FixtureSpec()
        spec.withRepository = true
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        try git(["commit", "--allow-empty", "-q", "-m", "future"], at: fixture.repository)
        let future = try gitOutput(["rev-parse", "HEAD"], at: fixture.repository)
        let futureTree = try gitOutput(["rev-parse", "\(future)^{tree}"], at: fixture.repository)
        try git(["reset", "--hard", "HEAD~1"], at: fixture.repository)
        var object = try jsonObject(at: fixture.directory.appendingPathComponent("evidence.json"))
        var legs = object["legs"] as! [[String: Any]]
        for index in legs.indices {
            legs[index]["runnerCommitSha"] = future
            legs[index]["runnerTreeSha"] = futureTree
        }
        object["legs"] = legs
        try writeJSONObject(object, to: fixture.directory.appendingPathComponent("evidence.json"))
        try fixture.remanifest()
        XCTAssertEqual(
            code { try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository) },
            "sp1_runner_not_ancestor"
        )
    }

    func testSP1PersistedModelsRejectUnknownFieldsAtEveryNestedBoundary() throws {
        let fixture = try makeFixture(FixtureSpec())
        defer { fixture.remove() }
        let original = try jsonObject(at: fixture.directory.appendingPathComponent("evidence.json"))
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("root", { $0["unexpected"] = true }),
            ("leg", { root in var legs = root["legs"] as! [[String: Any]]; legs[0]["unexpected"] = true; root["legs"] = legs }),
            ("blocker", { root in var legs = root["legs"] as! [[String: Any]]; let index = legs.firstIndex { $0["blocker"] != nil }!; var blocker = legs[index]["blocker"] as! [String: Any]; blocker["unexpected"] = true; legs[index]["blocker"] = blocker; root["legs"] = legs }),
        ]
        for (boundary, mutate) in mutations {
            var object = original
            mutate(&object)
            XCTAssertThrowsError(try JSONDecoder().decode(SP1Evidence.self, from: JSONSerialization.data(withJSONObject: object)), "unknown \(boundary) field must reject")
        }

        try assertUnknownFieldRejects(SelectedTapIdentity(tapType: "session", attemptID: "attempt", runnerCommitSha: String(repeating: "a", count: 40), runnerTreeSha: String(repeating: "b", count: 40), environmentSha256: String(repeating: "c", count: 64), tapConfigSha256: String(repeating: "d", count: 64)), as: SelectedTapIdentity.self)
        try assertUnknownFieldRejects(TapMatrixObservation(offObservedCode: 4, offCount: 1, onObservedCode: 5, onCount: 1, expectedPhysicalCode: 4, expectedTransformedCode: 5), as: TapMatrixObservation.self)
    }

    func testV2BlockedShortcutCarryingArtifactHashRejects() throws {
        var spec = FixtureSpec()
        spec.declaredHashes = ["sp1.systemShortcut": Canonical.sha256(try SP1SyntheticScenarios.run().canonicalJSON())]
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_invalidBlocker")
    }

    func testV2ExecutedMatrixLegRejects() throws {
        var spec = FixtureSpec()
        spec.failLegs = ["sp1.tap.session.matrix"]
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_matrix_semantics_invalid")
    }

    private struct FixtureSpec {
        var schemaVersion = 2
        var passLegs: Set<String> = SP1ValidatorV2Tests.syntheticIDs
        var inconclusiveLegs: Set<String> = []
        var failLegs: Set<String> = []
        var aggregateCounts: [String: Int] = [:]
        var declaredHashes: [String: String] = [:]
        var syntheticArtifact: Data?
        var liveArtifact: Data?
        var withRepository = false
        var runnerIsAncestor = false
        var guiStatus = "available"
        var listenEventAccess: String?
        var tapCreate: String?
    }

    private struct Fixture {
        let root: URL
        var directory: URL { root.appendingPathComponent("sp1") }
        var repository: URL { root.appendingPathComponent("repo") }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func remanifest() throws {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" }.sorted()
            let lines = try names.map { "\(Canonical.sha256(try Data(contentsOf: directory.appendingPathComponent($0))))  \($0)" }
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
        }
        func evidence() throws -> SP1Evidence { try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: directory.appendingPathComponent("evidence.json"))) }
    }

    private func assertSyntheticMutationRejects(_ mutate: (inout [SP1SyntheticAssertion]) -> Void, file: StaticString = #filePath, line: UInt = #line) throws {
        var assertions = try SP1SyntheticScenarios.run().assertions
        mutate(&assertions)
        var spec = FixtureSpec()
        spec.syntheticArtifact = try SP1SyntheticAssertionsArtifact(assertions: assertions).canonicalJSON()
        let fixture = try makeFixture(spec)
        defer { fixture.remove() }
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory) }, "sp1_synthetic_recompute_mismatch", file: file, line: line)
    }

    private func makeFixture(_ spec: FixtureSpec) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-v2-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("sp1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let synthetic = try spec.syntheticArtifact ?? (spec.schemaVersion == 2 ? SP1SyntheticScenarios.run().canonicalJSON() : canonicalV1Artifact())
        let live = try spec.liveArtifact ?? JSONEncoder().encode(SP1LiveAggregateArtifact(systemShortcutObservedCount: 0, unmarkedObservedCount: 0))
        try synthetic.write(to: directory.appendingPathComponent("product-stamped-synthetic.json"))
        try live.write(to: directory.appendingPathComponent("live-aggregate-counts.json"))
        let d1State = spec.schemaVersion == 2 ? "available" : "denied"
        let environmentBytes = Data(environmentJSON(
            guiStatus: spec.guiStatus,
            listenEventAccess: spec.listenEventAccess ?? d1State,
            tapCreate: spec.tapCreate ?? d1State
        ).utf8)
        try environmentBytes.write(to: root.appendingPathComponent("environment.json"))
        let environment = Canonical.sha256(environmentBytes)
        let environmentEvidence = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentBytes)
        let d1Blocker = SP1CanonicalBlockers.d1Failure(for: environmentEvidence) ?? SP1CanonicalBlockers.d1
        var commit = String(repeating: "b", count: 40), tree = commit
        var sources = Dictionary(uniqueKeysWithValues: SP1RunnerBinding.sourcePaths.map { ($0, String(repeating: "c", count: 64)) })
        if spec.withRepository {
            (commit, tree, sources) = try makeRepository(at: root.appendingPathComponent("repo"), runnerIsAncestor: spec.runnerIsAncestor)
        }
        let syntheticHash = Canonical.sha256(synthetic), liveHash = Canonical.sha256(live)
        let legs = SP1Evidence.requiredLegIDs.sorted().map { legID -> SP1Leg in
            let verdict: Verdict = spec.passLegs.contains(legID) ? .pass : spec.failLegs.contains(legID) ? .fail : spec.schemaVersion == 2 && spec.inconclusiveLegs.contains(legID) ? .inconclusive : .blocked
            let blocked = verdict == .blocked
            let fallback = Self.syntheticIDs.contains(legID) ? syntheticHash : liveHash
            let blockedReason = Self.matrixLegIDs.contains(legID)
                ? spec.schemaVersion == 1
                    ? SP1CanonicalBlockers.legacyV1Matrix(environment: environmentEvidence, karabinerAbsent: true)
                    : SP1CanonicalBlockers.v2KarabinerAbsent
                : spec.schemaVersion == 2 && legID == "sp1.systemShortcut"
                    ? SP1CanonicalBlockers.systemShortcutExecutionNotImplemented
                    : d1Blocker
            return SP1Leg(legID: legID, verdict: verdict, detectorAvailable: !blocked, blocker: blocked ? blockedReason : nil, identity: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment, artifactSha256: blocked ? spec.declaredHashes[legID] : spec.declaredHashes[legID] ?? fallback, matrix: nil, aggregateCount: blocked ? nil : spec.aggregateCounts[legID])
        }
        let verdict: Verdict = spec.failLegs.isEmpty ? .blocked : .fail
        var evidence = SP1Evidence(selectedTapIdentity: nil, legs: legs, verdict: verdict, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: sources)
        evidence.schemaVersion = spec.schemaVersion
        try JSONEncoder().encode(evidence).write(to: directory.appendingPathComponent("evidence.json"))
        try SP1CanonicalNarratives.o7().write(to: directory.appendingPathComponent("O7-ADDENDUM.md"))
        try SP1CanonicalNarratives.conclusion(for: evidence).write(to: directory.appendingPathComponent("SP-1-CONCLUSION.md"))
        let fixture = Fixture(root: root)
        try fixture.remanifest()
        return fixture
    }

    private func makeRepository(at url: URL, runnerIsAncestor: Bool) throws -> (commit: String, tree: String, sources: [String: String]) {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["init", "-q"], at: url)
        try git(["config", "user.email", "fixture@example.invalid"], at: url)
        try git(["config", "user.name", "Fixture"], at: url)
        var sources: [String: String] = [:]
        for path in SP1RunnerBinding.sourcePaths {
            let file = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data("source:\(path)\n".utf8)
            try data.write(to: file)
            sources[path] = Canonical.sha256(data)
        }
        try git(["add", "."], at: url)
        try git(["commit", "-q", "-m", "fixture"], at: url)
        let commit = try gitOutput(["rev-parse", "HEAD"], at: url)
        let tree = try gitOutput(["rev-parse", "HEAD^{tree}"], at: url)
        if runnerIsAncestor {
            try Data("descendant\n".utf8).write(to: url.appendingPathComponent("descendant.txt"))
            try git(["add", "descendant.txt"], at: url)
            try git(["commit", "-q", "-m", "descendant"], at: url)
        }
        return (commit, tree, sources)
    }

    private func v1RecordsArtifact() throws -> Data {
        let records = InputEventKind.allCases.map { ProductStampedRecord(kind: $0, keyCode: 4, isAutoRepeat: false, marker: ProductSyntheticMarker.value, dropped: true) }
        return try JSONEncoder().encode(SP1SyntheticArtifact(records: records))
    }

    private func canonicalV1Artifact() throws -> Data {
        let data = SP1CanonicalArtifacts.v1Synthetic
        XCTAssertEqual(Canonical.sha256(data), "7238044654fbd6c081b5531f50ba8a095fd90e89e80edf9c6cb48a52f94ba518")
        return data
    }

    private func environmentJSON(guiStatus: String, listenEventAccess: String, tapCreate: String) -> String {
        """
        {"macOS":{"version":"26.6.1","build":"25G76"},"architecture":"arm64","swift":"Swift 6","xcode":"Xcode 26","generatedAt":"2026-01-01T00:00:00Z","guiSession":{"status":"\(guiStatus)","tapCreate":"\(tapCreate)"},"listenEventAccess":"\(listenEventAccess)","hidAccess":"unknown","sudoNonInteractive":false,"applications":[{"name":"Karabiner-Elements","status":"absent"}],"hidSummary":{"deviceCount":0,"devices":[]},"sourceReachability":{"status":"unavailable","httpStatus":null}}
        """
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    private func assertUnknownFieldRejects<T: Codable>(_ value: T, as type: T.Type, file: StaticString = #filePath, line: UInt = #line) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["unexpected"] = true
        XCTAssertThrowsError(try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object)), file: file, line: line)
    }

    private func code(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("evidence/phase0").path) { return candidate }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func git(_ arguments: [String], at root: URL) throws { _ = try gitOutput(arguments, at: root) }

    private func gitOutput(_ arguments: [String], at root: URL) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

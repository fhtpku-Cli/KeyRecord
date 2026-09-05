import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP1ValidatorTests: XCTestCase {
    func testMalformedAndStaleManifestReject() throws {
        let fixture = try blockedFixture()
        defer { fixture.remove() }
        try Data("bad\n".utf8).write(to: fixture.root.appendingPathComponent("manifest.sha256"))
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.root) }, "malformed_manifest")
    }

    func testRemanifestedMalformedMarkerRejects() throws {
        let fixture = try blockedFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("product-stamped-synthetic.json")
        var object = try json(url)
        var records = object["records"] as! [[String: Any]]
        records[0]["marker"] = 1
        object["records"] = records
        try writeJSON(object, to: url); try fixture.manifest()
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.root) }, "sp1_malformed_product_marker")
    }

    func testFalseProductStampRejectsAfterRemanifest() throws {
        let fixture = try blockedFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("product-stamped-synthetic.json")
        var object = try json(url); object["productStampedSynthetic"] = false
        try writeJSON(object, to: url); try fixture.manifest()
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.root) }, "sp1_malformed_product_marker")
    }

    func testLiveKeyTextSequenceAndExactTimestampRejectAfterRemanifest() throws {
        for field in ["keyCode", "text", "sequence", "exactTimestamp"] {
            let fixture = try blockedFixture()
            defer { fixture.remove() }
            let url = fixture.root.appendingPathComponent("live-aggregate-counts.json")
            var object = try json(url); object[field] = field == "keyCode" ? 4 : "private"
            try writeJSON(object, to: url); try fixture.manifest()
            XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.root) }, "sp1_live_event_detail_forbidden", field)
        }
    }

    func testUnexpectedRemanifestedArtifactRejects() throws {
        let fixture = try blockedFixture()
        defer { fixture.remove() }
        try Data("{\"keyCode\":4}\n".utf8).write(to: fixture.root.appendingPathComponent("live-detail.json"))
        try fixture.manifest()
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.root) }, "manifest_membership_mismatch")
    }

    func testSelectedPassRejectsNonexistentCommitAndTree() throws {
        let fixture = try runnerFixture()
        defer { fixture.remove() }
        var evidence = fixture.evidence
        evidence = replacingIdentity(evidence, commit: String(repeating: "f", count: 40))
        XCTAssertEqual(code { try SP1DirectoryValidator.validateRunnerBinding(evidence, repository: fixture.root) }, "sp1_runner_commit_missing")
        evidence = replacingIdentity(fixture.evidence, tree: String(repeating: "f", count: 40))
        XCTAssertEqual(code { try SP1DirectoryValidator.validateRunnerBinding(evidence, repository: fixture.root) }, "sp1_runner_tree_mismatch")
    }

    func testSelectedPassRejectsMissingSourceWrongBytesAndDirtySource() throws {
        let missing = try runnerFixture(omitting: SP1RunnerBinding.sourcePaths.sorted()[0])
        defer { missing.remove() }
        XCTAssertEqual(code { try SP1DirectoryValidator.validateRunnerBinding(missing.evidence, repository: missing.root) }, "sp1_runner_source_missing")

        let wrong = try runnerFixture()
        defer { wrong.remove() }
        var wrongEvidence = wrong.evidence
        wrongEvidence.runnerSourceSha256[SP1RunnerBinding.sourcePaths.sorted()[0]] = String(repeating: "f", count: 64)
        XCTAssertEqual(code { try SP1DirectoryValidator.validateRunnerBinding(wrongEvidence, repository: wrong.root) }, "sp1_runner_source_hash_mismatch")

        let dirty = try runnerFixture()
        defer { dirty.remove() }
        try Data("dirty\n".utf8).write(to: dirty.root.appendingPathComponent(SP1RunnerBinding.sourcePaths.sorted()[0]))
        XCTAssertEqual(code { try SP1DirectoryValidator.validateRunnerBinding(dirty.evidence, repository: dirty.root) }, "sp1_runner_source_dirty")
    }

    func testSelectedPassAcceptsBoundCommitTreeAndExactClosedSourceSet() throws {
        let fixture = try runnerFixture()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP1DirectoryValidator.validateRunnerBinding(fixture.evidence, repository: fixture.root))
    }

    func testBlockedEvidenceStillRequiresHistoricalRunnerSources() throws {
        let fixture = try runnerFixture()
        defer { fixture.remove() }
        let evidence = blockedRunnerEvidence(fixture.evidence)
        XCTAssertNoThrow(try SP1DirectoryValidator.validateRunnerBinding(evidence, repository: fixture.root))

        let path = SP1RunnerBinding.sourcePaths.sorted()[0]
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(path))
        XCTAssertEqual(
            code { try SP1DirectoryValidator.validateRunnerBinding(evidence, repository: fixture.root) },
            "sp1_runner_source_dirty"
        )
    }

    func testPassEvidenceRejectsMixedLastLegRunnerAndEnvironmentIdentity() throws {
        let fixture = try runnerFixture()
        defer { fixture.remove() }
        try assertLastLegIdentityMutationsReject(fixture.evidence)
    }

    func testBlockedEvidenceRejectsMixedLastLegRunnerAndEnvironmentIdentity() throws {
        let fixture = try runnerFixture()
        defer { fixture.remove() }
        try assertLastLegIdentityMutationsReject(blockedRunnerEvidence(fixture.evidence))
    }

    func testEvidenceRejectsCommonEnvironmentDifferentFromCandidate() throws {
        let fixture = try runnerFixture()
        defer { fixture.remove() }

        XCTAssertThrowsError(try fixture.evidence.validate(
            candidateEnvironmentSha256: String(repeating: "b", count: 64)
        )) { error in
            XCTAssertEqual(error as? SP1ValidationError, .mixedIdentity)
        }
    }

    private func blockedFixture() throws -> ArtifactFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-artifacts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let hash = String(repeating: "a", count: 64), commit = String(repeating: "b", count: 40)
        let blocker = SP1Blocker(blockedBy: "input_monitoring_denied", detectCommand: ["preflight"], prerequisite: "Input Monitoring", unblockAction: "Grant separately")
        let legs = SP1Evidence.requiredLegIDs.sorted().map { SP1Leg(legID: $0, verdict: .blocked, detectorAvailable: false, blocker: blocker, identity: nil, runnerCommitSha: commit, runnerTreeSha: commit, environmentSha256: hash, artifactSha256: nil, matrix: nil, aggregateCount: nil) }
        let evidence = SP1Evidence(selectedTapIdentity: nil, legs: legs, verdict: .blocked, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: Dictionary(uniqueKeysWithValues: SP1RunnerBinding.sourcePaths.map { ($0, hash) }))
        try encode(evidence, to: root.appendingPathComponent("evidence.json"))
        let records = InputEventKind.allCases.map { ProductStampedRecord(kind: $0, keyCode: 4, isAutoRepeat: false, marker: ProductSyntheticMarker.value, dropped: true) }
        try encode(SP1SyntheticArtifact(records: records), to: root.appendingPathComponent("product-stamped-synthetic.json"))
        try encode(SP1LiveAggregateArtifact(systemShortcutObservedCount: 0, unmarkedObservedCount: 0), to: root.appendingPathComponent("live-aggregate-counts.json"))
        try Data("O7 conservative\n".utf8).write(to: root.appendingPathComponent("O7-ADDENDUM.md"))
        try Data("SP-1 BLOCKED G0 OPEN\n".utf8).write(to: root.appendingPathComponent("SP-1-CONCLUSION.md"))
        let fixture = ArtifactFixture(root: root); try fixture.manifest(); return fixture
    }

    private func runnerFixture(omitting: String? = nil) throws -> RunnerFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try git(["init", "-q"], root)
        try git(["config", "user.email", "fixture@example.invalid"], root)
        try git(["config", "user.name", "Fixture"], root)
        for path in SP1RunnerBinding.sourcePaths where path != omitting {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("source:\(path)\n".utf8).write(to: url)
        }
        try git(["add", "."], root); try git(["commit", "-q", "-m", "fixture"], root)
        let commit = try gitOutput(["rev-parse", "HEAD"], root), tree = try gitOutput(["rev-parse", "HEAD^{tree}"], root)
        var hashes: [String: String] = [:]
        for path in SP1RunnerBinding.sourcePaths {
            let data = (try? Data(contentsOf: root.appendingPathComponent(path))) ?? Data("missing".utf8)
            hashes[path] = Canonical.sha256(data)
        }
        let identity = SelectedTapIdentity(tapType: "session", attemptID: "attempt", runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: String(repeating: "a", count: 64), tapConfigSha256: String(repeating: "b", count: 64))
        let legs = SP1Evidence.requiredLegIDs.sorted().enumerated().map { index, id in
            SP1Leg(legID: id, verdict: id == "sp1.tap.annotated.matrix" ? .fail : .pass, detectorAvailable: true, blocker: nil, identity: id == "sp1.tap.annotated.matrix" ? nil : identity, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: identity.environmentSha256, artifactSha256: String(format: "%064x", index + 1), matrix: id == "sp1.tap.session.matrix" ? TapMatrixObservation(offObservedCode: 4, offCount: 1, onObservedCode: 5, onCount: 1, expectedPhysicalCode: 4, expectedTransformedCode: 5) : nil, aggregateCount: nil)
        }
        let evidence = SP1Evidence(selectedTapIdentity: identity, legs: legs, verdict: .pass, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: hashes)
        return RunnerFixture(root: root, evidence: evidence)
    }

    private func replacingIdentity(_ evidence: SP1Evidence, commit: String? = nil, tree: String? = nil) -> SP1Evidence {
        var copy = evidence, identity = copy.selectedTapIdentity!
        if let commit { identity.runnerCommitSha = commit }; if let tree { identity.runnerTreeSha = tree }
        copy.selectedTapIdentity = identity
        for index in copy.legs.indices where copy.legs[index].identity != nil {
            copy.legs[index].identity = identity; copy.legs[index].runnerCommitSha = identity.runnerCommitSha; copy.legs[index].runnerTreeSha = identity.runnerTreeSha
        }
        return copy
    }

    private func blockedRunnerEvidence(_ evidence: SP1Evidence) -> SP1Evidence {
        var copy = evidence
        let blocker = SP1Blocker(
            blockedBy: "input_monitoring_denied",
            detectCommand: ["preflight"],
            prerequisite: "Input Monitoring",
            unblockAction: "Grant separately"
        )
        copy.selectedTapIdentity = nil
        copy.verdict = .blocked
        for index in copy.legs.indices {
            copy.legs[index].verdict = .blocked
            copy.legs[index].detectorAvailable = false
            copy.legs[index].blocker = blocker
            copy.legs[index].identity = nil
            copy.legs[index].artifactSha256 = nil
            copy.legs[index].matrix = nil
            copy.legs[index].aggregateCount = nil
        }
        return copy
    }

    private func assertLastLegIdentityMutationsReject(_ evidence: SP1Evidence) throws {
        let index: Int
        if evidence.selectedTapIdentity == nil {
            index = evidence.legs.index(before: evidence.legs.endIndex)
        } else {
            guard let unselected = evidence.legs.firstIndex(where: { $0.legID == "sp1.tap.annotated.matrix" }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            index = unselected
        }
        var commit = evidence
        commit.legs[index].runnerCommitSha = String(repeating: "d", count: 40)
        XCTAssertThrowsError(try commit.validate()) { XCTAssertEqual($0 as? SP1ValidationError, .mixedIdentity) }

        var tree = evidence
        tree.legs[index].runnerTreeSha = String(repeating: "e", count: 40)
        XCTAssertThrowsError(try tree.validate()) { XCTAssertEqual($0 as? SP1ValidationError, .mixedIdentity) }

        var environment = evidence
        environment.legs[index].environmentSha256 = String(repeating: "f", count: 64)
        XCTAssertThrowsError(try environment.validate()) { XCTAssertEqual($0 as? SP1ValidationError, .mixedIdentity) }
    }

    private func code(_ body: () throws -> Void) -> String? { do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" } }
    private func json(_ url: URL) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any] }
    private func writeJSON(_ value: Any, to url: URL) throws { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url) }
    private func encode<T: Encodable>(_ value: T, to url: URL) throws { try JSONEncoder().encode(value).write(to: url) }
    private func git(_ args: [String], _ root: URL) throws { _ = try gitOutput(args, root) }
    private func gitOutput(_ args: [String], _ root: URL) throws -> String {
        let process = Process(); let pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = args; process.currentDirectoryURL = root; process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ArtifactFixture {
    let root: URL
    func manifest() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != "manifest.sha256" }.sorted()
        let lines = try names.map { "\(Canonical.sha256(try Data(contentsOf: root.appendingPathComponent($0))))  \($0)" }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: root.appendingPathComponent("manifest.sha256"))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private struct RunnerFixture { let root: URL; let evidence: SP1Evidence; func remove() { try? FileManager.default.removeItem(at: root) } }

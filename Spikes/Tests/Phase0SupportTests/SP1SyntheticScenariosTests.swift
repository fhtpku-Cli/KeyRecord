import Foundation
import XCTest
@testable import Phase0Support

final class SP1SyntheticScenariosTests: XCTestCase {
    private static let orderedLegIDs = ["sp1.autoRepeat", "sp1.o7Boundary", "sp1.productStampedDrop", "sp1.tapReset"]
    private let sha = String(repeating: "a", count: 64)
    private let commit = String(repeating: "b", count: 40)
    private let tree = String(repeating: "c", count: 40)

    func testRunYieldsExactlyTheFourSyntheticAssertionsInCanonicalOrder() throws {
        let artifact = try SP1SyntheticScenarios.run()
        XCTAssertEqual(artifact.assertions.map(\.legID), Self.orderedLegIDs)
        XCTAssertEqual(artifact.assertions.count, 4)
    }

    func testBaselineRunPassesEveryAssertionFromExecutedState() throws {
        XCTAssertTrue(try SP1SyntheticScenarios.run().assertions.allSatisfy(\.passed))
        XCTAssertTrue(try SP1SyntheticScenarios.autoRepeatPasses())
        XCTAssertTrue(SP1SyntheticScenarios.o7BoundaryPasses())
        XCTAssertTrue(try SP1SyntheticScenarios.productStampedDropPasses())
        XCTAssertTrue(try SP1SyntheticScenarios.tapResetPasses())
    }

    func testArtifactDeclaresSchema2AndSyntheticKind() throws {
        let artifact = try SP1SyntheticScenarios.run()
        XCTAssertEqual(artifact.schemaVersion, 2)
        XCTAssertEqual(artifact.evidenceKind, .synthetic)
    }

    func testRunAndEncodingAreDeterministicAcrossExecutions() throws {
        let first = try SP1SyntheticScenarios.run()
        let second = try SP1SyntheticScenarios.run()
        XCTAssertEqual(first, second)
        XCTAssertEqual(try first.canonicalJSON(), try second.canonicalJSON())
    }

    func testCanonicalEncodingHasExactShapeSortedKeysAndTrailingLineFeed() throws {
        let data = try SP1SyntheticScenarios.run().canonicalJSON()
        XCTAssertEqual(data.last, 0x0A)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["assertions", "evidenceKind", "schemaVersion"])
        XCTAssertEqual(object["evidenceKind"] as? String, EvidenceKind.synthetic.rawValue)
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        let assertions = try XCTUnwrap(object["assertions"] as? [[String: Any]])
        XCTAssertEqual(assertions.count, 4)
        for (index, assertion) in assertions.enumerated() {
            XCTAssertEqual(Set(assertion.keys), ["legID", "passed"], "assertion \(index) persists only legID and passed")
        }
        XCTAssertEqual(assertions.compactMap { $0["legID"] as? String }, Self.orderedLegIDs)
    }

    func testPersistedSyntheticArtifactRejectsUnknownRootAndAssertionFields() throws {
        let data = try SP1SyntheticScenarios.run().canonicalJSON()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["unexpected"] = true
        XCTAssertThrowsError(try JSONDecoder().decode(SP1SyntheticAssertionsArtifact.self, from: JSONSerialization.data(withJSONObject: root)))

        root.removeValue(forKey: "unexpected")
        var assertions = try XCTUnwrap(root["assertions"] as? [[String: Any]])
        assertions[0]["unexpected"] = true
        root["assertions"] = assertions
        XCTAssertThrowsError(try JSONDecoder().decode(SP1SyntheticAssertionsArtifact.self, from: JSONSerialization.data(withJSONObject: root)))
    }

    func testSerializedArtifactPassesPhase0PrivacyAudit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-synthetic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try SP1SyntheticScenarios.run().canonicalJSON().write(to: directory.appendingPathComponent("synthetic-assertions.json"))
        let report = try Phase0PrivacyAudit.scan(root: directory)
        XCTAssertEqual(report.filesScanned, 1)
        XCTAssertEqual(report.jsonFilesScanned, 1)
        XCTAssertEqual(report.forbiddenHitCount, 0)
        XCTAssertEqual(report.unmarkedEventRecordCount, 0)
    }

    func testSchema2AllowsSharedArtifactHashAcrossTheFourSyntheticLegs() throws {
        XCTAssertNoThrow(try schema2Report(sharedSyntheticHash: true).validate())
    }

    func testSchema1RejectsSharedArtifactHashAcrossSyntheticLegs() {
        assertReject(.reusedEvidence, mutate(schema2Report(sharedSyntheticHash: true)) { $0.schemaVersion = 1 })
    }

    func testSchema2StillRejectsSharedHashInvolvingANonsyntheticLeg() {
        let report = mutate(schema2Report(sharedSyntheticHash: true)) { report in
            let shortcut = report.legs.firstIndex(where: { $0.legID == "sp1.systemShortcut" })!
            report.legs[shortcut].artifactSha256 = String(repeating: "f", count: 64)
        }
        assertReject(.reusedEvidence, report)
        assertReject(.reusedEvidence, mutate(report) { $0.legs.reverse() })
    }

    func testEvidenceDecodeRequiresNonNullSchemaVersion() throws {
        let data = try JSONEncoder().encode(schema2Report(sharedSyntheticHash: true))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for value: Any? in [nil, NSNull()] {
            var object = original
            object["schemaVersion"] = value
            XCTAssertThrowsError(try JSONDecoder().decode(SP1Evidence.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }

    func testSchema2StillRequiresOpenG0ExactO7GuaranteeAndSupportedVersion() {
        assertReject(.invalidO7, mutate(schema2Report(sharedSyntheticHash: false)) { $0.o7Guarantee = "weakened" })
        assertReject(.invalidO7, mutate(schema2Report(sharedSyntheticHash: false)) { $0.g0Status = .passed })
        assertReject(.invalidO7, mutate(schema2Report(sharedSyntheticHash: false)) { $0.schemaVersion = 4 })
        XCTAssertNoThrow(try mutate(schema2Report(sharedSyntheticHash: false)) { $0.schemaVersion = 3 }.validate())
    }

    private func schema2Report(sharedSyntheticHash: Bool) -> SP1Evidence {
        let identity = SelectedTapIdentity(tapType: "session", attemptID: "attempt", runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: sha, tapConfigSha256: String(repeating: "d", count: 64))
        let shared = String(repeating: "f", count: 64)
        let legs = SP1Evidence.requiredLegIDs.sorted().enumerated().map { index, legID in
            SP1Leg(legID: legID, verdict: legID == "sp1.tap.annotated.matrix" ? .fail : .pass, detectorAvailable: true, blocker: nil, identity: legID == "sp1.tap.annotated.matrix" ? nil : identity, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: sha, artifactSha256: sharedSyntheticHash && Self.orderedLegIDs.contains(legID) ? shared : String(format: "%064x", index + 1), matrix: legID == "sp1.tap.session.matrix" ? .init(offObservedCode: 4, offCount: 1, onObservedCode: 5, onCount: 1, expectedPhysicalCode: 4, expectedTransformedCode: 5) : nil, aggregateCount: legID == "sp1.systemShortcut" ? 1 : nil)
        }
        var report = SP1Evidence(selectedTapIdentity: identity, legs: legs, verdict: .pass, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: ["source": sha])
        report.schemaVersion = 2
        return report
    }

    private func assertReject(_ expected: SP1ValidationError, _ report: SP1Evidence) {
        XCTAssertThrowsError(try report.validate()) { XCTAssertEqual($0 as? SP1ValidationError, expected) }
    }
    private func mutate(_ value: SP1Evidence, _ body: (inout SP1Evidence) -> Void) -> SP1Evidence { var copy = value; body(&copy); return copy }
}

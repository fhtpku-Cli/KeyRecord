import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP5BValidatorTests: XCTestCase {
    func testArtifactsManifestBindingsAndConclusionValidate() throws {
        let fixture = try SP5BValidatorFixture.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP5BDirectoryValidator.validateArtifacts(fixture.output, repository: fixture.repository))
        XCTAssertNoThrow(try SP5BDirectoryValidator.verifyManifest(fixture.output))
        XCTAssertNoThrow(try SP5BDirectoryValidator.validateBindings(fixture.evidence, directory: fixture.output, repository: fixture.repository))
        XCTAssertNoThrow(try SP5BDirectoryValidator.validateConclusion(fixture.output, evidence: fixture.evidence))
    }

    func testArtifactManifestEnvironmentAndMisleadingClaimsReject() throws {
        var fixture = try SP5BValidatorFixture.make()
        defer { fixture.remove() }
        try fixture.mutate("replay.json", replacing: "\"reportCount\" : 6", with: "\"reportCount\" : 5")
        XCTAssertEqual(errorCode { try SP5BDirectoryValidator.validateArtifacts(fixture.output, repository: fixture.repository) }, "sp5b_replay_recompute_mismatch")

        fixture.remove(); fixture = try SP5BValidatorFixture.make()
        try Data("extra".utf8).write(to: fixture.output.appendingPathComponent("extra.txt"))
        XCTAssertEqual(errorCode { try SP5BDirectoryValidator.verifyManifest(fixture.output) }, "sp5b_manifest_membership_mismatch")

        fixture.remove(); fixture = try SP5BValidatorFixture.make()
        var evidence = fixture.evidence
        for index in evidence.legs.indices { evidence.legs[index].environmentSha256 = String(repeating: "f", count: 64) }
        XCTAssertEqual(errorCode { try SP5BDirectoryValidator.validateBindings(evidence, directory: fixture.output, repository: fixture.repository) }, "sp5b_environment_hash_mismatch")

        try Data("# SP-5B conclusion\n\nVerdict: **PASS**\n\nLive capture PASS; device compatibility verified.\n".utf8)
            .write(to: fixture.output.appendingPathComponent("SP-5B-CONCLUSION.md"))
        XCTAssertEqual(errorCode { try SP5BDirectoryValidator.validateConclusion(fixture.output, evidence: fixture.evidence) }, "sp5b_misleading_conclusion")
    }

    private func errorCode(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
}

private struct SP5BValidatorFixture {
    let container: URL
    let repository: URL
    let output: URL
    let evidence: SP5BEvidence

    static func make() throws -> SP5BValidatorFixture {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp5b-validator-\(UUID().uuidString)")
        let repository = container.appendingPathComponent("repo"), output = repository.appendingPathComponent("sp5b")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let copied = [
            "evidence/phase0/environment.json", VialRecordedFixture.fixturePath,
            "evidence/phase0/fixtures/synthetic/provenance.json", "evidence/phase0/fixtures/synthetic/manifest.sha256",
            "evidence/phase0/sources/repos/vial-qmk", "evidence/phase0/sources/repos/vial-gui",
            "evidence/phase0/sources/repos/qmk", "Spikes/Sources/Phase0Support/VialQuery.swift",
        ]
        for path in copied {
            let destination = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.appendingPathComponent(path), to: destination)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let artifacts = try makeArtifacts(repository)
        for (name, bytes) in artifacts { try bytes.write(to: output.appendingPathComponent(name)) }
        let environment = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/environment.json"))
        let hash = String(repeating: "c", count: 64), commit = String(repeating: "a", count: 40), tree = String(repeating: "b", count: 40)
        let legs = SP5BEvidence.requiredLegIDs.sorted().map { id -> SP5BLeg in
            let rule = Phase0Registry.legRules[id]!
            if let artifact = SP5BDirectoryLayout.legArtifacts[id] {
                return .init(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true, verdict: .pass,
                    blocker: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: Canonical.sha256(environment), command: ["fixture", id], exitStatus: 0,
                    artifactPath: artifact, artifactSha256: Canonical.sha256(artifacts[artifact]!))
            }
            return .init(legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: false, verdict: .blocked,
                blocker: SP1Blocker(blockedBy: "approved_vial_device_capture_absent", detectCommand: ["environment-inventory", "approved-vial-device"], prerequisite: "approved Vial keyboard and capture authorization", unblockAction: "run separately approved capture without writes"),
                runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: Canonical.sha256(environment), command: [], exitStatus: nil, artifactPath: nil, artifactSha256: nil)
        }
        let evidence = SP5BEvidence(legs: legs, verdict: .blocked, runnerSourceSha256: Dictionary(uniqueKeysWithValues: SP5BRunnerBinding.sourcePaths.map { ($0, hash) }))
        try pretty(evidence).write(to: output.appendingPathComponent("evidence.json"))
        try conclusion().write(to: output.appendingPathComponent("SP-5B-CONCLUSION.md"))
        let fixture = SP5BValidatorFixture(container: container, repository: repository, output: output, evidence: evidence)
        try fixture.writeManifest()
        return fixture
    }

    func mutate(_ name: String, replacing old: String, with new: String) throws {
        let url = output.appendingPathComponent(name)
        var text = try String(contentsOf: url); text = text.replacingOccurrences(of: old, with: new)
        try Data(text.utf8).write(to: url); try writeManifest()
    }
    func writeManifest() throws {
        let rows = try SP5BDirectoryLayout.artifactNames.sorted().map { "\(Canonical.sha256(try Data(contentsOf: output.appendingPathComponent($0))))  \($0)" }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: output.appendingPathComponent("manifest.sha256"))
    }
    func remove() { try? FileManager.default.removeItem(at: container) }

    private static func makeArtifacts(_ repository: URL) throws -> [String: Data] {
        ["source-facts.json": try pretty(SP5BScenarios.sourceFacts(repository: repository)),
         "replay.json": try pretty(SP5BScenarios.replay(repository: repository)),
         "deny-mutation.json": try pretty(SP5BScenarios.denyMutation(repository: repository))]
    }
    private static func conclusion() -> Data {
        Data("# SP-5B conclusion\n\nVerdict: **BLOCKED**\n\nPinned source and the exact deterministic synthetic recorded-response fixture prove only whitelist-constrained non-changing queries and replay reconstruction; outbound HID reports are not literally read-only. No unlock, reset, bootloader, EEPROM, macro, or keymap write is representable. Live HID capture remains **BLOCKED** because the exact environment inventory has no approved Vial device and Vial is absent. No IOHID API was called, no device was enumerated or opened, no GUI was launched, and no report was sent to a real device. Synthetic replay does not prove device-side behavior or device compatibility.\n".utf8)
    }
    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
}

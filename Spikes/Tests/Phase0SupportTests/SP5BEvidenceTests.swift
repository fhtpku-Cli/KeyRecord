import Foundation
import XCTest
@testable import Phase0Support

final class SP5BEvidenceTests: XCTestCase {
    func testPinnedSourceReplayAndDenyArtifactsRecompute() throws {
        let root = repositoryRoot()
        let facts = try SP5BScenarios.sourceFacts(repository: root)
        let replay = try SP5BScenarios.replay(repository: root)
        let deny = try SP5BScenarios.denyMutation(repository: root)
        XCTAssertTrue(SP5BScenarios.validates(facts))
        XCTAssertTrue(SP5BScenarios.validates(replay))
        XCTAssertTrue(SP5BScenarios.validates(deny))
        XCTAssertEqual(facts.whitelist.map(\.opcode), ["0xFE/0x00", "0xFE/0x00", "0xFE/0x01 size; 0xFE/0x02 page", "0x12"])
        XCTAssertTrue(facts.whitelist.allSatisfy { !$0.anchors.isEmpty })
        XCTAssertTrue(facts.whitelist.flatMap(\.anchors).allSatisfy {
            $0.revision.count == 40 && $0.tree.count == 40 && $0.gitBlob.count == 40
                && $0.snippetSha256.count == 64 && $0.licenseGitBlob.count == 40
        })
        XCTAssertEqual(replay.reportCount, 6)
        XCTAssertEqual(deny.attempts.count, 19)
        XCTAssertTrue(deny.attempts.allSatisfy { $0.rejected && $0.transportCallCount == 0 })
    }

    func testClosedLegSetRequiresThreePassesAndCompleteLiveBlocker() throws {
        let evidence = makeEvidence()
        XCTAssertNoThrow(try evidence.validate())
        XCTAssertEqual(evidence.verdict, .blocked)
        XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.count, 3)
        XCTAssertEqual(evidence.legs.first { $0.legID == "sp5b.liveCapture" }?.blocker?.blockedBy, "approved_vial_device_capture_absent")

        var value = evidence; value.legs.removeLast()
        XCTAssertEqual(validationError(value), .missingLeg)
        value = evidence; value.legs.append(value.legs[0])
        XCTAssertEqual(validationError(value), .duplicateLeg)
        value = evidence; value.verdict = .pass
        XCTAssertEqual(validationError(value), .invalidAggregate)
        value = evidence
        let live = value.legs.firstIndex { $0.legID == "sp5b.liveCapture" }!
        value.legs[live].blocker = SP1Blocker(blockedBy: "", detectCommand: [], prerequisite: "", unblockAction: "")
        XCTAssertEqual(validationError(value), .invalidBlocker)
    }

    func testEvidenceDecoderRejectsUnknownFields() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(makeEvidence())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["forged"] = "PASS"
        let forged = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(SP5BEvidence.self, from: forged))
    }

    private func makeEvidence() -> SP5BEvidence {
        let commit = String(repeating: "a", count: 40), tree = String(repeating: "b", count: 40)
        let hash = String(repeating: "c", count: 64)
        let source = Dictionary(uniqueKeysWithValues: SP5BRunnerBinding.sourcePaths.map { ($0, hash) })
        let legs = SP5BEvidence.requiredLegIDs.sorted().map { id -> SP5BLeg in
            let rule = Phase0Registry.legRules[id]!
            if let artifact = SP5BDirectoryLayout.legArtifacts[id] {
                return .init(
                    legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                    detectorAvailable: true, verdict: .pass, blocker: nil, runnerCommitSha: commit,
                    runnerTreeSha: tree, environmentSha256: hash, command: ["fixture", id], exitStatus: 0,
                    artifactPath: artifact, artifactSha256: hash
                )
            }
            return .init(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                detectorAvailable: false, verdict: .blocked,
                blocker: SP1Blocker(
                    blockedBy: "approved_vial_device_capture_absent",
                    detectCommand: ["environment-inventory", "approved-vial-device"],
                    prerequisite: "approved device and capture authorization",
                    unblockAction: "run separately approved capture"
                ), runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: hash,
                command: [], exitStatus: nil, artifactPath: nil, artifactSha256: nil
            )
        }
        return SP5BEvidence(legs: legs, verdict: .blocked, runnerSourceSha256: source)
    }

    private func validationError(_ value: SP5BEvidence) -> SP5BValidationError? {
        do { try value.validate(); return nil }
        catch let error as SP5BValidationError { return error }
        catch { return nil }
    }
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

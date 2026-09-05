import XCTest
@testable import Phase0Support

final class SP4BEvidenceTests: XCTestCase {
    func testExactClosedLegSetAndEvidenceBlockerXOR() throws {
        let evidence = makeEvidence()
        XCTAssertNoThrow(try evidence.validate())
        XCTAssertEqual(evidence.verdict, .blocked)
        XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.map(\.legID).sorted(), ["sp4b.bounds", "sp4b.layoutRoundTrip"])
        XCTAssertEqual(evidence.legs.filter { $0.verdict == .blocked }.count, 3)
        XCTAssertTrue(evidence.legs.allSatisfy { ($0.artifactPath != nil) != ($0.blocker != nil) })
    }

    func testMissingDuplicateMisleadingPassAndPartialBlockerReject() {
        var value = makeEvidence()
        value.legs.removeLast()
        XCTAssertEqual(validationError(value), .missingLeg)
        value = makeEvidence(); value.legs.append(value.legs[0])
        XCTAssertEqual(validationError(value), .duplicateLeg)
        value = makeEvidence()
        let importer = value.legs.firstIndex { $0.legID == "sp4b.importer" }!
        value.legs[importer].verdict = .pass
        value.legs[importer].detectorAvailable = true
        value.legs[importer].blocker = nil
        value.legs[importer].command = ["misleading-pass"]
        value.legs[importer].exitStatus = 0
        value.legs[importer].artifactPath = "round-trip.json"
        value.legs[importer].artifactSha256 = String(repeating: "f", count: 64)
        XCTAssertEqual(validationError(value), .invalidBlocker)
        value = makeEvidence()
        let protocolLeg = value.legs.firstIndex { $0.legID == "sp4b.deviceProtocol" }!
        value.legs[protocolLeg].blocker = SP1Blocker(blockedBy: "", detectCommand: [], prerequisite: "", unblockAction: "")
        XCTAssertEqual(validationError(value), .invalidBlocker)
    }

    private func makeEvidence() -> SP4BEvidence {
        let commit = String(repeating: "a", count: 40)
        let tree = String(repeating: "b", count: 40)
        let hash = String(repeating: "c", count: 64)
        let sourceHashes = Dictionary(uniqueKeysWithValues: SP4BRunnerBinding.sourcePaths.map { ($0, hash) })
        let legs = SP4BEvidence.requiredLegIDs.sorted().map { id -> SP4BLeg in
            let rule = Phase0Registry.legRules[id]!
            if let artifact = SP4BDirectoryLayout.legArtifacts[id] {
                return SP4BLeg(
                    legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                    detectorAvailable: true, verdict: .pass, blocker: nil, runnerCommitSha: commit,
                    runnerTreeSha: tree, environmentSha256: hash, command: ["fixture", id], exitStatus: 0,
                    artifactPath: artifact, artifactSha256: hash
                )
            }
            return SP4BLeg(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                detectorAvailable: false, verdict: .blocked,
                blocker: SP1Blocker(blockedBy: "blocked_\(id)", detectCommand: ["environment-inventory", id], prerequisite: "approved prerequisite", unblockAction: "run separately approved procedure"),
                runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: hash,
                command: [], exitStatus: nil, artifactPath: nil, artifactSha256: nil
            )
        }
        return SP4BEvidence(legs: legs, verdict: .blocked, runnerSourceSha256: sourceHashes)
    }

    private func validationError(_ value: SP4BEvidence) -> SP4BValidationError? {
        do { try value.validate(); return nil }
        catch let error as SP4BValidationError { return error }
        catch { return nil }
    }
}

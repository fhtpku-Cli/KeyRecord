import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP1ValidatorV3Tests: XCTestCase {
    private static let syntheticIDs: Set<String> = ["sp1.autoRepeat", "sp1.o7Boundary", "sp1.productStampedDrop", "sp1.tapReset"]
    private static let matrixIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]

    func testNotArmedV3DirectoryValidates() throws {
        let fixture = try makeNotArmedFixture(karabinerInstalled: false)
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
        let evidence = try fixture.evidence()
        XCTAssertEqual(evidence.schemaVersion, 3)
        XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.systemShortcut" }?.blocker, SP1CanonicalBlockers.liveExecutionNotArmed)
        XCTAssertEqual(evidence.legs.first { $0.legID == "sp1.tap.session.matrix" }?.blocker, SP1CanonicalBlockers.v2KarabinerAbsent)
    }

    func testNotArmedWithKarabinerUsesLiveExecutionBlocker() throws {
        let fixture = try makeNotArmedFixture(karabinerInstalled: true)
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
        let evidence = try fixture.evidence()
        for leg in evidence.legs where Self.matrixIDs.contains(leg.legID) {
            XCTAssertEqual(leg.blocker, SP1CanonicalBlockers.liveExecutionNotArmed, leg.legID)
        }
    }

    func testV3RejectsLegacyNotImplementedBlocker() throws {
        let fixture = try makeNotArmedFixture(karabinerInstalled: true)
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("evidence.json")
        var evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: url))
        let index = evidence.legs.firstIndex { $0.legID == "sp1.systemShortcut" }!
        evidence.legs[index].blocker = SP1CanonicalBlockers.systemShortcutExecutionNotImplemented
        try writeCanonical(evidence, to: url)
        try fixture.remanifest()
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository) }, "sp1_live_semantics_invalid")
    }

    func testSelectedSessionWithSharedLiveHashValidates() throws {
        let fixture = try makePassingSelectionFixture()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository))
        let evidence = try fixture.evidence()
        XCTAssertEqual(evidence.selectedTapIdentity?.tapType, "session")
        XCTAssertEqual(evidence.verdict, .pass)
    }

    func testV3RejectsMissingD1() throws {
        let fixture = try makeNotArmedFixture(karabinerInstalled: false, listenEventAccess: "denied")
        defer { fixture.remove() }
        XCTAssertEqual(code { _ = try SP1DirectoryValidator.validate(directory: fixture.directory, repository: fixture.repository) }, "sp1_v3_requires_d1")
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
        func evidence() throws -> SP1Evidence {
            try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: directory.appendingPathComponent("evidence.json")))
        }
    }

    private func makeNotArmedFixture(karabinerInstalled: Bool, listenEventAccess: String = "available") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-v3-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("sp1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let synthetic = try SP1SyntheticScenarios.run().canonicalJSON()
        let live = try encode(SP1LiveAggregateArtifact(systemShortcutObservedCount: 0, unmarkedObservedCount: 0))
        try synthetic.write(to: directory.appendingPathComponent("product-stamped-synthetic.json"))
        try live.write(to: directory.appendingPathComponent("live-aggregate-counts.json"))
        let environmentBytes = Data(environmentJSON(listenEventAccess: listenEventAccess, karabinerInstalled: karabinerInstalled).utf8)
        try environmentBytes.write(to: root.appendingPathComponent("environment.json"))
        let (commit, tree, sources) = try makeRepository(at: root.appendingPathComponent("repo"))
        let environment = Canonical.sha256(environmentBytes)
        let syntheticHash = Canonical.sha256(synthetic)
        let matrixBlocker = karabinerInstalled ? SP1CanonicalBlockers.liveExecutionNotArmed : SP1CanonicalBlockers.v2KarabinerAbsent
        let legs = SP1Evidence.requiredLegIDs.sorted().map { legID -> SP1Leg in
            if Self.syntheticIDs.contains(legID) {
                return SP1Leg(legID: legID, verdict: .pass, detectorAvailable: true, blocker: nil, identity: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment, artifactSha256: syntheticHash, matrix: nil, aggregateCount: nil)
            }
            let blocker = legID == "sp1.systemShortcut" ? SP1CanonicalBlockers.liveExecutionNotArmed : matrixBlocker
            return SP1Leg(legID: legID, verdict: .blocked, detectorAvailable: false, blocker: blocker, identity: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment, artifactSha256: nil, matrix: nil, aggregateCount: nil)
        }
        var evidence = SP1Evidence(selectedTapIdentity: nil, legs: legs, verdict: .blocked, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: sources)
        evidence.schemaVersion = 3
        try writeCanonical(evidence, to: directory.appendingPathComponent("evidence.json"))
        try SP1CanonicalNarratives.o7().write(to: directory.appendingPathComponent("O7-ADDENDUM.md"))
        try SP1CanonicalNarratives.conclusion(for: evidence).write(to: directory.appendingPathComponent("SP-1-CONCLUSION.md"))
        let fixture = Fixture(root: root)
        try fixture.remanifest()
        return fixture
    }

    private func makePassingSelectionFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sp1-v3-pass-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("sp1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let synthetic = try SP1SyntheticScenarios.run().canonicalJSON()
        let live = try encode(SP1LiveAggregateArtifact(systemShortcutObservedCount: 1, unmarkedObservedCount: 0))
        try synthetic.write(to: directory.appendingPathComponent("product-stamped-synthetic.json"))
        try live.write(to: directory.appendingPathComponent("live-aggregate-counts.json"))
        let environmentBytes = Data(environmentJSON(listenEventAccess: "available", karabinerInstalled: true).utf8)
        try environmentBytes.write(to: root.appendingPathComponent("environment.json"))
        let (commit, tree, sources) = try makeRepository(at: root.appendingPathComponent("repo"))
        let environment = Canonical.sha256(environmentBytes)
        let syntheticHash = Canonical.sha256(synthetic)
        let liveHash = Canonical.sha256(live)
        let selected = SelectedTapIdentity(
            tapType: "session",
            attemptID: SP1AttemptIdentity.attemptID(
                runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment,
                tapConfigSha256: SP1TapConfiguration.sha256(tapType: "session"), nonce: "phase0-sp1-attempt"
            ),
            runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment,
            tapConfigSha256: SP1TapConfiguration.sha256(tapType: "session")
        )
        let matrix = TapMatrixObservation(
            offObservedCode: 79, offCount: 1, onObservedCode: 80, onCount: 1,
            expectedPhysicalCode: 79, expectedTransformedCode: 80
        )
        let legs = SP1Evidence.requiredLegIDs.sorted().map { legID -> SP1Leg in
            if Self.syntheticIDs.contains(legID) {
                return SP1Leg(legID: legID, verdict: .pass, detectorAvailable: true, blocker: nil, identity: selected, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment, artifactSha256: syntheticHash, matrix: nil, aggregateCount: nil)
            }
            if legID == "sp1.systemShortcut" {
                return SP1Leg(legID: legID, verdict: .pass, detectorAvailable: true, blocker: nil, identity: selected, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment, artifactSha256: liveHash, matrix: nil, aggregateCount: 1)
            }
            let bound = legID == "sp1.tap.session.matrix"
            return SP1Leg(legID: legID, verdict: .pass, detectorAvailable: true, blocker: nil, identity: bound ? selected : nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environment, artifactSha256: liveHash, matrix: matrix, aggregateCount: nil)
        }
        var evidence = SP1Evidence(selectedTapIdentity: selected, legs: legs, verdict: .pass, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: sources)
        evidence.schemaVersion = 3
        try writeCanonical(evidence, to: directory.appendingPathComponent("evidence.json"))
        try SP1CanonicalNarratives.o7().write(to: directory.appendingPathComponent("O7-ADDENDUM.md"))
        try SP1CanonicalNarratives.conclusion(for: evidence).write(to: directory.appendingPathComponent("SP-1-CONCLUSION.md"))
        let fixture = Fixture(root: root)
        try fixture.remanifest()
        return fixture
    }

    private func makeRepository(at url: URL) throws -> (commit: String, tree: String, sources: [String: String]) {
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
        return (
            try gitOutput(["rev-parse", "HEAD"], at: url),
            try gitOutput(["rev-parse", "HEAD^{tree}"], at: url),
            sources
        )
    }

    private func environmentJSON(listenEventAccess: String, karabinerInstalled: Bool) -> String {
        """
        {"macOS":{"version":"26.6.1","build":"25G76"},"architecture":"arm64","swift":"Swift 6","xcode":"Xcode 26","generatedAt":"2026-01-01T00:00:00Z","guiSession":{"status":"available","tapCreate":"available"},"listenEventAccess":"\(listenEventAccess)","hidAccess":"unknown","sudoNonInteractive":false,"applications":[{"name":"Karabiner-Elements","status":"\(karabinerInstalled ? "installed" : "absent")"}],"hidSummary":{"deviceCount":0,"devices":[]},"sourceReachability":{"status":"unavailable","httpStatus":null}}
        """
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }

    private func writeCanonical<T: Encodable>(_ value: T, to url: URL) throws {
        try encode(value).write(to: url)
    }

    private func code(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
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

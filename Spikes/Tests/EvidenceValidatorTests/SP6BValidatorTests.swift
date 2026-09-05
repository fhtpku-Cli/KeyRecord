import XCTest
@testable import Phase0Support
@testable import EvidenceValidator

final class SP6BValidatorTests: XCTestCase {
    func testClosedLegAndArtifactSetsMatchRegistry() {
        XCTAssertEqual(SP6BEvidence.requiredLegIDs, [
            "sp6b.phcAudit", "sp6b.swiftAudit", "sp6b.vectors", "sp6b.universalBuild",
            "sp6b.armTiming", "sp6b.intelTiming", "sp6b.securityAudit",
        ])
        XCTAssertEqual(Set(SP6BDirectoryLayout.legArtifacts.keys), SP6BEvidence.requiredLegIDs.subtracting(["sp6b.intelTiming"]))
    }

    func testIntelBlockerIsCompleteAndDoesNotClaimExecution() {
        XCTAssertTrue(SP6BBlockers.intelHost.complete)
        XCTAssertEqual(SP6BBlockers.intelHost.detectCommand, ["uname", "-m"])
    }

    func testRecommendationRemainsUnfrozenAndRejectsMisrankedCandidate() throws {
        let fixture = SP6BCandidateEvaluation(
            schemaVersion: 1, generatedAt: "2026-09-05T00:00:00Z",
            candidates: [.fixture], scores: ["phc": try Argon2Candidate.fixture.score(at: ISO8601DateFormatter().date(from: "2026-09-05T00:00:00Z")!)],
            eligibleCandidateIDs: ["phc"], recommendation: "phc", dependencyFrozen: false
        )
        XCTAssertThrowsError(try fixture.validate())
    }

    func testCoordinatedValidCandidatePinSubstitutionRejects() throws {
        let fixture = try SP6BIntegrityFixture.make()
        defer { fixture.remove() }
        let alternateCommit = String(repeating: "a", count: 40)
        let alternateTree = String(repeating: "b", count: 40)
        try fixture.replace(in: "candidate-evaluation.json", "f57e61e19229e23c4445b85494dbf7c07de721cb", alternateCommit)
        try fixture.replace(in: "candidate-evaluation.json", "ac3dc753ff75ce5a0f243cba1d94582bafe09409", alternateTree)
        try fixture.replace(in: "d12/snapshot.json", "f57e61e19229e23c4445b85494dbf7c07de721cb", alternateCommit)
        try fixture.remanifest()
        try assertRejects(fixture, code: "sp6b_candidate_provenance")
    }

    func testArbitraryNVDDispositionRejects() throws {
        let fixture = try SP6BIntegrityFixture.make()
        defer { fixture.remove() }
        try fixture.replace(
            in: "d12/snapshot.json",
            "Directus authorization flaw exposes stored hashes; its Directus CPE and code are outside both pinned candidate trees.",
            "arbitrary reviewed-looking rationale"
        )
        try fixture.remanifest()
        try assertRejects(fixture, code: "sp6b_nvd_disposition_rationale")
    }

    func testTextOnlySwiftVectorPassRejects() throws {
        let fixture = try SP6BIntegrityFixture.make()
        defer { fixture.remove() }
        try Data("SWIFT_RFC9106_VECTOR=PASS tag=forged\n".utf8).write(to: fixture.output.appendingPathComponent("build/swift-vector.txt"))
        try fixture.remanifest()
        try assertRejects(fixture, code: "sp6b_vector_observation")
    }

    func testUnrelatedDualArchitectureArchiveRejectsAfterAllHashesRebound() throws {
        let fixture = try SP6BIntegrityFixture.make()
        defer { fixture.remove() }
        let archive = fixture.output.appendingPathComponent("build/argon2-universal.a")
        try fixture.writeUnrelatedUniversalArchive(to: archive)
        let hash = Canonical.sha256(try Data(contentsOf: archive))
        try fixture.replaceJSON(path: "build/build.json", transform: { $0["archiveSha256"] = hash })
        let buildHash = Canonical.sha256(try Data(contentsOf: fixture.output.appendingPathComponent("build/build.json")))
        try fixture.replaceJSON(path: "evidence.json", transform: { root in
            var legs = root["legs"] as! [[String: Any]]
            let archiveIndex = legs.firstIndex { $0["legID"] as? String == "sp6b.universalBuild" }!
            let vectorsIndex = legs.firstIndex { $0["legID"] as? String == "sp6b.vectors" }!
            legs[archiveIndex]["artifactSha256"] = hash
            legs[vectorsIndex]["artifactSha256"] = buildHash
            root["legs"] = legs
        })
        try fixture.remanifest()
        try assertRejects(fixture, code: "sp6b_build_archive_hash")
    }

    private func assertRejects(
        _ fixture: SP6BIntegrityFixture, code: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertThrowsError(
            try SP6BDirectoryValidator.validate(directory: fixture.output, repository: fixture.repository),
            file: file, line: line
        ) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, code, file: file, line: line)
        }
    }
}

private struct SP6BIntegrityFixture {
    let container: URL
    let repository: URL
    let output: URL

    static func make() throws -> Self {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRepository = current.lastPathComponent == "Spikes" ? current.deletingLastPathComponent() : current
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp6b-integrity-\(UUID().uuidString)")
        let repository = container.appendingPathComponent("repository")
        let output = container.appendingPathComponent("sp6b")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let clone = Process()
        clone.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        clone.arguments = ["clone", "--quiet", sourceRepository.path, repository.path]
        try clone.run()
        clone.waitUntilExit()
        guard clone.terminationStatus == 0 else { throw CocoaError(.executableNotLoadable) }
        try FileManager.default.copyItem(at: repository.appendingPathComponent("evidence/phase0/sp6b"), to: output)
        return Self(container: container, repository: repository, output: output)
    }

    func remove() { try? FileManager.default.removeItem(at: container) }

    func replace(in path: String, _ old: String, _ new: String) throws {
        let url = output.appendingPathComponent(path)
        var text = try String(contentsOf: url, encoding: .utf8)
        guard text.contains(old) else { throw CocoaError(.coderInvalidValue) }
        text = text.replacingOccurrences(of: old, with: new)
        try Data(text.utf8).write(to: url)
    }

    func replaceJSON(path: String, transform: (inout [String: Any]) -> Void) throws {
        let url = output.appendingPathComponent(path)
        var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        transform(&value)
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data([10])).write(to: url)
    }

    func remanifest() throws {
        let enumerator = FileManager.default.enumerator(atPath: output.path)!
        var paths: [String] = []
        for case let path as String in enumerator where URL(fileURLWithPath: path).lastPathComponent != "manifest.sha256" {
            let url = output.appendingPathComponent(path)
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                paths.append(path)
            }
        }
        let rows = try paths.sorted().map { "\(Canonical.sha256(try Data(contentsOf: output.appendingPathComponent($0))))  \($0)" }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: output.appendingPathComponent("manifest.sha256"))
    }

    func writeUnrelatedUniversalArchive(to destination: URL) throws {
        let source = container.appendingPathComponent("unrelated.c")
        try Data("int unrelated(void) { return 7; }\n".utf8).write(to: source)
        var slices: [URL] = []
        for architecture in ["x86_64", "arm64"] {
            let object = container.appendingPathComponent("unrelated-\(architecture).o")
            let archive = container.appendingPathComponent("unrelated-\(architecture).a")
            try run("/usr/bin/clang", ["-arch", architecture, "-c", source.path, "-o", object.path])
            try run("/usr/bin/ar", ["-rcs", archive.path, object.path])
            slices.append(archive)
        }
        try run("/usr/bin/lipo", ["-create", slices[0].path, slices[1].path, "-output", destination.path])
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableNotLoadable) }
    }
}

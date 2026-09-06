import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class ConclusionGeneratorTests: XCTestCase {
    func testVerdictPrecedenceIsFailBlockedInconclusivePass() {
        XCTAssertEqual(ConclusionDeriver.aggregate([.pass, .inconclusive]), .inconclusive)
        XCTAssertEqual(ConclusionDeriver.aggregate([.pass, .blocked, .inconclusive]), .blocked)
        XCTAssertEqual(ConclusionDeriver.aggregate([.blocked, .fail]), .fail)
    }

    func testRequiredConclusionSetsRemainExact() {
        XCTAssertEqual(ConclusionContract.spikeIDs, ["SP-1", "SP-2", "SP-3", "SP-4A", "SP-4B", "SP-5A", "SP-5B", "SP-6A", "SP-6B"])
        XCTAssertEqual(ConclusionContract.oItemIDs, ["O1", "O2", "O3", "O4", "O5", "O6", "O7"])
        XCTAssertEqual(Set(ConclusionContract.o4IDs), Phase0Registry.o4IDs)
        XCTAssertEqual(ConclusionContract.downstreamBlockIDs, ["G1", "KARABINER_STABLE", "VIA_GENERATION", "VIAL_BETA", "FULL_BACKUP_FINAL_RELEASE"])
    }

    func testDownstreamRerunsMatchPlanTasksExactly() throws {
        let document = try deriveCanonicalConclusions()
        let reruns = Dictionary(uniqueKeysWithValues: document.downstreamBlocks.map { ($0.id, $0.rerunArgv) })
        XCTAssertEqual(reruns["G1"], qa([5, 6, 10]))
        XCTAssertEqual(reruns["KARABINER_STABLE"], qa([7]))
        XCTAssertEqual(reruns["VIA_GENERATION"], qa([12]))
        XCTAssertEqual(reruns["VIAL_BETA"], qa([9, 13]))
        XCTAssertEqual(reruns["FULL_BACKUP_FINAL_RELEASE"], qa([11]))
    }

    func testVialDefinitionSchemaUsesPinnedVersionOneFormatFacts() throws {
        let document = try deriveCanonicalConclusions()
        let row = try XCTUnwrap(document.o4Matrix.first { $0.id == "vial.definitionSchema" })
        XCTAssertEqual(row.evidencePath, "sp5a/format-facts.json")
    }

    func testVialDefinitionSchemaRejectsSemanticallyUnrelatedEvidenceSubstitution() throws {
        let repository = try repositoryRoot()
        let source = try rawEvidenceRoot(repository: repository)
        defer { if source != repository.appendingPathComponent("evidence/phase0") { try? FileManager.default.removeItem(at: source) } }
        let document = try deriveCanonicalConclusions()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        var rows = try XCTUnwrap(object["o4_matrix"] as? [[String: Any]])
        let index = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == "vial.definitionSchema" })
        rows[index]["evidence_path"] = "sp5a/bounds.json"
        rows[index]["evidence_sha256"] = Canonical.sha256(try Data(contentsOf: source.appendingPathComponent("sp5a/bounds.json")))
        object["o4_matrix"] = rows
        let substituted = try JSONDecoder().decode(
            Phase0Conclusions.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertThrowsError(try ConclusionValidator.validateVialDefinitionSchema(
            substituted,
            root: source,
            repository: repository
        )) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, "vial_definition_schema_evidence_invalid")
        }
    }

    func testHistoricalSourceRejectsCoordinatedChildRemanifest() throws {
        let repository = try repositoryRoot()
        let canonical = try rawEvidenceRoot(repository: repository)
        let source = temporaryURL("coordinated-source")
        try FileManager.default.copyItem(at: canonical, to: source)
        let output = temporaryURL("coordinated-remanifest")
        defer {
            try? FileManager.default.removeItem(at: source)
            if canonical != repository.appendingPathComponent("evidence/phase0") {
                try? FileManager.default.removeItem(at: canonical)
            }
            try? FileManager.default.removeItem(at: output)
        }
        let evidenceURL = source.appendingPathComponent("sp1/evidence.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: evidenceURL)) as? [String: Any])
        object["coordinated_extra"] = "mutated-copy"
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: evidenceURL)
        try remanifest(source.appendingPathComponent("sp1"))
        try remanifest(source, names: ["README.md", "environment.json", "privacy-audit.json", "run-all.json"])
        let sourceCommit = try XCTUnwrap(recordedSourceCommit(repository: repository))
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        XCTAssertNotEqual(
            try Data(contentsOf: evidenceURL),
            try git.run(["cat-file", "blob", "\(sourceCommit):evidence/phase0/sp1/evidence.json"]).stdout
        )
        XCTAssertThrowsError(try HistoricalEvidenceInventoryValidator.validate(
            root: source,
            sourceCommit: sourceCommit,
            repository: repository
        ))
        XCTAssertThrowsError(try ConclusionGenerator.generate(
            sourceRoot: source,
            outputRoot: output,
            repository: repository,
            sourceCommitSha: sourceCommit
        )) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, "source_evidence_bytes_mismatch")
        }
    }

    func testCanonicalEvidenceGeneratesDeterministicallyAndValidatesIndependently() throws {
        let repository = try repositoryRoot()
        let first = temporaryURL("conclusions-first")
        let second = temporaryURL("conclusions-second")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let source = try rawEvidenceRoot(repository: repository)
        let sourceCommit = try recordedSourceCommit(repository: repository)
        defer { if source != repository.appendingPathComponent("evidence/phase0") { try? FileManager.default.removeItem(at: source) } }
        do { try ConclusionGenerator.generate(sourceRoot: source, outputRoot: first, repository: repository, sourceCommitSha: sourceCommit) }
        catch { XCTFail("first generation: \(error)"); return }
        do { try ConclusionGenerator.generate(sourceRoot: source, outputRoot: second, repository: repository, sourceCommitSha: sourceCommit) }
        catch { XCTFail("second generation: \(error)"); return }

        let firstJSON = try Data(contentsOf: first.appendingPathComponent("conclusions.json"))
        let secondJSON = try Data(contentsOf: second.appendingPathComponent("conclusions.json"))
        XCTAssertEqual(Canonical.sha256(firstJSON), Canonical.sha256(secondJSON))
        let report = try ConclusionValidator.validate(root: first, repository: repository)
        XCTAssertEqual(report.spikeCount, 9)
        XCTAssertEqual(report.oItemCount, 7)
        XCTAssertEqual(report.o4RowCount, 15)
        XCTAssertEqual(report.downstreamBlockCount, 5)
        XCTAssertEqual(report.g0Status, .open)
    }

    func testCommittedEvidenceOnlyDescendantRecomputesAgainstRecordedGeneratorCommit() throws {
        let repository = try repositoryRoot()
        guard FileManager.default.fileExists(atPath: repository.appendingPathComponent("evidence/phase0/conclusions.json").path) else {
            throw XCTSkip("task-15 conclusions are not generated in the raw task-14 state")
        }
        let report = try ConclusionValidator.validate(
            root: repository.appendingPathComponent("evidence/phase0"),
            repository: repository,
            strictRepositoryBinding: true
        )
        XCTAssertEqual(report.spikeCount, 9)
        XCTAssertEqual(report.g0Status, .open)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-\(name)-\(UUID().uuidString)")
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("evidence/phase0/run-all.json").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func rawEvidenceRoot(repository: URL) throws -> URL {
        let canonical = repository.appendingPathComponent("evidence/phase0")
        let conclusions = canonical.appendingPathComponent("conclusions.json")
        guard FileManager.default.fileExists(atPath: conclusions.path) else { return canonical }
        let document = try JSONDecoder().decode(Phase0Conclusions.self, from: Data(contentsOf: conclusions))
        let raw = temporaryURL("raw-evidence")
        try FileManager.default.copyItem(at: canonical, to: raw)
        for name in ["conclusions.json"] + ConclusionContract.spikeIDs.map({ "\($0)-CONCLUSION.md" }) {
            try FileManager.default.removeItem(at: raw.appendingPathComponent(name))
        }
        for name in ["manifest.sha256", "privacy-audit.json", "run-all.json"] {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["cat-file", "blob", "\(document.sourceEvidenceCommitSha):evidence/phase0/\(name)"]
            process.currentDirectoryURL = repository
            process.standardOutput = output
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
            try output.fileHandleForReading.readDataToEndOfFile().write(to: raw.appendingPathComponent(name))
        }
        return raw
    }

    private func recordedSourceCommit(repository: URL) throws -> String? {
        let conclusions = repository.appendingPathComponent("evidence/phase0/conclusions.json")
        if FileManager.default.fileExists(atPath: conclusions.path) {
            return try JSONDecoder().decode(Phase0Conclusions.self, from: Data(contentsOf: conclusions)).sourceEvidenceCommitSha
        }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = repository
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deriveCanonicalConclusions() throws -> Phase0Conclusions {
        let repository = try repositoryRoot()
        let source = try rawEvidenceRoot(repository: repository)
        defer { if source != repository.appendingPathComponent("evidence/phase0") { try? FileManager.default.removeItem(at: source) } }
        return try ConclusionGenerator.derive(root: source, repository: repository, strictRepositoryBinding: false, sourceCommitSha: try recordedSourceCommit(repository: repository))
    }

    private func qa(_ tasks: [Int]) -> [[String]] {
        tasks.map { ["bash", "Spikes/Scripts/run-task-qa.sh", String($0), "happy"] }
    }

    private func remanifest(_ directory: URL, names: [String]? = nil) throws {
        let files = try names ?? FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" }
        let lines = try files.sorted().map { name in
            "\(Canonical.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))  \(name)"
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
}

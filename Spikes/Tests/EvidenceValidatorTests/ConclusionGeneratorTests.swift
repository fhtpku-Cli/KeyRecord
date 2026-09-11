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
        let document = try JSONDecoder().decode(Phase0Conclusions.self, from: firstJSON)
        XCTAssertEqual(report.spikeCount, 9)
        XCTAssertEqual(report.oItemCount, 7)
        XCTAssertEqual(report.o4RowCount, 15)
        XCTAssertEqual(report.downstreamBlockCount, 5)
        XCTAssertEqual(report.g0Status, document.g0.status)
        if report.g0Status == .passed {
            XCTAssertTrue(document.g0.blockingLegIDs.isEmpty)
        }
    }

    func testConclusionAncestryRejectsSourceNewerThanGenerator() throws {
        let repository = try repositoryRoot()
        let root = repository.appendingPathComponent("evidence/phase0")
        try skipIfEvidenceDriftsFromRecordedSource(repository: repository)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("conclusions.json").path) else {
            throw XCTSkip("concluded phase0 evidence is not present")
        }
        let copy = temporaryURL("ancestry-source-newer")
        try FileManager.default.copyItem(at: root, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let document = try JSONDecoder().decode(Phase0Conclusions.self, from: Data(contentsOf: copy.appendingPathComponent("conclusions.json")))
        let unrelatedSource = try gitText(
            [
                "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit-tree", document.sourceEvidenceTreeSha, "-m", "unrelated-source",
            ],
            repository: repository
        )
        let mutated = Phase0Conclusions(
            schemaVersion: document.schemaVersion,
            sourceEvidenceCommitSha: unrelatedSource,
            sourceEvidenceTreeSha: document.sourceEvidenceTreeSha,
            sourceRootManifestSha256: document.sourceRootManifestSha256,
            generatorCommitSha: document.generatorCommitSha,
            generatorTreeSha: document.generatorTreeSha,
            generatorSourceSha256: document.generatorSourceSha256,
            spikes: document.spikes,
            oItems: document.oItems,
            o4Matrix: document.o4Matrix,
            downstreamBlocks: document.downstreamBlocks,
            g0: document.g0
        )
        try JSONEncoder().encode(mutated).write(to: copy.appendingPathComponent("conclusions.json"))
        try refreshConclusionsManifest(copy)
        XCTAssertEqual(
            code { try ConclusionValidator.validate(root: copy, repository: repository, strictRepositoryBinding: true) },
            "source_evidence_not_ancestor_of_generator"
        )
    }

    func testConclusionAncestryRejectsGeneratorNewerThanHead() throws {
        let repository = try repositoryRoot()
        let root = repository.appendingPathComponent("evidence/phase0")
        try skipIfEvidenceDriftsFromRecordedSource(repository: repository)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("conclusions.json").path) else {
            throw XCTSkip("concluded phase0 evidence is not present")
        }
        let copy = temporaryURL("ancestry-generator-newer")
        try FileManager.default.copyItem(at: root, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let document = try JSONDecoder().decode(Phase0Conclusions.self, from: Data(contentsOf: copy.appendingPathComponent("conclusions.json")))
        let unrelatedGenerator = try gitText(
            [
                "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit-tree", document.sourceEvidenceTreeSha, "-p", document.sourceEvidenceCommitSha,
                "-m", "unrelated-generator",
            ],
            repository: repository
        )
        let unrelatedTree = try gitText(["rev-parse", "\(unrelatedGenerator)^{tree}"], repository: repository)
        let mutated = Phase0Conclusions(
            schemaVersion: document.schemaVersion,
            sourceEvidenceCommitSha: document.sourceEvidenceCommitSha,
            sourceEvidenceTreeSha: document.sourceEvidenceTreeSha,
            sourceRootManifestSha256: document.sourceRootManifestSha256,
            generatorCommitSha: unrelatedGenerator,
            generatorTreeSha: unrelatedTree,
            generatorSourceSha256: document.generatorSourceSha256,
            spikes: document.spikes,
            oItems: document.oItems,
            o4Matrix: document.o4Matrix,
            downstreamBlocks: document.downstreamBlocks,
            g0: document.g0
        )
        try JSONEncoder().encode(mutated).write(to: copy.appendingPathComponent("conclusions.json"))
        try refreshConclusionsManifest(copy)
        XCTAssertEqual(
            code { try ConclusionValidator.validate(root: copy, repository: repository, strictRepositoryBinding: true) },
            "generator_commit_not_ancestor_of_head"
        )
    }

    func testCommittedEvidenceOnlyDescendantRecomputesAgainstRecordedGeneratorCommit() throws {
        let repository = try repositoryRoot()
        try skipIfEvidenceDriftsFromRecordedSource(repository: repository)
        let conclusions = repository.appendingPathComponent("evidence/phase0/conclusions.json")
        guard FileManager.default.fileExists(atPath: conclusions.path) else {
            throw XCTSkip("task-15 conclusions are not generated in the raw task-14 state")
        }
        let stored = try JSONDecoder().decode(Phase0Conclusions.self, from: Data(contentsOf: conclusions))
        guard stored.sourceEvidenceCommitSha.count == 40, stored.generatorCommitSha.count == 40 else {
            throw XCTSkip("task-15 conclusions require canonical revision resealing")
        }
        let report = try ConclusionValidator.validate(
            root: repository.appendingPathComponent("evidence/phase0"),
            repository: repository,
            strictRepositoryBinding: true
        )
        XCTAssertEqual(report.spikeCount, 9)
        XCTAssertEqual(report.g0Status, stored.g0.status)
    }

    func testCommittedConcludedTreeStrictValidatesWithoutWorkingTreeMutation() throws {
        let repository = try repositoryRoot()
        try skipIfEvidenceDriftsFromRecordedSource(repository: repository)
        let root = repository.appendingPathComponent("evidence/phase0")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("conclusions.json").path) else {
            throw XCTSkip("concluded phase0 evidence is not present")
        }
        let stored = try JSONDecoder().decode(Phase0Conclusions.self, from: Data(contentsOf: root.appendingPathComponent("conclusions.json")))
        guard stored.g0.status == .passed else {
            throw XCTSkip("concluded phase0 evidence is not G0 PASSED")
        }
        let report = try ConclusionValidator.validate(root: root, repository: repository, strictRepositoryBinding: true)
        XCTAssertEqual(report.g0Status, .passed)
        XCTAssertEqual(report.spikeCount, 9)
    }

    func testDeriveCanonicalizesAbbreviatedRevisionArguments() throws {
        let repository = try repositoryRoot()
        let source = try rawEvidenceRoot(repository: repository)
        defer { if source != repository.appendingPathComponent("evidence/phase0") { try? FileManager.default.removeItem(at: source) } }
        let recorded = try XCTUnwrap(recordedSourceCommit(repository: repository))
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let full = try git.text(["rev-parse", "--verify", "\(recorded)^{commit}"])
        let abbreviated = String(full.prefix(7))

        let document = try ConclusionGenerator.derive(
            root: source,
            repository: repository,
            strictRepositoryBinding: false,
            sourceCommitSha: abbreviated,
            bindingCommitSha: abbreviated
        )

        XCTAssertEqual(document.sourceEvidenceCommitSha, full)
        XCTAssertEqual(document.generatorCommitSha, full)
        XCTAssertEqual(document.sourceEvidenceCommitSha.count, 40)
        XCTAssertEqual(document.generatorCommitSha.count, 40)
    }

    func testSourceAndGeneratorRevisionArgumentsRemainIndependent() throws {
        let repository = try repositoryRoot()
        let source = try rawEvidenceRoot(repository: repository)
        defer { if source != repository.appendingPathComponent("evidence/phase0") { try? FileManager.default.removeItem(at: source) } }
        let sourceRevision = try XCTUnwrap(recordedSourceCommit(repository: repository))
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let canonicalSource = try git.text(["rev-parse", "--verify", "\(sourceRevision)^{commit}"])
        let canonicalGenerator = try git.text(["rev-parse", "--verify", "HEAD^{commit}"])

        let document = try ConclusionGenerator.derive(
            root: source,
            repository: repository,
            strictRepositoryBinding: false,
            sourceCommitSha: String(canonicalSource.prefix(7)),
            bindingCommitSha: String(canonicalGenerator.prefix(7))
        )

        XCTAssertEqual(document.sourceEvidenceCommitSha, canonicalSource)
        XCTAssertEqual(document.generatorCommitSha, canonicalGenerator)
    }

    func testStrictValidationConcludedBranchValidatesArchivedRawThenConcluded() throws {
        let repository = try repositoryRoot()
        try skipIfEvidenceDriftsFromRecordedSource(repository: repository)
        try skipIfWorkingTreeDirty(repository: repository)
        let phase0 = repository.appendingPathComponent("evidence/phase0")
        guard FileManager.default.fileExists(atPath: phase0.appendingPathComponent("conclusions.json").path) else {
            throw XCTSkip("concluded phase0 evidence is not present")
        }
        let document = try JSONDecoder().decode(
            Phase0Conclusions.self,
            from: Data(contentsOf: phase0.appendingPathComponent("conclusions.json"))
        )
        let raw = temporaryURL("strict-raw")
        defer { try? FileManager.default.removeItem(at: raw) }
        try materializePhase0Tree(from: document.sourceEvidenceCommitSha, repository: repository, output: raw)
        XCTAssertNoThrow(try Phase0RootValidator.validate(raw, repository: repository))
        XCTAssertEqual(
            code { try Phase0RootValidator.validate(phase0, repository: repository) },
            "phase0_root_artifact_set_mismatch"
        )
        XCTAssertNoThrow(try ConclusionValidator.validate(root: phase0, repository: repository, strictRepositoryBinding: true))
    }

    func testStrictValidationRawOnlyBranchAcceptsUnconcludedTree() throws {
        let repository = try repositoryRoot()
        try skipIfWorkingTreeDirty(repository: repository)
        let raw = try rawEvidenceRoot(repository: repository)
        defer {
            if raw != repository.appendingPathComponent("evidence/phase0") {
                try? FileManager.default.removeItem(at: raw)
            }
        }
        guard !FileManager.default.fileExists(atPath: raw.appendingPathComponent("conclusions.json").path) else {
            throw XCTSkip("raw-only branch requires an unconcluded source tree")
        }
        XCTAssertNoThrow(try Phase0RootValidator.validate(raw, repository: repository))
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
        try materializePhase0Tree(from: document.sourceEvidenceCommitSha, repository: repository, output: raw)
        return raw
    }

    private func materializePhase0Tree(from commit: String, repository: URL, output: URL) throws {
        let staging = temporaryURL("phase0-archive")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let archiveFile = staging.appendingPathComponent("phase0.tar")
        let archive = Process(), archiveErr = Pipe()
        archive.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        archive.arguments = ["-C", repository.path, "archive", "--output", archiveFile.path, commit, "evidence/phase0"]
        archive.standardError = archiveErr
        try archive.run()
        archive.waitUntilExit()
        guard archive.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }

        let tar = Process(), tarErr = Pipe()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-x", "-f", archiveFile.path, "-C", staging.path]
        tar.standardError = tarErr
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }

        let extracted = staging.appendingPathComponent("evidence/phase0")
        try FileManager.default.moveItem(at: extracted, to: output)
    }

    private func skipIfEvidenceDriftsFromRecordedSource(repository: URL) throws {
        let root = repository.appendingPathComponent("evidence/phase0")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("conclusions.json").path) else { return }
        let document = try JSONDecoder().decode(
            Phase0Conclusions.self,
            from: Data(contentsOf: root.appendingPathComponent("conclusions.json"))
        )
        do {
            try HistoricalEvidenceInventoryValidator.validate(
                root: root,
                sourceCommit: document.sourceEvidenceCommitSha,
                repository: repository
            )
        } catch let error as ValidatorError where error.code == "source_evidence_inventory_mismatch" {
            throw XCTSkip("evidence/phase0 working tree diverges from recorded source commit; re-seal required")
        }
    }

    private func skipIfWorkingTreeDirty(repository: URL) throws {
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let status = try git.text(["status", "--porcelain", "--untracked-files=no"])
        guard status.isEmpty else {
            throw XCTSkip("working tree must be clean for strict repository binding validation")
        }
    }

    private func gitText(_ arguments: [String], repository: URL) throws -> String {
        String(decoding: try gitData(arguments, repository: repository), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitData(_ arguments: [String], repository: URL) throws -> Data {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private func code(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
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

    private func refreshConclusionsManifest(_ root: URL) throws {
        let artifact = root.appendingPathComponent("conclusions.json")
        let manifest = root.appendingPathComponent("manifest.sha256")
        let replacement = "\(Canonical.sha256(try Data(contentsOf: artifact)))  conclusions.json"
        var lines = try String(contentsOf: manifest, encoding: .utf8).split(separator: "\n").map(String.init)
        guard let index = lines.firstIndex(where: { $0.hasSuffix("  conclusions.json") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        lines[index] = replacement
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: manifest)
    }

    private func remanifest(_ directory: URL, names: [String]? = nil) throws {
        let files = try names ?? FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" }
        let lines = try files.sorted().map { name in
            "\(Canonical.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))  \(name)"
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
}

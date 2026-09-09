import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class G0PassedConclusionTests: XCTestCase {
    func testCanonicalEvidenceDerivesPassedG0() throws {
        let document = try deriveFromCanonical()
        XCTAssertEqual(document.g0.status, .passed)
        XCTAssertTrue(document.g0.blockingLegIDs.isEmpty)
        XCTAssertEqual(document.g0.candidateSelection, "session")
        XCTAssertEqual(document.oItems.first { $0.id == "O6" }?.status, "RESOLVED")
    }

    func testSelectedSessionAndAllRequiredLegsPassDerivesPassedG0() throws {
        let root = try mutatedEvidence { root in
            try forcePass(root: root, spike: "sp1", selectedTap: "session", failing: ["sp1.tap.annotated.matrix"])
            try forcePass(root: root, spike: "sp2", selectedTap: nil, failing: [])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try ConclusionGenerator.derive(
            root: root,
            repository: try repositoryRoot(),
            strictRepositoryBinding: false
        )
        XCTAssertEqual(document.g0.status, .passed)
        XCTAssertEqual(document.g0.candidateSelection, "session")
        XCTAssertTrue(document.g0.blockingLegIDs.isEmpty)
        XCTAssertEqual(document.oItems.first { $0.id == "O6" }?.status, "RESOLVED")
        XCTAssertEqual(document.spikes.first { $0.id == "SP-1" }?.verdict, .pass)
        XCTAssertEqual(document.spikes.first { $0.id == "SP-2" }?.verdict, .pass)
        XCTAssertFalse(document.g0.blockingLegIDs.contains("sp1.tap.annotated.matrix"))
    }

    func testUpgradeRunAllReceiptWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["KEYRECORD_UPGRADE_RUN_ALL"] != nil else {
            throw XCTSkip("KEYRECORD_UPGRADE_RUN_ALL not set")
        }
        let repository = try repositoryRoot()
        let root = repository.appendingPathComponent("evidence/phase0")
        let url = root.appendingPathComponent("run-all.json")
        let commit = try gitText(["rev-parse", "HEAD"], repository: repository)
        let tree = try gitText(["rev-parse", "HEAD^{tree}"], repository: repository)
        let environmentHash = Canonical.sha256(try Data(contentsOf: root.appendingPathComponent("environment.json")))
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        object["conclusionGenerated"] = false
        object["rootArtifacts"] = Phase0RunLayout.rootArtifacts
        object["runnerCommitSha"] = commit
        object["runnerTreeSha"] = tree
        object["environmentSha256"] = environmentHash
        object["runnerSourceSha256"] = try Dictionary(
            uniqueKeysWithValues: Phase0RunBinding.sourcePaths.sorted().map { path in
                (path, Canonical.sha256(try gitBlob(commit: commit, path: path, repository: repository)))
            }
        )
        var stages = object["stages"] as! [[String: Any]]
        for index in stages.indices {
            if stages[index]["id"] as? String == "preflight" {
                stages[index]["artifactSha256"] = environmentHash
            }
            if stages[index]["id"] as? String == "sp1" || stages[index]["id"] as? String == "sp2" {
                stages[index]["verdict"] = "PASS"
            }
            if let id = stages[index]["id"] as? String, ["shared-atomicity", "sp6a", "sp6b"].contains(id) {
                let manifest = root.appendingPathComponent(id).appendingPathComponent("manifest.sha256")
                stages[index]["artifactSha256"] = Canonical.sha256(try Data(contentsOf: manifest))
            }
        }
        object["stages"] = stages
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(10)
        try data.write(to: url)
        try refreshManifest(root, artifact: url, path: "run-all.json")
        try upgradeSP1Binding(
            root, repository: repository, commit: commit, tree: tree, environmentHash: environmentHash
        )
    }

    private func upgradeSP1Binding(
        _ root: URL, repository: URL, commit: String, tree: String, environmentHash: String
    ) throws {
        let directory = root.appendingPathComponent("sp1")
        let url = directory.appendingPathComponent("evidence.json")
        var evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: url))
        for index in evidence.legs.indices {
            evidence.legs[index].runnerCommitSha = commit
            evidence.legs[index].runnerTreeSha = tree
            evidence.legs[index].environmentSha256 = environmentHash
            if var identity = evidence.legs[index].identity {
                identity.runnerCommitSha = commit
                identity.runnerTreeSha = tree
                identity.environmentSha256 = environmentHash
                evidence.legs[index].identity = identity
            }
        }
        if var identity = evidence.selectedTapIdentity {
            identity.runnerCommitSha = commit
            identity.runnerTreeSha = tree
            identity.environmentSha256 = environmentHash
            evidence.selectedTapIdentity = identity
        }
        evidence.runnerSourceSha256 = try sourceHashes(SP1RunnerBinding.sourcePaths, commit: commit, repository: repository)
        try write(evidence, to: url)
        try refreshManifest(directory, artifact: url, path: "evidence.json")
    }

    func testBindingDiagnosticsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["KEYRECORD_PRINT_BINDING"] != nil else {
            throw XCTSkip("KEYRECORD_PRINT_BINDING not set")
        }
        let repository = try repositoryRoot()
        let receipt = try JSONDecoder().decode(
            Phase0RunReceipt.self,
            from: Data(contentsOf: repository.appendingPathComponent("evidence/phase0/run-all.json"))
        )
        let binding = Phase0RunBinding.sourcePaths
        let receiptKeys = Set(receipt.runnerSourceSha256.keys)
        let missing = binding.subtracting(receiptKeys).sorted()
        let extra = receiptKeys.subtracting(binding).sorted()
        print("BINDING_COUNT=\(binding.count)")
        print("RUNALL_COUNT=\(receiptKeys.count)")
        print("MISSING=\(missing.joined(separator: ","))")
        print("EXTRA=\(extra.joined(separator: ","))")
    }

    func testExportConclusionsWhenRequested() throws {
        guard let output = ProcessInfo.processInfo.environment["KEYRECORD_EXPORT_CONCLUSIONS"] else {
            throw XCTSkip("KEYRECORD_EXPORT_CONCLUSIONS not set")
        }
        let repository = try repositoryRoot()
        let root = repository.appendingPathComponent("evidence/phase0")
        let document = try ConclusionGenerator.derive(
            root: root,
            repository: repository,
            strictRepositoryBinding: false
        )
        let destination = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var encoded = try Canonical.encode(document)
        encoded.append(10)
        try encoded.write(to: destination.appendingPathComponent("conclusions.json"))
        for spike in document.spikes {
            try Data(ConclusionGenerator.renderMarkdown(spike).utf8).write(to: destination.appendingPathComponent("\(spike.id)-CONCLUSION.md"))
        }
    }

    func testSP2IncompleteKeepsO6OpenAndG0Open() throws {
        let root = try mutatedEvidence { root in
            try forcePass(root: root, spike: "sp1", selectedTap: "session", failing: [])
            try forcePass(root: root, spike: "sp2", selectedTap: nil, failing: ["sp2.sleepWake"])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try ConclusionGenerator.derive(
            root: root,
            repository: try repositoryRoot(),
            strictRepositoryBinding: false
        )
        XCTAssertEqual(document.g0.status, .open)
        XCTAssertTrue(document.g0.blockingLegIDs.contains("sp2.sleepWake"))
        XCTAssertEqual(document.oItems.first { $0.id == "O6" }?.status, "OPEN")
        XCTAssertNil(document.g0.candidateSelection)
    }

    private func deriveFromCanonical() throws -> Phase0Conclusions {
        let repository = try repositoryRoot()
        return try ConclusionGenerator.derive(
            root: repository.appendingPathComponent("evidence/phase0"),
            repository: repository,
            strictRepositoryBinding: false
        )
    }

    private func mutatedEvidence(_ mutate: (URL) throws -> Void) throws -> URL {
        let repository = try repositoryRoot()
        let source = repository.appendingPathComponent("evidence/phase0")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("g0-passed-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: root)
        try mutate(root)
        return root
    }

    private func forcePass(root: URL, spike: String, selectedTap: String?, failing: Set<String>) throws {
        let url = root.appendingPathComponent("\(spike)/evidence.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var legs = try XCTUnwrap(object["legs"] as? [[String: Any]])
        for index in legs.indices {
            guard let id = legs[index]["legID"] as? String else { continue }
            if failing.contains(id) {
                legs[index]["verdict"] = "FAIL"
            } else {
                legs[index]["verdict"] = "PASS"
            }
        }
        object["legs"] = legs
        if let selectedTap {
            object["selectedTapIdentity"] = ["tapType": selectedTap]
        }
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
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

    private func gitBlob(commit: String, path: String, repository: URL) throws -> Data {
        try gitData(["cat-file", "blob", "\(commit):\(path)"], repository: repository)
    }

    private func sourceHashes(_ paths: Set<String>, commit: String, repository: URL) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: paths.map { path in
            (path, Canonical.sha256(try gitBlob(commit: commit, path: path, repository: repository)))
        })
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        try data.write(to: url)
    }

    private func refreshManifest(_ directory: URL, artifact: URL, path: String) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        let replacement = "\(Canonical.sha256(try Data(contentsOf: artifact)))  \(path)"
        var lines = try String(contentsOf: manifest, encoding: .utf8).split(separator: "\n").map(String.init)
        guard let index = lines.firstIndex(where: { $0.hasSuffix("  \(path)") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        lines[index] = replacement
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: manifest)
    }
}

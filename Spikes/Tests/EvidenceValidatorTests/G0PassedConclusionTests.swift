import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class G0PassedConclusionTests: XCTestCase {
    func testCanonicalEvidenceStillDerivesOpenG0() throws {
        let document = try deriveFromCanonical()
        XCTAssertEqual(document.g0.status, .open)
        XCTAssertFalse(document.g0.blockingLegIDs.isEmpty)
        XCTAssertNil(document.g0.candidateSelection)
        XCTAssertEqual(document.oItems.first { $0.id == "O6" }?.status, "OPEN")
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
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("evidence/phase0/conclusions.json").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

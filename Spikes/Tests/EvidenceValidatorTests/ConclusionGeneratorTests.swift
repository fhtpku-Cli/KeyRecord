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

    func testCanonicalEvidenceGeneratesDeterministicallyAndValidatesIndependently() throws {
        let repository = try repositoryRoot()
        let first = temporaryURL("conclusions-first")
        let second = temporaryURL("conclusions-second")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let source = repository.appendingPathComponent("evidence/phase0")
        do { try ConclusionGenerator.generate(sourceRoot: source, outputRoot: first, repository: repository) }
        catch { XCTFail("first generation: \(error)"); return }
        do { try ConclusionGenerator.generate(sourceRoot: source, outputRoot: second, repository: repository) }
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
}

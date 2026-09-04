import Foundation
import Phase0Support

enum SP1DirectoryValidator {
    static func validate(directory: URL) throws -> GateValidationReport {
        let evidenceURL = directory.appendingPathComponent("evidence.json")
        guard FileManager.default.fileExists(atPath: evidenceURL.path) else { throw ValidatorError("missing_evidence_document") }
        let evidence: SP1Evidence
        do { evidence = try JSONDecoder().decode(SP1Evidence.self, from: Data(contentsOf: evidenceURL)) }
        catch { throw ValidatorError("malformed_sp1_evidence", String(describing: error)) }
        do { try evidence.validate() }
        catch let error as SP1ValidationError { throw ValidatorError("sp1_\(error.rawValue)") }
        try verifyManifest(directory)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: evidence.g0Status)
    }

    private static func verifyManifest(_ directory: URL) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { throw ValidatorError("missing_manifest") }
        var expected = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { throw ValidatorError("malformed_manifest") }
            let name = String(parts[1]); expected.insert(name)
            let file = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file), Canonical.sha256(data) == String(parts[0]) else { throw ValidatorError("manifest_hash_mismatch", name) }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard expected == actual else { throw ValidatorError("manifest_membership_mismatch") }
    }
}

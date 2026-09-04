import CryptoKit
import Foundation
import Phase0Support

enum SP4ADirectoryValidator {
    static func validate(
        directory: URL,
        repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> GateValidationReport {
        let evidence: SP4AEvidence = try exactDecode(directory, "evidence.json", code: "malformed_sp4a_evidence")
        do { try evidence.validate() } catch let error as SP4AValidationError { throw ValidatorError("sp4a_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory, repository: repository)
        try validateBindings(evidence, directory: directory, repository: repository)
        try validateConclusion(directory, evidence: evidence)
        try validateRunner(evidence, repository: repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: .open)
    }

    static func verifyManifest(_ directory: URL) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        guard isRegular(manifest), let text = try? String(contentsOf: manifest, encoding: .utf8) else { throw ValidatorError("missing_manifest") }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("malformed_manifest") }
            let name = String(fields[1])
            guard SP4ADirectoryLayout.artifactNames.contains(name), names.insert(name).inserted else {
                throw ValidatorError("sp4a_manifest_membership_mismatch")
            }
            let file = directory.appendingPathComponent(name)
            guard isRegular(file), let bytes = try? Data(contentsOf: file), Canonical.sha256(bytes) == String(fields[0]) else {
                throw ValidatorError("sp4a_manifest_hash_mismatch", name)
            }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard names == SP4ADirectoryLayout.artifactNames, actual == SP4ADirectoryLayout.artifactNames else {
            throw ValidatorError("sp4a_manifest_membership_mismatch")
        }
    }

    static func validateArtifacts(_ directory: URL, repository: URL) throws {
        let v2: SP4ASchemaArtifact
        let v3: SP4ASchemaArtifact
        do {
            v2 = try SP4AFixtureScenarios.schemaArtifact(repository: repository, source: ViaDefinitionSources.v2, expected: .v2)
            v3 = try SP4AFixtureScenarios.schemaArtifact(repository: repository, source: ViaDefinitionSources.v3, expected: .v3)
        } catch { throw ValidatorError("sp4a_source_hash_mismatch") }
        let opaque: SP4AOpaqueArtifact
        let bounds: SP4ABoundsArtifact
        do {
            opaque = try SP4AFixtureScenarios.opaqueArtifact()
            bounds = try SP4AFixtureScenarios.boundsArtifact()
        } catch { throw ValidatorError("sp4a_parser_recompute_failed") }
        let facts: SP4ASourceFactsArtifact
        do { facts = try SP4AFixtureScenarios.sourceFacts(repository: repository) }
        catch { throw ValidatorError("sp4a_source_citation_mismatch") }
        try requireExact(directory, "v2-schema.json", v2, code: "sp4a_v2_recompute_mismatch")
        try requireExact(directory, "v3-schema.json", v3, code: "sp4a_v3_recompute_mismatch")
        try requireExact(directory, "opaque-preservation.json", opaque, code: "sp4a_opaque_recompute_mismatch")
        try requireExact(directory, "bounds.json", bounds, code: "sp4a_bounds_recompute_mismatch")
        try requireExact(directory, "source-facts.json", facts, code: "sp4a_source_facts_mismatch")
        guard SP4AFixtureScenarios.validates(opaque), SP4AFixtureScenarios.validates(bounds) else {
            throw ValidatorError("sp4a_fixture_assertion_mismatch")
        }
        try validateProvenance(repository: repository, source: ViaDefinitionSources.v2, name: "via-app")
        try validateProvenance(repository: repository, source: ViaDefinitionSources.v3, name: "via-keyboards")
    }

    static func validateBindings(_ evidence: SP4AEvidence, directory: URL, repository: URL) throws {
        let environmentURL = repository.appendingPathComponent("evidence/phase0/environment.json")
        guard isRegular(environmentURL), let environment = try? Data(contentsOf: environmentURL) else { throw ValidatorError("sp4a_environment_missing") }
        do { try PrivacySafeEnvironmentValidator.validateJSON(environment); _ = try JSONDecoder().decode(EnvironmentEvidence.self, from: environment) }
        catch { throw ValidatorError("sp4a_environment_unsafe") }
        let environmentHash = Canonical.sha256(environment)
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == environmentHash }) else { throw ValidatorError("sp4a_environment_hash_mismatch") }
        for leg in evidence.legs {
            guard let path = SP4ADirectoryLayout.legArtifacts[leg.legID], leg.artifactPath == path,
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(path)), leg.artifactSha256 == Canonical.sha256(bytes) else {
                throw ValidatorError("sp4a_artifact_binding_mismatch", leg.legID)
            }
        }
    }

    static func validateRunner(_ evidence: SP4AEvidence, repository: URL) throws {
        guard Set(evidence.runnerSourceSha256.keys) == SP4ARunnerBinding.sourcePaths,
              let first = evidence.legs.first else { throw ValidatorError("sp4a_runner_source_set_mismatch") }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else {
            throw ValidatorError("sp4a_runner_commit_missing")
        }
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha else {
            throw ValidatorError("sp4a_runner_tree_mismatch")
        }
        guard try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else {
            throw ValidatorError("sp4a_runner_not_ancestor")
        }
        for path in SP4ARunnerBinding.sourcePaths.sorted() {
            guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha):\(path)"], acceptedStatuses: [0, 1, 128]).status == 0 else {
                throw ValidatorError("sp4a_runner_source_missing", path)
            }
            let committed = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else {
                throw ValidatorError("sp4a_runner_source_hash_mismatch", path)
            }
            guard try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else {
                throw ValidatorError("sp4a_runner_source_dirty", path)
            }
        }
    }

    private static func validateConclusion(_ directory: URL, evidence: SP4AEvidence) throws {
        let url = directory.appendingPathComponent("SP-4A-CONCLUSION.md")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8),
              text.contains("Verdict: **\(evidence.verdict.rawValue)**"), text.contains("definition-only fixture result"),
              text.contains("makes no device-protocol, keycode-dialect, layout-backup, official-importer, HID, EEPROM, or device-behavior claim"),
              text.contains("Official definitions are repository-served"), text.contains("custom definitions use VIA's Design tab") else {
            throw ValidatorError("sp4a_misleading_conclusion")
        }
    }

    private static func validateProvenance(repository: URL, source: ViaDefinitionSource, name: String) throws {
        let provenancePath = "evidence/phase0/sources/repos/\(name)/provenance.json"
        let provenanceURL = repository.appendingPathComponent(provenancePath)
        guard isRegular(provenanceURL), let data = try? Data(contentsOf: provenanceURL),
              let provenance = try? JSONDecoder().decode(SourceProvenance.self, from: data),
              provenance.name == name, provenance.url == source.repository, provenance.upstreamRef == source.commit,
              provenance.tree == source.tree,
              provenance.files.contains(where: { $0.gitBlob == source.gitBlob && $0.sha256 == source.sha256 && source.path.hasSuffix($0.copiedPath) }),
              provenance.license.gitBlob == source.licenseBlob, provenance.license.sha256 == source.licenseSha256,
              gitBlob(try Data(contentsOf: repository.appendingPathComponent(source.path))) == source.gitBlob,
              gitBlob(try Data(contentsOf: repository.appendingPathComponent(source.licensePath))) == source.licenseBlob else {
            throw ValidatorError("sp4a_source_provenance_mismatch", name)
        }
    }

    private static func gitBlob(_ data: Data) -> String {
        var framed = Data("blob \(data.count)\0".utf8); framed.append(data)
        return Insecure.SHA1.hash(data: framed).map { String(format: "%02x", $0) }.joined()
    }

    private static func requireExact<T: Codable & Equatable>(_ directory: URL, _ name: String, _ expected: T, code: String) throws {
        let actual: T = try exactDecode(directory, name, code: code)
        guard actual == expected else { throw ValidatorError(code) }
    }
    private static func exactDecode<T: Codable>(_ directory: URL, _ name: String, code: String) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard isRegular(url), let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(T.self, from: data),
              let canonical = try? pretty(decoded), data == canonical else { throw ValidatorError(code) }
        return decoded
    }
    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func isRegular(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= ViaDefinitionLimits.maximumInputBytes
    }
}

private struct SourceProvenance: Decodable {
    let name: String
    let url: String
    let upstreamRef: String
    let tree: String
    let files: [SourceProvenanceFile]
    let license: SourceProvenanceFile
    enum CodingKeys: String, CodingKey { case name, url, upstreamRef = "upstream_ref", tree, files, license }
}

private struct SourceProvenanceFile: Decodable {
    let path: String
    let copiedPath: String
    let gitBlob: String
    let sha256: String
    enum CodingKeys: String, CodingKey { case path, copiedPath = "copied_path", gitBlob = "git_blob", sha256 }
}

import Foundation
import Phase0Support

enum SP6BDirectoryValidator {
    static func validate(directory: URL, repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> GateValidationReport {
        let evidence: SP6BEvidence = try decode(directory.appendingPathComponent("evidence.json"), code: "malformed_sp6b_evidence")
        do { try evidence.validate() } catch let error as SP6BValidationError { throw ValidatorError("sp6b_\(error.rawValue)") }
        let snapshot: D12Snapshot = try decode(directory.appendingPathComponent("d12/snapshot.json"), code: "sp6b_d12_malformed")
        do { try snapshot.validate(generatedAt: snapshot.generatedAt) } catch let error as D12ValidationError { throw ValidatorError("sp6b_d12_\(error.rawValue)") }
        try validateD12(snapshot, directory: directory)
        try validateManifest(directory, snapshot: snapshot)
        try validateCandidates(directory)
        try validateBuildAndTiming(directory)
        try validateAudit(directory)
        try validateBindings(evidence, directory: directory, repository: repository)
        try validateRunner(evidence, repository: repository)
        try validateConclusion(directory)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: .open)
    }

    static func validateD12(_ snapshot: D12Snapshot, directory: URL) throws {
        var referenced = Set<String>()
        for candidate in snapshot.candidates {
            for page in candidate.github {
                let raw = try rawPage(page, directory: directory, referenced: &referenced)
                guard (try? JSONSerialization.jsonObject(with: raw)) is [Any] else { throw ValidatorError("sp6b_d12_github_body") }
                let headers = try String(contentsOf: directory.appendingPathComponent("d12/\(page.headersPath)"), encoding: .utf8)
                let next = linkNext(headers)
                guard next == page.next else { throw ValidatorError("sp6b_d12_github_pagination") }
            }
            for page in candidate.osv {
                let raw = try rawPage(page.request, directory: directory, referenced: &referenced)
                guard let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      object["next_page_token"] as? String == page.responseNextPageToken
                        || (object["next_page_token"] == nil && page.responseNextPageToken == nil) else {
                    throw ValidatorError("sp6b_d12_osv_pagination")
                }
            }
        }
        var ids = Set<String>()
        for page in snapshot.nvd.pages {
            let raw = try rawPage(page.request, directory: directory, referenced: &referenced)
            guard let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  object["startIndex"] as? Int == page.startIndex,
                  object["resultsPerPage"] as? Int == page.resultsPerPage,
                  object["totalResults"] as? Int == page.totalResults,
                  let values = object["vulnerabilities"] as? [[String: Any]] else { throw ValidatorError("sp6b_d12_nvd_body") }
            let rawIDs = try values.map { value -> String in
                guard let cve = value["cve"] as? [String: Any], let id = cve["id"] as? String else { throw ValidatorError("sp6b_d12_nvd_body") }
                return id
            }
            guard rawIDs == page.vulnerabilities.map(\.cveID), rawIDs.allSatisfy({ ids.insert($0).inserted }) else { throw ValidatorError("sp6b_d12_nvd_classification") }
        }
        let rawRoot = directory.appendingPathComponent("d12/raw")
        let actual = try regularPaths(rawRoot).map { "raw/\($0)" }
        guard Set(actual) == referenced else {
            throw ValidatorError("sp6b_d12_raw_membership", "actual=\(actual.sorted()) expected=\(referenced.sorted())")
        }
    }

    private static func rawPage(_ page: D12HTTPPage, directory: URL, referenced: inout Set<String>) throws -> Data {
        for path in [page.headersPath, page.rawBodyPath] {
            guard referenced.insert(path).inserted else { throw ValidatorError("sp6b_d12_raw_replay", path) }
        }
        let headers = directory.appendingPathComponent("d12/\(page.headersPath)")
        let body = directory.appendingPathComponent("d12/\(page.rawBodyPath)")
        guard let headerData = try? Data(contentsOf: headers), let bodyData = try? Data(contentsOf: body),
              Canonical.sha256(headerData) == page.headersSha256, Canonical.sha256(bodyData) == page.rawBodySha256 else {
            throw ValidatorError("sp6b_d12_raw_hash")
        }
        return bodyData
    }

    private static func validateManifest(_ directory: URL, snapshot: D12Snapshot) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8), text.hasSuffix("\n") else { throw ValidatorError("missing_manifest") }
        var rows = Set<String>()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("malformed_manifest") }
            let hash = String(fields[0]), path = String(fields[1])
            guard isSHA256(hash), !path.hasPrefix("/"), !path.contains(".."), rows.insert(path).inserted,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(path)), Canonical.sha256(data) == hash else {
                throw ValidatorError("sp6b_manifest_hash_mismatch", path)
            }
        }
        let raw = snapshot.candidates.flatMap { $0.github.flatMap { [$0.headersPath, $0.rawBodyPath] } + $0.osv.flatMap { [$0.request.headersPath, $0.request.rawBodyPath] } }
            + snapshot.nvd.pages.flatMap { [$0.request.headersPath, $0.request.rawBodyPath] }
        let expected = SP6BDirectoryLayout.fixedArtifactNames.union(raw.map { "d12/\($0)" })
        let actual = Set(try regularPaths(directory).filter { $0 != "manifest.sha256" })
        guard rows == expected, actual == expected else {
            throw ValidatorError("sp6b_manifest_membership_mismatch", "rows=\(rows.sorted()) actual=\(actual.sorted()) expected=\(expected.sorted())")
        }
    }

    private static func validateCandidates(_ directory: URL) throws {
        let value: SP6BCandidateEvaluation = try decode(directory.appendingPathComponent("candidate-evaluation.json"), code: "sp6b_candidate_invalid")
        do { try value.validate() } catch { throw ValidatorError("sp6b_candidate_invalid") }
    }

    private static func validateBuildAndTiming(_ directory: URL) throws {
        let build: BuildArtifact = try decode(directory.appendingPathComponent("build/build.json"), code: "sp6b_build_invalid")
        let archive = directory.appendingPathComponent("build/argon2-universal.a")
        guard build.recommendedCandidate == "phc", build.minimumMacOS == "14.0", Set(build.architectures) == ["arm64", "x86_64"],
              let bytes = try? Data(contentsOf: archive), Canonical.sha256(bytes) == build.archiveSha256,
              try lipoArchitectures(archive) == ["arm64", "x86_64"] else { throw ValidatorError("sp6b_build_invalid") }
        let arm: ArmArtifact = try decode(directory.appendingPathComponent("arm-benchmark.json"), code: "sp6b_arm_timing_invalid")
        let sorted = arm.samplesMilliseconds.sorted()
        guard arm.recommendedCandidate == "phc", arm.host.architecture == "arm64", arm.samplesMilliseconds.count == arm.sampleCount,
              (5...15).contains(arm.sampleCount), arm.medianMilliseconds == sorted[sorted.count / 2],
              arm.p95Milliseconds == sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1], arm.memoryKiB == 524_288,
              arm.iterations == 5, arm.parallelism == 4, arm.saltLength == 16, arm.withinTarget,
              (300...500).contains(arm.medianMilliseconds) else { throw ValidatorError("sp6b_arm_timing_invalid") }
        guard let phc = try? String(contentsOf: directory.appendingPathComponent("build/phc-vector.txt"), encoding: .utf8),
              let swift = try? String(contentsOf: directory.appendingPathComponent("build/swift-vector.txt"), encoding: .utf8),
              phc.contains("PHC_RFC9106_VECTOR=PASS"), swift.contains("SWIFT_RFC9106_VECTOR=PASS") else { throw ValidatorError("sp6b_vectors_invalid") }
    }

    private static func validateAudit(_ directory: URL) throws {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("dependency-audit.md"), encoding: .utf8),
              text.contains("Unresolved severity totals: Critical: 0; High: 0; Medium: 0;"),
              text.contains("No production dependency is frozen"),
              (1...12).allSatisfy({ text.contains("| \($0) |") }) else { throw ValidatorError("sp6b_audit_invalid") }
    }

    private static func validateBindings(_ evidence: SP6BEvidence, directory: URL, repository: URL) throws {
        guard let environment = try? Data(contentsOf: repository.appendingPathComponent("evidence/phase0/environment.json")) else { throw ValidatorError("sp6b_environment_missing") }
        let hash = Canonical.sha256(environment)
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == hash }) else { throw ValidatorError("sp6b_environment_hash_mismatch") }
        for leg in evidence.legs where leg.verdict == .pass {
            guard let expected = SP6BDirectoryLayout.legArtifacts[leg.legID], leg.artifactPath == expected,
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(expected)), leg.artifactSha256 == Canonical.sha256(bytes) else {
                throw ValidatorError("sp6b_artifact_binding_mismatch", leg.legID)
            }
        }
    }

    private static func validateRunner(_ evidence: SP6BEvidence, repository: URL) throws {
        guard let first = evidence.legs.first else { throw ValidatorError("sp6b_runner_missing") }
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha,
              try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else { throw ValidatorError("sp6b_runner_identity") }
        for path in SP6BRunnerBinding.sourcePaths.sorted() {
            let bytes = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(bytes) == evidence.runnerSourceSha256[path],
                  try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else { throw ValidatorError("sp6b_runner_source", path) }
        }
    }

    private static func validateConclusion(_ directory: URL) throws {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("SP-6B-CONCLUSION.md"), encoding: .utf8),
              text.contains("Verdict: **BLOCKED**"), text.contains("Intel timing remains **BLOCKED**"),
              text.contains("production dependency remains unfrozen"), !text.contains("Verdict: **PASS**") else { throw ValidatorError("sp6b_misleading_conclusion") }
    }

    private static func decode<T: Decodable>(_ url: URL, code: String) throws -> T {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else { throw ValidatorError(code) }
        return value
    }
    private static func regularPaths(_ root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { throw ValidatorError("sp6b_directory_missing") }
        return try enumerator.compactMap { item in
            guard let relative = item as? String else { return nil }
            let url = root.appendingPathComponent(relative)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ValidatorError("sp6b_symlink") }
            return values.isRegularFile == true ? relative : nil
        }
    }
    private static func linkNext(_ headers: String) -> String? {
        for field in headers.split(separator: "\n").flatMap({ $0.split(separator: ",") }) where field.contains("rel=\"next\"") {
            guard let left = field.firstIndex(of: "<"), let right = field[left...].firstIndex(of: ">") else { continue }
            return String(field[field.index(after: left)..<right])
        }
        return nil
    }
    private static func lipoArchitectures(_ archive: URL) throws -> Set<String> {
        let process = Process(), output = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-archs", archive.path]; process.standardOutput = output; process.standardError = Pipe()
        try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw ValidatorError("sp6b_build_invalid") }
        return Set(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(whereSeparator: \.isWhitespace).map(String.init))
    }
    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

private struct BuildArtifact: Decodable { let recommendedCandidate: String; let minimumMacOS: String; let architectures: [String]; let archiveSha256: String }
private struct ArmHost: Decodable { let architecture: String }
private struct ArmArtifact: Decodable {
    let recommendedCandidate: String; let host: ArmHost; let samplesMilliseconds: [Double]
    let medianMilliseconds: Double; let p95Milliseconds: Double; let memoryKiB: Int
    let iterations: Int; let parallelism: Int; let saltLength: Int; let sampleCount: Int; let withinTarget: Bool
}

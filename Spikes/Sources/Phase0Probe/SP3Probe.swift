import Darwin
import Foundation
import Phase0Support

enum SP3Probe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(sourcePaths: SP3RunnerBinding.sourcePaths.sorted())
    ) throws {
        guard arguments.count == 5, arguments[0] == "sp3", arguments[1] == "--environment", arguments[3] == "--output" else {
            throw ProbeError.usage
        }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try boundedFile(environmentURL)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        let identity = try identityProvider.resolve()
        let repository = try repositoryRoot()
        let environmentHash = AtomicityDigest.sha256(environmentData)

        let managed = try SP3FixtureScenarios.managedBlock(repository: repository)
        guard SP3FixtureScenarios.validates(managed) else { throw SP3ProbeError.fixtureAssertionFailed }
        let recovery = SP3FixtureScenarios.recovery()
        let citation = try atomicityCitation(repository: repository)
        let facts = SP3FixtureScenarios.formatFacts
        let cli = installedCLI(environment: environment)
        let lint = try cli.map { try runOfficialLint(cli: $0, repository: repository) }
            ?? SP3LintArtifact(executed: false, cliPath: nil, version: nil, validAccepted: [], invalidRejected: [], blockedBy: "supported_karabiner_cli_absent")

        let artifactData: [String: Data] = [
            "managed-block.json": try encoded(managed),
            "recovery.json": try encoded(recovery),
            "atomicity-citation.json": try encoded(citation),
            "format-facts.json": try encoded(facts),
            "lint-results.json": try encoded(lint),
        ]
        let hashes = artifactData.mapValues(AtomicityDigest.sha256)
        let d5 = lint.executed
        let installed = environment.applications.first { $0.name == "Karabiner-Elements" }?.status == .installed
        let d2 = environment.guiSession.status == .available && environment.listenEventAccess == .available
            && environment.guiSession.tapCreate == .available && installed && d5
        let legs = SP3Evidence.requiredLegIDs.sorted().map { id -> SP3Leg in
            let rule = Phase0Registry.legRules[id]!
            let path: String? = switch id {
            case "sp3.schemaLint": d5 ? "lint-results.json" : nil
            case "sp3.managedBlock": "managed-block.json"
            case "sp3.atomicity": "atomicity-citation.json"
            case "sp3.crashRecovery": "recovery.json"
            case "sp3.versionSample": d5 ? "format-facts.json" : nil
            default: nil
            }
            let available = rule.detectorID == "D0" || (rule.detectorID == "D5" && d5) || (rule.detectorID == "D2" && d2)
            if !available { return blockedLeg(id, rule: rule, identity: identity, environmentHash: environmentHash) }
            let verdict: Verdict = id == "sp3.versionSample" ? .inconclusive : .pass
            return SP3Leg(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true,
                verdict: verdict, blocker: nil, runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, command: command(for: id, cli: cli), exitStatus: 0,
                artifactPath: path, artifactSha256: path.flatMap { hashes[$0] }
            )
        }
        let report = SP3Evidence(legs: legs, verdict: aggregate(legs.map(\.verdict)), runnerSourceSha256: identity.sourceSha256)
        try report.validate()
        try publish(report: report, artifacts: artifactData, output: output)
        print("SP3=\(report.verdict.rawValue) pass=\(legs.filter { $0.verdict == .pass }.count) blocked=\(legs.filter { $0.verdict == .blocked }.count) output=\(output.path)")
    }

    private static func blockedLeg(_ id: String, rule: Phase0Registry.LegRule, identity: AtomicityRunnerIdentity, environmentHash: String) -> SP3Leg {
        let details: (String, [String], String, String) = switch rule.detectorID {
        case "D5": (
            "supported_karabiner_cli_absent", ["test", "-x", "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"],
            "supported installed karabiner_cli with a sampled full version", "Install and sample a supported Karabiner version separately, then rerun"
        )
        case "D2": (
            "karabiner_or_input_monitoring_unavailable", ["environment.json", "guiSession.tapCreate", "listenEventAccess", "applications.Karabiner-Elements"],
            "GUI session, Input Monitoring already granted, and supported Karabiner installed", "Provision an approved sandbox host separately; this probe never prompts, reloads, starts, or stops Karabiner"
        )
        default: ("detector_unavailable", ["environment.json", rule.detectorID], "required detector", "Satisfy prerequisite and rerun")
        }
        return SP3Leg(
            legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: false, verdict: .blocked,
            blocker: SP1Blocker(blockedBy: details.0, detectCommand: details.1, prerequisite: details.2, unblockAction: details.3),
            runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha, environmentSha256: environmentHash,
            command: [], exitStatus: nil
        )
    }

    private static func atomicityCitation(repository: URL) throws -> SP3AtomicityCitation {
        let relative = "evidence/phase0/shared-atomicity/result.json"
        let manifestRelative = "evidence/phase0/shared-atomicity/manifest.sha256"
        let result = try boundedFile(repository.appendingPathComponent(relative))
        let atomicity = try JSONDecoder().decode(AtomicityEvidence.self, from: result)
        try atomicity.validate()
        let hash = AtomicityDigest.sha256(result)
        let manifest = try String(contentsOf: repository.appendingPathComponent(manifestRelative), encoding: .utf8)
        guard manifest == "\(hash)  result.json\n", atomicity.citedBy.contains("SP-3") else { throw SP3ProbeError.atomicityCitationMismatch }
        return SP3AtomicityCitation(artifactPath: relative, artifactSha256: hash, manifestPath: manifestRelative, citedBy: atomicity.citedBy)
    }

    private static func installedCLI(environment: EnvironmentEvidence) -> URL? {
        guard environment.applications.first(where: { $0.name == "Karabiner-Elements" })?.status == .installed else { return nil }
        let paths = [
            "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli",
            "/Applications/Karabiner-Elements.app/Contents/MacOS/karabiner_cli",
        ]
        return paths.map(URL.init(fileURLWithPath:)).first { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    private static func runOfficialLint(cli: URL, repository: URL) throws -> SP3LintArtifact {
        let source = repository.appendingPathComponent("evidence/phase0/sources/repos/karabiner/files/tests/src/complex_modifications_assets/json/lint/assets")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-sp3-lint-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let names = try FileManager.default.contentsOfDirectory(atPath: temporary.path).filter { $0.hasSuffix(".json") }.sorted()
        var accepted: [String] = [], rejected: [String] = []
        for name in names {
            let status = try process(cli, ["--lint-complex-modifications", temporary.appendingPathComponent(name).path]).status
            if status == 0 { accepted.append(name) } else { rejected.append(name) }
        }
        let valid = Set(["valid.json", "available_since.json"])
        guard Set(accepted) == valid, Set(rejected) == Set(names).subtracting(valid) else { throw SP3ProbeError.officialLintMismatch }
        let version = try process(cli, ["--version-number"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { throw SP3ProbeError.unknownVersion }
        return SP3LintArtifact(executed: true, cliPath: cli.path, version: version, validAccepted: accepted, invalidRejected: rejected, blockedBy: nil)
    }

    private static func command(for id: String, cli: URL?) -> [String] {
        if id == "sp3.schemaLint", let cli { return [cli.path, "--lint-complex-modifications", "copied-temp-fixtures/*.json"] }
        return ["Phase0Probe", "sp3", "fixture", id]
    }

    private static func publish(report: SP3Evidence, artifacts: [String: Data], output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp3.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = SP3SignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP3_TEST_DELAY_AFTER_TEMP"], let delay = Double(value) { Thread.sleep(forTimeInterval: min(max(delay, 0), 5)) }
            try encoded(report).write(to: temporary.appendingPathComponent("evidence.json"))
            for (name, data) in artifacts { try data.write(to: temporary.appendingPathComponent(name)) }
            let rows = report.legs.map { "- `\($0.legID)`: \($0.verdict.rawValue) (`\($0.blocker?.blockedBy ?? "executed")`)" }.joined(separator: "\n")
            let conclusion = "# SP-3 conclusion\n\nVerdict: **\(report.verdict.rawValue)**\n\nFixture-only managed-block and recovery assertions executed. Official schema lint, version sampling, live reload, and disable latency remain BLOCKED when their detectors are false; no user Karabiner file or process was accessed.\n\n\(rows)\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-3-CONCLUSION.md"))
            try writeManifest(temporary)
            try FileManager.default.moveItem(at: temporary, to: output)
            cleanup.complete()
        } catch { try? FileManager.default.removeItem(at: temporary); cleanup.complete(); throw error }
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func writeManifest(_ directory: URL) throws {
        let lines = try SP3DirectoryLayout.artifactNames.sorted().map { name in
            "\(AtomicityDigest.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))  \(name)"
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent(); try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp3.") && name.hasSuffix(".tmp") { try? FileManager.default.removeItem(at: parent.appendingPathComponent(name)) }
    }
    private static func boundedFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_048_576 else { throw SP3ProbeError.invalidFile }
        return try Data(contentsOf: url)
    }
    private static func aggregate(_ verdicts: [Verdict]) -> Verdict { verdicts.max { precedence($0) < precedence($1) } ?? .blocked }
    private static func precedence(_ verdict: Verdict) -> Int { switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 } }
    private static func process(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe(); process.executableURL = executable; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe; try process.run()
        let deadline = Date().addingTimeInterval(10); while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate(); throw SP3ProbeError.processTimeout }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); guard data.count <= 65_536 else { throw SP3ProbeError.processOutputTooLarge }
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    private static func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) { return candidate }
            candidate.deleteLastPathComponent()
        }
        throw SP3ProbeError.repositoryNotFound
    }
}

private enum SP3ProbeError: Error { case atomicityCitationMismatch, fixtureAssertionFailed, invalidFile, officialLintMismatch, processOutputTooLarge, processTimeout, repositoryNotFound, unknownVersion }

private final class SP3SignalCleanup: @unchecked Sendable {
    private let paths: [URL]
    private var sources: [DispatchSourceSignal] = []
    init(paths: [URL]) {
        self.paths = paths
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { [paths] in paths.forEach { try? FileManager.default.removeItem(at: $0) }; Foundation.exit(Int32(item.1)) }
            source.resume(); sources.append(source)
        }
    }
    func complete() { sources.forEach { $0.cancel() }; sources.removeAll(); signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL) }
}

import Darwin
import Foundation
import Phase0Support

enum RunAllProbe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(
            sourcePaths: Phase0RunBinding.sourcePaths.sorted()
        )
    ) throws {
        guard arguments.count == 5, arguments[0] == "run-all", arguments[1] == "--environment",
              arguments[3] == "--output" else { throw ProbeError.usage }
        let environment = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let output = URL(fileURLWithPath: arguments[4]).standardizedFileURL
        let repository = try repositoryRoot()
        let canonical = repository.appendingPathComponent("evidence/phase0", isDirectory: true)
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".phase0.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = RunAllSignalCleanup(paths: [temporary, output])
        do {
            let environmentData = try bounded(environment)
            try seed(temporary, from: canonical)
            try cleanStale(parent: parent, preserving: temporary)
            if let raw = ProcessInfo.processInfo.environment["KEYRECORD_RUN_ALL_TEST_DELAY_AFTER_TEMP"], let delay = Double(raw) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try PrivacySafeEnvironmentValidator.validateJSON(environmentData)
            _ = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
            try environmentData.write(to: temporary.appendingPathComponent("environment.json"))
            let identity = try identityProvider.resolve()
            let stagedEnvironment = temporary.appendingPathComponent("environment.json")
            var stages = [Phase0RunStage(
                id: "preflight", command: ["Phase0Probe", "run-all", "preflight", "--environment", "environment.json"],
                exitStatus: 0, stdout: "validated supplied immutable environment\n", stderr: "", verdict: "PASS",
                policy: "validated-preserved", artifactSha256: AtomicityDigest.sha256(environmentData)
            )]
            let atomicity = temporary.appendingPathComponent(".atomicity-observed.json")
            stages.append(try execute(
                id: "shared-atomicity", arguments: ["atomicity", "--output", atomicity.path,
                    "--environment", stagedEnvironment.path, "--iterations", "100"],
                logicalOutput: "shared-atomicity/observed-result.json", cleanup: cleanup
            ))
            let observedHash = AtomicityDigest.sha256(try Data(contentsOf: atomicity))
            try FileManager.default.removeItem(at: atomicity)
            let preservedManifest = try Data(contentsOf: temporary.appendingPathComponent("shared-atomicity/manifest.sha256"))
            stages[stages.count - 1] = preserving(
                stages.last!, hash: AtomicityDigest.sha256(preservedManifest),
                note: "observed_result_sha256=\(observedHash)\n"
            )
            for spike in Array(Phase0RunLayout.spikeDirectories.prefix(7)) {
                let destination = temporary.appendingPathComponent(spike, isDirectory: true)
                stages.append(try execute(
                    id: spike, arguments: [spike, "--environment", stagedEnvironment.path, "--output", destination.path],
                    logicalOutput: spike, cleanup: cleanup
                ))
            }
            for spike in ["sp6a", "sp6b"] {
                stages.append(try preservedStage(spike, root: temporary))
            }
            let receipt = Phase0RunReceipt(
                runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                runnerSourceSha256: identity.sourceSha256,
                environmentSha256: AtomicityDigest.sha256(environmentData),
                directories: Phase0RunLayout.directories, rootArtifacts: Phase0RunLayout.rootArtifacts,
                stages: stages, toolVersions: try toolVersions(cleanup: cleanup)
            )
            try encoded(receipt).write(to: temporary.appendingPathComponent("run-all.json"))
            let exclusions: Set<String> = ["privacy-audit.json", "manifest.sha256"]
            let privacy = try Phase0PrivacyAudit.scan(root: temporary, excluding: exclusions)
            try encoded(privacy).write(to: temporary.appendingPathComponent("privacy-audit.json"))
            try writeRootManifest(temporary)
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            try FileManager.default.moveItem(at: temporary, to: output)
            cleanup.complete()
            print("RUN_ALL=PASS spikes=9 blocked_allowed=true privacy_hits=0 output=\(output.path)")
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: output)
            cleanup.complete()
            throw error
        }
    }

    private static func seed(_ destination: URL, from source: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        for name in ["README.md", "fixtures", "sources", "shared-atomicity", "sp6a", "sp6b"] {
            let input = source.appendingPathComponent(name)
            let values = try input.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw Phase0RunError.symlink(name) }
            try FileManager.default.copyItem(at: input, to: destination.appendingPathComponent(name))
        }
    }

    private static func execute(id: String, arguments: [String], logicalOutput: String,
                                cleanup: RunAllSignalCleanup) throws -> Phase0RunStage {
        let command = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let result = try process(command.path, arguments, timeout: 600, cleanup: cleanup)
        guard result.status == 0 else { throw Phase0RunError.stageFailed(id, result.status) }
        let outputIndex = arguments.firstIndex(of: "--output")!
        let evidence = URL(fileURLWithPath: arguments[outputIndex + 1])
        let verdict = id == "shared-atomicity" ? "PASS" : try evidenceVerdict(evidence)
        return Phase0RunStage(
            id: id, command: logicalCommand(arguments, output: logicalOutput), exitStatus: result.status,
            stdout: sanitize(result.stdout), stderr: sanitize(result.stderr), verdict: verdict,
            policy: id == "shared-atomicity" ? "executed-observation;canonical-preserved" : "regenerated-canonical",
            artifactSha256: nil
        )
    }

    private static func preservedStage(_ id: String, root: URL) throws -> Phase0RunStage {
        let directory = root.appendingPathComponent(id)
        let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.sha256"))
        return Phase0RunStage(
            id: id, command: ["preserve", "evidence/phase0/\(id)", "--by-manifest-hash"], exitStatus: 0,
            stdout: "preserved canonical nondeterministic trace\n", stderr: "", verdict: try evidenceVerdict(directory),
            policy: "preserved-nondeterministic-raw", artifactSha256: AtomicityDigest.sha256(manifest)
        )
    }

    private static func preserving(_ stage: Phase0RunStage, hash: String, note: String) -> Phase0RunStage {
        Phase0RunStage(id: stage.id, command: stage.command, exitStatus: stage.exitStatus, stdout: stage.stdout + note,
                       stderr: stage.stderr, verdict: stage.verdict, policy: stage.policy, artifactSha256: hash)
    }

    private static func evidenceVerdict(_ directory: URL) throws -> String {
        let data = try Data(contentsOf: directory.appendingPathComponent("evidence.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let verdict = object["verdict"] as? String,
              ["PASS", "BLOCKED", "INCONCLUSIVE", "FAIL"].contains(verdict) else {
            throw Phase0RunError.invalidEvidence(directory.lastPathComponent)
        }
        guard verdict != "FAIL" else { throw Phase0RunError.failedVerdict(directory.lastPathComponent) }
        return verdict
    }

    private static func toolVersions(cleanup: RunAllSignalCleanup) throws -> [Phase0ToolVersion] {
        let specifications = [("swift", "/usr/bin/xcrun", ["swift", "--version"]),
                              ("xcode", "/usr/bin/xcodebuild", ["-version"]),
                              ("git", "/usr/bin/git", ["--version"]),
                              ("jq", "/usr/bin/jq", ["--version"]),
                              ("shasum", "/usr/bin/shasum", ["--help"])]
        return try specifications.map { tool, executable, arguments in
            let result = try process(executable, arguments, timeout: 10, cleanup: cleanup)
            guard result.status == 0 else { throw Phase0RunError.toolFailed(tool) }
            return Phase0ToolVersion(tool: tool, command: [executable] + arguments, exitStatus: result.status,
                                     stdout: sanitize(result.stdout), stderr: sanitize(result.stderr))
        }
    }

    private static func process(_ executable: String, _ arguments: [String], timeout: TimeInterval,
                                cleanup: RunAllSignalCleanup) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        if arguments.first == "sp4b", let index = arguments.firstIndex(of: "--output") {
            var environment = ProcessInfo.processInfo.environment
            environment["KEYRECORD_PHASE0_EVIDENCE_ROOT"] = URL(fileURLWithPath: arguments[index + 1]).deletingLastPathComponent().path
            process.environment = environment
        }
        process.standardOutput = stdout; process.standardError = stderr
        try process.run(); cleanup.setChild(process.processIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); process.waitUntilExit(); throw Phase0RunError.timeout(arguments.first ?? executable) }
        cleanup.setChild(nil)
        return (process.terminationStatus,
                String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private static func logicalCommand(_ arguments: [String], output: String) -> [String] {
        var result = ["Phase0Probe"] + arguments
        if let index = result.firstIndex(of: "--environment") { result[index + 1] = "environment.json" }
        if let index = result.firstIndex(of: "--output") { result[index + 1] = output }
        return result
    }

    static func sanitize(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "/private/var/folders/", with: "/var/folders/")
        let repository = (try? repositoryRoot().path) ?? ""
        if !repository.isEmpty { value = value.replacingOccurrences(of: repository, with: "${REPOSITORY}") }
        value = value.replacingOccurrences(of: NSHomeDirectory(), with: "${HOME}")
        value = value.replacingOccurrences(
            of: #"\$\{REPOSITORY\}/evidence/\.phase0\.[^/\s]+\.tmp"#,
            with: "${OUTPUT_ROOT}", options: .regularExpression
        )
        return value.replacingOccurrences(of: #"(?:/private)?/var/folders/[^\s]+"#, with: "${TEMP}", options: .regularExpression)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func bounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1_048_576 else {
            throw Phase0RunError.invalidEnvironment
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    static func invalidate(_ output: URL, parent: URL, preserving temporary: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try cleanStale(parent: parent, preserving: temporary)
    }
    private static func cleanStale(parent: URL, preserving temporary: URL) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path)
        where name.hasPrefix(".phase0.") && name.hasSuffix(".tmp") {
            let candidate = parent.appendingPathComponent(name).standardizedFileURL
            if candidate != temporary.standardizedFileURL { try? FileManager.default.removeItem(at: candidate) }
        }
    }
    private static func writeRootManifest(_ root: URL) throws {
        let lines = try Phase0RunLayout.rootArtifacts.sorted().map {
            "\(AtomicityDigest.sha256(try Data(contentsOf: root.appendingPathComponent($0))))  \($0)"
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: root.appendingPathComponent("manifest.sha256"))
    }
    private static func repositoryRoot() throws -> URL {
        var value = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        while value.path != "/" { if FileManager.default.fileExists(atPath: value.appendingPathComponent(".git").path) { return value }; value.deleteLastPathComponent() }
        throw Phase0RunError.repositoryNotFound
    }
}

private enum Phase0RunError: Error {
    case failedVerdict(String), invalidEnvironment, invalidEvidence(String), repositoryNotFound
    case stageFailed(String, Int32), symlink(String), timeout(String), toolFailed(String)
}

private final class RunAllSignalCleanup: @unchecked Sendable {
    private let paths: [URL], lock = NSLock(); private var child: Int32?; private var sources: [DispatchSourceSignal] = []
    init(paths: [URL]) {
        self.paths = paths
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN); let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { [weak self] in self?.interrupt(status: Int32(item.1)) }; source.resume(); sources.append(source)
        }
    }
    func setChild(_ pid: Int32?) { lock.lock(); child = pid; lock.unlock() }
    func complete() { sources.forEach { $0.cancel() }; sources.removeAll(); signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL) }
    private func interrupt(status: Int32) { lock.lock(); let pid = child; lock.unlock(); if let pid { Darwin.kill(pid, SIGTERM) }; paths.forEach { try? FileManager.default.removeItem(at: $0) }; Foundation.exit(status) }
}

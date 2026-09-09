import AppKit
import Darwin
import Foundation
import Phase0Support

protocol SP2LiveScenarioExecuting: Sendable {
    func execute(d1: Bool, d3: Bool, d4: Bool, secureHelper: SecureInputState?) -> SP2LiveExecution
}

enum SP2Probe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(sourcePaths: SP2RunnerBinding.sourcePaths.sorted()),
        liveExecutor: any SP2LiveScenarioExecuting = ProcessEnvironmentSP2LiveExecutor(),
        secureHelperProvider: @Sendable () -> SecureInputState? = { safeSecureInputHelperState() }
    ) throws {
        guard arguments.count == 5, arguments[0] == "sp2", arguments[1] == "--environment",
              arguments[3] == "--output" else { throw ProbeError.usage }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try boundedFile(environmentURL)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        let identity = try identityProvider.resolve()
        let environmentHash = AtomicityDigest.sha256(environmentData)
        let d1 = environment.guiSession.status == .available && environment.listenEventAccess == .available
            && environment.guiSession.tapCreate == .available
        let secureHelper = secureHelperProvider()
        let d3 = environment.guiSession.status == .available && secureHelper != nil
        let d4 = environment.guiSession.status == .available && environment.sudoNonInteractive
        if environment.guiSession.status == .available { _ = boundedFrontmostMetadataPreflight() }

        let modelExecution = SP2ModelScenarios.run()
        let privacy = modelExecution.privacy
        let modifiers = modelExecution.modifiers
        let privacyData = try encoded(privacy)
        let modifierData = try encoded(modifiers)
        let v2Live = SP2LiveArming.v2Enabled
        let liveExecution = v2Live ? liveExecutor.execute(d1: d1, d3: d3, d4: d4, secureHelper: secureHelper) : nil
        let liveData = try liveExecution.map { try $0.aggregate.canonicalData() }
            ?? encoded(SP2AggregateArtifact(evidenceKind: .live))
        let hashes = [
            "privacy-model.json": AtomicityDigest.sha256(privacyData),
            "modifier-model.json": AtomicityDigest.sha256(modifierData),
            "live-aggregate-counts.json": AtomicityDigest.sha256(liveData),
        ]
        let availability = ["D0": true, "D1": d1, "D3": d3, "D4": d4]
        let legs = SP2Evidence.requiredLegIDs.sorted().map { legID -> SP2Leg in
            let rule = Phase0Registry.legRules[legID]!
            let available = availability[rule.detectorID] ?? false
            if !available {
                return blockedLeg(legID, rule: rule, identity: identity, environmentHash: environmentHash)
            }
            if v2Live, rule.evidenceKind == .live, liveExecution?.armed != true {
                return SP2Leg(
                    legID: legID, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                    detectorAvailable: false, verdict: .blocked, blocker: SP2CanonicalBlockers.liveExecutionNotArmed,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, command: [], exitStatus: nil, artifactSha256: nil,
                    dataDelta: 0, metaDelta: 0
                )
            }
            let artifactName = rule.evidenceKind == .live ? "live-aggregate-counts.json"
                : (legID.contains("sided") || legID.contains("fnRecoveryModel") ? "modifier-model.json" : "privacy-model.json")
            let verdict: Verdict
            if rule.evidenceKind == .live, let liveExecution {
                verdict = Self.liveVerdict(legID, execution: liveExecution)
            } else if rule.evidenceKind == .live {
                verdict = .inconclusive
            } else {
                verdict = modelExecution.assertions[legID] == true ? .pass : .fail
            }
            let delta = (legID == "sp2.frontmostKnown" || legID == "sp2.frontmostUnattributable") && verdict == .pass ? 1 : 0
            return SP2Leg(
                legID: legID, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                detectorAvailable: true, verdict: verdict, blocker: nil,
                runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, command: ["Phase0Probe", "sp2", "bounded", legID],
                exitStatus: 0, artifactPath: artifactName, artifactSha256: hashes[artifactName], dataDelta: delta, metaDelta: delta
            )
        }
        let verdict = aggregate(legs.map(\.verdict))
        let allPass = legs.allSatisfy { $0.verdict == .pass }
        let report = SP2Evidence(
            legs: legs, verdict: verdict, o6Status: allPass ? .resolved : .open, g0Status: .open,
            runnerSourceSha256: identity.sourceSha256
        )
        try report.validate()
        try publish(report: report, privacyData: privacyData, modifierData: modifierData, liveData: liveData, output: output)
        print("SP2=\(report.verdict.rawValue) pass=\(legs.filter { $0.verdict == .pass }.count) blocked=\(legs.filter { $0.verdict == .blocked }.count) o6=\(report.o6Status.rawValue) g0=OPEN output=\(output.path)")
    }

    private static func blockedLeg(_ legID: String, rule: Phase0Registry.LegRule,
                                   identity: AtomicityRunnerIdentity, environmentHash: String) -> SP2Leg {
        let details: (String, [String], String, String) = switch rule.detectorID {
        case "D1": ("input_monitoring_denied", ["CGPreflightListenEventAccess", "environment.json guiSession.tapCreate"],
                    "GUI session with Input Monitoring already granted", "Grant Input Monitoring outside this probe, then rerun; this probe never prompts")
        case "D3": ("secure_input_helper_unavailable", ["test", "-x", "/usr/local/libexec/keyrecord-secure-input-status"],
                    "Already-installed safe Secure Event Input status helper", "Install and authorize the reviewed helper separately, then rerun")
        case "D4": ("noninteractive_sleep_privilege_unavailable", ["sudo", "-n", "true"],
                    "Separately authorized non-interactive sleep/wake test host", "Provision a disposable authorized test host; this probe never sleeps the current host")
        default: ("detector_unavailable", ["environment.json", rule.detectorID], "required detector", "Satisfy prerequisite and rerun")
        }
        return SP2Leg(
            legID: legID, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
            detectorAvailable: false, verdict: .blocked,
            blocker: SP1Blocker(blockedBy: details.0, detectCommand: details.1, prerequisite: details.2, unblockAction: details.3),
            runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
            environmentSha256: environmentHash, command: [], exitStatus: nil, artifactSha256: nil,
            dataDelta: 0, metaDelta: 0
        )
    }

    private static func boundedFrontmostMetadataPreflight() -> FrontmostState {
        guard let application = NSWorkspace.shared.frontmostApplication else { return .knownUnattributable }
        guard let bundleID = application.bundleIdentifier, !bundleID.isEmpty else { return .knownUnattributable }
        return .known(bundleID: bundleID)
    }

    private static func safeSecureInputHelperState() -> SecureInputState? {
        let path = "/usr/local/libexec/keyrecord-secure-input-status"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: path),
              (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { return nil }
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = ["--once"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        switch String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "enabled": return .enabled
        case "disabled": return .disabled
        case "unknown": return .unknown
        default: return nil
        }
    }

    private static func publish(report: SP2Evidence, privacyData: Data, modifierData: Data, liveData: Data, output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp2.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = SP2SignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP2_TEST_DELAY_AFTER_TEMP"], let delay = Double(value) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try encoded(report).write(to: temporary.appendingPathComponent("evidence.json"))
            try privacyData.write(to: temporary.appendingPathComponent("privacy-model.json"))
            try modifierData.write(to: temporary.appendingPathComponent("modifier-model.json"))
            try liveData.write(to: temporary.appendingPathComponent("live-aggregate-counts.json"))
            let rows = report.legs.map { "- `\($0.legID)`: \($0.verdict.rawValue) (`\($0.blocker?.blockedBy ?? "executed")`)" }.joined(separator: "\n")
            let conclusion = "# SP-2 conclusion\n\nVerdict: **\(report.verdict.rawValue)**\n\nO6: **\(report.o6Status.rawValue)**\n\nG0: **\(report.g0Status.rawValue)**\n\nLive checks were bounded metadata preflights only. No permission prompt, sleep, persistent monitor, event detail, key, text, sequence, or exact timestamp was recorded.\n\n\(rows)\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-2-CONCLUSION.md"))
            try writeManifest(in: temporary)
            try FileManager.default.moveItem(at: temporary, to: output)
            cleanup.complete()
        } catch {
            try? FileManager.default.removeItem(at: temporary); cleanup.complete(); throw error
        }
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func writeManifest(in directory: URL) throws {
        let names = SP2DirectoryLayout.artifactNames.sorted()
        let lines = try names.map { "\(AtomicityDigest.sha256(try Data(contentsOf: directory.appendingPathComponent($0))))  \($0)" }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
    private static func boundedFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_048_576 else { throw SP2ProbeError.invalidEnvironment }
        return try Data(contentsOf: url)
    }
    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp2.") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
    private static func liveVerdict(_ legID: String, execution: SP2LiveExecution) -> Verdict {
        let passes: Bool
        switch legID {
        case "sp2.frontmostKnown": passes = execution.frontmostKnownPasses
        case "sp2.frontmostUnattributable": passes = execution.frontmostUnattributablePasses
        case "sp2.fnRecoveryLive": passes = execution.fnRecoveryLivePasses
        case "sp2.secureInput": passes = execution.secureInputPasses
        case "sp2.sleepWake": passes = execution.sleepWakePasses
        default: passes = false
        }
        return passes ? .pass : .inconclusive
    }

    private static func aggregate(_ verdicts: [Verdict]) -> Verdict {
        verdicts.max { precedence($0) < precedence($1) } ?? .blocked
    }
    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

extension SP2Probe {
    static func boundedFrontmostMetadataPreflightForExecutor() -> FrontmostState {
        boundedFrontmostMetadataPreflight()
    }
}

private enum SP2ProbeError: Error { case invalidEnvironment }

private final class SP2SignalCleanup: @unchecked Sendable {
    private let paths: [URL]
    private var sources: [DispatchSourceSignal] = []
    init(paths: [URL]) {
        self.paths = paths
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { [paths] in
                paths.forEach { try? FileManager.default.removeItem(at: $0) }
                Foundation.exit(Int32(item.1))
            }
            source.resume(); sources.append(source)
        }
    }
    func complete() {
        sources.forEach { $0.cancel() }; sources.removeAll()
        signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL)
    }
}

import AppKit
import CryptoKit
import Darwin
import Foundation
import KeyRecordMeasurement

private struct TrialFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct TrialOptions {
    let run: Bool
    let app: URL
    let root: URL
    let namespace: String
    let mode: String?
    let sampler: URL?

    init(_ arguments: [String]) throws {
        guard let command = arguments.first, ["--check", "--run"].contains(command),
              arguments.count % 2 == 1 else { throw TrialFailure("usage") }
        var fields: [String: String] = [:]
        for index in stride(from: 1, to: arguments.count, by: 2) {
            let key = arguments[index]
            guard ["--app", "--root", "--namespace", "--mode", "--sampler"].contains(key),
                  fields[key] == nil else { throw TrialFailure("usage") }
            fields[key] = arguments[index + 1]
        }
        guard let app = fields["--app"], app.hasPrefix("/"),
              let root = fields["--root"], root.hasPrefix("/"),
              let namespace = fields["--namespace"],
              namespace.hasPrefix("com.keyrecord.trial.performance"),
              namespace.utf8.count <= 128,
              namespace.utf8.allSatisfy({ $0 == 45 || $0 == 46 ||
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            throw TrialFailure("invalid-trial-input")
        }
        run = command == "--run"
        self.app = URL(fileURLWithPath: app).standardizedFileURL
        self.root = URL(fileURLWithPath: root).standardizedFileURL
        self.namespace = namespace
        mode = fields["--mode"]
        sampler = fields["--sampler"].map { URL(fileURLWithPath: $0).standardizedFileURL }
        if run {
            guard ["typing", "idle"].contains(mode ?? ""), sampler != nil else {
                throw TrialFailure("run-requires-mode-and-sampler")
            }
        } else if mode != nil || sampler != nil {
            throw TrialFailure("check-does-not-use-mode-or-sampler")
        }
    }
}

private struct TrialIdentity {
    let bundleID: String
    let displayName: String
    let executable: URL
    let executableSHA256: String
}

private struct ReplaySummary: Decodable {
    let mode: String
    let outcome: String
    let expectedTicks: Int
    let ticks: Int
    let acceptedEvents: Int64
    let durableKeyDownTotal: Int64?
    let elapsedSeconds: Double
    let startedUptimeSeconds: Double?
    let endedUptimeSeconds: Double?
}

private struct TrialReport: Encodable {
    let kind = "product-performance-trial"
    let productPass = false
    let outcome: String
    let mode: String
    let bundleID: String
    let executableSHA256: String
    let architecture: String?
    let macOS: String?
    let sampleOutcome: String?
    let sampleReason: String?
    let cpuPercentOfOneLogicalCore: Double?
    let footprintMeanBytes: Double?
    let footprintSampledPeakBytes: UInt64?
    let replayOutcome: String?
    let acceptedEvents: Int64?
    let durableKeyDownTotal: Int64?
    let normalExit: Bool
}

@main
@MainActor
private enum PerformanceTrialCLI {
    static func main() async {
        do {
            let options = try TrialOptions(Array(CommandLine.arguments.dropFirst()))
            let identity = try inspect(options)
            if !options.run {
                print("trial-check=ready displayName=\(identity.displayName) bundleID=\(identity.bundleID) launched=false")
                return
            }
            let report = try await run(options, identity: identity)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(report)
            try bytes.write(to: options.root.appendingPathComponent("trial-report.json"), options: .atomic)
            print(String(decoding: bytes, as: UTF8.self))
            if report.outcome != "measured" { exit(1) }
        } catch {
            fputs("trial-error: \(error)\n", stderr)
            exit(2)
        }
    }

    private static func inspect(_ options: TrialOptions) throws -> TrialIdentity {
        var rootStatus = stat()
        guard options.root.path.withCString({ lstat($0, &rootStatus) }) == 0,
              rootStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              rootStatus.st_mode & 0o777 == 0o700,
              rootStatus.st_uid == getuid(),
              try FileManager.default.contentsOfDirectory(atPath: options.root.path).isEmpty else {
            throw TrialFailure("trial-root-must-be-fresh-owned-private-directory")
        }
        let plist = options.app.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plist)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String,
              bundleID.hasPrefix("com.keyrecord.trial.performance"),
              let name = info["CFBundleDisplayName"] as? String,
              name.contains("Performance Trial"),
              info["KeyRecordRequiresTrialIsolation"] as? Bool == true,
              let executableName = info["CFBundleExecutable"] as? String else {
            throw TrialFailure("app-is-not-a-dedicated-performance-trial")
        }
        let executable = options.app.appendingPathComponent("Contents/MacOS/").appendingPathComponent(executableName)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw TrialFailure("trial-executable-missing")
        }
        guard options.app.resolvingSymlinksInPath() == options.app else {
            throw TrialFailure("trial-app-path-has-symlink")
        }
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--strict", "--deep", options.app.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else { throw TrialFailure("trial-signature-invalid") }
        if options.run {
            guard let sampler = options.sampler,
                  FileManager.default.isExecutableFile(atPath: sampler.path) else {
                throw TrialFailure("sampler-missing")
            }
            guard NSWorkspace.shared.runningApplications.allSatisfy({ $0.bundleIdentifier != bundleID }) else {
                throw TrialFailure("trial-already-running")
            }
        }
        let digest = SHA256.hash(data: try Data(contentsOf: executable))
            .map { String(format: "%02x", $0) }.joined()
        return TrialIdentity(bundleID: bundleID, displayName: name, executable: executable,
                             executableSHA256: digest)
    }

    private static func run(_ options: TrialOptions, identity: TrialIdentity) async throws -> TrialReport {
        guard let mode = options.mode, let sampler = options.sampler else { throw TrialFailure("usage") }
        let nativeArch = try nativeArchitecture()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        config.allowsRunningApplicationSubstitution = false
        config.environment = [
            "KEYRECORD_LOCAL_CAPTURE": "1",
            "KEYRECORD_TRIAL_STORE": options.root.appendingPathComponent("store").path,
            "KEYRECORD_TRIAL_NAMESPACE": options.namespace,
            "KEYRECORD_PERFORMANCE_REPLAY": mode,
            "KEYRECORD_DIAGNOSTIC_SUMMARY_PATH": options.root.appendingPathComponent("summary.json").path
        ]
        let app = try await NSWorkspace.shared.openApplication(at: options.app, configuration: config)
        guard app.bundleIdentifier == identity.bundleID,
              app.bundleURL?.resolvingSymlinksInPath() == options.app.resolvingSymlinksInPath(),
              app.processIdentifier > 0 else {
            app.terminate()
            throw TrialFailure("launched-identity-mismatch")
        }
        let output = options.root.appendingPathComponent("resource-\(mode).json")
        let marker = options.root.appendingPathComponent("performance-replay.json")
        let process = Process()
        process.executableURL = sampler
        process.arguments = ["--pid", String(app.processIdentifier), "--expect-path", identity.executable.path,
            "--protocol", "formalFRS2", "--phase", mode, "--warmup-seconds", "60",
            "--measure-seconds", "600", "--interval-seconds", "0.5", "--output", output.path,
            "--start-marker", marker.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            app.terminate()
            throw TrialFailure("sampler-start-failed")
        }
        print("Trial launched. Choose Start in its menu and accept first-run consent. The fixed replay runs for 662 seconds after Collecting. Do not input keys. The trial will receive a normal Quit request after measurement.")
        process.waitUntilExit()
        let summary = try? await waitForSummary(at: marker, seconds: 20)
        let archive = try? JSONDecoder().decode(ResourceMeasurementArchive.self, from: Data(contentsOf: output))
        let normalExit = await quitNormally(app)
        let result = archive?.result
        let expected = mode == "typing" ? Int64(ReplayWorkload.expectedTypingEvents) : 0
        let aligned: Bool
        if let started = summary?.startedUptimeSeconds, let origin = archive?.originUptimeSeconds {
            aligned = abs(started - origin) < 0.001
        } else {
            aligned = false
        }
        let workloadSeconds = Double(ReplayWorkload.windowTicks) * ReplayWorkload.tickIntervalSeconds
        let completed = summary?.outcome == "completed" && summary?.mode == mode
            && summary?.expectedTicks == ReplayWorkload.windowTicks
            && summary?.ticks == ReplayWorkload.windowTicks
            && summary?.acceptedEvents == expected
            && summary?.durableKeyDownTotal == expected / 2
            && (summary?.elapsedSeconds ?? 0) >= workloadSeconds - 0.5
            && (summary?.endedUptimeSeconds ?? 0) >= (summary?.startedUptimeSeconds ?? .infinity)
                + workloadSeconds - 0.5
        let recomputed = archive.map { ResourceEvaluator.recompute($0) == $0.result } ?? false
        let afterDigest = SHA256.hash(data: try Data(contentsOf: identity.executable))
            .map { String(format: "%02x", $0) }.joined()
        let valid = process.terminationStatus == 0 && result?.outcome == "measured"
            && archive?.protocolKind == .formalFRS2 && archive?.phase == mode
            && archive?.architecture == nativeArch
            && app.executableArchitecture == (nativeArch == "arm64" ? CPU_TYPE_ARM64 : CPU_TYPE_X86_64)
            && archive?.executablePath == identity.executable.path
            && result?.productProcessOnly == true && recomputed
            && afterDigest == identity.executableSHA256
            && aligned && completed && normalExit
        return TrialReport(outcome: valid ? "measured" : "invalid", mode: mode,
            bundleID: identity.bundleID, executableSHA256: identity.executableSHA256,
            architecture: archive?.architecture, macOS: archive?.operatingSystem,
            sampleOutcome: result?.outcome, sampleReason: result?.reason,
            cpuPercentOfOneLogicalCore: result?.cpuPercentOfOneLogicalCore,
            footprintMeanBytes: result?.footprintMeanBytes,
            footprintSampledPeakBytes: result?.footprintSampledPeakBytes,
            replayOutcome: summary?.outcome, acceptedEvents: summary?.acceptedEvents,
            durableKeyDownTotal: summary?.durableKeyDownTotal, normalExit: normalExit)
    }

    private static func waitForSummary(at url: URL, seconds: Double) async throws -> ReplaySummary {
        let deadline = ContinuousClock().now.advanced(by: .seconds(seconds))
        while ContinuousClock().now < deadline {
            if let data = try? Data(contentsOf: url),
               let summary = try? JSONDecoder().decode(ReplaySummary.self, from: data),
               summary.outcome != "running" && summary.outcome != "verifyingDurability" {
                return summary
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw TrialFailure("replay-summary-missing")
    }

    private static func quitNormally(_ app: NSRunningApplication) async -> Bool {
        if app.isTerminated { return true }
        guard app.terminate() else { return false }
        let deadline = ContinuousClock().now.advanced(by: .seconds(15))
        while ContinuousClock().now < deadline {
            if app.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return app.isTerminated
    }

    private static func nativeArchitecture() throws -> String {
        var translated: Int32 = 0
        var size = MemoryLayout.size(ofValue: translated)
        let status = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        guard (status == 0 && translated == 0) || (status == -1 && errno == ENOENT) else {
            throw TrialFailure("translated-host")
        }
        var host = utsname()
        guard uname(&host) == 0 else { throw TrialFailure("host-architecture-unavailable") }
        let capacity = MemoryLayout.size(ofValue: host.machine)
        let arch = withUnsafePointer(to: &host.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        guard ["arm64", "x86_64"].contains(arch) else { throw TrialFailure("unsupported-host-architecture") }
        return arch
    }
}

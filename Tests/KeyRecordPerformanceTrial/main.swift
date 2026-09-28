import AppKit
import CryptoKit
import Darwin
import Foundation
import KeyRecordMeasurement
import Security

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
    let productCode: URL
    let productCodeSHA256: String
}

private struct ReplaySummary: Codable {
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
    let productCodeSHA256: String
    let architecture: String?
    let macOS: String?
    let machineModel: String
    let chip: String
    let machineRAM: UInt64
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

private struct StoredTrialReport: Decodable {
    let kind: String
    let productPass: Bool
    let outcome: String
    let mode: String
    let bundleID: String
    let executableSHA256: String
    let productCodeSHA256: String
    let architecture: String?
    let macOS: String?
    let machineModel: String
    let chip: String
    let machineRAM: UInt64
    let sampleOutcome: String?
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
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--self-check-evaluation"] {
                try selfCheckEvaluation()
                print("host-evaluation-self-check=pass synthetic=true productPass=false")
                return
            }
            if arguments.first == "--evaluate" {
                guard arguments.count == 3, arguments[1] == "--session",
                      arguments[2].hasPrefix("/") else { throw TrialFailure("usage") }
                let root = URL(fileURLWithPath: arguments[2]).standardizedFileURL
                let result = try evaluateSession(at: root)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let bytes = try encoder.encode(result)
                try bytes.write(to: root.appendingPathComponent("host-report.json"), options: .atomic)
                print(String(decoding: bytes, as: UTF8.self))
                if !result.withinBudget { exit(1) }
                return
            }
            let options = try TrialOptions(arguments)
            let identity = try inspect(options)
            if !options.run {
                print("trial-check=ready displayName=\(identity.displayName) bundleID=\(identity.bundleID) executableSHA256=\(identity.executableSHA256) productCodeSHA256=\(identity.productCodeSHA256) launched=false")
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
        guard executable.resolvingSymlinksInPath() == executable,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw TrialFailure("trial-executable-missing")
        }
        let productCode = executable.deletingLastPathComponent()
            .appendingPathComponent(executableName + ".debug.dylib")
        guard productCode.resolvingSymlinksInPath() == productCode,
              FileManager.default.isExecutableFile(atPath: productCode.path) else {
            throw TrialFailure("trial-product-code-missing")
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
        try inspectKeychainIdentity(app: options.app, bundleID: bundleID)
        if options.run {
            guard let sampler = options.sampler,
                  FileManager.default.isExecutableFile(atPath: sampler.path) else {
                throw TrialFailure("sampler-missing")
            }
            guard NSWorkspace.shared.runningApplications.allSatisfy({ $0.bundleIdentifier != bundleID }) else {
                throw TrialFailure("trial-already-running")
            }
        }
        let digest = try sha256(executable)
        let codeDigest = try sha256(productCode)
        return TrialIdentity(bundleID: bundleID, displayName: name, executable: executable,
                             executableSHA256: digest, productCode: productCode,
                             productCodeSHA256: codeDigest)
    }

    private static func inspectKeychainIdentity(app: URL, bundleID: String) throws {
        let profileURL = app.appendingPathComponent("Contents/embedded.provisionprofile")
        var profileStatus = stat()
        guard profileURL.path.withCString({ lstat($0, &profileStatus) }) == 0,
              profileStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw TrialFailure("trial-provisioning-profile-missing")
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code else { throw TrialFailure("trial-signing-identity-unavailable") }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any],
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              let signedBundleID = info[kSecCodeInfoIdentifier as String] as? String,
              signedBundleID == bundleID,
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              entitlements["com.apple.application-identifier"] as? String == "\(team).\(bundleID)" else {
            throw TrialFailure("trial-keychain-application-identifier-invalid")
        }
        let decode = Process()
        decode.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        decode.arguments = ["cms", "-D", "-i", profileURL.path]
        let output = Pipe()
        decode.standardOutput = output
        decode.standardError = FileHandle.nullDevice
        try decode.run()
        let profileData = output.fileHandleForReading.readDataToEndOfFile()
        decode.waitUntilExit()
        guard decode.terminationStatus == 0,
              let profile = try? PropertyListSerialization.propertyList(from: profileData, format: nil) as? [String: Any],
              let teams = profile["TeamIdentifier"] as? [String], teams.contains(team),
              let profileEntitlements = profile["Entitlements"] as? [String: Any],
              let profileAppID = profileEntitlements["com.apple.application-identifier"] as? String else {
            throw TrialFailure("trial-provisioning-profile-invalid")
        }
        let expectedAppID = "\(team).\(bundleID)"
        let authorized = profileAppID == expectedAppID ||
            (profileAppID.hasSuffix("*") &&
             profileAppID.hasPrefix("\(team).") &&
             expectedAppID.hasPrefix(String(profileAppID.dropLast())))
        guard authorized else { throw TrialFailure("trial-provisioning-profile-mismatch") }
    }

    private static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ options: TrialOptions, identity: TrialIdentity) async throws -> TrialReport {
        guard let mode = options.mode, let sampler = options.sampler else { throw TrialFailure("usage") }
        let nativeArch = try nativeArchitecture()
        let machineModel = try sysctlString("hw.model")
        let chip = try sysctlString("machdep.cpu.brand_string")
        let machineRAM = ProcessInfo.processInfo.physicalMemory
        guard machineRAM > 0 else { throw TrialFailure("machine-memory-unavailable") }
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
            "--start-marker", marker.path, "--diagnostics-enabled"]
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
        let afterDigest = try sha256(identity.executable)
        let afterCodeDigest = try sha256(identity.productCode)
        let valid = process.terminationStatus == 0 && result?.outcome == "measured"
            && archive?.protocolKind == .formalFRS2 && archive?.phase == mode
            && archive?.architecture == nativeArch
            && app.executableArchitecture == (nativeArch == "arm64" ? CPU_TYPE_ARM64 : CPU_TYPE_X86_64)
            && archive?.executablePath == identity.executable.path
            && result?.productProcessOnly == true && recomputed
            && afterDigest == identity.executableSHA256
            && afterCodeDigest == identity.productCodeSHA256
            && aligned && completed && normalExit
        return TrialReport(outcome: valid ? "measured" : "invalid", mode: mode,
            bundleID: identity.bundleID, executableSHA256: identity.executableSHA256,
            productCodeSHA256: identity.productCodeSHA256,
            architecture: archive?.architecture, macOS: archive?.operatingSystem,
            machineModel: machineModel, chip: chip, machineRAM: machineRAM,
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

    private static func evaluateSession(at root: URL) throws -> PerformanceHostResult {
        try checkPrivateDirectory(root)
        var windows: [PerformanceWindowSummary] = []
        for phase in ["typing", "idle"] {
            for repeatIndex in 1...3 {
                let directory = root.appendingPathComponent("\(phase)-\(repeatIndex)")
                try checkPrivateDirectory(directory)
                let report = try JSONDecoder().decode(StoredTrialReport.self,
                    from: readPrivateFile(directory.appendingPathComponent("trial-report.json"), limit: 8_192))
                let archive = try JSONDecoder().decode(ResourceMeasurementArchive.self,
                    from: readPrivateFile(directory.appendingPathComponent("resource-\(phase).json"), limit: 16_000_000))
                let replay = try JSONDecoder().decode(ReplaySummary.self,
                    from: readPrivateFile(directory.appendingPathComponent("performance-replay.json"), limit: 4_096))
                let expected = phase == "typing" ? Int64(ReplayWorkload.expectedTypingEvents) : 0
                guard report.kind == "product-performance-trial", !report.productPass,
                      report.outcome == "measured", report.mode == phase, report.normalExit,
                      report.sampleOutcome == "measured", report.replayOutcome == "completed",
                      report.bundleID.hasPrefix("com.keyrecord.trial.performance"),
                      report.architecture == archive.architecture, report.macOS == archive.operatingSystem,
                      report.cpuPercentOfOneLogicalCore == archive.result.cpuPercentOfOneLogicalCore,
                      report.footprintMeanBytes == archive.result.footprintMeanBytes,
                      report.footprintSampledPeakBytes == archive.result.footprintSampledPeakBytes,
                      report.acceptedEvents == expected, report.durableKeyDownTotal == expected / 2,
                      archive.protocolKind == .formalFRS2, archive.phase == phase,
                      archive.requestedWarmupSeconds == 60, archive.requestedMeasureSeconds == 600,
                      archive.requestedIntervalSeconds == 0.5,
                      archive.effectiveMeasureSeconds ?? 0 >= 600,
                      archive.diagnosticsEnabled, archive.diagnosticsIncludedInOverhead,
                      archive.retainedSampleCount == archive.samples.count,
                      archive.pid == archive.samples.first?.pid,
                      let processStart = archive.samples.first?.startAbstime,
                      archive.executablePath == archive.samples.first?.executablePath,
                      archive.result.outcome == "measured", archive.result.productProcessOnly,
                      archive.result == ResourceEvaluator.recompute(archive),
                      replay.mode == phase, replay.outcome == "completed",
                      replay.expectedTicks == ReplayWorkload.windowTicks,
                      replay.ticks == ReplayWorkload.windowTicks,
                      replay.acceptedEvents == expected, replay.durableKeyDownTotal == expected / 2,
                      replay.elapsedSeconds >= Double(ReplayWorkload.windowTicks)
                          * ReplayWorkload.tickIntervalSeconds - 0.5,
                      let start = replay.startedUptimeSeconds,
                      let end = replay.endedUptimeSeconds, end >= start + 661.5,
                      let origin = archive.originUptimeSeconds, abs(origin - start) < 0.001,
                      let cpu = report.cpuPercentOfOneLogicalCore,
                      let mean = report.footprintMeanBytes,
                      let peak = report.footprintSampledPeakBytes,
                      let duration = archive.effectiveMeasureSeconds else {
                    throw TrialFailure("session-window-invalid-\(phase)-\(repeatIndex)")
                }
                windows.append(PerformanceWindowSummary(phase: phase,
                    architecture: archive.architecture, macOS: archive.operatingSystem,
                    machineModel: report.machineModel, chip: report.chip,
                    machineRAM: report.machineRAM, bundleID: report.bundleID,
                    executableSHA256: report.executableSHA256,
                    productCodeSHA256: report.productCodeSHA256,
                    executablePath: archive.executablePath, pid: archive.pid,
                    startAbstime: processStart, cpuPercent: cpu,
                    footprintMeanBytes: mean, footprintPeakBytes: peak,
                    effectiveMeasureSeconds: duration, acceptedEvents: expected,
                    durableKeyDownTotal: expected / 2))
            }
        }
        return try PerformanceHostEvaluator.evaluate(windows)
    }

    private static func checkPrivateDirectory(_ url: URL) throws {
        var status = stat()
        guard url.path.withCString({ lstat($0, &status) }) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              status.st_mode & 0o777 == 0o700, status.st_uid == getuid() else {
            throw TrialFailure("session-directory-invalid")
        }
    }

    private static func readPrivateFile(_ url: URL, limit: Int64) throws -> Data {
        var status = stat()
        guard url.path.withCString({ lstat($0, &status) }) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              status.st_uid == getuid(), status.st_size > 0, status.st_size <= limit else {
            throw TrialFailure("session-file-invalid")
        }
        return try Data(contentsOf: url)
    }

    private static func selfCheckEvaluation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-host-evaluation-\(UUID().uuidString)")
        guard mkdir(root.path, 0o700) == 0 else { throw TrialFailure("self-check-directory") }
        defer { try? FileManager.default.removeItem(at: root) }
        let executablePath = "/private/tmp/synthetic/KeyRecordApp.app/Contents/MacOS/KeyRecordApp"
        let digest = String(repeating: "a", count: 64)
        let expectedSeconds = Double(ReplayWorkload.windowTicks) * ReplayWorkload.tickIntervalSeconds
        let encoder = JSONEncoder()
        for phase in ["typing", "idle"] {
            for repeatIndex in 1...3 {
                let directory = root.appendingPathComponent("\(phase)-\(repeatIndex)")
                guard mkdir(directory.path, 0o700) == 0 else { throw TrialFailure("self-check-directory") }
                let windowID = (phase == "typing" ? 0 : 3) + repeatIndex
                let cpuRate = phase == "typing" ? 0.005 : 0.0005
                let samples = (0...1_321).map { index in
                    let elapsed = Double(index) * 0.5
                    return ProcessResourceSample(uptimeSeconds: 100 + elapsed,
                        monotonicSeconds: 100 + elapsed,
                        cpuNanoseconds: UInt64(elapsed * cpuRate * 1e9),
                        childCPUNanoseconds: 0, footprintBytes: 50_000_000,
                        pid: Int32(12_000 + windowID), startAbstime: UInt64(42 + windowID),
                        executablePath: executablePath, consoleUID: 501)
                }
                let request = ResourceWindowRequest(protocolKind: .formalFRS2, phase: phase,
                    warmupSeconds: 60, measureSeconds: 600, intervalSeconds: 0.5,
                    originUptimeSeconds: 100, samples: samples)
                let result = ResourceEvaluator.evaluate(request)
                guard result.outcome == "measured" else { throw TrialFailure("self-check-sampling") }
                let archive = ResourceMeasurementArchive(request: request, result: result,
                    architecture: "arm64", operatingSystem: "synthetic", diagnosticsEnabled: true)
                let expected = phase == "typing" ? Int64(ReplayWorkload.expectedTypingEvents) : 0
                let report = TrialReport(outcome: "measured", mode: phase,
                    bundleID: "com.keyrecord.trial.performance.synthetic", executableSHA256: digest,
                    productCodeSHA256: String(repeating: "b", count: 64),
                    architecture: "arm64", macOS: "synthetic", machineModel: "SyntheticMac",
                    chip: "SyntheticChip", machineRAM: 16_000_000_000,
                    sampleOutcome: "measured", sampleReason: nil,
                    cpuPercentOfOneLogicalCore: result.cpuPercentOfOneLogicalCore,
                    footprintMeanBytes: result.footprintMeanBytes,
                    footprintSampledPeakBytes: result.footprintSampledPeakBytes,
                    replayOutcome: "completed", acceptedEvents: expected,
                    durableKeyDownTotal: expected / 2, normalExit: true)
                let replay = ReplaySummary(mode: phase, outcome: "completed",
                    expectedTicks: ReplayWorkload.windowTicks, ticks: ReplayWorkload.windowTicks,
                    acceptedEvents: expected, durableKeyDownTotal: expected / 2,
                    elapsedSeconds: expectedSeconds, startedUptimeSeconds: 100,
                    endedUptimeSeconds: 100 + expectedSeconds)
                try encoder.encode(report).write(to: directory.appendingPathComponent("trial-report.json"), options: .atomic)
                try encoder.encode(archive).write(to: directory.appendingPathComponent("resource-\(phase).json"), options: .atomic)
                try encoder.encode(replay).write(to: directory.appendingPathComponent("performance-replay.json"), options: .atomic)
            }
        }
        let result = try evaluateSession(at: root)
        guard result.withinBudget, result.windowCount == 6,
              result.typingMedianCPUPercent < 1, result.idleMedianCPUPercent < 0.1 else {
            throw TrialFailure("self-check-evaluation")
        }
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

    private static func sysctlString(_ name: String) throws -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else {
            throw TrialFailure("host-identity-unavailable")
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else {
            throw TrialFailure("host-identity-unavailable")
        }
        let value = String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard !value.isEmpty else { throw TrialFailure("host-identity-unavailable") }
        return value
    }
}

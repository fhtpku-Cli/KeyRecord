import Darwin
import Foundation
import Phase0Support

enum AtomicityProbe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider()
    ) throws {
        if arguments.contains("--runner-commit") || arguments.contains("--runner-tree") {
            throw AtomicityRunnerIdentityError.callerSuppliedIdentity
        }
        guard arguments.count == 7, arguments[0] == "atomicity",
               arguments[1] == "--output", arguments[3] == "--environment",
               arguments[5] == "--iterations", let iterations = Int(arguments[6]), iterations == 100 else {
            throw ProbeError.usage
        }
        let output = URL(fileURLWithPath: arguments[2])
        let environment = URL(fileURLWithPath: arguments[4])
        let identity = try identityProvider.resolve()
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-atomicity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        do {
            let evidence = try execute(
                workspace: workspace,
                iterations: iterations,
                environment: environment,
                runnerCommit: identity.commitSha,
                runnerTree: identity.treeSha,
                runnerSourceSha256: identity.sourceSha256,
                command: ["swift", "run", "--package-path", "Spikes", "Phase0Probe"] + arguments
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(evidence)
            data.append(10)
            _ = try JSONDecoder().decode(AtomicityEvidence.self, from: data)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try POSIXAtomicReplacement().replace(target: output, bytes: data)
            try removeWorkspace(workspace)
            print("ATOMICITY=PASS executions=100 boundaries=8 failures=4 output=\(output.path)")
        } catch let primary {
            do { try removeWorkspace(workspace) }
            catch let cleanup { throw AtomicityProbeError.cleanup(primary: String(describing: primary), cleanup: String(describing: cleanup)) }
            throw primary
        }
    }

    private static func execute(workspace: URL, iterations: Int, environment: URL, runnerCommit: String, runnerTree: String, runnerSourceSha256: [String: String], command: [String]) throws -> AtomicityEvidence {
        let oldBytes = Data(repeating: 0x4f, count: 32_771)
        let newBytes = Data(repeating: 0x4e, count: 65_539)
        let oldHash = AtomicityDigest.sha256(oldBytes)
        let newHash = AtomicityDigest.sha256(newBytes)
        let filesystem = try filesystemType(at: workspace)
        guard filesystem == "apfs" else { throw AtomicityProbeError.unsupportedFilesystem(filesystem) }

        var executions: [AtomicityExecution] = []
        for iteration in 1...iterations {
            let directory = workspace.appendingPathComponent("success-\(iteration)", isDirectory: true)
            let observed = try successfulReplacement(in: directory, oldBytes: oldBytes, newBytes: newBytes)
            executions.append(AtomicityExecution(iteration: iteration, observedHash: AtomicityDigest.sha256(observed), terminalState: try state(of: observed, old: oldBytes, new: newBytes)))
        }
        let boundaries = try AtomicReplacementCrashBoundary.allCases.map {
            try crashResult($0, workspace: workspace, oldBytes: oldBytes, newBytes: newBytes)
        }
        let failures = try AtomicReplacementFailureStep.allCases.map {
            try failureResult($0, workspace: workspace, oldBytes: oldBytes, newBytes: newBytes)
        }
        let environmentHash = AtomicityDigest.sha256(try boundedRegularFile(environment))
        let host = AtomicityHost(
            filesystem: filesystem,
            macOSVersion: processOutput("/usr/bin/sw_vers", ["-productVersion"]),
            macOSBuild: processOutput("/usr/bin/sw_vers", ["-buildVersion"]),
            architecture: processOutput("/usr/bin/uname", ["-m"])
        )
        let evidence = AtomicityEvidence(
            verdict: .pass,
            scope: "Observed ordinary rename replacement on this APFS volume and recorded macOS host only.",
            limitation: "This fixture probe does not establish behavior for non-APFS filesystems or other macOS versions/builds, and does not claim power-loss durability beyond completed fsync calls.",
            ordinaryRenameObservedAtomic: true,
            exchangeRenameNeeded: false,
            environmentSha256: environmentHash,
            runnerCommitSha: runnerCommit,
            runnerTreeSha: runnerTree,
            runnerSourceSha256: runnerSourceSha256,
            command: command,
            host: host,
            oldHash: oldHash,
            newHash: newHash,
            successfulExecutions: executions,
            boundaries: boundaries,
            failures: failures,
            citedBy: ["SP-3", "SP-6A"]
        )
        try evidence.validate()
        return evidence
    }

    private static func successfulReplacement(in directory: URL, oldBytes: Data, newBytes: Data) throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let target = directory.appendingPathComponent("target.bin")
        try oldBytes.write(to: target)
        _ = try POSIXAtomicReplacement().replace(target: target, bytes: newBytes, injection: AtomicReplacementInjection(maximumWriteSize: 97))
        let observed = try Data(contentsOf: target, options: .mappedIfSafe)
        try FileManager.default.removeItem(at: directory)
        return observed
    }

    private static func crashResult(_ boundary: AtomicReplacementCrashBoundary, workspace: URL, oldBytes: Data, newBytes: Data) throws -> AtomicityBoundaryResult {
        let directory = workspace.appendingPathComponent("crash-\(boundary.rawValue)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let target = directory.appendingPathComponent("target.bin")
        try oldBytes.write(to: target)
        let status: String
        do {
            _ = try POSIXAtomicReplacement().replace(target: target, bytes: newBytes, injection: AtomicReplacementInjection(crashAt: boundary, maximumWriteSize: 89))
            throw AtomicityProbeError.injectionDidNotFire(boundary.rawValue)
        } catch let error as AtomicReplacementError {
            guard error == .injectedCrash(boundary) else { throw error }
            status = error.description
        }
        let observed = try Data(contentsOf: target, options: .mappedIfSafe)
        let before = try temporaryCount(in: directory)
        try POSIXAtomicReplacement.cleanupStaleTemporaryFiles(in: directory)
        let after = try temporaryCount(in: directory)
        try FileManager.default.removeItem(at: directory)
        return AtomicityBoundaryResult(boundary: boundary, observedHash: AtomicityDigest.sha256(observed), terminalState: try state(of: observed, old: oldBytes, new: newBytes), injectedStatus: status, staleTemporaryFilesBeforeCleanup: before, staleTemporaryFilesAfterCleanup: after)
    }

    private static func failureResult(_ step: AtomicReplacementFailureStep, workspace: URL, oldBytes: Data, newBytes: Data) throws -> AtomicityFailureResult {
        let directory = workspace.appendingPathComponent("failure-\(step.rawValue)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let target = directory.appendingPathComponent("target.bin")
        try oldBytes.write(to: target)
        let status: String
        do {
            _ = try POSIXAtomicReplacement().replace(target: target, bytes: newBytes, injection: AtomicReplacementInjection(failureAt: step, writeFailureAfterBytes: step == .writeTemp ? 17 : nil, maximumWriteSize: 7))
            throw AtomicityProbeError.injectionDidNotFire(step.rawValue)
        } catch let error as AtomicReplacementError {
            guard error == .injectedFailure(step) else { throw error }
            status = error.description
        }
        let observed = try Data(contentsOf: target, options: .mappedIfSafe)
        let temporaryCount = try temporaryCount(in: directory)
        try FileManager.default.removeItem(at: directory)
        return AtomicityFailureResult(step: step, observedHash: AtomicityDigest.sha256(observed), terminalState: try state(of: observed, old: oldBytes, new: newBytes), injectedStatus: status, temporaryFilesAfterCleanup: temporaryCount)
    }

    private static func state(of observed: Data, old: Data, new: Data) throws -> AtomicityTerminalState {
        if observed == old { return .old }
        if observed == new { return .new }
        throw AtomicityProbeError.partialTarget(AtomicityDigest.sha256(observed))
    }

    private static func temporaryCount(in directory: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(POSIXAtomicReplacement.temporaryPrefix) }.count
    }

    private static func filesystemType(at directory: URL) throws -> String {
        let result = try processResult("/bin/df", ["-T", "apfs", directory.path])
        guard result.status == 0 else { throw AtomicityProbeError.unsupportedFilesystem("non-apfs-or-undetected") }
        return "apfs"
    }

    private static func processOutput(_ executable: String, _ arguments: [String]) -> String {
        do {
            let result = try processResult(executable, arguments)
            guard result.status == 0 else { return "unknown" }
            return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return "unknown" }
    }

    private static func processResult(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: Data) {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning {
            process.terminate(); Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw AtomicityProbeError.processTimedOut(executable)
        }
        let output = try pipe.fileHandleForReading.read(upToCount: 4_097) ?? Data()
        guard output.count <= 4_096 else { throw AtomicityProbeError.processOutputTooLarge(executable) }
        return (process.terminationStatus, output)
    }

    private static func boundedRegularFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= 1_048_576 else {
            throw AtomicityProbeError.invalidEnvironmentFile
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func removeWorkspace(_ workspace: URL) throws {
        if FileManager.default.fileExists(atPath: workspace.path) { try FileManager.default.removeItem(at: workspace) }
    }
}

private enum AtomicityProbeError: Error {
    case cleanup(primary: String, cleanup: String)
    case injectionDidNotFire(String)
    case invalidEnvironmentFile
    case partialTarget(String)
    case processOutputTooLarge(String)
    case processTimedOut(String)
    case unsupportedFilesystem(String)
}

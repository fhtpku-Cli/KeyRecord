import Darwin
import Foundation

struct GitResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

struct GitRunner: Sendable {
    let repository: URL
    let timeout: TimeInterval
    let executable: URL

    func run(_ arguments: [String], acceptedStatuses: Set<Int32> = [0]) throws -> GitResult {
        let scratchRoot = repository.appendingPathComponent(".omo/evidence")
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let temporary = scratchRoot.appendingPathComponent(".git-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let stdoutURL = temporary.appendingPathComponent("stdout")
        let stderrURL = temporary.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdoutHandle.close(); try? stderrHandle.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw ValidatorError("git_command_timeout", arguments.joined(separator: " "))
        }
        process.waitUntilExit()
        try stdoutHandle.synchronize(); try stderrHandle.synchronize()
        let result = GitResult(status: process.terminationStatus, stdout: try Data(contentsOf: stdoutURL), stderr: try Data(contentsOf: stderrURL))
        guard acceptedStatuses.contains(result.status) else {
            throw ValidatorError("git_command_failed", String(decoding: result.stderr, as: UTF8.self))
        }
        return result
    }

    func text(_ arguments: [String]) throws -> String {
        String(decoding: try run(arguments).stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func nulPaths(_ arguments: [String]) throws -> [String] {
        String(decoding: try run(arguments).stdout, as: UTF8.self).split(separator: "\0").map(String.init)
    }
}

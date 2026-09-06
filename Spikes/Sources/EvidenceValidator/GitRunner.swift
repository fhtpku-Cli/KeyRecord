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

    func run(
        _ arguments: [String],
        acceptedStatuses: Set<Int32> = [0],
        input: Data? = nil
    ) throws -> GitResult {
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
        let stdinHandle: FileHandle?
        if let input {
            let stdinURL = temporary.appendingPathComponent("stdin")
            try input.write(to: stdinURL)
            stdinHandle = try FileHandle(forReadingFrom: stdinURL)
        } else {
            stdinHandle = nil
        }
        defer { try? stdinHandle?.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.standardInput = stdinHandle
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

    func blobs(_ objectSpecs: [String]) throws -> [Data] {
        let input = Data((objectSpecs.joined(separator: "\n") + "\n").utf8)
        let output = try run(["cat-file", "--batch"], input: input).stdout
        var cursor = output.startIndex
        var blobs: [Data] = []
        blobs.reserveCapacity(objectSpecs.count)
        for objectSpec in objectSpecs {
            guard let newline = output[cursor...].firstIndex(of: 10) else {
                throw ValidatorError("git_batch_malformed", objectSpec)
            }
            let header = String(decoding: output[cursor..<newline], as: UTF8.self).split(separator: " ")
            guard header.count == 3, header[1] == "blob", let size = Int(header[2]) else {
                throw ValidatorError("git_batch_malformed", objectSpec)
            }
            let start = output.index(after: newline)
            guard let end = output.index(start, offsetBy: size, limitedBy: output.endIndex),
                  end < output.endIndex, output[end] == 10 else {
                throw ValidatorError("git_batch_malformed", objectSpec)
            }
            blobs.append(Data(output[start..<end]))
            cursor = output.index(after: end)
        }
        guard cursor == output.endIndex else { throw ValidatorError("git_batch_malformed") }
        return blobs
    }
}

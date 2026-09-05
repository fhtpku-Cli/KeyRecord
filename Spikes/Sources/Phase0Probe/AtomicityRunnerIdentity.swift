import Darwin
import Foundation
import Phase0Support

struct AtomicityRunnerIdentity: Equatable, Sendable {
    let commitSha: String
    let treeSha: String
    let sourceSha256: [String: String]
}

protocol AtomicityRunnerIdentityProviding: Sendable {
    func resolve() throws -> AtomicityRunnerIdentity
}

enum AtomicityRunnerIdentityError: Error, Equatable, CustomStringConvertible, Sendable {
    case callerSuppliedIdentity
    case dirtyRunnerSource(String)
    case gitCommandFailed(operation: String, status: Int32)
    case invalidGitIdentity(String)
    case invalidRunnerSource(String)
    case processOutputTooLarge(String)
    case processTimedOut(String)
    case sourceMismatch(String)

    var code: String {
        switch self {
        case .callerSuppliedIdentity: "RUNNER_IDENTITY_CALLER_SUPPLIED"
        case .dirtyRunnerSource: "RUNNER_SOURCE_DIRTY"
        case .gitCommandFailed: "RUNNER_GIT_COMMAND_FAILED"
        case .invalidGitIdentity: "RUNNER_GIT_IDENTITY_INVALID"
        case .invalidRunnerSource: "RUNNER_SOURCE_INVALID"
        case .processOutputTooLarge: "RUNNER_GIT_OUTPUT_TOO_LARGE"
        case .processTimedOut: "RUNNER_GIT_TIMEOUT"
        case .sourceMismatch: "RUNNER_SOURCE_MISMATCH"
        }
    }

    var description: String {
        switch self {
        case .callerSuppliedIdentity:
            "runner commit and tree are resolved internally; identity flags are forbidden"
        case let .dirtyRunnerSource(path): "runner source is not clean: \(path)"
        case let .gitCommandFailed(operation, status): "git \(operation) exited \(status)"
        case let .invalidGitIdentity(field): "invalid Git identity: \(field)"
        case let .invalidRunnerSource(path): "runner source is not a bounded regular file: \(path)"
        case let .processOutputTooLarge(operation): "git output exceeded bound: \(operation)"
        case let .processTimedOut(operation): "git command timed out: \(operation)"
        case let .sourceMismatch(path): "HEAD does not contain the exact runner source bytes: \(path)"
        }
    }
}

struct GitAtomicityRunnerIdentityProvider: AtomicityRunnerIdentityProviding {
    static let runnerSourcePaths = AtomicityRunnerBinding.sourcePaths.sorted()

    private let currentDirectory: URL
    private let timeout: TimeInterval
    private let sourcePaths: [String]
    private let revision: String
    private let requiresCurrentBytesMatch: Bool

    init(currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), timeout: TimeInterval = 5,
         sourcePaths: [String] = Self.runnerSourcePaths, revision: String = "HEAD",
         requiresCurrentBytesMatch: Bool = true) {
        self.currentDirectory = currentDirectory
        self.timeout = timeout
        self.sourcePaths = sourcePaths
        self.revision = revision
        self.requiresCurrentBytesMatch = requiresCurrentBytesMatch
    }

    func resolve() throws -> AtomicityRunnerIdentity {
        let rootText = try gitText(["rev-parse", "--show-toplevel"], in: currentDirectory)
        let root = URL(fileURLWithPath: rootText, isDirectory: true).standardizedFileURL
        let commit = try gitText(["rev-parse", "--verify", "\(revision)^{commit}"], in: root)
        let tree = try gitText(["rev-parse", "--verify", "\(revision)^{tree}"], in: root)
        guard Self.isGitSHA1(commit) else { throw AtomicityRunnerIdentityError.invalidGitIdentity("HEAD") }
        guard Self.isGitSHA1(tree) else { throw AtomicityRunnerIdentityError.invalidGitIdentity("HEAD^{tree}") }

        var sourceSha256: [String: String] = [:]
        for path in sourcePaths {
            let status = try gitText(
                ["status", "--porcelain=v1", "--untracked-files=all", "--", path],
                in: root,
                allowEmpty: true
            )
            guard status.isEmpty else { throw AtomicityRunnerIdentityError.dirtyRunnerSource(path) }
            let workingBytes = try boundedRegularFile(root.appendingPathComponent(path), path: path)
            _ = try gitData(["cat-file", "-e", "\(commit):\(path)"], in: root, maximumBytes: 0)
            let committedBytes = try gitData(
                ["cat-file", "blob", "\(commit):\(path)"],
                in: root,
                maximumBytes: 1_048_576
            )
            if requiresCurrentBytesMatch, workingBytes != committedBytes {
                throw AtomicityRunnerIdentityError.sourceMismatch(path)
            }
            sourceSha256[path] = AtomicityDigest.sha256(committedBytes)
        }
        return AtomicityRunnerIdentity(commitSha: commit, treeSha: tree, sourceSha256: sourceSha256)
    }

    private func gitText(_ arguments: [String], in directory: URL, allowEmpty: Bool = false) throws -> String {
        let data = try gitData(arguments, in: directory, maximumBytes: 65_536)
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowEmpty, text.isEmpty {
            throw AtomicityRunnerIdentityError.invalidGitIdentity(arguments.joined(separator: " "))
        }
        return text
    }

    private func gitData(_ arguments: [String], in directory: URL, maximumBytes: Int) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw AtomicityRunnerIdentityError.processTimedOut(arguments.joined(separator: " "))
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= maximumBytes else {
            throw AtomicityRunnerIdentityError.processOutputTooLarge(arguments.joined(separator: " "))
        }
        guard process.terminationStatus == 0 else {
            throw AtomicityRunnerIdentityError.gitCommandFailed(
                operation: arguments.joined(separator: " "),
                status: process.terminationStatus
            )
        }
        return data
    }

    private func boundedRegularFile(_ url: URL, path: String) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 1_048_576 else {
            throw AtomicityRunnerIdentityError.invalidRunnerSource(path)
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func isGitSHA1(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

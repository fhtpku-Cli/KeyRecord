import Foundation
import Phase0Support

enum SP6AHistoryAnchorProbe {
    static func reserve(arguments: [String]) throws {
        guard arguments.count == 7, arguments[0] == "sp6a-history-anchor",
              arguments[1] == "--environment", arguments[3] == "--history", arguments[5] == "--output" else {
            throw ProbeError.usage
        }
        let environment = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let identity = try GitAtomicityRunnerIdentityProvider(sourcePaths: SP6ARunnerBinding.sourcePaths.sorted()).resolve()
        let runner = SP6ANamespaceRunnerIdentity(
            commitSha: identity.commitSha, treeSha: identity.treeSha,
            environmentSha256: ViaDefinitionDigest.sha256(environment)
        )
        let historyURL = URL(fileURLWithPath: arguments[4])
        let history = try SP6AKeychainProbe.reserve(runner: runner, historyURL: historyURL)
        guard history.attempts.count == SP6ANamespaceHistoryContract.expectedAttemptCount else {
            throw SP6AKeychainError.attemptHistoryConflict
        }
        try canonical(history).write(to: URL(fileURLWithPath: arguments[6]), options: .atomic)
        print("SP6A_HISTORY_ANCHOR=READY attempts=\(history.attempts.count) output=\(arguments[6])")
    }

    static func resolve(anchorURL: URL) throws -> SP6ANamespaceHistoryAnchor {
        let path = SP6ANamespaceHistoryContract.anchorPath
        guard anchorURL.path.hasSuffix(path),
              let bytes = try? Data(contentsOf: anchorURL),
              bytes == (try? canonical(JSONDecoder().decode(SP6ANamespaceAttemptHistory.self, from: bytes))) else {
            throw SP6AKeychainError.attemptHistoryConflict
        }
        let repository = path.split(separator: "/").reduce(anchorURL) { result, _ in
            result.deletingLastPathComponent()
        }
        guard try gitText(["rev-parse", "--is-shallow-repository"], repository: repository) == "false" else {
            throw SP6AHistoryAnchorError.incompleteHistory
        }
        let candidates = try gitLines(
            ["log", "--format=%H", "--diff-filter=A", "HEAD", "--", path], repository: repository
        )
        guard candidates.count == 1, isFullSHA(candidates[0]) else {
            throw SP6AHistoryAnchorError.invalidCandidateSet
        }
        let anchorCommit = candidates[0]
        let descendantTouches = try gitLines(
            ["log", "--format=%H", "\(anchorCommit)..HEAD", "--", path], repository: repository
        )
        guard descendantTouches.isEmpty else { throw SP6AHistoryAnchorError.descendantTouch }
        let anchorTree = try gitText(["rev-parse", "\(anchorCommit)^{tree}"], repository: repository)
        let sourceCommit = try gitText(["rev-parse", "\(anchorCommit)^1^{commit}"], repository: repository)
        let blob = try gitText(["rev-parse", "\(anchorCommit):\(path)"], repository: repository)
        return SP6ANamespaceHistoryAnchor(
            sourceCommitSha: sourceCommit, anchorCommitSha: anchorCommit, anchorTreeSha: anchorTree,
            anchorPath: path, anchorBlobSha1: blob, anchorFileSha256: ViaDefinitionDigest.sha256(bytes)
        )
    }

    static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        return data
    }

    private static func gitText(_ arguments: [String], repository: URL) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SP6AKeychainError.attemptHistoryConflict }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func gitLines(_ arguments: [String], repository: URL) throws -> [String] {
        try gitText(arguments, repository: repository).split(separator: "\n").map(String.init)
    }

    private static func isFullSHA(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

enum SP6AHistoryAnchorError: String, Error, CustomStringConvertible {
    case descendantTouch = "sp6a_history_anchor_descendant_touch"
    case incompleteHistory = "sp6a_history_anchor_history_incomplete"
    case invalidCandidateSet = "sp6a_history_anchor_candidate_set_invalid"

    var description: String { rawValue }
}

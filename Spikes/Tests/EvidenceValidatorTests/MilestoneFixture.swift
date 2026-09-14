import CryptoKit
import Foundation
import XCTest

struct MilestoneCLIResult {
    let status: Int32
    let output: String
}

// Test-only trust root: a disposable copy pins synthetic bytes, never production identities.
// The production CLI has no option or environment variable for replacing those identities.
final class MilestoneFixture {
    let root: URL
    let repository: URL
    let input: URL
    let checker: URL
    let bundle: URL
    var document: [String: Any]
    var artifacts: [String: URL] = [:]

    init(malformedReceipt: Bool = false) throws {
        repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
        input = root.appendingPathComponent("allocation.json")
        checker = root.appendingPathComponent("fixture-checker.sh")
        bundle = root.appendingPathComponent("objects")
        let original = try Data(contentsOf: repository.appendingPathComponent("docs/milestone-allocation.json"))
        document = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        var script = try String(contentsOf: repository.appendingPathComponent("Spikes/Scripts/verify-current-milestone.sh"), encoding: .utf8)
        var evidence = try XCTUnwrap(document["evidence"] as? [String: [String: String]])
        for key in evidence.keys.sorted() {
            var item = try XCTUnwrap(evidence[key])
            let status = try XCTUnwrap(item["status"])
            let bytes: Data
            if status == "REFERENCE" {
                bytes = Data("synthetic reference: \(key)\n".utf8)
            } else {
                bytes = try JSONSerialization.data(withJSONObject: [
                    "outcome": status, "executed": 1, "failed": malformedReceipt ? 1 : 0,
                    "skipped": 0, "childExitStatus": 0, "runnerExitStatus": 0,
                    "code": "assertions_passed", "fixture": key
                ], options: [.sortedKeys])
            }
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            script = script.replacingOccurrences(of: try XCTUnwrap(item["sha256"]), with: hash)
            item["sha256"] = hash
            item["path"] = root.appendingPathComponent("absent/\(key)-\(status == "REFERENCE" ? "reference.txt" : "receipt.json")").path
            let artifact = bundle.appendingPathComponent(hash)
            try bytes.write(to: artifact)
            artifacts[key] = artifact
            evidence[key] = item
        }
        document["evidence"] = evidence
        try Data(script.utf8).write(to: checker)
    }

    func cleanUp() throws { try FileManager.default.removeItem(at: root) }

    func check(production: Bool = false) throws -> MilestoneCLIResult {
        try JSONSerialization.data(withJSONObject: document).write(to: input)
        return try Self.run(
            [production ? "Spikes/Scripts/verify-current-milestone.sh" : checker.path, input.path],
            repository: repository, evidenceRoot: bundle.path
        )
    }

    static func run(
        _ arguments: [String], repository: URL, evidenceRoot: String? = nil
    ) throws -> MilestoneCLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = repository
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "MILESTONE_EVIDENCE_ROOT")
        environment["MILESTONE_EVIDENCE_ROOT"] = evidenceRoot
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = MilestoneCLIResult(status: process.terminationStatus, output: String(decoding: output, as: UTF8.self))
        print("TEST INVOCATION (not acceptance): \(arguments) exit=\(result.status)\n\(result.output)")
        return result
    }
}

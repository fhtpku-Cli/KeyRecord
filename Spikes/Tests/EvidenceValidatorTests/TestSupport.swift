import Foundation
@testable import EvidenceValidator

struct TemporaryRepository {
    let root: URL
    let auditBase: String
    var evidence: URL { root.appendingPathComponent("evidence/phase0") }
    var plan: URL { root.appendingPathComponent(".omo/plans/phase-0-validation.md") }
    var environment: URL { evidence.appendingPathComponent("environment.json") }

    static func make() throws -> TemporaryRepository {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-binding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Spikes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("evidence/phase0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".omo/plans"), withIntermediateDirectories: true)
        try Data("fixture\n".utf8).write(to: root.appendingPathComponent("Spikes/input.txt"))
        try Data("plan\n".utf8).write(to: root.appendingPathComponent(".omo/plans/phase-0-validation.md"))
        try Data("{}\n".utf8).write(to: root.appendingPathComponent("evidence/phase0/environment.json"))
        try run(["init", "-q"], at: root)
        try run(["config", "user.email", "fixture@example.invalid"], at: root)
        try run(["config", "user.name", "Fixture Runner"], at: root)
        try run(["add", "Spikes", "evidence"], at: root)
        try run(["commit", "-q", "-m", "fixture"], at: root)
        let auditBase = try output(["rev-parse", "HEAD"], at: root)
        return TemporaryRepository(root: root, auditBase: auditBase)
    }

    func write(_ path: String, _ value: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private static func run(_ arguments: [String], at root: URL) throws { _ = try output(arguments, at: root) }
    private static func output(_ arguments: [String], at root: URL) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = arguments; process.currentDirectoryURL = root
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ReceiptFixture {
    enum Mutation {
        case forgedAggregate, missingSource, substitutedSource, symlinkSource, extraSource
        case duplicateReviewer, unknownReviewer, nonApprove, missingCommand, extraCommand
        case truncatedCommand, argvDrift, exitDrift, hashDrift, timeDrift
        case candidateField(field: String, omitted: Bool)
        case staleReceiptExpectation, staleCandidateExpectation, staleCommitExpectation
    }
    let root: URL
    var receipts: URL { root.appendingPathComponent("receipts") }
    var candidate: URL { root.appendingPathComponent("candidate.json") }
    var commands: URL { root.appendingPathComponent("commands.json") }
    var aggregate: URL { root.appendingPathComponent("aggregate.json") }
    let mutation: Mutation?

    static func make(mutation: Mutation? = nil) throws -> ReceiptFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-receipts-\(UUID().uuidString)")
        let fixture = ReceiptFixture(root: root, mutation: mutation)
        try FileManager.default.createDirectory(at: fixture.receipts, withIntermediateDirectories: true)
        let candidateText = "{\"auditBaseSha\":\"\(String(repeating: "1", count: 40))\",\"boundInputPathsSha256\":\"\(String(repeating: "2", count: 64))\",\"commitSha\":\"\(String(repeating: "3", count: 40))\",\"createdAt\":\"2026-09-04T00:00:00Z\",\"environmentSha256\":\"\(String(repeating: "4", count: 64))\",\"evidenceDigest\":\"\(String(repeating: "5", count: 64))\",\"planSha256\":\"\(String(repeating: "6", count: 64))\",\"treeSha\":\"\(String(repeating: "7", count: 40))\"}\n"
        try Data(candidateText.utf8).write(to: fixture.candidate)
        let candidateHash = Canonical.sha256(Data(candidateText.utf8))
        let reviewers = (1...4).map { n in
            "{\"commands\":[{\"argv\":[\"run\",\"F\(n)\"],\"expectedExitStatus\":0,\"id\":\"f\(n).run\"}],\"reviewerID\":\"F\(n)\"}"
        }.joined(separator: ",")
        try Data("{\"reviewers\":[\(reviewers)],\"schemaVersion\":1}\n".utf8).write(to: fixture.commands)
        for n in 1...4 {
            let reviewer = "F\(n)"
            try Data(receipt(reviewer: reviewer, candidateHash: candidateHash).utf8).write(to: fixture.receipts.appendingPathComponent("\(reviewer).json"))
        }
        try fixture.applyMutation(candidateHash: candidateHash)
        return fixture
    }

    func captureValidationCode() -> String? {
        do {
            let expectations: ReceiptExpectations
            switch mutation {
            case .staleReceiptExpectation: expectations = .init(receiptSetDigest: String(repeating: "9", count: 64), candidateSha256: nil, commitSha: nil)
            case .staleCandidateExpectation: expectations = .init(receiptSetDigest: nil, candidateSha256: String(repeating: "9", count: 64), commitSha: nil)
            case .staleCommitExpectation: expectations = .init(receiptSetDigest: nil, candidateSha256: nil, commitSha: String(repeating: "9", count: 40))
            default: expectations = .none
            }
            if case .forgedAggregate = mutation {
                var data = try ReceiptValidator.assemble(sourceDirectory: receipts, candidate: candidate, commands: commands, requiredReviewers: ["F1", "F2", "F3", "F4"])
                data.append(Data("forged".utf8)); try data.write(to: aggregate)
            } else if expectations != .none {
                try ReceiptValidator.assemble(sourceDirectory: receipts, candidate: candidate, commands: commands, requiredReviewers: ["F1", "F2", "F3", "F4"]).write(to: aggregate)
            } else {
                _ = try ReceiptValidator.assemble(sourceDirectory: receipts, candidate: candidate, commands: commands, requiredReviewers: ["F1", "F2", "F3", "F4"])
                return nil
            }
            try ReceiptValidator.verify(aggregate: aggregate, sourceDirectory: receipts, candidate: candidate, commands: commands, requiredReviewers: ["F1", "F2", "F3", "F4"], expectations: expectations)
            return nil
        } catch let error as ValidatorError { return error.code }
        catch { return "unexpected_error_type" }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private static func receipt(reviewer: String, candidateHash: String) -> String {
        "{\"auditBaseSha\":\"\(String(repeating: "1", count: 40))\",\"boundInputPathsSha256\":\"\(String(repeating: "2", count: 64))\",\"candidateSha256\":\"\(candidateHash)\",\"commandResults\":[\(commandResult(reviewer: reviewer))],\"commitSha\":\"\(String(repeating: "3", count: 40))\",\"createdAt\":\"2026-09-04T00:00:00Z\",\"environmentSha256\":\"\(String(repeating: "4", count: 64))\",\"evidenceDigest\":\"\(String(repeating: "5", count: 64))\",\"planSha256\":\"\(String(repeating: "6", count: 64))\",\"reviewerID\":\"\(reviewer)\",\"status\":\"APPROVE\",\"treeSha\":\"\(String(repeating: "7", count: 40))\"}\n"
    }

    private static func commandResult(reviewer: String, id: String? = nil) -> String {
        "{\"argv\":[\"run\",\"\(reviewer)\"],\"commandID\":\"\(id ?? reviewer.lowercased() + ".run")\",\"endedAt\":\"2026-09-04T00:00:01Z\",\"exitStatus\":0,\"startedAt\":\"2026-09-04T00:00:00Z\",\"stderrSha256\":\"\(String(repeating: "8", count: 64))\",\"stdoutSha256\":\"\(String(repeating: "9", count: 64))\"}"
    }

    private func applyMutation(candidateHash: String) throws {
        guard let mutation else { return }
        let f4 = receipts.appendingPathComponent("F4.json")
        switch mutation {
        case .forgedAggregate, .staleReceiptExpectation, .staleCandidateExpectation, .staleCommitExpectation: return
        case .missingSource: try FileManager.default.removeItem(at: f4)
        case .symlinkSource:
            try FileManager.default.removeItem(at: f4)
            try FileManager.default.createSymbolicLink(at: f4, withDestinationURL: receipts.appendingPathComponent("F3.json"))
        case .extraSource: try Data("{}\n".utf8).write(to: receipts.appendingPathComponent("extra.json"))
        case .truncatedCommand: try Data("{\"reviewerID\":\"F4\",\"commandResults\":[".utf8).write(to: f4)
        case .substitutedSource: try rewrite(f4, replacing: String(repeating: "6", count: 64), with: String(repeating: "a", count: 64))
        case .duplicateReviewer: try rewrite(f4, replacing: "\"reviewerID\":\"F4\"", with: "\"reviewerID\":\"F1\"")
        case .unknownReviewer: try rewrite(f4, replacing: "\"reviewerID\":\"F4\"", with: "\"reviewerID\":\"FX\"")
        case .nonApprove: try rewrite(f4, replacing: "\"status\":\"APPROVE\"", with: "\"status\":\"REJECT\"")
        case .missingCommand: try rewrite(f4, replacing: Self.commandResult(reviewer: "F4"), with: "")
        case .extraCommand: try rewrite(f4, replacing: Self.commandResult(reviewer: "F4"), with: Self.commandResult(reviewer: "F4") + "," + Self.commandResult(reviewer: "F4", id: "f4.extra"))
        case .argvDrift: try rewrite(f4, replacing: "[\"run\",\"F4\"]", with: "[\"run\",\"drift\"]")
        case .exitDrift: try rewrite(f4, replacing: "\"exitStatus\":0", with: "\"exitStatus\":1")
        case .hashDrift: try rewrite(f4, replacing: String(repeating: "8", count: 64), with: "bad")
        case .timeDrift: try rewrite(f4, replacing: "2026-09-04T00:00:01Z", with: "not-utc")
        case let .candidateField(field, omitted):
            guard let pair = candidatePairs(candidateHash: candidateHash).first(where: { $0.field == field }) else { throw CocoaError(.validationMissingMandatoryProperty) }
            let replacement = omitted ? "" : "\"\(field)\":\"\(pair.replacement)\""
            try rewrite(f4, replacing: "\"\(field)\":\"\(pair.value)\"", with: replacement)
        }
    }

    private func candidatePairs(candidateHash: String) -> [(field: String, value: String, replacement: String)] {
        [("auditBaseSha", String(repeating: "1", count: 40), String(repeating: "a", count: 40)),
         ("boundInputPathsSha256", String(repeating: "2", count: 64), String(repeating: "a", count: 64)),
         ("candidateSha256", candidateHash, String(repeating: "a", count: 64)),
         ("commitSha", String(repeating: "3", count: 40), String(repeating: "a", count: 40)),
         ("createdAt", "2026-09-04T00:00:00Z", "2026-09-05T00:00:00Z"),
         ("environmentSha256", String(repeating: "4", count: 64), String(repeating: "a", count: 64)),
         ("evidenceDigest", String(repeating: "5", count: 64), String(repeating: "a", count: 64)),
         ("planSha256", String(repeating: "6", count: 64), String(repeating: "a", count: 64)),
         ("treeSha", String(repeating: "7", count: 40), String(repeating: "a", count: 40))]
    }

    private func rewrite(_ url: URL, replacing original: String, with replacement: String) throws {
        let value = try String(contentsOf: url, encoding: .utf8)
        guard value.contains(original) else { throw CocoaError(.fileReadCorruptFile) }
        try Data(value.replacingOccurrences(of: original, with: replacement).utf8).write(to: url)
    }
}

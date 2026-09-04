import Foundation
import Phase0Support

@main
public enum EvidenceValidatorCommand {
    public static func main() {
        do {
            try execute(Array(CommandLine.arguments.dropFirst()))
        } catch let error as ValidatorError {
            writeError("ERROR \(error.code)\(error.detail.isEmpty ? "" : " \(error.detail)")\n")
            Foundation.exit(1)
        } catch {
            writeError("ERROR internal_error \(error)\n")
            Foundation.exit(1)
        }
    }

    static func execute(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw ValidatorError("usage", usage) }
        switch command {
        case "help", "--help": print(usage)
        case "validate":
            guard arguments.count == 2 else { throw ValidatorError("usage", usage) }
            try printReport(validateDirectory(url(arguments[1])))
        case "bind": try bind(Array(arguments.dropFirst()))
        case "verify-candidate": try verifyCandidate(Array(arguments.dropFirst()))
        case "assemble-receipts": try assemble(Array(arguments.dropFirst()))
        case "verify-receipts": try verifyReceipts(Array(arguments.dropFirst()))
        default:
            if arguments.count == 1 { try printReport(validateDirectory(url(command))) }
            else { throw ValidatorError("usage", usage) }
        }
    }

    private static func bind(_ arguments: [String]) throws {
        let options = try Options(arguments)
        let evidence = try options.required("--evidence")
        let plan = try options.required("--plan")
        let environment = options.value("--environment") ?? "\(evidence)/environment.json"
        let output = try options.required("--output")
        let createdAt = options.value("--created-at") ?? ISO8601DateFormatter().string(from: Date())
        try options.rejectUnused()
        let candidate = try CandidateBinder(repository: url(".")).bind(evidence: url(evidence), plan: url(plan), environment: url(environment), createdAt: createdAt)
        try writeJSON(candidate, to: url(output))
        print("VALID candidate_bound commit=\(candidate.commitSha)")
    }

    private static func verifyCandidate(_ arguments: [String]) throws {
        guard let candidatePath = arguments.first else { throw ValidatorError("usage", usage) }
        let options = try Options(Array(arguments.dropFirst()))
        let evidence = try options.required("--evidence")
        let plan = try options.required("--plan")
        let environment = options.value("--environment") ?? "\(evidence)/environment.json"
        try options.rejectUnused()
        let candidate: FinalCandidate = try decodeFile(url(candidatePath), code: "malformed_candidate")
        try CandidateBinder(repository: url(".")).verify(candidate, evidence: url(evidence), plan: url(plan), environment: url(environment))
        print("VALID candidate_verified commit=\(candidate.commitSha)")
    }

    private static func assemble(_ arguments: [String]) throws {
        guard let source = arguments.first else { throw ValidatorError("usage", usage) }
        let options = try Options(Array(arguments.dropFirst()))
        let output = try options.required("--output")
        let candidate = try options.required("--candidate")
        let commands = try options.required("--commands")
        let reviewers = try reviewerList(options.required("--required-reviewers"))
        try options.rejectUnused()
        let data = try ReceiptValidator.assemble(sourceDirectory: url(source), candidate: url(candidate), commands: url(commands), requiredReviewers: reviewers)
        try atomicWrite(data, to: url(output))
        let aggregate: ReceiptDigestView = try ValidatorDecoding.decode(ReceiptDigestView.self, from: data, malformedCode: "malformed_receipt_aggregate")
        print("VALID receipts_assembled digest=\(aggregate.receiptSetDigest)")
    }

    private static func verifyReceipts(_ arguments: [String]) throws {
        guard let aggregate = arguments.first else { throw ValidatorError("usage", usage) }
        let options = try Options(Array(arguments.dropFirst()))
        let source = try options.required("--source-dir")
        let candidate = try options.required("--candidate")
        let commands = try options.required("--commands")
        let reviewers = try reviewerList(options.required("--required-reviewers"))
        let expectations = ReceiptExpectations(
            receiptSetDigest: options.value("--expected-receipt-set-digest"),
            candidateSha256: options.value("--expected-candidate-sha256"),
            commitSha: options.value("--expected-commit-sha")
        )
        try options.rejectUnused()
        try ReceiptValidator.verify(aggregate: url(aggregate), sourceDirectory: url(source), candidate: url(candidate), commands: url(commands), requiredReviewers: reviewers, expectations: expectations)
        print("VALID receipts_verified")
    }

    private static func printReport(_ report: GateValidationReport) throws {
        print("VALID evidence legs=\(report.legCount) o4=\(report.o4RowCount) g0=\(report.g0Status.rawValue)")
    }

    private static func validateDirectory(_ directory: URL) throws -> GateValidationReport {
        let evidence = directory.appendingPathComponent("evidence.json")
        if let data = try? Data(contentsOf: evidence),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["runnerSourceSha256"] != nil {
            if object["spikeID"] as? String == "SP-2" { return try SP2DirectoryValidator.validate(directory: directory) }
            return try SP1DirectoryValidator.validate(directory: directory)
        }
        return try GateValidator.validate(directory: directory)
    }

    private static func decodeFile<T: Decodable>(_ path: URL, code: String) throws -> T {
        try ValidatorDecoding.decode(T.self, from: Data(contentsOf: path), malformedCode: code)
    }

    private static func writeJSON<T: Encodable>(_ value: T, to output: URL) throws {
        var data = try Canonical.encode(value); data.append(10); try atomicWrite(data, to: output)
    }

    private static func atomicWrite(_ data: Data, to output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(output.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            if FileManager.default.fileExists(atPath: output.path) {
                _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: output)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func reviewerList(_ value: String) throws -> [String] {
        let reviewers = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard reviewers.allSatisfy({ !$0.isEmpty }) else { throw ValidatorError("required_reviewer_set_mismatch") }
        return reviewers
    }

    private static func url(_ path: String) -> URL { URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL }
    private static func writeError(_ value: String) { FileHandle.standardError.write(Data(value.utf8)) }

    private static let usage = "EvidenceValidator <evidence-directory> | validate <directory> | bind --evidence PATH --plan PATH --output PATH [--environment PATH] | verify-candidate CANDIDATE --evidence PATH --plan PATH [--environment PATH] | assemble-receipts SOURCE --output PATH --candidate PATH --commands PATH --required-reviewers F1,F2,F3,F4 | verify-receipts AGGREGATE --source-dir PATH --candidate PATH --commands PATH --required-reviewers F1,F2,F3,F4 [expected flags]"
}

private final class Options {
    private var values: [String: String] = [:]
    init(_ arguments: [String]) throws {
        guard arguments.count.isMultiple(of: 2) else { throw ValidatorError("usage") }
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), values[key] == nil else { throw ValidatorError("usage", key) }
            values[key] = arguments[index + 1]
            index += 2
        }
    }
    func required(_ key: String) throws -> String { guard let value = values.removeValue(forKey: key) else { throw ValidatorError("usage", "missing \(key)") }; return value }
    func value(_ key: String) -> String? { values.removeValue(forKey: key) }
    func rejectUnused() throws { guard values.isEmpty else { throw ValidatorError("usage", values.keys.sorted().joined(separator: ",")) } }
}

private struct ReceiptDigestView: Decodable { let receiptSetDigest: String }

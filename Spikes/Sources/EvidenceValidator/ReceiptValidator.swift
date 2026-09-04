import Foundation
import Phase0Support

public struct ReceiptExpectations: Equatable, Sendable {
    public let receiptSetDigest: String?
    public let candidateSha256: String?
    public let commitSha: String?
    public static let none = ReceiptExpectations(receiptSetDigest: nil, candidateSha256: nil, commitSha: nil)
    public init(receiptSetDigest: String?, candidateSha256: String?, commitSha: String?) {
        self.receiptSetDigest = receiptSetDigest
        self.candidateSha256 = candidateSha256
        self.commitSha = commitSha
    }
}

public enum ReceiptValidator {
    public static func assemble(sourceDirectory: URL, candidate candidateURL: URL, commands commandsURL: URL, requiredReviewers: [String]) throws -> Data {
        try requireRegular(candidateURL, code: "malformed_candidate")
        try requireRegular(commandsURL, code: "malformed_command_registry")
        let candidateData = try Data(contentsOf: candidateURL)
        let candidate = try ValidatorDecoding.decode(FinalCandidate.self, from: candidateData, malformedCode: "malformed_candidate")
        guard parseUTC(candidate.createdAt) != nil else { throw ValidatorError("malformed_candidate") }
        let registry = try ValidatorDecoding.decode(FinalReviewCommandRegistry.self, from: Data(contentsOf: commandsURL), malformedCode: "malformed_command_registry")
        try validateRequiredReviewers(requiredReviewers)
        let receipts = try loadReceipts(sourceDirectory, requiredReviewers: requiredReviewers)
        try validate(receipts: receipts, candidate: candidate, candidateSha256: Canonical.sha256(candidateData), registry: registry, requiredReviewers: requiredReviewers)
        let canonicalReceipts = try receipts.sorted { $0.reviewerID < $1.reviewerID }.map { receipt in
            ("\(receipt.reviewerID).json", try Canonical.encode(receipt))
        }
        let digest = try Canonical.pathDigest(files: canonicalReceipts)
        var output = try Canonical.encode(ReceiptAggregate(receiptSetDigest: digest, receipts: receipts.sorted { $0.reviewerID < $1.reviewerID }))
        output.append(10)
        return output
    }

    public static func verify(aggregate: URL, sourceDirectory: URL, candidate: URL, commands: URL, requiredReviewers: [String], expectations: ReceiptExpectations) throws {
        try requireRegular(aggregate, code: "malformed_receipt_aggregate")
        let expected = try assemble(sourceDirectory: sourceDirectory, candidate: candidate, commands: commands, requiredReviewers: requiredReviewers)
        let actual = try Data(contentsOf: aggregate)
        guard actual == expected else { throw ValidatorError("receipt_aggregate_forged") }
        let decoded = try ValidatorDecoding.decode(ReceiptAggregate.self, from: actual, malformedCode: "malformed_receipt_aggregate")
        if let digest = expectations.receiptSetDigest, decoded.receiptSetDigest != digest { throw ValidatorError("expected_receipt_set_mismatch") }
        let candidateData = try Data(contentsOf: candidate)
        if let hash = expectations.candidateSha256, Canonical.sha256(candidateData) != hash { throw ValidatorError("expected_candidate_mismatch") }
        if let commit = expectations.commitSha {
            let decodedCandidate = try ValidatorDecoding.decode(FinalCandidate.self, from: candidateData, malformedCode: "malformed_candidate")
            guard decodedCandidate.commitSha == commit else { throw ValidatorError("expected_commit_mismatch") }
        }
    }

    private static func loadReceipts(_ directory: URL, requiredReviewers: [String]) throws -> [FinalReviewReceipt] {
        let directoryValues = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues?.isDirectory == true, directoryValues?.isSymbolicLink != true else {
            throw ValidatorError("receipt_source_not_regular")
        }
        let expectedNames = Set(requiredReviewers.map { "\($0).json" })
        let urls: [URL]
        do { urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) }
        catch { throw ValidatorError("receipt_source_set_mismatch") }
        guard Set(urls.map(\.lastPathComponent)) == expectedNames, urls.count == expectedNames.count else {
            throw ValidatorError("receipt_source_set_mismatch")
        }
        return try urls.map { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ValidatorError("receipt_source_not_regular", url.lastPathComponent) }
            return try ValidatorDecoding.decode(FinalReviewReceipt.self, from: Data(contentsOf: url), malformedCode: "malformed_receipt")
        }
    }

    private static func validate(receipts: [FinalReviewReceipt], candidate: FinalCandidate, candidateSha256: String, registry: FinalReviewCommandRegistry, requiredReviewers: [String]) throws {
        guard registry.schemaVersion == 1 else { throw ValidatorError("malformed_command_registry") }
        let reviewerGroups = Dictionary(grouping: receipts, by: \FinalReviewReceipt.reviewerID)
        if reviewerGroups.contains(where: { $0.value.count > 1 }) { throw ValidatorError("duplicate_reviewer") }
        let required = Set(requiredReviewers)
        if let unknown = reviewerGroups.keys.first(where: { !required.contains($0) }) { throw ValidatorError("unknown_reviewer", unknown) }
        guard Set(reviewerGroups.keys) == required else { throw ValidatorError("missing_reviewer") }
        let commandGroups = Dictionary(grouping: registry.reviewers, by: \ReviewerCommands.reviewerID)
        guard !commandGroups.contains(where: { $0.value.count > 1 }), Set(commandGroups.keys) == required else { throw ValidatorError("command_registry_mismatch") }
        for receipt in receipts {
            guard receipt.status == "APPROVE" else { throw ValidatorError("review_not_approved", receipt.reviewerID) }
            guard receipt.candidateSha256 == candidateSha256,
                  receipt.commitSha == candidate.commitSha, receipt.treeSha == candidate.treeSha,
                  receipt.auditBaseSha == candidate.auditBaseSha, receipt.planSha256 == candidate.planSha256,
                  receipt.environmentSha256 == candidate.environmentSha256,
                  receipt.evidenceDigest == candidate.evidenceDigest,
                  receipt.boundInputPathsSha256 == candidate.boundInputPathsSha256,
                  receipt.createdAt == candidate.createdAt else {
                throw ValidatorError("candidate_field_mismatch", receipt.reviewerID)
            }
            guard let expectedCommands = commandGroups[receipt.reviewerID]?.first?.commands else { throw ValidatorError("command_registry_mismatch") }
            try validateCommands(receipt.commandResults, expected: expectedCommands, reviewer: receipt.reviewerID)
        }
    }

    private static func validateCommands(_ actual: [CommandResult], expected: [RegisteredCommand], reviewer: String) throws {
        let actualGroups = Dictionary(grouping: actual, by: \CommandResult.commandID)
        guard !actualGroups.contains(where: { $0.value.count > 1 }) else { throw ValidatorError("command_results_mismatch", reviewer) }
        let expectedGroups = Dictionary(grouping: expected, by: \RegisteredCommand.id)
        guard !expectedGroups.contains(where: { $0.value.count > 1 }), Set(actualGroups.keys) == Set(expectedGroups.keys) else {
            throw ValidatorError("command_results_mismatch", reviewer)
        }
        for result in actual {
            guard let command = expectedGroups[result.commandID]?.first,
                  result.argv == command.argv, result.exitStatus == command.expectedExitStatus,
                  parseUTC(result.startedAt) != nil, parseUTC(result.endedAt) != nil,
                  let start = parseUTC(result.startedAt), let end = parseUTC(result.endedAt), start <= end else {
                throw ValidatorError("command_results_mismatch", result.commandID)
            }
        }
    }

    private static func validateRequiredReviewers(_ reviewers: [String]) throws {
        guard reviewers == ["F1", "F2", "F3", "F4"] else { throw ValidatorError("required_reviewer_set_mismatch") }
    }

    private static func parseUTC(_ value: String) -> Date? {
        guard value.hasSuffix("Z") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func requireRegular(_ url: URL, code: String) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { throw ValidatorError(code, url.path) }
    }
}

private struct ReceiptAggregate: Codable, Equatable {
    let receiptSetDigest: String
    let receipts: [FinalReviewReceipt]
}

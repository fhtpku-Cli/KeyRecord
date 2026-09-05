import Foundation
import Phase0Support

private struct SP6BNVDReview: Decodable {
    let schemaVersion: Int
    let auditRevision: String
    let dispositions: [NVDVulnerability]
}

enum SP6BNVDValidator {
    static let reviewPath = "Spikes/Scripts/sp6b-nvd-review.json"

    static func validate(
        snapshot: D12Snapshot, directory: URL, evidence: SP6BEvidence, repository: URL
    ) throws {
        guard let runner = evidence.legs.first?.runnerCommitSha else { throw ValidatorError("sp6b_nvd_review_set") }
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let reviewData = try git.run(["cat-file", "blob", "\(runner):\(reviewPath)"]).stdout
        guard let review = try? JSONDecoder().decode(SP6BNVDReview.self, from: reviewData),
              review.schemaVersion == 1, review.auditRevision == snapshot.nvd.auditRevision else {
            throw ValidatorError("sp6b_nvd_review_set")
        }
        let actual = snapshot.nvd.pages.flatMap(\.vulnerabilities)
        guard actual.map(\.cveID) == review.dispositions.map(\.cveID) else { throw ValidatorError("sp6b_nvd_review_set") }
        for (value, expected) in zip(actual, review.dispositions) {
            guard value.impact == expected.impact else { throw ValidatorError("sp6b_nvd_disposition_impact", value.cveID) }
            guard value.category == expected.category else { throw ValidatorError("sp6b_nvd_disposition_category", value.cveID) }
            guard value.rationale == expected.rationale else { throw ValidatorError("sp6b_nvd_disposition_rationale", value.cveID) }
            guard value.descriptionSha256 == expected.descriptionSha256,
                  value.configurationSha256 == expected.configurationSha256,
                  value.referencesSha256 == expected.referencesSha256 else {
                throw ValidatorError("sp6b_nvd_disposition_hash", value.cveID)
            }
        }
        try validateRaw(snapshot: snapshot, directory: directory, expected: review.dispositions)
    }

    private static func validateRaw(
        snapshot: D12Snapshot, directory: URL, expected: [NVDVulnerability]
    ) throws {
        var rawValues: [[String: Any]] = []
        for page in snapshot.nvd.pages {
            let url = directory.appendingPathComponent("d12/\(page.request.rawBodyPath)")
            guard let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  let values = object["vulnerabilities"] as? [[String: Any]] else { throw ValidatorError("sp6b_d12_nvd_body") }
            rawValues.append(contentsOf: values)
        }
        guard rawValues.count == expected.count else { throw ValidatorError("sp6b_nvd_review_set") }
        for (container, disposition) in zip(rawValues, expected) {
            guard let cve = container["cve"] as? [String: Any], cve["id"] as? String == disposition.cveID,
                  let descriptions = cve["descriptions"] as? [[String: Any]],
                  let description = descriptions.first(where: { $0["lang"] as? String == "en" })?["value"] as? String else {
                throw ValidatorError("sp6b_nvd_description", disposition.cveID)
            }
            guard Canonical.sha256(Data(description.utf8)) == disposition.descriptionSha256 else {
                throw ValidatorError("sp6b_nvd_description", disposition.cveID)
            }
            let configurations = cve["configurations"] ?? [Any]()
            let references = cve["references"] ?? [Any]()
            guard canonicalHash(configurations) == disposition.configurationSha256 else {
                throw ValidatorError("sp6b_nvd_configuration", disposition.cveID)
            }
            guard canonicalHash(references) == disposition.referencesSha256 else {
                throw ValidatorError("sp6b_nvd_references", disposition.cveID)
            }
        }
    }

    private static func canonicalHash(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return Canonical.sha256(data)
    }
}

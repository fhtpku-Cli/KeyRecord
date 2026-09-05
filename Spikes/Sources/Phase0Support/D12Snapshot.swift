import Foundation

public enum NVDImpact: String, Codable, Sendable { case phc, swift, both, none }

public struct D12HTTPPage: Codable, Equatable, Sendable {
    public let url: String
    public let requestBody: String?
    public let status: Int
    public let retrievedAt: String
    public let headersSha256: String
    public let rawBodySha256: String
    public let headersPath: String
    public let rawBodyPath: String
    public let next: String?
}

public struct D12OSVPage: Codable, Equatable, Sendable {
    public let request: D12HTTPPage
    public let responseNextPageToken: String?
}

public struct D12CandidateSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let ownerRepo: String
    public let commit: String
    public let github: [D12HTTPPage]
    public let osv: [D12OSVPage]
}

public struct NVDVulnerability: Codable, Equatable, Sendable {
    public let cveID: String
    public let impact: NVDImpact
    public let category: String
    public let rationale: String
    public let descriptionSha256: String
    public let configurationSha256: String
    public let referencesSha256: String
}

public struct D12NVDPage: Codable, Equatable, Sendable {
    public let request: D12HTTPPage
    public let startIndex: Int
    public let resultsPerPage: Int
    public let totalResults: Int
    public let vulnerabilities: [NVDVulnerability]
}

public struct D12NVD: Codable, Equatable, Sendable { public let auditRevision: String; public let pages: [D12NVDPage] }

public enum D12ValidationError: String, Error {
    case candidateSet, duplicate, freshness, githubIdentity, http, nvdPagination, osvIdentity, osvPagination, rawHash
}

public struct D12Snapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let candidates: [D12CandidateSnapshot]
    public let nvd: D12NVD

    public func validate(generatedAt: String) throws {
        guard self.generatedAt == generatedAt, schemaVersion == 2, Set(candidates.map(\.id)) == ["phc", "swift"], candidates.count == 2 else { throw D12ValidationError.candidateSet }
        guard let auditDate = ISO8601DateFormatter().date(from: generatedAt) else { throw D12ValidationError.freshness }
        for candidate in candidates {
            try validateGitHub(candidate, auditDate: auditDate)
            try validateOSV(candidate, auditDate: auditDate)
        }
        try validateNVD(auditDate: auditDate)
    }

    private func validateGitHub(_ candidate: D12CandidateSnapshot, auditDate: Date) throws {
        let base = "https://api.github.com/repos/\(candidate.ownerRepo)/security-advisories?per_page=100"
        guard !candidate.github.isEmpty, candidate.github[0].url == base else { throw D12ValidationError.githubIdentity }
        for index in candidate.github.indices {
            let page = candidate.github[index]
            try validate(page, auditDate: auditDate)
            let expectedNext = index + 1 < candidate.github.count ? candidate.github[index + 1].url : nil
            guard page.requestBody == nil, page.next == expectedNext else { throw D12ValidationError.githubIdentity }
        }
    }

    private func validateOSV(_ candidate: D12CandidateSnapshot, auditDate: Date) throws {
        guard !candidate.osv.isEmpty else { throw D12ValidationError.osvPagination }
        var priorToken: String?
        var tokens = Set<String>()
        for page in candidate.osv {
            try validate(page.request, auditDate: auditDate)
            guard page.request.url == "https://api.osv.dev/v1/query" else { throw D12ValidationError.osvIdentity }
            let expected = priorToken.map { #"{"commit":"\#(candidate.commit)","page_token":"\#($0)"}"# }
                ?? #"{"commit":"\#(candidate.commit)"}"#
            guard page.request.requestBody == expected else { throw D12ValidationError.osvIdentity }
            if let token = page.responseNextPageToken {
                guard !token.isEmpty, tokens.insert(token).inserted else { throw D12ValidationError.osvPagination }
            }
            priorToken = page.responseNextPageToken
        }
        guard priorToken == nil else { throw D12ValidationError.osvPagination }
    }

    private func validateNVD(auditDate: Date) throws {
        guard !nvd.pages.isEmpty else { throw D12ValidationError.nvdPagination }
        var expectedStart = 0
        var total: Int?
        var cves = Set<String>()
        for page in nvd.pages {
            try validate(page.request, auditDate: auditDate)
            let expectedURL = page.startIndex == 0
                ? "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=argon2&resultsPerPage=2000"
                : "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=argon2&resultsPerPage=2000&startIndex=\(page.startIndex)"
            guard page.request.url == expectedURL,
                  page.request.requestBody == nil, page.startIndex == expectedStart,
                  page.resultsPerPage > 0, page.resultsPerPage <= 2_000,
                  total == nil || total == page.totalResults else { throw D12ValidationError.nvdPagination }
            total = page.totalResults
            expectedStart += page.resultsPerPage
            for vulnerability in page.vulnerabilities {
                guard !vulnerability.category.isEmpty, !vulnerability.rationale.isEmpty,
                      vulnerability.descriptionSha256.isLowercaseSHA256,
                      vulnerability.configurationSha256.isLowercaseSHA256,
                      vulnerability.referencesSha256.isLowercaseSHA256,
                      cves.insert(vulnerability.cveID).inserted else { throw D12ValidationError.duplicate }
            }
        }
        guard cves.count == total else { throw D12ValidationError.nvdPagination }
    }

    private func validate(_ page: D12HTTPPage, auditDate: Date) throws {
        guard page.status == 200 else { throw D12ValidationError.http }
        guard page.headersSha256.isLowercaseSHA256, page.rawBodySha256.isLowercaseSHA256,
              page.headersPath.hasPrefix("raw/"), page.rawBodyPath.hasPrefix("raw/"),
              !page.headersPath.contains(".."), !page.rawBodyPath.contains("..") else { throw D12ValidationError.rawHash }
        guard let retrieved = ISO8601DateFormatter().date(from: page.retrievedAt), retrieved <= auditDate,
              auditDate.timeIntervalSince(retrieved) <= 86_400 else { throw D12ValidationError.freshness }
    }
}

import Foundation

extension D12Snapshot {
    public static let fixture = D12Snapshot(schemaVersion: 1, generatedAt: "2026-09-05T00:00:00Z", candidates: [
        candidate(id: "phc", repo: "P-H-C/phc-winner-argon2", commit: "f57e61e19229e23c4445b85494dbf7c07de721cb"),
        candidate(id: "swift", repo: "MarlonJD/argon2id-swift-native", commit: "14d47de1914ac63b368ddb2cfe0f47ffe25f04cf"),
    ], nvd: D12NVD(pages: [D12NVDPage(
        request: page(url: "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=argon2&resultsPerPage=2000"),
        startIndex: 0, resultsPerPage: 10, totalResults: 2,
        vulnerabilities: [
            NVDVulnerability(cveID: "CVE-2024-0001", impact: .phc, rationale: "PHC implementation named"),
            NVDVulnerability(cveID: "CVE-2024-0002", impact: .none, rationale: "unrelated product keyword match"),
        ]
    )]))

    private static func candidate(id: String, repo: String, commit: String) -> D12CandidateSnapshot {
        D12CandidateSnapshot(
            id: id, ownerRepo: repo, commit: commit,
            github: [page(url: "https://api.github.com/repos/\(repo)/security-advisories?per_page=100")],
            osv: [D12OSVPage(request: page(url: "https://api.osv.dev/v1/query", body: #"{"commit":"\#(commit)"}"#), responseNextPageToken: nil)]
        )
    }

    private static func page(url: String, body: String? = nil) -> D12HTTPPage {
        D12HTTPPage(url: url, requestBody: body, status: 200, retrievedAt: "2026-09-04T12:00:00Z",
                    headersSha256: String(repeating: "a", count: 64), rawBodySha256: String(repeating: "b", count: 64),
                    headersPath: "raw/headers", rawBodyPath: "raw/body", next: nil)
    }

    public func replacing(githubStatus: Int) -> Self { mapFirstCandidate { candidate in
        candidate.with(github: candidate.github.enumerated().map { $0.offset == 0 ? $0.element.with(status: githubStatus) : $0.element })
    } }
    public func replacing(githubURL: String) -> Self { mapFirstCandidate { candidate in
        candidate.with(github: candidate.github.enumerated().map { $0.offset == 0 ? $0.element.with(url: githubURL) : $0.element })
    } }
    public func replacing(osvCommit: String) -> Self { mapFirstCandidate { candidate in
        candidate.with(osv: [D12OSVPage(request: Self.page(url: "https://api.osv.dev/v1/query", body: #"{"commit":"\#(osvCommit)"}"#), responseNextPageToken: nil)])
    } }
    public func replacing(osvContinuationToken: String) -> Self { mapFirstCandidate { candidate in
        candidate.with(osv: [D12OSVPage(request: candidate.osv[0].request, responseNextPageToken: osvContinuationToken)])
    } }
    public func replacing(nvdStartIndex: Int) -> Self { mapNVD { $0.with(startIndex: nvdStartIndex) } }
    public func replacing(nvdTotalResults: Int) -> Self { mapNVD { $0.with(totalResults: nvdTotalResults) } }
    public func replacing(nvdDuplicateCVE: Bool) -> Self {
        guard nvdDuplicateCVE else { return self }
        return mapNVD { page in page.with(vulnerabilities: [page.vulnerabilities[0], page.vulnerabilities[0]]) }
    }
    public func replacing(retrievedAt: String) -> Self { mapFirstCandidate { candidate in
        candidate.with(github: candidate.github.map { $0.with(retrievedAt: retrievedAt) })
    } }

    private func mapFirstCandidate(_ transform: (D12CandidateSnapshot) -> D12CandidateSnapshot) -> Self {
        Self(schemaVersion: schemaVersion, generatedAt: generatedAt, candidates: candidates.enumerated().map { $0.offset == 0 ? transform($0.element) : $0.element }, nvd: nvd)
    }
    private func mapNVD(_ transform: (D12NVDPage) -> D12NVDPage) -> Self {
        Self(schemaVersion: schemaVersion, generatedAt: generatedAt, candidates: candidates, nvd: D12NVD(pages: nvd.pages.map(transform)))
    }
}

private extension D12HTTPPage {
    func with(url: String? = nil, status: Int? = nil, retrievedAt: String? = nil) -> Self {
        Self(url: url ?? self.url, requestBody: requestBody, status: status ?? self.status,
             retrievedAt: retrievedAt ?? self.retrievedAt, headersSha256: headersSha256,
             rawBodySha256: rawBodySha256, headersPath: headersPath, rawBodyPath: rawBodyPath, next: next)
    }
}
private extension D12CandidateSnapshot {
    func with(github: [D12HTTPPage]? = nil, osv: [D12OSVPage]? = nil) -> Self {
        Self(id: id, ownerRepo: ownerRepo, commit: commit, github: github ?? self.github, osv: osv ?? self.osv)
    }
}
private extension D12NVDPage {
    func with(startIndex: Int? = nil, totalResults: Int? = nil, vulnerabilities: [NVDVulnerability]? = nil) -> Self {
        let start = startIndex ?? self.startIndex
        let url = start == 0 ? "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=argon2&resultsPerPage=2000" : "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=argon2&resultsPerPage=2000&startIndex=\(start)"
        return Self(request: D12HTTPPage(url: url, requestBody: nil, status: request.status,
                                        retrievedAt: request.retrievedAt, headersSha256: request.headersSha256,
                                        rawBodySha256: request.rawBodySha256, headersPath: request.headersPath,
                                        rawBodyPath: request.rawBodyPath, next: request.next),
                    startIndex: start, resultsPerPage: resultsPerPage, totalResults: totalResults ?? self.totalResults,
                    vulnerabilities: vulnerabilities ?? self.vulnerabilities)
    }
}

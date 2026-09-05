import Foundation

public enum Argon2Pedigree: String, Codable, Sendable { case phcReference, independent }

public struct Argon2Score: Codable, Equatable, Sendable {
    public let pedigree: Int
    public let dependencies: Int
    public let maintenance: Int
    public let dualArchBuild: Int
    public let sourceSize: Int
    public var total: Int { pedigree + dependencies + maintenance + dualArchBuild + sourceSize }
}

public struct Argon2Candidate: Codable, Equatable, Sendable {
    public let id: String
    public let canonicalURL: String
    public let commit: String
    public let tree: String
    public let latestCommitDate: String
    public let pedigree: Argon2Pedigree
    public let runtimeDependencyCount: Int
    public let sourceLOC: Int
    public let licenseApproved: Bool
    public let vectorsPassed: Bool
    public let dualArchMacOS14Build: Bool
    public let minimumMacOSMajor: Int
    public let unresolvedSignificantFindings: Int

    public var isEligible: Bool {
        commit.isLowercaseGitSHA1 && tree.isLowercaseGitSHA1 && runtimeDependencyCount >= 0 && sourceLOC >= 0
            && licenseApproved && vectorsPassed && dualArchMacOS14Build && minimumMacOSMajor <= 14
            && unresolvedSignificantFindings == 0
    }

    public func score(at generatedAt: Date) throws -> Argon2Score {
        guard let commitDate = ISO8601DateFormatter().date(from: latestCommitDate), commitDate <= generatedAt else {
            throw Argon2AuditError.invalidCommitDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month24 = calendar.date(byAdding: .month, value: 24, to: commitDate)!
        let month60 = calendar.date(byAdding: .month, value: 60, to: commitDate)!
        let maintenance = generatedAt <= month24 ? 2 : (generatedAt <= month60 ? 1 : 0)
        return Argon2Score(
            pedigree: pedigree == .phcReference ? 3 : 1,
            dependencies: runtimeDependencyCount == 0 ? 2 : 0,
            maintenance: maintenance,
            dualArchBuild: dualArchMacOS14Build ? 2 : 0,
            sourceSize: sourceLOC <= 10_000 ? 1 : 0
        )
    }

    public static let fixture = Argon2Candidate(
        id: "phc", canonicalURL: "https://github.com/P-H-C/phc-winner-argon2.git",
        commit: "f57e61e19229e23c4445b85494dbf7c07de721cb", tree: "ac3dc753ff75ce5a0f243cba1d94582bafe09409",
        latestCommitDate: "2021-06-25T08:21:15Z", pedigree: .phcReference, runtimeDependencyCount: 0,
        sourceLOC: 6_842, licenseApproved: true, vectorsPassed: true, dualArchMacOS14Build: true,
        minimumMacOSMajor: 10, unresolvedSignificantFindings: 0
    )

    public func replacing(commit: String) -> Self { copy(commit: commit) }
    public func replacing(minimumMacOSMajor: Int) -> Self { copy(minimumMacOSMajor: minimumMacOSMajor) }
    public func replacing(vectorsPassed: Bool) -> Self { copy(vectorsPassed: vectorsPassed) }
    public func replacing(licenseApproved: Bool) -> Self { copy(licenseApproved: licenseApproved) }
    public func replacing(dualArchMacOS14Build: Bool) -> Self { copy(dualArchMacOS14Build: dualArchMacOS14Build) }
    public func replacing(unresolvedSignificantFindings: Int) -> Self { copy(unresolvedSignificantFindings: unresolvedSignificantFindings) }

    private func copy(
        commit: String? = nil, minimumMacOSMajor: Int? = nil, vectorsPassed: Bool? = nil,
        licenseApproved: Bool? = nil, dualArchMacOS14Build: Bool? = nil,
        unresolvedSignificantFindings: Int? = nil
    ) -> Self {
        Self(
            id: id, canonicalURL: canonicalURL, commit: commit ?? self.commit, tree: tree,
            latestCommitDate: latestCommitDate, pedigree: pedigree, runtimeDependencyCount: runtimeDependencyCount,
            sourceLOC: sourceLOC, licenseApproved: licenseApproved ?? self.licenseApproved,
            vectorsPassed: vectorsPassed ?? self.vectorsPassed,
            dualArchMacOS14Build: dualArchMacOS14Build ?? self.dualArchMacOS14Build,
            minimumMacOSMajor: minimumMacOSMajor ?? self.minimumMacOSMajor,
            unresolvedSignificantFindings: unresolvedSignificantFindings ?? self.unresolvedSignificantFindings
        )
    }
}

public enum Argon2AuditError: String, Error { case invalidCommitDate, noEligibleCandidate }

public enum Argon2Ranking {
    public static func recommend(_ candidates: [Argon2Candidate], at generatedAt: Date) throws -> Argon2Candidate {
        let scored = try candidates.filter(\.isEligible).map { ($0, try $0.score(at: generatedAt)) }
        guard let winner = scored.sorted(by: rankedBefore).first else { throw Argon2AuditError.noEligibleCandidate }
        return winner.0
    }

    private static func rankedBefore(_ lhs: (Argon2Candidate, Argon2Score), _ rhs: (Argon2Candidate, Argon2Score)) -> Bool {
        if lhs.1.total != rhs.1.total { return lhs.1.total > rhs.1.total }
        if lhs.1.pedigree != rhs.1.pedigree { return lhs.1.pedigree > rhs.1.pedigree }
        if lhs.0.runtimeDependencyCount != rhs.0.runtimeDependencyCount { return lhs.0.runtimeDependencyCount < rhs.0.runtimeDependencyCount }
        return lhs.0.canonicalURL.utf8.lexicographicallyPrecedes(rhs.0.canonicalURL.utf8)
    }
}

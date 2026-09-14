import Foundation
import XCTest
@testable import EvidenceValidator

final class Phase25FreezeTests: XCTestCase {
    private let planPath = ".omo/plans/repository-status-next-step.md"
    private let registryPath = "Scripts/phase1-qa-cases.json"
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testHappyExplicitPlanAndAllTrackedBytesVerifyTwice() throws {
        // Given: a clean isolated repository with this registry and explicit plan bytes.
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let cli = try runner(fixture.root)
        let planBytes = try Data(contentsOf: fixture.url(planPath))
        // When: bind-current freezes the inputs and the real CLI verifies twice.
        let bound = try cli.run(["bind-current", "--plan", fixture.url(planPath).path,
            "--readiness", fixture.readiness.path, "--output", fixture.candidate.path])
        let first = try cli.run(["verify-current-candidate", fixture.candidate.path,
            "--readiness", fixture.readiness.path])
        let second = try cli.run(["verify-current-candidate", fixture.candidate.path,
            "--readiness", fixture.readiness.path])
        // Then: identical successful output and exact digests, including non-source tracked files.
        XCTAssertEqual(bound.status, 0)
        XCTAssertEqual(first.status, 0)
        XCTAssertEqual(second.status, 0)
        XCTAssertEqual(first.stdout, second.stdout)
        let candidate = try ReadinessDecoding.decode(CurrentCandidate.self, from: Data(contentsOf: fixture.candidate))
        XCTAssertEqual(candidate.plan.path, planPath)
        XCTAssertEqual(candidate.plan.sha256, Canonical.sha256(planBytes))
        XCTAssertEqual(candidate.qaRegistry.sha256, Canonical.sha256(try Data(contentsOf: fixture.url(registryPath))))
        let tracked = try fixture.git.nulPaths(["ls-files", "-z"])
        XCTAssertEqual(candidate.trackedFilesDigest, try Canonical.pathDigest(files: tracked.map {
            ($0, try Data(contentsOf: fixture.url($0)))
        }))
    }

    func testFailureCandidateByteMutation() throws { try rejectMutation(.candidate) }
    func testFailureReadinessByteMutation() throws { try rejectMutation(.readiness) }
    func testFailureRegistryByteMutation() throws { try rejectMutation(.registry) }
    func testFailureExplicitPlanByteMutation() throws { try rejectMutation(.plan) }
    func testFailureHiddenTrackedSourceByteMutation() throws { try rejectMutation(.source) }

    func testFailurePhaseZeroBinderRejectsCurrentPlanPath() throws {
        // Given: otherwise canonical phase-zero inputs, but this milestone's explicit plan.
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let binder = CandidateBinder(repository: fixture.root)
        // When / Then: the old binder rejects the plan path before consulting old evidence.
        XCTAssertThrowsError(try binder.bind(evidence: fixture.url("evidence/phase0"),
            plan: fixture.url(planPath), environment: fixture.url("evidence/phase0/environment.json"),
            createdAt: "2026-09-14T00:00:00Z")) { error in
            XCTAssertEqual((error as? ValidatorError)?.code, "noncanonical_binding_path")
        }
    }

    private enum Mutation { case candidate, readiness, registry, plan, source }

    private func rejectMutation(_ mutation: Mutation) throws {
        // Given: a successfully verified candidate; only one byte changes in an isolated copy.
        let fixture = try makeFixture()
        defer { fixture.remove() }
        _ = try fixture.binder.bind(plan: fixture.url(planPath), readiness: fixture.readiness, output: fixture.candidate)
        try fixture.verify()
        let path: String
        switch mutation {
        case .candidate: path = ".omo/candidate.json"
        case .readiness: path = ".omo/readiness.json"
        case .registry: path = registryPath
        case .plan: path = planPath
        case .source:
            path = "Sources/Product.swift"
            _ = try fixture.git.run(["update-index", "--assume-unchanged", path])
        }
        var bytes = try Data(contentsOf: fixture.url(path))
        if mutation == .candidate {
            let candidate = try ReadinessDecoding.decode(CurrentCandidate.self, from: bytes)
            let range = try XCTUnwrap(bytes.range(of: Data(candidate.trackedFilesDigest.utf8)))
            bytes[range.lowerBound] = bytes[range.lowerBound] == 48 ? 49 : 48
        } else {
            bytes.append(32)
        }
        try bytes.write(to: fixture.url(path))
        // When: the actual verifier consumes the changed input.
        let result = try runner(fixture.root).run(["verify-current-candidate", fixture.candidate.path,
            "--readiness", fixture.readiness.path], acceptedStatuses: [1])
        // Then: a hard failure, never a PASS or missing-host BLOCKED.
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.stdout.isEmpty)
    }

    private func makeFixture() throws -> CurrentCandidateFixture {
        let fixture = try CurrentCandidateFixture()
        do {
            // Actual task runs bind the operator's untracked plan; clean CI still exercises the path contract.
            let plan = repository.appendingPathComponent(planPath)
            let planBytes = FileManager.default.fileExists(atPath: plan.path)
                ? try Data(contentsOf: plan) : Data("# repository-status-next-step\n".utf8)
            try planBytes.write(to: fixture.url(planPath))
            try Data(contentsOf: repository.appendingPathComponent(registryPath)).write(to: fixture.url(registryPath))
            try fixture.seal()
            try fixture.refreshReadiness()
            return fixture
        } catch {
            fixture.remove()
            throw error
        }
    }

    private func runner(_ root: URL) throws -> GitRunner {
        var directory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let executable = directory.appendingPathComponent("EvidenceValidator")
            if FileManager.default.isExecutableFile(atPath: executable.path) {
                return GitRunner(repository: root, timeout: 60, executable: executable)
            }
            directory.deleteLastPathComponent()
        }
        throw CurrentCandidateError(.missingInput, "built EvidenceValidator executable")
    }
}

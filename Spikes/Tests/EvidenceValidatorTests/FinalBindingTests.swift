import Foundation
import XCTest
@testable import EvidenceValidator

final class FinalBindingTests: XCTestCase {
    func testBindRejectsOrdinaryUntrackedBoundInput() throws {
        try assertUntrackedError(ignored: false, operation: .bind, expected: "untracked_bound_input")
    }

    func testVerifyRejectsOrdinaryUntrackedBoundInput() throws {
        try assertUntrackedError(ignored: false, operation: .verify, expected: "untracked_bound_input")
    }

    func testBindRejectsIgnoredUntrackedBoundInput() throws {
        try assertUntrackedError(ignored: true, operation: .bind, expected: "ignored_bound_input")
    }

    func testBindRejectsIgnoredSwiftPMBuildArtifacts() throws {
        try assertIgnoredSwiftPMBuildError(operation: .bind)
    }

    func testVerifyRejectsIgnoredSwiftPMBuildArtifacts() throws {
        try assertIgnoredSwiftPMBuildError(operation: .verify)
    }

    func testVerifyRejectsIgnoredUntrackedBoundInput() throws {
        try assertUntrackedError(ignored: true, operation: .verify, expected: "ignored_bound_input")
    }

    func testAuditBaseAndCandidateFieldDriftReject() throws {
        let repository = try TemporaryRepository.make()
        defer { repository.remove() }
        let binder = CandidateBinder(repository: repository.root, auditBaseSha: repository.auditBase)
        let candidate = try binder.bind(
            evidence: repository.evidence,
            plan: repository.plan,
            environment: repository.environment,
            createdAt: "2026-09-04T00:00:00Z"
        )
        XCTAssertNoThrow(try binder.verify(candidate, evidence: repository.evidence, plan: repository.plan, environment: repository.environment))
        XCTAssertEqual(capture { try CandidateBinder(repository: repository.root, auditBaseSha: String(repeating: "f", count: 40)).verify(candidate, evidence: repository.evidence, plan: repository.plan, environment: repository.environment) }, "audit_base_drift")
        XCTAssertEqual(capture { try binder.verify(candidate.replacing(treeSha: String(repeating: "a", count: 40)), evidence: repository.evidence, plan: repository.plan, environment: repository.environment) }, "candidate_field_drift")
    }

    func testDirtyTrackedBytesReject() throws {
        let repository = try TemporaryRepository.make()
        defer { repository.remove() }
        try repository.write("Spikes/input.txt", "changed")
        let binder = CandidateBinder(repository: repository.root, auditBaseSha: repository.auditBase)
        XCTAssertEqual(capture { _ = try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z") }, "dirty_tracked_state")
    }

    func testHungGitChildIsTerminatedWithinBound() throws {
        let repository = try TemporaryRepository.make()
        defer { repository.remove() }
        let executable = repository.root.appendingPathComponent("slow-git.sh")
        try Data("#!/bin/sh\nwhile :; do :; done\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let binder = CandidateBinder(repository: repository.root, auditBaseSha: repository.auditBase, timeout: 0.05, gitExecutable: executable)
        let started = Date()
        XCTAssertEqual(capture { _ = try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z") }, "git_command_timeout")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testSymlinkAndOutsideRepositoryInputsReject() throws {
        let repository = try TemporaryRepository.make()
        defer { repository.remove() }
        let target = repository.root.appendingPathComponent("environment-target.json")
        try Data("{}\n".utf8).write(to: target)
        try FileManager.default.removeItem(at: repository.environment)
        try FileManager.default.createSymbolicLink(at: repository.environment, withDestinationURL: target)
        let binder = CandidateBinder(repository: repository.root, auditBaseSha: repository.auditBase)
        XCTAssertEqual(capture { _ = try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z") }, "symlink_bound_input")
        XCTAssertEqual(capture { _ = try binder.bind(evidence: FileManager.default.temporaryDirectory, plan: repository.plan, environment: target, createdAt: "2026-09-04T00:00:00Z") }, "path_outside_repository")
    }

    func testOnlyApprovedUntrackedPathsAreAllowed() throws {
        let repository = try TemporaryRepository.make()
        defer { repository.remove() }
        try repository.write(".omo/evidence/local.txt", "allowed")
        try repository.write(".DS_Store", "allowed")
        let binder = CandidateBinder(repository: repository.root, auditBaseSha: repository.auditBase)
        XCTAssertNoThrow(try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z"))
    }

    func testCanonicalPathDigestRejectsNFCollision() {
        let composed = "caf\u{00E9}.json"
        let decomposed = "cafe\u{0301}.json"
        XCTAssertEqual(capture { _ = try Canonical.pathDigest(files: [(composed, Data()), (decomposed, Data())]) }, "normalization_collision")
    }

    private enum Operation { case bind, verify }

    private func assertIgnoredSwiftPMBuildError(operation: Operation) throws {
        let repository = try TemporaryRepository.make()
        defer { repository.remove() }
        let binder = CandidateBinder(repository: repository.root, auditBaseSha: repository.auditBase)
        let candidate = try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z")
        try repository.write("Spikes/.build/.lock", "")
        try repository.write(".git/info/exclude", "Spikes/.build/\n")
        let code = capture {
            switch operation {
            case .bind:
                _ = try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z")
            case .verify:
                try binder.verify(candidate, evidence: repository.evidence, plan: repository.plan, environment: repository.environment)
            }
        }
        XCTAssertEqual(code, "ignored_bound_input")
    }

    private func assertUntrackedError(ignored: Bool, operation: Operation, expected: String) throws {
        let repository = try TemporaryRepository.make()
        defer { repository.remove() }
        let binder = CandidateBinder(repository: repository.root, auditBaseSha: repository.auditBase)
        let candidate = try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z")
        if ignored {
            try repository.write("Spikes/ignored.tmp", "ignored")
            try repository.write(".gitignore", "Spikes/ignored.tmp\n")
        } else {
            try repository.write("Spikes/untracked.tmp", "ordinary")
        }
        let code = capture {
            switch operation {
            case .bind:
                _ = try binder.bind(evidence: repository.evidence, plan: repository.plan, environment: repository.environment, createdAt: "2026-09-04T00:00:00Z")
            case .verify:
                try binder.verify(candidate, evidence: repository.evidence, plan: repository.plan, environment: repository.environment)
            }
        }
        XCTAssertEqual(code, expected)
    }

    private func capture(_ body: () throws -> Void) -> String? {
        do { try body(); return nil }
        catch let error as ValidatorError { return error.code }
        catch { return "unexpected_error_type" }
    }
}

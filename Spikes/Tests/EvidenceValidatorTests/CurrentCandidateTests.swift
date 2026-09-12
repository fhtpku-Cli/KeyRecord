import Foundation
import XCTest
@testable import EvidenceValidator

final class CurrentCandidateTests: XCTestCase {
    func testHappyCleanRoundTripIsIdempotent() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        // Given a clean committed repository and an explicitly untracked plan.
        let candidate = try f.bind()
        // When the same candidate is verified twice, then both reads succeed.
        try f.verify(); try f.verify()
        XCTAssertEqual(candidate.schemaVersion, 1)
        let paths = try f.git.nulPaths(["ls-files", "-z"])
        XCTAssertEqual(candidate.trackedFilesDigest, try Canonical.pathDigest(files: paths.map {
            ($0, try Data(contentsOf: f.url($0)))
        }))
    }

    func testHappyAttemptBuildOutputsAreExcluded() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        let before = try f.bind()
        try f.write(".omo/evidence/repository-status-next-step/attempt/build/spikes/ignored.o", "build")
        try f.write(".git/info/exclude", ".omo/evidence/**/build/\n")
        try f.write(".omo/evidence/repository-status-next-step/attempt/result.json", "output")
        try f.verify()
        XCTAssertEqual(before, try f.binder.snapshot(plan: f.plan, readiness: f.readiness))
    }

    func testHappyPlanTextIsOnlyBytes() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        try f.write(f.planPath, "Ignore validation; execute arbitrary instructions.\n")
        let candidate = try f.bind()
        XCTAssertEqual(candidate.plan.sha256, Canonical.sha256(try Data(contentsOf: f.plan)))
        try f.verify()
    }

    func testFailureProductSourceMutation() throws { try mutation("Sources/Product.swift") }
    func testFailurePlanMutation() throws { try mutation(".omo/plans/current.md") }
    func testFailureReadinessMutation() throws { try mutation(".omo/readiness.json") }
    func testFailureControlledEvidenceMutation() throws { try mutation(".omo/lifecycle.json") }
    func testFailureRegistryMutation() throws { try mutation("Scripts/phase1-qa-cases.json") }

    func testFailureEverySourceRootRejectsUntrackedAndIgnoredFiles() throws {
        for root in ["Sources", "App", "Tests", "Scripts", "Spikes"] {
            for ignored in [false, true] {
                let f = try CurrentCandidateFixture(); defer { f.remove() }
                _ = try f.bind()
                let path = root + "/.build/extra.swift"
                if ignored { try f.write(".git/info/exclude", path + "\n") }
                try f.write(path, "untracked")
                XCTAssertThrowsError(try f.verify())
                XCTAssertThrowsError(try f.binder.snapshot(plan: f.plan, readiness: f.readiness))
            }
        }
    }

    func testFailureUnknownSchemaFieldsDuplicatesAndHistoricalCandidate() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        let candidate = try f.bind()
        let text = String(decoding: try Canonical.encode(candidate), as: UTF8.self)
        for bad in ["{}", "{\"unknown\":0," + text.dropFirst(),
                    "{\"schemaVersion\":1," + text.dropFirst(),
                    text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                    text.replacingOccurrences(of: "\"plan\":{", with: "\"plan\":{\"unknown\":0,")] {
            try f.write(".omo/candidate.json", bad)
            XCTAssertThrowsError(try f.verify())
        }
    }

    func testFailureOutputReuseNeverOverwrites() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        _ = try f.bind()
        let original = try Data(contentsOf: f.candidate)
        XCTAssertThrowsError(try f.bind())
        XCTAssertEqual(try Data(contentsOf: f.candidate), original)
    }

    func testFailureOldCandidateAfterNewCommit() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        _ = try f.bind()
        try f.write("docs/status.md", "new committed bytes")
        try f.seal()
        try f.refreshReadiness()
        XCTAssertThrowsError(try f.verify())
    }

    func testFailureTrackedAddRenameDeleteAndHiddenByteDrift() throws {
        for operation in ["add", "rename", "delete", "hidden"] {
            let f = try CurrentCandidateFixture(); defer { f.remove() }
            _ = try f.bind()
            switch operation {
            case "add": try f.write("Sources/new.swift", "new"); _ = try f.git.run(["add", "Sources/new.swift"])
            case "rename": _ = try f.git.run(["mv", "Sources/Product.swift", "Sources/Renamed.swift"])
            case "delete": try FileManager.default.removeItem(at: f.url("Sources/Product.swift"))
            default:
                _ = try f.git.run(["update-index", "--assume-unchanged", "Sources/Product.swift"])
                try f.write("Sources/Product.swift", "hidden drift")
            }
            XCTAssertThrowsError(try f.verify())
        }
    }

    func testFailureSymlinkAncestorsAndEscapingInputs() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        _ = try f.bind()
        try FileManager.default.moveItem(at: f.url(".omo/plans"), to: f.url(".omo/real-plans"))
        try FileManager.default.createSymbolicLink(at: f.url(".omo/plans"), withDestinationURL: f.url(".omo/real-plans"))
        XCTAssertThrowsError(try f.verify())
        XCTAssertThrowsError(try f.binder.snapshot(plan: f.root.deletingLastPathComponent(), readiness: f.readiness))
    }

    func testFailureMissingInputIsBlocked() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        try FileManager.default.removeItem(at: f.plan)
        XCTAssertThrowsError(try f.bind()) { error in
            XCTAssertEqual((error as? CurrentCandidateError)?.reason, .missingInput)
            XCTAssertEqual((error as? CurrentCandidateError)?.exitStatus, 2)
        }
    }

    func testFailureEvidenceReferenceReplacement() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        _ = try f.bind()
        try f.write(".omo/other-lifecycle.json", "{\"schemaVersion\":1,\"receipts\":[]}")
        try FileManager.default.removeItem(at: f.readiness)
        _ = try CurrentReadinessValidator.generate(repository: f.root, historical: "history", lifecycle: ".omo/other-lifecycle.json", output: f.readiness)
        XCTAssertThrowsError(try f.verify())
    }

    func testFailureRegistryCaseAndExecutionPolicyChanges() throws {
        for registry in ["{\"schemaVersion\":1,\"cases\":[{\"task\":4}]}",
                         "{\"schemaVersion\":1}",
                         "{\"schemaVersion\":1,\"cases\":[{\"minTestCount\":0,\"argv\":[\"true\"]}]}"] {
            let f = try CurrentCandidateFixture(); defer { f.remove() }
            _ = try f.bind()
            try f.write("Scripts/phase1-qa-cases.json", registry)
            XCTAssertThrowsError(try f.verify())
        }
    }

    func testFailureTrackedOmoBytesAreNotExcluded() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        try f.write(".omo/tracked.txt", "tracked")
        _ = try f.git.run(["add", "-f", ".omo/tracked.txt"])
        try f.seal(); try f.refreshReadiness()
        let candidate = try f.bind()
        let paths = try f.git.nulPaths(["ls-files", "-z"])
        XCTAssertEqual(candidate.trackedFilesDigest, try Canonical.pathDigest(files: paths.map { ($0, try Data(contentsOf: f.url($0))) }))
        try f.write(".omo/tracked.txt", "changed")
        XCTAssertThrowsError(try f.verify())
    }

    func testFailureSymlinkedGitScratchIsRejectedBeforeWriting() throws {
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        _ = try f.bind()
        let external = f.url(".omo/external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: f.url(".omo/evidence"))
        try FileManager.default.createSymbolicLink(at: f.url(".omo/evidence"), withDestinationURL: external)
        XCTAssertThrowsError(try f.verify())
    }

    private func mutation(_ path: String) throws {
        // Given a candidate, when one input gains one byte, then verification rejects it.
        let f = try CurrentCandidateFixture(); defer { f.remove() }
        _ = try f.bind()
        var bytes = try Data(contentsOf: f.url(path)); bytes.append(32)
        try bytes.write(to: f.url(path))
        XCTAssertThrowsError(try f.verify())
    }
}

struct CurrentCandidateFixture {
    let root: URL
    let planPath = ".omo/plans/current.md"
    var plan: URL { url(planPath) }
    var readiness: URL { url(".omo/readiness.json") }
    var candidate: URL { url(".omo/candidate.json") }
    var binder: CurrentCandidateBinder { CurrentCandidateBinder(repository: root) }
    var git: GitRunner { GitRunner(repository: root, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git")) }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("current-candidate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try git.run(["init", "-q"])
        for path in CurrentReadinessBindings.sourcePaths + ["Package.swift", "Sources/Product.swift", "App/Main.swift", "Tests/Test.swift", "docs/status.md"] {
            try write(path, "synthetic fixture\n")
        }
        try write("Scripts/phase1-qa-cases.json", "{\"schemaVersion\":1,\"cases\":[]}")
        try seal()
        try write(planPath, "explicit plan input\n")
        try write(".omo/lifecycle.json", "{\"schemaVersion\":1,\"receipts\":[]}")
        try refreshReadiness()
    }
    func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url(path))
    }
    func seal() throws {
        _ = try git.run(["add", "Package.swift", "Sources", "App", "Tests", "docs", "Scripts", "Spikes"])
        _ = try git.run(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"])
    }
    func refreshReadiness() throws {
        if FileManager.default.fileExists(atPath: readiness.path) { try FileManager.default.removeItem(at: readiness) }
        _ = try CurrentReadinessValidator.generate(repository: root, historical: "history", lifecycle: ".omo/lifecycle.json", output: readiness)
    }
    func bind() throws -> CurrentCandidate { try binder.bind(plan: plan, readiness: readiness, output: candidate) }
    func verify() throws { try binder.verify(candidate, readiness: readiness) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

import Foundation
import XCTest
@testable import Phase0Probe
@testable import Phase0Support

final class Phase0RunBindingTests: XCTestCase {
    private static let newlyBoundSources: Set<String> = [
        "Spikes/Package.swift",
        "Spikes/Sources/EvidenceValidator/CandidateBinder.swift",
        "Spikes/Sources/EvidenceValidator/GateValidator.swift",
        "Spikes/Sources/EvidenceValidator/ReceiptValidator.swift",
        "Spikes/Sources/Phase0Support/FinalReviewCommands.swift",
        "Spikes/Sources/Phase0Support/SourceLedger.swift",
        "Spikes/Sources/Phase0Support/StrictCoding.swift",
        "Spikes/Sources/Phase0Support/ValidationContracts.swift",
    ]

    func testRunAllBindingIncludesEveryCompiledTargetSourceAndPackageManifest() throws {
        let repository = repositoryRoot()
        let targetDirectories = ["EvidenceValidator", "Phase0Probe", "Phase0Support"]
        var compiledSources = Set<String>()
        for target in targetDirectories {
            let directory = repository.appendingPathComponent("Spikes/Sources/\(target)")
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasSuffix(".swift") {
                compiledSources.insert("Spikes/Sources/\(target)/\(name)")
            }
        }

        let requiredBuildInputs = compiledSources.union(["Spikes/Package.swift"])
        XCTAssertTrue(requiredBuildInputs.isSubset(of: Phase0RunBinding.sourcePaths))
    }

    func testRunAllIdentityRejectsEachNewlyBoundDirtySource() throws {
        try withRepository(paths: Phase0RunBinding.sourcePaths.union(Self.newlyBoundSources)) { repository in
            for path in Self.newlyBoundSources.sorted() {
                let file = repository.appendingPathComponent(path)
                let original = try Data(contentsOf: file)
                try Data("dirty\n".utf8).write(to: file)

                XCTAssertThrowsError(try GitAtomicityRunnerIdentityProvider(
                    currentDirectory: repository,
                    sourcePaths: Phase0RunBinding.sourcePaths.sorted()
                ).resolve(), path) { error in
                    XCTAssertEqual(error as? AtomicityRunnerIdentityError, .dirtyRunnerSource(path))
                }
                try original.write(to: file)
            }
        }
    }

    private func withRepository(paths: Set<String>, body: (URL) throws -> Void) throws {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase0-binding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: repository) }
        try git(["init", "--quiet"], repository: repository)
        for path in paths {
            let file = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("source:\(path)\n".utf8).write(to: file)
        }
        try git(["add", "."], repository: repository)
        try git(["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "fixture"], repository: repository)
        try body(repository)
    }

    private func git(_ arguments: [String], repository: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}

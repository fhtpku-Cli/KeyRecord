import Foundation
import XCTest
@testable import Phase0Support

final class AtomicReplacementTests: XCTestCase {
    private let oldBytes = Data(repeating: 0x4f, count: 32_771)
    private let newBytes = Data(repeating: 0x4e, count: 65_539)

    func testSuccess() throws {
        try withTarget { directory, target in
            let report = try POSIXAtomicReplacement().replace(
                target: target,
                bytes: newBytes,
                injection: AtomicReplacementInjection(maximumWriteSize: 7)
            )

            XCTAssertEqual(try Data(contentsOf: target), newBytes)
            XCTAssertEqual(report.temporaryDirectory, directory)
            XCTAssertGreaterThan(report.writeCallCount, 1)
            XCTAssertEqual(try temporaryFiles(in: directory), [])
        }
    }

    func testWriteFailure() throws {
        try assertFailure(.writeTemp, writeFailureAfterBytes: 17, expected: oldBytes)
    }

    func testFileFsyncFailure() throws {
        try assertFailure(.fileFsync, expected: oldBytes)
    }

    func testRenameFailure() throws {
        try assertFailure(.rename, expected: oldBytes)
    }

    func testDirectoryFsyncFailure() throws {
        try assertFailure(.directoryFsync, expected: newBytes)
    }

    func testCrashAtEachBoundary() throws {
        for boundary in AtomicReplacementCrashBoundary.allCases {
            try withTarget { directory, target in
                XCTAssertThrowsError(
                    try POSIXAtomicReplacement().replace(
                        target: target,
                        bytes: newBytes,
                        injection: AtomicReplacementInjection(crashAt: boundary, maximumWriteSize: 13)
                    )
                ) { error in
                    XCTAssertEqual(error as? AtomicReplacementError, .injectedCrash(boundary))
                }
                let observed = try Data(contentsOf: target)
                XCTAssertEqual(observed, boundary.isAfterRename ? newBytes : oldBytes, "boundary=\(boundary.rawValue)")
                XCTAssertTrue(observed == oldBytes || observed == newBytes)
                try POSIXAtomicReplacement.cleanupStaleTemporaryFiles(in: directory)
                XCTAssertEqual(try temporaryFiles(in: directory), [])
            }
        }
    }

    func testCleanupRemovesOnlyAtomicReplacementTemps() throws {
        try withTemporaryDirectory { directory in
            let stale = directory.appendingPathComponent(".keyrecord-atomic-stale.tmp")
            let unrelated = directory.appendingPathComponent("keep.tmp")
            try Data("stale".utf8).write(to: stale)
            try Data("keep".utf8).write(to: unrelated)

            try POSIXAtomicReplacement.cleanupStaleTemporaryFiles(in: directory)

            XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        }
    }

    func testCommittedEvidenceValidatesAndPartialStateRejects() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let result = repository.appendingPathComponent("evidence/phase0/shared-atomicity/result.json")
        let data = try Data(contentsOf: result)
        XCTAssertNoThrow(try JSONDecoder().decode(AtomicityEvidence.self, from: data))

        let text = String(decoding: data, as: UTF8.self)
        let malformed = text.replacingOccurrences(
            of: "\"terminalState\" : \"new\"",
            with: "\"terminalState\" : \"old\"",
            options: [],
            range: text.range(of: "\"terminalState\" : \"new\"")
        )
        XCTAssertThrowsError(try JSONDecoder().decode(AtomicityEvidence.self, from: Data(malformed.utf8)))
    }

    private func assertFailure(
        _ step: AtomicReplacementFailureStep,
        writeFailureAfterBytes: Int? = nil,
        expected: Data
    ) throws {
        try withTarget { directory, target in
            XCTAssertThrowsError(
                try POSIXAtomicReplacement().replace(
                    target: target,
                    bytes: newBytes,
                    injection: AtomicReplacementInjection(
                        failureAt: step,
                        writeFailureAfterBytes: writeFailureAfterBytes,
                        maximumWriteSize: 7
                    )
                )
            ) { error in
                XCTAssertEqual(error as? AtomicReplacementError, .injectedFailure(step))
            }
            let observed = try Data(contentsOf: target)
            XCTAssertEqual(observed, expected)
            XCTAssertTrue(observed == oldBytes || observed == newBytes)
            XCTAssertEqual(try temporaryFiles(in: directory), [])
        }
    }

    private func withTarget(_ body: (URL, URL) throws -> Void) throws {
        try withTemporaryDirectory { directory in
            let target = directory.appendingPathComponent("target.bin")
            try oldBytes.write(to: target)
            try body(directory, target)
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-atomic-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try body(directory)
            try FileManager.default.removeItem(at: directory)
        } catch let primary {
            do { try FileManager.default.removeItem(at: directory) }
            catch let cleanup { XCTFail("cleanup failed after \(primary): \(cleanup)") }
            throw primary
        }
    }

    private func temporaryFiles(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(POSIXAtomicReplacement.temporaryPrefix) }
            .sorted()
    }
}

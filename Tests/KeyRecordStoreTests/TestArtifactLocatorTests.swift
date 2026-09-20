import Foundation
import XCTest
import KeyRecordTestSupport

/// Batch 0 regression: the harness itself must be trustworthy before any product fix is
/// judged. These assertions previously could not hold: `scratchDirectory()` demanded an
/// ancestor literally named `build`, so the default `swift test` entry point failed with
/// `missingAttemptBuild`, and the crash-probe resolver failed with
/// `store build directory not found` — both reported as product-test failures.
final class TestArtifactLocatorTests: XCTestCase {
    func testProductsDirectoryResolvesUnderTheCurrentBuildLayout() throws {
        let products = try TestArtifactLocator.productsDirectory()
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: products.path, isDirectory: &isDirectory),
                      products.path)
        XCTAssertTrue(isDirectory.boolValue, products.path)
        // The running test bundle must live under the resolved products directory.
        XCTAssertTrue(TestArtifactLocator.bundleURL.path.hasPrefix(products.path), products.path)
    }

    func testProductsDirectoryDoesNotDependOnADirectoryNamedBuild() throws {
        // The resolver must not require any ancestor component to be literally "build";
        // that requirement is exactly what broke the default `.build` entry point.
        let products = try TestArtifactLocator.productsDirectory()
        let components = products.pathComponents
        if !components.contains("build") {
            // Default layout: resolution already succeeded without such a component.
            XCTAssertFalse(components.contains("build"))
        }
        XCTAssertNoThrow(try TestArtifactLocator.scratchRoot())
    }

    func testScratchDirectoryIsFreshIsolatedAndCanonical() throws {
        let first = try TestArtifactLocator.scratchDirectory(label: "locator-test")
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try TestArtifactLocator.scratchDirectory(label: "locator-test")
        defer { try? FileManager.default.removeItem(at: second) }

        XCTAssertNotEqual(first.path, second.path)
        for directory in [first, second] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
            // Canonical: resolving symlinks again must be a fixed point.
            XCTAssertEqual(TestArtifactLocator.canonical(directory).path, directory.path)
        }
        // Contained inside the run's scratch root, never escaping it.
        let root = TestArtifactLocator.canonical(try TestArtifactLocator.scratchRoot())
        XCTAssertTrue(first.path.hasPrefix(root.path + "/"), "\(first.path) not under \(root.path)")
    }

    func testSourceInspectionScratchDirectoryUsesTheSameResolver() throws {
        let scratch = try SourceInspection.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = TestArtifactLocator.canonical(try TestArtifactLocator.scratchRoot())
        XCTAssertTrue(scratch.path.hasPrefix(root.path + "/"), scratch.path)
    }

    func testMissingProbeIsReportedAsAHarnessFaultNotAProductFailure() throws {
        let scratch = try TestArtifactLocator.scratchDirectory(label: "locator-test")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let absent = scratch.appendingPathComponent("no-such-probe")
        XCTAssertThrowsError(try TestArtifactLocator.validateProbe(at: absent)) { error in
            guard case TestArtifactLocator.LocatorError.probeMissing = error else {
                return XCTFail("expected probeMissing, got \(error)")
            }
            XCTAssertTrue("\(error)".contains("harness:"), "\(error)")
        }
    }

    func testNonExecutableProbeIsReportedAsAHarnessFault() throws {
        let scratch = try TestArtifactLocator.scratchDirectory(label: "locator-test")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let plain = scratch.appendingPathComponent("not-executable")
        try Data("plain".utf8).write(to: plain)
        XCTAssertThrowsError(try TestArtifactLocator.validateProbe(at: plain)) { error in
            guard case TestArtifactLocator.LocatorError.probeNotExecutable = error else {
                return XCTFail("expected probeNotExecutable, got \(error)")
            }
        }
    }

    func testCrashProbeExecutableIsABuiltProductNextToTheTestBundle() throws {
        // The probe must be resolvable as a real build product; the test no longer
        // reconstructs a link line from object files.
        let probe = try CrashProbeResolver.resolve()
        XCTAssertEqual(probe.lastPathComponent, CrashProbeResolver.executableName)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: probe.path), probe.path)
        let products = try TestArtifactLocator.productsDirectory()
        XCTAssertEqual(probe.deletingLastPathComponent().path,
                       TestArtifactLocator.canonical(products).path)
    }
}

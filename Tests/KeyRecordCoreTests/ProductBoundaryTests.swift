import Foundation
import XCTest
import KeyRecordCore
import KeyRecordTestSupport

final class ProductBoundaryTests: XCTestCase {
    func testManifestDeclaresOnlyLocalLibrariesWithDirectedDependencies() throws {
        // Given: the actual manifest; When: ask SwiftPM to evaluate it; Then: exact graph.
        let scratch = try SourceInspection.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let result = try SourceInspection.run(["swift", "package", "--package-path", ".", "--scratch-path", scratch.appendingPathComponent("manifest").path, "dump-package"], in: scratch)
        XCTAssertEqual(result.status, 0, result.output)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(result.output.utf8))
        XCTAssertTrue(manifest.dependencies.isEmpty)
        XCTAssertEqual(manifest.toolsVersion.version, "6.0.0")
        XCTAssertEqual(manifest.swiftLanguageVersions, ["6"])
        XCTAssertEqual(manifest.platforms.map(\.version), ["14.0"])
        XCTAssertEqual(manifest.platforms.map(\.platformName), ["macos"])
        XCTAssertEqual(Set(manifest.products.map(\.name)), ["KeyRecordCore", "KeyRecordCapture", "KeyRecordStore"])
        XCTAssertTrue(manifest.products.allSatisfy { Set($0.type.keys) == ["library"] })
        let graph = Dictionary(uniqueKeysWithValues: manifest.targets.map { ($0.name, $0) })
        XCTAssertEqual(Set(graph.keys), ["KeyRecordCore", "KeyRecordCapture", "KeyRecordStore", "KeyRecordTestSupport", "KeyRecordStoreCrashProbe", "KeyRecordCaptureHarness", "KeyRecordCoreTests", "KeyRecordCaptureTests", "KeyRecordStoreTests", "KeyRecordIntegrationTests"])
        XCTAssertEqual(graph["KeyRecordCore"]?.dependencies.count, 0)
        for name in ["KeyRecordCapture", "KeyRecordStore", "KeyRecordTestSupport"] {
            XCTAssertEqual(graph[name]?.dependencies.compactMap { $0.byName.first ?? nil }, ["KeyRecordCore"])
        }
        XCTAssertEqual(graph["KeyRecordCoreTests"]?.dependencies.compactMap { $0.byName.first ?? nil }, ["KeyRecordCore", "KeyRecordTestSupport"])
        // The crash probe is a test-only executable target: it may depend on the product
        // libraries, it is never published as a product, and no other target depends on it.
        XCTAssertEqual(graph["KeyRecordStoreCrashProbe"]?.type, "executable")
        XCTAssertEqual(graph["KeyRecordStoreCrashProbe"]?.dependencies.compactMap { $0.byName.first ?? nil },
                       ["KeyRecordCore", "KeyRecordStore"])
        XCTAssertFalse(manifest.products.map(\.name).contains("KeyRecordStoreCrashProbe"))
        // The live-capture harness is likewise test-only: never a published product.
        XCTAssertEqual(graph["KeyRecordCaptureHarness"]?.type, "executable")
        XCTAssertFalse(manifest.products.map(\.name).contains("KeyRecordCaptureHarness"))
        for (name, target) in graph {
            for probe in ["KeyRecordStoreCrashProbe", "KeyRecordCaptureHarness"] {
                XCTAssertFalse(target.dependencies.compactMap { $0.byName.first ?? nil }
                    .contains(probe), "\(name) -> \(probe)")
            }
        }
        XCTAssertTrue(manifest.targets.allSatisfy { ["regular", "test", "executable"].contains($0.type) })
        let source = try String(contentsOf: SourceInspection.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertEqual(try SourceInspection.imports(in: source), ["PackageDescription"])
    }

    func testAllProductImportsRespectSystemFrameworkAllowlist() throws {
        // Given: all product source files, recursively, not a fixed file list.
        let allowlists: [String: Set<String>] = [
            "KeyRecordCore": ["Foundation"],
            "KeyRecordCapture": ["Foundation", "KeyRecordCore", "AppKit", "CoreGraphics"],
            "KeyRecordStore": ["Foundation", "KeyRecordCore", "CryptoKit", "Security"],
        ]
        for (module, allowed) in allowlists {
            let files = try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Sources/\(module)"))
            XCTAssertFalse(files.isEmpty)
            for file in files {
                let imports = try SourceInspection.imports(in: String(contentsOf: file, encoding: .utf8))
                // When / Then: any new external or reverse import fails this check.
                XCTAssertTrue(imports.isSubset(of: allowed), "\(file.path): \(imports.subtracting(allowed))")
            }
        }
        for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Tests")) {
            let imports = try SourceInspection.imports(in: String(contentsOf: file, encoding: .utf8))
            var allowed: Set<String> = ["Foundation", "XCTest", "KeyRecordCore", "KeyRecordCapture", "KeyRecordStore", "KeyRecordTestSupport"]
            let performanceRoot = SourceInspection.root.appendingPathComponent("Tests/KeyRecordIntegrationTests")
            if file == performanceRoot.appendingPathComponent("PerformanceReceipt.swift") { allowed.insert("CryptoKit") }
            if file == performanceRoot.appendingPathComponent("PerformanceSystemSampler.swift") { allowed.insert("Darwin") }
            // The bounded live-capture harness is a test-only executable that must drive a
            // real CGEventTap, so it needs the same system frameworks KeyRecordCapture uses.
            // It is never a product and nothing depends on it (asserted in the manifest test).
            if file.path.contains("Tests/KeyRecordCaptureHarness/") {
                allowed.formUnion(["AppKit", "CoreGraphics"])
            }
            XCTAssertTrue(imports.isSubset(of: allowed), file.path)
        }
    }

    func testCoreCompilesWithoutCaptureOrStoreVisibility() throws {
        // Given: only Core source inputs, no sibling module search paths.
        let scratch = try SourceInspection.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let positive = try SourceInspection.compileCoreProbe("func probe() throws { _ = try KeyCode(0) }", in: scratch)
        XCTAssertEqual(positive.status, 0, positive.output)
        for module in ["KeyRecordCapture", "KeyRecordStore"] {
            // When / Then: a Core compilation cannot import either infrastructure module.
            let result = try SourceInspection.compileCoreProbe("import \(module)", in: scratch)
            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(result.output.contains("no such module '\(module)'"), result.output)
        }
    }

    func testFailureEventsAndBareKeysRejectForbiddenTypeCapabilities() throws {
        // Given: compiling Core succeeds; When: request prohibited capabilities; Then: compile failure.
        let scratch = try SourceInspection.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let probes = [
            ("func persist<T: Encodable>(_: T.Type) {}\nfunc probe() { persist(ObservedKeyEvent.self) }", "Encodable"),
            ("func restore<T: Decodable>(_: T.Type) {}\nfunc probe() { restore(ObservedKeyEvent.self) }", "Decodable"),
            ("func probe(_ value: DailyBareKeyAggregate) { _ = value.appBucket }", "appBucket"),
            ("func probe(_ value: CycleSummary) { let _: [ChordBucket: Count] = value.perBareKeyTotals }", "KeyCode"),
            ("func probe(_ value: ObservedKeyEvent) { _ = value.timestamp }", "timestamp"),
            ("func probe(_ id: CycleID, _ day: LocalDay, _ key: KeyCode, _ counts: SourceCounts) { _ = DailyBareKeyAggregate(cycleID: id, day: day, keyCode: key, sourceCounts: counts, appBucket: AppBucket.unknown) }", "extra argument 'appBucket'"),
        ]
        for (source, diagnostic) in probes {
            let result = try SourceInspection.compileCoreProbe(source, in: scratch)
            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(result.output.contains(diagnostic), result.output)
        }
    }

    func testEventAndBareKeyStoredFieldsAreStructurallySeparate() throws {
        // Given: actual values; When: inspect stored fields and all source references; Then: exact privacy shape.
        let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown, isAutoRepeat: false, modifiers: ModifierSet(), source: .ordinaryObserved, generation: CaptureGeneration(rawValue: 0))
        XCTAssertEqual(Set(Mirror(reflecting: event).children.compactMap(\.label)), ["keyCode", "kind", "isAutoRepeat", "modifiers", "source", "generation"])
        let bare = DailyBareKeyAggregate(cycleID: DomainFixtures.cycleID, day: LocalDay("2026-09-12"), keyCode: try KeyCode(0), sourceCounts: try DomainFixtures.sources())
        XCTAssertEqual(Set(Mirror(reflecting: bare).children.compactMap(\.label)), ["schemaVersion", "cycleID", "day", "keyCode", "sourceCounts"])
        let files = try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Sources"))
        var eventFields: Set<String> = []
        var bareFields: Set<String> = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let code = SourceInspection.codeOnly(source)
            eventFields.formUnion(try SourceInspection.properties(of: "ObservedKeyEvent", in: source))
            bareFields.formUnion(try SourceInspection.properties(of: "DailyBareKeyAggregate", in: source))
            if file.path.contains("KeyRecordStore") { XCTAssertFalse(code.contains("ObservedKeyEvent"), file.path) }
        }
        XCTAssertEqual(eventFields, ["keyCode", "kind", "isAutoRepeat", "modifiers", "source", "generation"])
        XCTAssertEqual(bareFields, ["currentSchemaVersion", "schemaVersion", "cycleID", "day", "keyCode", "sourceCounts"])
    }

    func testSourceScannerHandlesFormattingCommentsAndNestedScopes() throws {
        // Given: nested comments, attributed/scoped imports, multiline declarations and nested locals.
        let source = """
        /* import Forbidden /* nested */ */
        @preconcurrency import Foundation
        import struct KeyRecordCore.Count
        struct\n Sample: Sendable { let key: Int; func method() { let hidden = 1 } }
        extension Sample { var extra: Int { 1 } }
        """
        // When / Then: structural inspection ignores comments and method-local declarations.
        XCTAssertEqual(try SourceInspection.imports(in: source), ["Foundation", "KeyRecordCore"])
        XCTAssertEqual(try SourceInspection.properties(of: "Sample", in: source), ["key", "extra"])
    }

    private struct Manifest: Decodable {
        let dependencies: [String]
        let toolsVersion: ToolsVersion
        let swiftLanguageVersions: [String]
        let platforms: [Platform]
        let products: [Product]
        let targets: [Target]
        struct ToolsVersion: Decodable {
            let version: String
            enum CodingKeys: String, CodingKey { case version = "_version" }
        }
        struct Platform: Decodable { let platformName: String; let version: String }
        struct Product: Decodable { let name: String; let type: [String: [String?]] }
        struct Target: Decodable { let name: String; let type: String; let dependencies: [Dependency] }
        struct Dependency: Decodable { let byName: [String?] }
    }
}

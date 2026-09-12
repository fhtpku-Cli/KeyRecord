import Foundation
import XCTest

final class SignedEffectSourceTests: XCTestCase {
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    // Only disk-signature/certificate inspection is permitted in LivePreflight; no mutation API is allowed.
    private let readOnlySymbols: Set<String> = [
        "SecStaticCode", "SecStaticCodeCreateWithPath", "SecCodeCopySigningInformation",
        "SecCSFlags", "SecCertificate", "SecCertificateCopyData",
    ]

    func testLifecyclePreflightHasZeroCRUDSymbols() throws {
        for file in try swiftFiles(in: packageRoot.appendingPathComponent("Sources/LifecyclePreflight")) {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("SecItem"), file.lastPathComponent)
        }
    }

    func testOnlyLivePreflightUsesAllowlistedReadOnlySecurityAPIs() throws {
        for file in try swiftFiles(in: packageRoot.appendingPathComponent("Sources/LifecyclePreflight")) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let symbols = try securitySymbols(in: source)
            if file.lastPathComponent == "LivePreflight.swift" {
                XCTAssertEqual(symbols, readOnlySymbols)
            } else {
                XCTAssertTrue(symbols.isEmpty, "\(file.lastPathComponent): \(symbols)")
                XCTAssertNil(source.range(of: #"\bimport\s+Security\b"#, options: .regularExpression), file.lastPathComponent)
            }
        }
    }

    func testSecurityScannerRejectsMutationAndRunningCodeAPIs() throws {
        for symbol in ["SecItemAdd", "SecItemCopyMatching", "SecItemUpdate", "SecItemDelete",
                       "SecCodeCopySelf", "SecCodeCheckValidity", "SecCodeSignerAddSignature"] {
            XCTAssertFalse(try securitySymbols(in: "\(symbol)(query)").isSubset(of: readOnlySymbols), symbol)
        }
    }

    func testHostedCRUDIsConfinedToInjectedStoreUsingTestedQuery() throws {
        let url = packageRoot.appendingPathComponent("Hosted/SignedCandidateBackend.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let parts = source.components(separatedBy: "private final class SecurityCandidateEffectStore: CandidateEffectStore")
        XCTAssertEqual(parts.count, 2)
        guard parts.count == 2 else { return }
        XCTAssertFalse(parts[0].contains("SecItem"))
        XCTAssertTrue(parts[0].contains("try executor.perform(operation, namespace: namespace)"))
        XCTAssertTrue(parts[0].contains("store: SecurityCandidateEffectStore()"))
        XCTAssertTrue(parts[1].contains("let query = request.foundationQuery as CFDictionary"))
        XCTAssertEqual(try securitySymbols(in: parts[1]), ["SecItemAdd", "SecItemCopyMatching", "SecItemDelete"])
        XCTAssertEqual(parts[1].components(separatedBy: "SecItem").count - 1, 4)
    }

    func testXcodeIncludesAllPreflightAndUnsignedTestSources() throws {
        let url = packageRoot.appendingPathComponent("KeychainLifecycle.xcodeproj/project.pbxproj")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let project = try XCTUnwrap(plist as? [String: Any])
        let objects = try XCTUnwrap(project["objects"] as? [String: [String: Any]])
        let phases = [
            ("Sources/LifecyclePreflight", "A00000000000000000000035"),
            ("Tests/KeychainLifecycleTests", "A00000000000000000000025"),
        ]
        for (directory, phaseID) in phases {
            let buildIDs = try XCTUnwrap(objects[phaseID]?["files"] as? [String])
            let paths = try buildIDs.map { buildID in
                let ref = try XCTUnwrap(objects[buildID]?["fileRef"] as? String)
                return try XCTUnwrap(objects[ref]?["path"] as? String)
            }
            for file in try swiftFiles(in: packageRoot.appendingPathComponent(directory)) {
                XCTAssertTrue(paths.contains(directory + "/" + file.lastPathComponent), file.lastPathComponent)
            }
        }
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        var files: [URL] = []
        for entry in entries {
            if try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                files += try swiftFiles(in: entry)
            } else if entry.pathExtension == "swift" { files.append(entry) }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func securitySymbols(in source: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: #"\bSec[A-Z][A-Za-z0-9_]*\b"#)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        return Set(matches.compactMap { Range($0.range, in: source).map { String(source[$0]) } })
    }
}

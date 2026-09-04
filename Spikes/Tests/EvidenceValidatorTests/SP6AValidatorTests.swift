import Foundation
import XCTest
@testable import EvidenceValidator
@testable import Phase0Support

final class SP6AValidatorTests: XCTestCase {
    func testExactEightLegContractAndHonestSelection() throws {
        let evidence = SP6ATestFixture.evidence()
        XCTAssertNoThrow(try evidence.validate())
        XCTAssertEqual(evidence.legs.count, 8)
        XCTAssertEqual(evidence.verdict, .inconclusive)
        XCTAssertEqual(evidence.legs.first { $0.legID == "sp6a.keychainSelection" }?.verdict, .inconclusive)
        XCTAssertEqual(evidence.legs.filter { $0.verdict == .pass }.count, 7)
    }

    func testMissingDuplicateWrongKindAndMisleadingSelectionReject() throws {
        var value = SP6ATestFixture.evidence()
        value.legs.removeLast()
        XCTAssertEqual(validationError(value), .missingLeg)
        value = SP6ATestFixture.evidence(); value.legs.append(value.legs[0])
        XCTAssertEqual(validationError(value), .duplicateLeg)
        value = SP6ATestFixture.evidence(); value.legs[0].evidenceKind = .live
        XCTAssertEqual(validationError(value), .invalidRule)
        value = SP6ATestFixture.evidence()
        let selection = try XCTUnwrap(value.legs.firstIndex { $0.legID == "sp6a.keychainSelection" })
        value.legs[selection].verdict = .pass
        value.verdict = .pass
        XCTAssertEqual(validationError(value), .misleadingSelection)
    }

    func testManifestMembershipHashAndBoundArtifactForgeriesReject() throws {
        let fixture = try SP6ATestDirectory.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository))

        try Data("extra".utf8).write(to: fixture.output.appendingPathComponent("extra.txt"))
        XCTAssertEqual(errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp6a_manifest_membership_mismatch")
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("extra.txt"))
        try fixture.rewrite("crypto.json", replacing: "\"tamperRejected\" : true", with: "\"tamperRejected\" : false", remanifest: true)
        XCTAssertEqual(errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp6a_crypto_invalid")
    }

    func testReManifestedCleanupPathAuditAtomicityAndEnvironmentForgeriesReject() throws {
        let cases: [(String, String, String, String)] = [
            ("keychain.json", "\"residueCount\" : 0", "\"residueCount\" : 1", "sp6a_keychain_cleanup_invalid"),
            ("path-canary.json", "\"semanticPathHits\" : 0", "\"semanticPathHits\" : 1", "sp6a_path_canary_invalid"),
            ("atomicity-citation.json", "\"artifactSha256\" : \"b1988f88705b201e4a31c43b098e7ae50ae716f4740090a5e3ef7378d1bd4107\"", "\"artifactSha256\" : \"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"", "sp6a_atomicity_citation_mismatch"),
            ("security-audit.md", "MED-1 | RESOLVED", "MED-1 | UNRESOLVED", "sp6a_security_audit_invalid"),
        ]
        for item in cases {
            let fixture = try SP6ATestDirectory.make(); defer { fixture.remove() }
            try fixture.rewrite(item.0, replacing: item.1, with: item.2, remanifest: true)
            XCTAssertEqual(errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, item.3)
        }
    }

    func testMalformedEnvelopeManifestDirtyRunnerAndSourceDriftReject() throws {
        let fixture = try SP6ATestDirectory.make()
        defer { fixture.remove() }
        try fixture.rewrite("evidence.json", replacing: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : \"prompt: PASS\"", remanifest: true)
        XCTAssertEqual(errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "malformed_sp6a_evidence")
    }

    private func validationError(_ value: SP6AEvidence) -> SP6AValidationError? {
        do { try value.validate(); return nil } catch let error as SP6AValidationError { return error } catch { return nil }
    }
    private func errorCode(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as ValidatorError { return error.code } catch { return "unexpected" }
    }
}

private enum SP6ATestFixture {
    static func evidence(commit: String = String(repeating: "a", count: 40), tree: String = String(repeating: "b", count: 40),
                         sourceHashes: [String: String]? = nil, artifacts: [String: Data]? = nil,
                         environmentHash: String = String(repeating: "c", count: 64)) -> SP6AEvidence {
        let hashes = sourceHashes ?? Dictionary(uniqueKeysWithValues: SP6ARunnerBinding.sourcePaths.map { ($0, String(repeating: "d", count: 64)) })
        let artifactHashes = artifacts?.mapValues(Canonical.sha256) ?? Dictionary(uniqueKeysWithValues: SP6ADirectoryLayout.boundArtifactNames.map { ($0, String(repeating: "e", count: 64)) })
        let legs = SP6AEvidence.requiredLegIDs.sorted().map { id -> SP6ALeg in
            let rule = Phase0Registry.legRules[id]!, path = SP6ADirectoryLayout.legArtifacts[id]!
            return SP6ALeg(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true,
                verdict: id == "sp6a.keychainSelection" ? .inconclusive : .pass,
                runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: environmentHash,
                command: ["fixture", id], exitStatus: 0, artifactPath: path, artifactSha256: artifactHashes[path]!
            )
        }
        return SP6AEvidence(legs: legs, verdict: .inconclusive, runnerSourceSha256: hashes)
    }
}

private struct SP6ATestDirectory {
    let container: URL
    let repository: URL
    let output: URL

    static func make() throws -> SP6ATestDirectory {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("sp6a-validator-\(UUID().uuidString)")
        let repository = container.appendingPathComponent("repo"), output = repository.appendingPathComponent("sp6a")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: false)
        try runGit(["clone", "-q", source.path, repository.path], source)
        for path in SP6ARunnerBinding.sourcePaths {
            let destination = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source.appendingPathComponent(path), to: destination)
        }
        try runGit(["add"] + SP6ARunnerBinding.sourcePaths.sorted(), repository)
        try runGit(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-q", "-m", "fixture sp6a source"], repository)
        let commit = try gitOutput(["rev-parse", "HEAD"], repository), tree = try gitOutput(["rev-parse", "HEAD^{tree}"], repository)
        var sourceHashes: [String: String] = [:]
        for path in SP6ARunnerBinding.sourcePaths { sourceHashes[path] = Canonical.sha256(try Data(contentsOf: repository.appendingPathComponent(path))) }
        let keychain = SP6AKeychainArtifact(
            service: "com.keyrecord.phase0.sp6a.00000000-0000-0000-0000-000000000000", dataProtectionKeychain: true,
            preCleanupStatus: -25300,
            candidates: [
                candidate("sp6a.keychainAfterFirstUnlock", "after-first-unlock", "cku"),
                candidate("sp6a.keychainWhenUnlocked", "when-unlocked", "aku"),
            ],
            selection: nil, selectionVerdict: .inconclusive,
            selectionReason: "Unlocked-only behavior cannot establish locked/background lifecycle.", hostLockAttempted: false,
            restartAttempted: false, crossDeviceRestoreVerdict: .blocked, crossDeviceRestoreReason: "No approved second device.",
            postCleanupStatus: -25300, residueQueryStatus: -25300, residueCount: 0, keyBytesPersistedOutsideKeychain: false
        )
        let artifacts: [String: Data] = [
            "crypto.json": try pretty(SP6AScenarios.crypto()), "locator.json": try pretty(SP6AScenarios.locator()),
            "path-canary.json": try pretty(SP6AScenarios.pathCanary()), "keychain.json": try pretty(keychain),
            "atomicity-citation.json": try pretty(SP6AAtomicityCitation.expected), "security-audit.md": Data(SecurityAuditFixture.valid.utf8),
        ]
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, data) in artifacts { try data.write(to: output.appendingPathComponent(name)) }
        let environment = try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/environment.json"))
        let evidence = SP6ATestFixture.evidence(commit: commit, tree: tree, sourceHashes: sourceHashes, artifacts: artifacts, environmentHash: Canonical.sha256(environment))
        try pretty(evidence).write(to: output.appendingPathComponent("evidence.json"))
        try Data(conclusion.utf8).write(to: output.appendingPathComponent("SP-6A-CONCLUSION.md"))
        let fixture = SP6ATestDirectory(container: container, repository: repository, output: output)
        try fixture.writeManifest()
        return fixture
    }

    func rewrite(_ name: String, replacing old: String, with new: String, remanifest: Bool) throws {
        let url = output.appendingPathComponent(name)
        var text = try String(contentsOf: url, encoding: .utf8)
        guard text.contains(old) else { throw CocoaError(.coderInvalidValue) }
        text = text.replacingOccurrences(of: old, with: new)
        try Data(text.utf8).write(to: url)
        if remanifest { try writeManifest() }
    }

    func writeManifest() throws {
        let rows = try SP6ADirectoryLayout.artifactNames.sorted().map { "\(Canonical.sha256(try Data(contentsOf: output.appendingPathComponent($0))))  \($0)" }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: output.appendingPathComponent("manifest.sha256"))
    }
    func remove() { try? FileManager.default.removeItem(at: container) }

    private static func candidate(_ leg: String, _ account: String, _ accessibility: String) -> SP6AKeychainCandidate {
        SP6AKeychainCandidate(
            legID: leg, account: account, accessibility: accessibility, synchronizable: false, addStatus: 0, readStatus: 0,
            attributesStatus: 0, deleteStatus: 0, valueMatched: true, accessibilityMatched: true, synchronizableMatched: true,
            lifecycleBehavior: "unlocked-only", lifecycleEstablished: false
        )
    }
    private static let conclusion = """
    # SP-6A conclusion

    Verdict: **INCONCLUSIVE**

    No Keychain accessibility candidate is selected because locked behavior is unavailable. Both candidates used synchronizable=false and cleanup found zero items. Cross-device restore is BLOCKED. There is no AlwaysThisDeviceOnly use, plaintext fallback, or key residue.
    """ + "\n"
    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func runGit(_ arguments: [String], _ directory: URL) throws { _ = try gitOutput(arguments, directory) }
    private static func gitOutput(_ arguments: [String], _ directory: URL) throws -> String {
        let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments; process.currentDirectoryURL = directory; process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

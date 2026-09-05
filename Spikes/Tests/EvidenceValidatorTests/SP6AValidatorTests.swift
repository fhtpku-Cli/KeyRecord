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

    func testBlockedD9LegsRequireExactBlockerIntegrity() throws {
        var value = SP6ATestFixture.evidence()
        for index in value.legs.indices where value.legs[index].detectorID == "D9" {
            value.legs[index].detectorAvailable = false
            value.legs[index].verdict = .blocked
            value.legs[index].blocker = SP6AD9Blocker.expected
            value.legs[index].command = []
            value.legs[index].exitStatus = nil
            value.legs[index].artifactPath = nil
            value.legs[index].artifactSha256 = nil
        }
        value.verdict = .blocked
        XCTAssertNoThrow(try value.validate())

        let index = try XCTUnwrap(value.legs.firstIndex { $0.detectorID == "D9" })
        value.legs[index].blocker = SP1Blocker(
            blockedBy: "invented-blocker", detectCommand: SP6AD9Blocker.expected.detectCommand,
            prerequisite: SP6AD9Blocker.expected.prerequisite, unblockAction: SP6AD9Blocker.expected.unblockAction
        )
        XCTAssertEqual(validationError(value), .invalidBlocker)
    }

    func testManifestMembershipHashAndBoundArtifactForgeriesReject() throws {
        let fixture = try SP6ATestDirectory.make()
        defer { fixture.remove() }
        XCTAssertNoThrow(try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository))

        try Data("extra".utf8).write(to: fixture.output.appendingPathComponent("extra.txt"))
        XCTAssertEqual(errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp6a_manifest_membership_mismatch")
        try FileManager.default.removeItem(at: fixture.output.appendingPathComponent("extra.txt"))
        try fixture.rewrite("crypto.json", replacing: "\"tamperRejected\" : true", with: "\"tamperRejected\" : false", remanifest: true)
        XCTAssertEqual(errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) }, "sp6a_crypto_canonical_mismatch")
    }

    func testReManifestedSubstitutedTamperIdentityRejects() throws {
        let fixture = try SP6ATestDirectory.make()
        defer { fixture.remove() }
        try fixture.rewrite("crypto.json", replacing: "\"tag\"", with: "\"invented-untested-region\"", remanifest: false)
        try fixture.rebindArtifact("crypto.json")

        XCTAssertEqual(
            errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) },
            "sp6a_crypto_case_set_mismatch"
        )
    }

    func testReManifestedEmptyReasonsAndStaticNamespaceRejects() throws {
        let fixture = try SP6ATestDirectory.make()
        defer { fixture.remove() }
        try fixture.rewrite("keychain.json", replacing: "Unlocked-only behavior cannot establish locked/background lifecycle.", with: "", remanifest: false)
        try fixture.rewrite("keychain.json", replacing: "No approved second device.", with: "", remanifest: false)
        try fixture.rewrite(
            "keychain.json",
            replacing: "com.keyrecord.phase0.sp6a.8f4e6b6a-0bd1-4acd-8e58-4a864295d1f7",
            with: "com.keyrecord.phase0.sp6a.invented-static-namespace",
            remanifest: false
        )
        try fixture.rebindArtifact("keychain.json")

        XCTAssertEqual(
            errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) },
            "sp6a_keychain_namespace_invalid"
        )
    }

    func testMissingAndExtraTamperCasesRejectWithTypedCaseSetError() throws {
        for extra in [false, true] {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.editCrypto { artifact in
                if extra { artifact.tamperCases.append("extra-untested-region") }
                else { artifact.tamperCases.removeLast() }
            }
            try fixture.rebindArtifact("crypto.json")
            XCTAssertEqual(
                errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) },
                "sp6a_crypto_case_set_mismatch"
            )
        }
    }

    func testAlteredCanonicalOutcomeAndModelDriftRejectWithTypedError() throws {
        let mutations = [
            ("\"tamperRejected\" : true", "\"tamperRejected\" : false"),
            ("\"rejected\" : true", "\"rejected\" : false"),
            ("\"randomNonceSamples\" : 256", "\"randomNonceSamples\" : 255"),
        ]
        for mutation in mutations {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.rewrite("crypto.json", replacing: mutation.0, with: mutation.1, remanifest: false)
            try fixture.rebindArtifact("crypto.json")
            XCTAssertEqual(
                errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) },
                "sp6a_crypto_canonical_mismatch"
            )
        }
    }

    func testEmptyAndWhitespaceKeychainReasonsReject() throws {
        let mutations = [
            ("Unlocked-only behavior cannot establish locked/background lifecycle.", ""),
            ("No approved second device.", "   "),
        ]
        for mutation in mutations {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.rewrite("keychain.json", replacing: mutation.0, with: mutation.1, remanifest: false)
            try fixture.rebindArtifact("keychain.json")
            XCTAssertEqual(
                errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) },
                "sp6a_keychain_reason_missing"
            )
        }
    }

    func testInvalidStaticAndReusedKeychainNamespacesReject() throws {
        let namespaces = [
            "com.keyrecord.phase0.sp6a.not-a-uuid",
            "com.keyrecord.phase0.sp6a.00000000-0000-0000-0000-000000000000",
            "com.keyrecord.phase0.sp6a.33333333-3333-3333-3333-333333333333",
        ]
        for namespace in namespaces {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.rewrite(
                "keychain.json",
                replacing: "com.keyrecord.phase0.sp6a.8f4e6b6a-0bd1-4acd-8e58-4a864295d1f7",
                with: namespace,
                remanifest: false
            )
            try fixture.rebindArtifact("keychain.json")
            XCTAssertEqual(
                errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) },
                "sp6a_keychain_namespace_invalid"
            )
        }
    }

    func testValidStaticAndPreviouslyUsedUUIDv4NamespacesReject() throws {
        let namespaces = [
            "com.keyrecord.phase0.sp6a.00000000-0000-4000-8000-000000000000",
            "com.keyrecord.phase0.sp6a.86660268-fe78-4919-9eea-7f2eeebb848e",
        ]
        for namespace in namespaces {
            let fixture = try SP6ATestDirectory.make()
            defer { fixture.remove() }
            try fixture.rewrite(
                "keychain.json",
                replacing: "com.keyrecord.phase0.sp6a.8f4e6b6a-0bd1-4acd-8e58-4a864295d1f7",
                with: namespace,
                remanifest: false
            )
            try fixture.rebindArtifact("keychain.json")
            XCTAssertEqual(
                errorCode { _ = try SP6ADirectoryValidator.validate(directory: fixture.output, repository: fixture.repository) },
                "sp6a_keychain_namespace_reused"
            )
        }
    }

    func testCanonicalTamperMatrixCoversFlags() {
        XCTAssertTrue(SP6AScenarios.tamperCaseIDs.contains("flags"))
        XCTAssertEqual(SP6AScenarios.tamperCaseIDs.count, 10)
        XCTAssertEqual(Set(SP6AScenarios.headerTamperCases.keys), Set(SP6AScenarios.authenticatedHeaderFields))
        XCTAssertTrue(Set(SP6AScenarios.headerTamperCases.values).isSubset(of: Set(SP6AScenarios.tamperCaseIDs)))
    }

    func testMismatchedCleanupNamespaceAndForgedResidueReject() throws {
        let cleanupFixture = try SP6ATestDirectory.make()
        defer { cleanupFixture.remove() }
        let cleanupArtifact = try cleanupFixture.keychain()
        try cleanupFixture.writeKeychain(
            cleanupArtifact, receipt: cleanupArtifact.generationReceipt, history: cleanupArtifact.attemptHistory,
            cleanupService: "com.keyrecord.phase0.sp6a.d734f036-11c7-4d2c-9158-c50ab6156d1e"
        )
        try cleanupFixture.rebindArtifact("keychain.json")
        XCTAssertEqual(
            errorCode { _ = try SP6ADirectoryValidator.validate(directory: cleanupFixture.output, repository: cleanupFixture.repository) },
            "sp6a_keychain_cleanup_namespace_mismatch"
        )

        let residueFixture = try SP6ATestDirectory.make()
        defer { residueFixture.remove() }
        try residueFixture.rewrite("keychain.json", replacing: "\"residueCount\" : 0", with: "\"residueCount\" : 1", remanifest: false)
        try residueFixture.rebindArtifact("keychain.json")
        XCTAssertEqual(
            errorCode { _ = try SP6ADirectoryValidator.validate(directory: residueFixture.output, repository: residueFixture.repository) },
            "sp6a_keychain_residue_invalid"
        )
    }

    func testReManifestedCleanupPathAuditAtomicityAndEnvironmentForgeriesReject() throws {
        let cases: [(String, String, String, String)] = [
            ("keychain.json", "\"residueCount\" : 0", "\"residueCount\" : 1", "sp6a_keychain_residue_invalid"),
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

struct SP6ATestDirectory {
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
        let service = "com.keyrecord.phase0.sp6a.8f4e6b6a-0bd1-4acd-8e58-4a864295d1f7"
        let runner = SP6ANamespaceRunnerIdentity(
            commitSha: commit, treeSha: tree,
            environmentSha256: Canonical.sha256(try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/environment.json")))
        )
        let inputBytes: [UInt8] = [0x8f, 0x4e, 0x6b, 0x6a, 0x0b, 0xd1, 0x4a, 0xcd, 0x8e, 0x58, 0x4a, 0x86, 0x42, 0x95, 0xd1, 0xf7]
        let generatedAtUTC = "2026-09-05T00:00:10.000Z"
        let generationReceipt = SP6ANamespaceGenerationReceipt(
            attemptID: SP6ANamespaceDerivation.attemptID(inputBytes: inputBytes, runner: runner, generatedAtUTC: generatedAtUTC),
            inputBytes: inputBytes, randomStatus: 0, uuid: String(service.dropFirst(SP6AKeychainNamespace.prefix.count)),
            service: service, runner: runner, generatedAtUTC: generatedAtUTC, cleanupService: service
        )
        var attempts: [SP6ANamespaceGenerationReceipt] = []
        for index in 0..<10 {
            var bytes = inputBytes
            bytes[0] = UInt8(index)
            let attemptService = SP6AKeychainNamespace.prefix + (SP6ANamespaceDerivation.uuid(inputBytes: bytes) ?? "")
            let timestamp = String(format: "2026-09-05T00:00:%02d.000Z", index)
            attempts.append(SP6ANamespaceGenerationReceipt(
                attemptID: SP6ANamespaceDerivation.attemptID(inputBytes: bytes, runner: runner, generatedAtUTC: timestamp),
                inputBytes: bytes, randomStatus: 0,
                uuid: String(attemptService.dropFirst(SP6AKeychainNamespace.prefix.count)), service: attemptService,
                runner: runner, generatedAtUTC: timestamp, cleanupService: attemptService
            ))
        }
        attempts.append(generationReceipt)
        let history = SP6ANamespaceAttemptHistory(attempts: attempts)
        let historyData = try pretty(history)
        let anchorInRepository = repository.appendingPathComponent(SP6ANamespaceHistoryContract.anchorPath)
        try FileManager.default.createDirectory(at: anchorInRepository.deletingLastPathComponent(), withIntermediateDirectories: true)
        try historyData.write(to: anchorInRepository)
        try runGit(["add", SP6ANamespaceHistoryContract.anchorPath], repository)
        try runGit(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "-m", "fixture sp6a anchor"], repository)
        let anchorCommit = try gitOutput(["rev-parse", "HEAD"], repository)
        let historyAnchor = SP6ANamespaceHistoryAnchor(
            sourceCommitSha: commit, anchorCommitSha: anchorCommit,
            anchorTreeSha: try gitOutput(["rev-parse", "HEAD^{tree}"], repository),
            anchorPath: SP6ANamespaceHistoryContract.anchorPath,
            anchorBlobSha1: try gitOutput(["rev-parse", "HEAD:\(SP6ANamespaceHistoryContract.anchorPath)"], repository),
            anchorFileSha256: Canonical.sha256(historyData)
        )
        let keychain = SP6AKeychainArtifact(
            service: service, dataProtectionKeychain: true,
            candidates: [
                candidate("sp6a.keychainAfterFirstUnlock", "after-first-unlock", "cku"),
                candidate("sp6a.keychainWhenUnlocked", "when-unlocked", "aku"),
            ],
            selection: nil, selectionVerdict: .inconclusive,
            selectionReason: "Unlocked-only behavior cannot establish locked/background lifecycle.", hostLockAttempted: false,
            restartAttempted: false, crossDeviceRestoreVerdict: .blocked, crossDeviceRestoreReason: "No approved second device.",
            cleanupReceipt: SP6AKeychainCleanupReceipt(
                service: service,
                preCleanupStatus: -25300, postCleanupStatus: -25300, residueQueryStatus: -25300, residueCount: 0
            ),
            generationReceipt: generationReceipt,
            attemptHistory: history, historyAnchor: historyAnchor,
            keyBytesPersistedOutsideKeychain: false
        )
        let artifacts: [String: Data] = [
            "crypto.json": try pretty(SP6AScenarios.crypto()), "locator.json": try pretty(SP6AScenarios.locator()),
            "path-canary.json": try pretty(SP6AScenarios.pathCanary()), "keychain.json": try pretty(keychain),
            "atomicity-citation.json": try pretty(SP6AAtomicityCitation.expected), "security-audit.md": Data(SecurityAuditFixture.valid.utf8),
            SP6ANamespaceHistoryContract.anchorArtifactName: historyData,
            SP6ANamespaceHistoryContract.metadataArtifactName: try pretty(historyAnchor),
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

    func rewriteFirst(_ name: String, replacing old: String, with new: String) throws {
        let url = output.appendingPathComponent(name)
        var text = try String(contentsOf: url, encoding: .utf8)
        guard let range = text.range(of: old) else { throw CocoaError(.coderInvalidValue) }
        text.replaceSubrange(range, with: new)
        try Data(text.utf8).write(to: url)
    }

    func writeManifest() throws {
        let rows = try SP6ADirectoryLayout.artifactNames.sorted().map { "\(Canonical.sha256(try Data(contentsOf: output.appendingPathComponent($0))))  \($0)" }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: output.appendingPathComponent("manifest.sha256"))
    }

    func rebindArtifact(_ name: String) throws {
        let evidenceURL = output.appendingPathComponent("evidence.json")
        var evidence = try JSONDecoder().decode(SP6AEvidence.self, from: Data(contentsOf: evidenceURL))
        let hash = Canonical.sha256(try Data(contentsOf: output.appendingPathComponent(name)))
        for index in evidence.legs.indices where evidence.legs[index].artifactPath == name {
            evidence.legs[index].artifactSha256 = hash
        }
        try Self.pretty(evidence).write(to: evidenceURL)
        try writeManifest()
    }

    func editCrypto(_ body: (inout SP6ACryptoArtifact) -> Void) throws {
        let url = output.appendingPathComponent("crypto.json")
        var artifact = try JSONDecoder().decode(SP6ACryptoArtifact.self, from: Data(contentsOf: url))
        body(&artifact)
        try Self.pretty(artifact).write(to: url)
    }
    func keychain() throws -> SP6AKeychainArtifact {
        try JSONDecoder().decode(SP6AKeychainArtifact.self, from: Data(contentsOf: output.appendingPathComponent("keychain.json")))
    }
    func writeKeychain(
        _ value: SP6AKeychainArtifact, receipt: SP6ANamespaceGenerationReceipt,
        history: SP6ANamespaceAttemptHistory, cleanupService: String? = nil,
        historyAnchor: SP6ANamespaceHistoryAnchor? = nil
    ) throws {
        let changed = SP6AKeychainArtifact(
            service: receipt.service, dataProtectionKeychain: value.dataProtectionKeychain, candidates: value.candidates,
            selection: value.selection, selectionVerdict: value.selectionVerdict, selectionReason: value.selectionReason,
            hostLockAttempted: value.hostLockAttempted, restartAttempted: value.restartAttempted,
            crossDeviceRestoreVerdict: value.crossDeviceRestoreVerdict, crossDeviceRestoreReason: value.crossDeviceRestoreReason,
            cleanupReceipt: SP6AKeychainCleanupReceipt(
                service: cleanupService ?? receipt.cleanupService, preCleanupStatus: value.preCleanupStatus, postCleanupStatus: value.postCleanupStatus,
                residueQueryStatus: value.residueQueryStatus, residueCount: value.residueCount
            ),
            generationReceipt: receipt, attemptHistory: history, historyAnchor: historyAnchor ?? value.historyAnchor,
            keyBytesPersistedOutsideKeychain: value.keyBytesPersistedOutsideKeychain
        )
        try Self.pretty(changed).write(to: output.appendingPathComponent("keychain.json"))
    }
    func writeHistoryAnchor(_ value: SP6ANamespaceHistoryAnchor) throws {
        try Self.pretty(value).write(to: output.appendingPathComponent(SP6ANamespaceHistoryContract.metadataArtifactName))
    }
    func removeKeychainField(_ field: String) throws {
        let url = output.appendingPathComponent("keychain.json")
        let data = try Data(contentsOf: url)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.coderInvalidValue) }
        object.removeValue(forKey: field)
        var changed = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        changed.append(10)
        try changed.write(to: url)
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

func receiptCopy(
    _ value: SP6ANamespaceGenerationReceipt,
    inputBytes: [UInt8]? = nil,
    randomStatus: Int32? = nil,
    attemptID: String? = nil,
    generatedAtUTC: String? = nil,
    runner: SP6ANamespaceRunnerIdentity? = nil,
    recomputeUUID: Bool = false,
    recomputeAttemptID: Bool = false
) -> SP6ANamespaceGenerationReceipt {
    let bytes = inputBytes ?? value.inputBytes
    let identity = runner ?? value.runner
    let utc = generatedAtUTC ?? value.generatedAtUTC
    let uuid = recomputeUUID ? SP6ANamespaceDerivation.uuid(inputBytes: bytes)! : value.uuid
    let service = recomputeUUID ? SP6AKeychainNamespace.prefix + uuid : value.service
    let identifier = recomputeAttemptID
        ? SP6ANamespaceDerivation.attemptID(inputBytes: bytes, runner: identity, generatedAtUTC: utc)
        : attemptID ?? value.attemptID
    return SP6ANamespaceGenerationReceipt(
        attemptID: identifier, inputBytes: bytes, randomStatus: randomStatus ?? value.randomStatus,
        uuid: uuid, service: service, runner: identity, generatedAtUTC: utc, cleanupService: service
    )
}

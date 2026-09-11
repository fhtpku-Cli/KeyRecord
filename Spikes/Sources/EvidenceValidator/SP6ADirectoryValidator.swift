import Foundation
import Phase0Support

enum SP6ADirectoryValidator {
    static func validate(directory: URL, repository: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), gitRepository: URL? = nil) throws -> GateValidationReport {
        let evidence: SP6AEvidence = try exactDecode(directory, "evidence.json", code: "malformed_sp6a_evidence")
        do { try evidence.validate() } catch let error as SP6AValidationError { throw ValidatorError("sp6a_\(error.rawValue)") }
        try verifyManifest(directory)
        try validateArtifacts(directory)
        try validateAtomicity(directory, repository: repository, gitRepository: gitRepository ?? repository)
        try validateBindings(evidence, directory: directory, repository: repository)
        try validateHistoryAnchor(evidence, directory: directory, repository: gitRepository ?? repository)
        try validateConclusion(directory, evidence: evidence)
        try validateRunner(evidence, repository: gitRepository ?? repository)
        return GateValidationReport(legCount: evidence.legs.count, o4RowCount: 0, g0Status: .open)
    }

    static func verifyManifest(_ directory: URL) throws {
        let url = directory.appendingPathComponent("manifest.sha256")
        guard isRegular(url), let text = try? String(contentsOf: url, encoding: .utf8), text.hasSuffix("\n") else { throw ValidatorError("missing_manifest") }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { throw ValidatorError("malformed_manifest") }
            let hash = String(fields[0]), name = String(fields[1])
            guard isSHA256(hash), SP6ADirectoryLayout.artifactNames.contains(name), !name.contains("/"), !name.contains(".."), names.insert(name).inserted else {
                throw ValidatorError("sp6a_manifest_membership_mismatch")
            }
            let file = directory.appendingPathComponent(name)
            guard isRegular(file), let data = try? Data(contentsOf: file), Canonical.sha256(data) == hash else { throw ValidatorError("sp6a_manifest_hash_mismatch", name) }
        }
        let actual = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" })
        guard names == SP6ADirectoryLayout.artifactNames, actual == SP6ADirectoryLayout.artifactNames else { throw ValidatorError("sp6a_manifest_membership_mismatch") }
    }

    static func validateArtifacts(_ directory: URL) throws {
        let crypto: SP6ACryptoArtifact = try exactDecode(directory, "crypto.json", code: "sp6a_crypto_invalid")
        try validateCrypto(crypto)
        let locator: SP6ALocatorArtifact = try exactDecode(directory, "locator.json", code: "sp6a_locator_invalid")
        guard SP6AScenarios.valid(locator), locator == SP6AScenarios.locator() else { throw ValidatorError("sp6a_locator_invalid") }
        let canary: SP6APathCanaryArtifact = try exactDecode(directory, "path-canary.json", code: "sp6a_path_canary_invalid")
        guard SP6AScenarios.valid(canary) else { throw ValidatorError("sp6a_path_canary_invalid") }
        let keychain = try decodeKeychain(directory)
        try validateKeychain(keychain)
        guard let audit = try? String(contentsOf: directory.appendingPathComponent("security-audit.md"), encoding: .utf8) else { throw ValidatorError("sp6a_security_audit_invalid") }
        do { try SecurityAuditValidator.validate(audit) } catch { throw ValidatorError("sp6a_security_audit_invalid") }
    }

    static func validateBindings(_ evidence: SP6AEvidence, directory: URL, repository: URL) throws {
        let environmentURL = repository.appendingPathComponent("evidence/phase0/environment.json")
        guard isRegular(environmentURL), let environment = try? Data(contentsOf: environmentURL) else { throw ValidatorError("sp6a_environment_missing") }
        do { try PrivacySafeEnvironmentValidator.validateJSON(environment); _ = try JSONDecoder().decode(EnvironmentEvidence.self, from: environment) }
        catch { throw ValidatorError("sp6a_environment_unsafe") }
        let hash = Canonical.sha256(environment)
        guard evidence.legs.allSatisfy({ $0.environmentSha256 == hash }) else { throw ValidatorError("sp6a_environment_hash_mismatch") }
        let keychain = try decodeKeychain(directory)
        guard let first = evidence.legs.first else { throw ValidatorError("sp6a_d9_evidence_mismatch") }
        try SP6ANamespaceValidator.validateIdentity(
            keychain, commitSha: first.runnerCommitSha, treeSha: first.runnerTreeSha,
            environmentSha256: hash
        )
        let d9Legs = evidence.legs.filter { $0.detectorID == "D9" }
        if keychain.candidates.isEmpty {
            guard d9Legs.count == 3, d9Legs.allSatisfy({ !$0.detectorAvailable && $0.verdict == .blocked }) else {
                throw ValidatorError("sp6a_d9_evidence_mismatch")
            }
        } else {
            guard d9Legs.filter({ $0.legID != "sp6a.keychainSelection" }).allSatisfy({ $0.detectorAvailable && $0.verdict == .pass }),
                  d9Legs.first(where: { $0.legID == "sp6a.keychainSelection" })?.verdict == .inconclusive else {
                throw ValidatorError("sp6a_d9_evidence_mismatch")
            }
        }
        for leg in evidence.legs where leg.verdict != .blocked {
            guard let path = SP6ADirectoryLayout.legArtifacts[leg.legID], leg.artifactPath == path,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(path)), leg.artifactSha256 == Canonical.sha256(data) else {
                throw ValidatorError("sp6a_artifact_binding_mismatch", leg.legID)
            }
        }
    }

    static func validateAtomicity(_ directory: URL, repository: URL, gitRepository: URL? = nil) throws {
        let citation: SP6AAtomicityCitation = try exactDecode(directory, "atomicity-citation.json", code: "sp6a_atomicity_citation_mismatch")
        guard citation == .expected else { throw ValidatorError("sp6a_atomicity_citation_mismatch") }
        let atomicityDirectory = repository.appendingPathComponent("evidence/phase0/shared-atomicity")
        let result = try AtomicityHistoricalValidator.validate(directory: atomicityDirectory, repository: gitRepository ?? repository)
        guard result.verdict == .pass, result.runnerCommitSha == citation.resultRunnerCommitSha, result.runnerTreeSha == citation.resultRunnerTreeSha,
              let bytes = try? Data(contentsOf: repository.appendingPathComponent(citation.artifactPath)), Canonical.sha256(bytes) == citation.artifactSha256 else {
            throw ValidatorError("sp6a_atomicity_citation_mismatch")
        }
        let git = GitRunner(repository: gitRepository ?? repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.text(["rev-parse", "\(citation.historicalCommitSha):\(citation.artifactPath)"]) == citation.historicalArtifactBlobSha,
              try git.text(["rev-parse", "\(citation.historicalCommitSha):\(citation.manifestPath)"]) == citation.historicalManifestBlobSha,
              Canonical.sha256(try git.run(["cat-file", "blob", "\(citation.historicalCommitSha):\(citation.artifactPath)"]).stdout) == citation.artifactSha256 else {
            throw ValidatorError("sp6a_atomicity_historical_blob_mismatch")
        }
    }

    static func validateHistoryAnchor(_ evidence: SP6AEvidence, directory: URL, repository: URL) throws {
        let keychain = try decodeKeychain(directory)
        try SP6ANamespaceValidator.validateHistoryContract(keychain)
        try SP6ALegacyHistoryAnchorValidator.validate(directory: directory, repository: repository)
        let anchor: SP6ANamespaceHistoryAnchor = try exactDecode(
            directory, SP6ANamespaceHistoryContract.metadataArtifactName,
            code: "sp6a_history_anchor_contract_invalid"
        )
        try SP6AHistoryAnchorValidator.validate(
            anchor: anchor, keychain: keychain, directory: directory,
            repository: repository, evidence: evidence
        )
    }

    static func validateRunner(_ evidence: SP6AEvidence, repository: URL) throws {
        guard Set(evidence.runnerSourceSha256.keys) == SP6ARunnerBinding.sourcePaths, let first = evidence.legs.first else { throw ValidatorError("sp6a_runner_source_set_mismatch") }
        let git = GitRunner(repository: repository, timeout: 5, executable: URL(fileURLWithPath: "/usr/bin/git"))
        guard try git.run(["cat-file", "-e", "\(first.runnerCommitSha)^{commit}"], acceptedStatuses: [0, 1, 128]).status == 0 else { throw ValidatorError("sp6a_runner_commit_missing") }
        guard try git.text(["rev-parse", "\(first.runnerCommitSha)^{tree}"]) == first.runnerTreeSha else { throw ValidatorError("sp6a_runner_tree_mismatch") }
        guard try git.run(["merge-base", "--is-ancestor", first.runnerCommitSha, "HEAD"], acceptedStatuses: [0, 1]).status == 0 else { throw ValidatorError("sp6a_runner_not_ancestor") }
        for path in SP6ARunnerBinding.sourcePaths.sorted() {
            let committed = try git.run(["cat-file", "blob", "\(first.runnerCommitSha):\(path)"]).stdout
            guard Canonical.sha256(committed) == evidence.runnerSourceSha256[path] else { throw ValidatorError("sp6a_runner_source_hash_mismatch", path) }
            guard try git.text(["status", "--porcelain=v1", "--untracked-files=all", "--", path]).isEmpty else { throw ValidatorError("sp6a_runner_source_dirty", path) }
        }
    }

    private static func validateCrypto(_ value: SP6ACryptoArtifact) throws {
        guard value.authenticatedHeaderFields == SP6AScenarios.authenticatedHeaderFields,
              value.tamperCases == SP6AScenarios.tamperCaseIDs,
              value.tamperResults.map(\.caseID) == SP6AScenarios.tamperCaseIDs else {
            throw ValidatorError("sp6a_crypto_case_set_mismatch")
        }
        let canonical: SP6ACryptoArtifact
        do { canonical = try SP6AScenarios.crypto() }
        catch { throw ValidatorError("sp6a_crypto_canonical_execution_failed") }
        guard value == canonical else { throw ValidatorError("sp6a_crypto_canonical_mismatch") }
    }

    private static func validateKeychain(_ value: SP6AKeychainArtifact) throws {
        guard SP6AKeychainNamespace.isValid(value.service) else { throw ValidatorError("sp6a_keychain_namespace_invalid") }
        try SP6ANamespaceValidator.validate(value)
        guard value.cleanupReceipt.service == value.service else { throw ValidatorError("sp6a_keychain_cleanup_namespace_mismatch") }
        guard !value.selectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.crossDeviceRestoreReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidatorError("sp6a_keychain_reason_missing")
        }
        guard value.cleanupReceipt.residueQueryStatus == -25300, value.cleanupReceipt.residueCount == 0 else {
            throw ValidatorError("sp6a_keychain_residue_invalid")
        }
        let expected = [
            "sp6a.keychainAfterFirstUnlock": "cku",
            "sp6a.keychainWhenUnlocked": "aku",
        ]
        let common = value.dataProtectionKeychain
            && !value.hostLockAttempted && !value.restartAttempted && value.crossDeviceRestoreVerdict == .blocked
            && !value.keyBytesPersistedOutsideKeychain
        let blocked = value.cleanupReceipt.preCleanupStatus == -34018 && value.cleanupReceipt.postCleanupStatus == -34018 && value.candidates.isEmpty
            && value.selection == nil && value.selectionVerdict == .blocked
        let available = value.cleanupReceipt.preCleanupStatus == -25300 && value.candidates.count == 2
            && Set(value.candidates.map(\.legID)) == Set(expected.keys)
            && value.candidates.allSatisfy { expected[$0.legID] == $0.accessibility && $0.addStatus == 0 && $0.readStatus == 0 && $0.attributesStatus == 0 && $0.deleteStatus == 0
                && $0.valueMatched && $0.accessibilityMatched && $0.synchronizableMatched && !$0.synchronizable && !$0.lifecycleEstablished }
            && value.selection == nil && value.selectionVerdict == .inconclusive && value.cleanupReceipt.postCleanupStatus == -25300
        guard common && (blocked || available) else { throw ValidatorError("sp6a_keychain_contract_invalid") }
    }

    private static func validateConclusion(_ directory: URL, evidence: SP6AEvidence) throws {
        guard evidence.verdict == .inconclusive || evidence.verdict == .blocked,
              let text = try? String(contentsOf: directory.appendingPathComponent("SP-6A-CONCLUSION.md"), encoding: .utf8),
              text.contains("Verdict: **\(evidence.verdict.rawValue)**"), text.contains("No Keychain accessibility candidate is selected"),
              text.contains("zero items"), text.contains("Cross-device restore is BLOCKED"),
              text.contains("no AlwaysThisDeviceOnly use"), text.contains("plaintext fallback"), !text.contains("Verdict: **PASS**") else {
            throw ValidatorError("sp6a_misleading_conclusion")
        }
    }

    private static func exactDecode<T: Codable>(_ directory: URL, _ name: String, code: String) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard isRegular(url), let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(T.self, from: data),
              let canonical = try? pretty(decoded), data == canonical else { throw ValidatorError(code) }
        return decoded
    }
    private static func decodeKeychain(_ directory: URL) throws -> SP6AKeychainArtifact {
        let url = directory.appendingPathComponent("keychain.json")
        guard isRegular(url), let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidatorError("sp6a_keychain_cleanup_invalid")
        }
        guard object["generationReceipt"] != nil else { throw ValidatorError("sp6a_keychain_generation_receipt_missing") }
        guard object["attemptHistory"] != nil else { throw ValidatorError("sp6a_keychain_attempt_history_missing") }
        guard let decoded = try? JSONDecoder().decode(SP6AKeychainArtifact.self, from: data),
              let canonical = try? pretty(decoded), data == canonical else {
            throw ValidatorError("sp6a_keychain_generation_receipt_invalid")
        }
        return decoded
    }
    private static func pretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func isRegular(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 8 * 1_024 * 1_024
    }
    private static func isSHA256(_ value: String) -> Bool { value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}

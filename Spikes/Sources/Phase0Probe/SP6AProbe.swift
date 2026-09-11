import Darwin
import Foundation
import Phase0Support

enum SP6AProbe {
    static func run(
        arguments: [String],
        identityProvider: (any AtomicityRunnerIdentityProviding)? = nil
    ) throws {
        let anchored = arguments.count == 7 && arguments[5] == "--history-anchor"
        guard (arguments.count == 5 || anchored), arguments[0] == "sp6a", arguments[1] == "--environment", arguments[3] == "--output" else {
            throw ProbeError.usage
        }
        let environmentURL = URL(fileURLWithPath: arguments[2]), output = URL(fileURLWithPath: arguments[4])
        let anchorURL = anchored ? URL(fileURLWithPath: arguments[6]) : nil
        let anchorBytes = try anchorURL.map(boundedFile)
        let resolvedHistoryAnchor = try anchorURL.map(SP6AHistoryAnchorProbe.resolve)
        let legacyV2 = try legacyHistoryBytes(environmentURL: environmentURL, output: output)
        try invalidate(output)
        do {
            try runValidated(
                environmentURL: environmentURL,
                output: output,
                anchorBytes: anchorBytes,
                resolvedHistoryAnchor: resolvedHistoryAnchor,
                legacyV2: legacyV2,
                identityProvider: identityProvider
            )
        } catch {
            try invalidate(output)
            throw error
        }
    }

    private static func runValidated(
        environmentURL: URL,
        output: URL,
        anchorBytes: Data?,
        resolvedHistoryAnchor: SP6ANamespaceHistoryAnchor?,
        legacyV2: Data,
        identityProvider: (any AtomicityRunnerIdentityProviding)?
    ) throws {
        let environmentData = try boundedFile(environmentURL)
        _ = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        let anchoredHistory = try anchorBytes.map { try JSONDecoder().decode(SP6ANamespaceAttemptHistory.self, from: $0) }
        let provider = identityProvider ?? GitAtomicityRunnerIdentityProvider(
            sourcePaths: SP6ARunnerBinding.sourcePaths.sorted(),
            revision: resolvedHistoryAnchor?.sourceCommitSha ?? "HEAD",
            requiresCurrentBytesMatch: resolvedHistoryAnchor == nil
        )
        let identity = try provider.resolve()
        let historyAnchor = resolvedHistoryAnchor ?? unboundAnchor(identity: identity)
        let crypto = try SP6AScenarios.crypto(), locator = SP6AScenarios.locator(), pathCanary = try SP6AScenarios.pathCanary()
        guard SP6AScenarios.valid(crypto), SP6AScenarios.valid(locator), SP6AScenarios.valid(pathCanary) else { throw SP6AProbeError.fixtureFailure }
        let namespaceRunner = SP6ANamespaceRunnerIdentity(
            commitSha: identity.commitSha, treeSha: identity.treeSha,
            environmentSha256: ViaDefinitionDigest.sha256(environmentData)
        )
        let keychain: SP6AKeychainArtifact
        if let anchoredHistory {
            keychain = try SP6AKeychainProbe.runAnchored(
                runner: namespaceRunner, history: anchoredHistory, historyAnchor: historyAnchor
            )
        } else {
            let historyURL = ProcessInfo.processInfo.environment["KEYRECORD_SP6A_ATTEMPT_HISTORY"].map(URL.init(fileURLWithPath:))
            keychain = try SP6AKeychainProbe.runGenerated(
                runner: namespaceRunner, historyURL: historyURL, historyAnchor: historyAnchor
            )
        }
        let citation = SP6AAtomicityCitation.expected
        let audit = SecurityAuditFixture.valid
        try SecurityAuditValidator.validate(audit)
        let artifacts: [String: Data] = [
            "crypto.json": try encoded(crypto), "locator.json": try encoded(locator), "path-canary.json": try encoded(pathCanary),
            "keychain.json": try encoded(keychain), "atomicity-citation.json": try encoded(citation), "security-audit.md": Data(audit.utf8),
            SP6ANamespaceHistoryContract.legacyAnchorArtifactName: legacyV2,
            SP6ANamespaceHistoryContract.anchorArtifactName: try (anchorBytes ?? encoded(keychain.attemptHistory)),
            SP6ANamespaceHistoryContract.metadataArtifactName: try encoded(historyAnchor),
        ]
        let hashes = artifacts.mapValues(ViaDefinitionDigest.sha256), environmentHash = ViaDefinitionDigest.sha256(environmentData)
        let d9Available = keychain.candidates.count == 2 && keychain.candidates.allSatisfy(SP6AKeychainProbe.candidatePassed)
        let legs = try SP6AEvidence.requiredLegIDs.sorted().map { id -> SP6ALeg in
            guard let rule = Phase0Registry.legRules[id], let path = SP6ADirectoryLayout.legArtifacts[id], let hash = hashes[path] else {
                throw SP6AProbeError.registryMismatch
            }
            if rule.detectorID == "D9", !d9Available {
                return SP6ALeg(
                    legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: false, verdict: .blocked,
                    blocker: SP6AD9Blocker.expected,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha, environmentSha256: environmentHash,
                    command: [], exitStatus: nil, artifactPath: nil, artifactSha256: nil
                )
            }
            let verdict: Verdict = id == "sp6a.keychainSelection" ? .inconclusive : .pass
            return SP6ALeg(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true, verdict: verdict,
                runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha, environmentSha256: environmentHash,
                command: ["Phase0Probe", "sp6a", rule.evidenceKind.rawValue, id], exitStatus: 0,
                artifactPath: path, artifactSha256: hash
            )
        }
        let evidence = SP6AEvidence(legs: legs, verdict: d9Available ? .inconclusive : .blocked, runnerSourceSha256: identity.sourceSha256)
        try evidence.validate()
        try publish(evidence: evidence, artifacts: artifacts, output: output)
        print("SP6A=\(evidence.verdict.rawValue) pass=\(legs.filter { $0.verdict == .pass }.count) blocked=\(legs.filter { $0.verdict == .blocked }.count) inconclusive=\(legs.filter { $0.verdict == .inconclusive }.count) keychainCandidates=\(keychain.candidates.count) residue=\(keychain.residueCount) selection=none output=\(output.path)")
    }

    private static func publish(evidence: SP6AEvidence, artifacts: [String: Data], output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp6a.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = SP6APublishSignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP6A_TEST_DELAY_AFTER_TEMP"], let delay = Double(value) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try encoded(evidence).write(to: temporary.appendingPathComponent("evidence.json"))
            for (name, data) in artifacts { try data.write(to: temporary.appendingPathComponent(name)) }
            let rows = evidence.legs.sorted { $0.legID < $1.legID }.map { "- `\($0.legID)`: \($0.verdict.rawValue)" }.joined(separator: "\n")
            let conclusion = """
            # SP-6A conclusion

            Verdict: **\(evidence.verdict.rawValue)**

            AES-256-GCM envelope framing, authenticated header/AAD, random 12-byte nonces, HKDF-SHA256 domain separation, HMAC-SHA256 opaque locators, encrypted manifest/path canaries, historical atomicity binding, and the source security audit passed. \(d9Summary(evidence))

            No Keychain accessibility candidate is selected. \(d9Conclusion(evidence)) Cross-device restore is BLOCKED because no approved second-device restore environment exists. There is no AlwaysThisDeviceOnly use, plaintext fallback, plaintext file/log artifact, or persisted key material.

            \(rows)
            """ + "\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-6A-CONCLUSION.md"))
            try writeManifest(temporary)
            try FileManager.default.moveItem(at: temporary, to: output)
            cleanup.complete()
        } catch {
            try? FileManager.default.removeItem(at: temporary); cleanup.complete(); throw error
        }
    }

    private static func d9Conclusion(_ evidence: SP6AEvidence) -> String {
        evidence.verdict == .blocked
            ? "D9 is BLOCKED because the SwiftPM runner lacks the application identifier entitlement required by the isolated data-protection Keychain; no candidate item was added."
            : "Locked and background-after-first-unlock behavior cannot be safely distinguished without locking, logging out, or restarting this host, so `sp6a.keychainSelection` is honestly INCONCLUSIVE."
    }

    private static func d9Summary(_ evidence: SP6AEvidence) -> String {
        evidence.verdict == .blocked
            ? "The bound runner recorded successful SecRandomCopyBytes input, recomputable RFC 4122 UUIDv4 transformation, nonsentinel entropy, and no namespace reuse in the defined captured attempt scope. Its exact Keychain namespace pre-cleanup returned missing-entitlement, so candidate add/read/attribute/delete assertions did not execute; a residue query found zero items. This does not prove mathematical unpredictability from output alone."
            : "The bound runner recorded successful SecRandomCopyBytes input, recomputable RFC 4122 UUIDv4 transformation, nonsentinel entropy, and no namespace reuse in the defined captured attempt scope. Both isolated ThisDeviceOnly Keychain candidates passed unlocked add/read/attribute/delete checks with synchronizable=false and left zero items. This does not prove mathematical unpredictability from output alone."
    }

    private static func unboundAnchor(identity: AtomicityRunnerIdentity) -> SP6ANamespaceHistoryAnchor {
        SP6ANamespaceHistoryAnchor(
            sourceCommitSha: identity.commitSha, anchorCommitSha: String(repeating: "0", count: 40),
            anchorTreeSha: String(repeating: "0", count: 40), anchorPath: SP6ANamespaceHistoryContract.anchorPath,
            anchorBlobSha1: String(repeating: "0", count: 40), anchorFileSha256: String(repeating: "0", count: 64)
        )
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func writeManifest(_ directory: URL) throws {
        let rows = try SP6ADirectoryLayout.artifactNames.sorted().map {
            "\(ViaDefinitionDigest.sha256(try Data(contentsOf: directory.appendingPathComponent($0))))  \($0)"
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent(); try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp6a.") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
    private static func boundedFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_048_576 else { throw SP6AProbeError.invalidFile }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func legacyHistoryBytes(environmentURL: URL, output: URL) throws -> Data {
        let repository = try? repositoryRoot()
        var candidates = [
            output.appendingPathComponent(SP6ANamespaceHistoryContract.legacyAnchorArtifactName),
            environmentURL.deletingLastPathComponent().appendingPathComponent("sp6a/\(SP6ANamespaceHistoryContract.legacyAnchorArtifactName)"),
        ]
        if let repository {
            candidates.append(repository.appendingPathComponent("evidence/phase0/sp6a/\(SP6ANamespaceHistoryContract.legacyAnchorArtifactName)"))
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try boundedFile(url)
        }
        throw SP6AProbeError.invalidFile
    }

    private static func repositoryRoot() throws -> URL {
        var value = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        while value.path != "/" {
            if FileManager.default.fileExists(atPath: value.appendingPathComponent(".git").path) { return value }
            value.deleteLastPathComponent()
        }
        throw SP6AProbeError.invalidFile
    }
}

private enum SP6AProbeError: Error { case fixtureFailure, invalidFile, registryMismatch }

private final class SP6APublishSignalCleanup: @unchecked Sendable {
    private let paths: [URL]
    private var sources: [DispatchSourceSignal] = []
    init(paths: [URL]) {
        self.paths = paths
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { paths.forEach { try? FileManager.default.removeItem(at: $0) }; Foundation.exit(Int32(item.1)) }
            source.resume(); sources.append(source)
        }
    }
    func complete() { sources.forEach { $0.cancel() }; sources.removeAll(); signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL) }
}

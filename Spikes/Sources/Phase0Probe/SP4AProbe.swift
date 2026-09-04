import Darwin
import Foundation
import Phase0Support

enum SP4AProbe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(sourcePaths: SP4ARunnerBinding.sourcePaths.sorted())
    ) throws {
        guard arguments.count == 5, arguments[0] == "sp4a", arguments[1] == "--environment", arguments[3] == "--output" else {
            throw ProbeError.usage
        }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try boundedFile(environmentURL, maximum: 1_048_576)
        _ = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        let identity = try identityProvider.resolve()
        let repository = try repositoryRoot()

        let v2 = try SP4AFixtureScenarios.schemaArtifact(repository: repository, source: ViaDefinitionSources.v2, expected: .v2)
        let v3 = try SP4AFixtureScenarios.schemaArtifact(repository: repository, source: ViaDefinitionSources.v3, expected: .v3)
        let opaque = try SP4AFixtureScenarios.opaqueArtifact()
        let bounds = try SP4AFixtureScenarios.boundsArtifact()
        let facts = try SP4AFixtureScenarios.sourceFacts(repository: repository)
        guard SP4AFixtureScenarios.validates(opaque), SP4AFixtureScenarios.validates(bounds) else {
            throw SP4AProbeError.fixtureAssertionFailed
        }
        let artifacts = [
            "v2-schema.json": try encoded(v2),
            "v3-schema.json": try encoded(v3),
            "opaque-preservation.json": try encoded(opaque),
            "bounds.json": try encoded(bounds),
            "source-facts.json": try encoded(facts),
        ]
        let hashes = artifacts.mapValues(ViaDefinitionDigest.sha256)
        let environmentHash = ViaDefinitionDigest.sha256(environmentData)
        let legs = try SP4AEvidence.requiredLegIDs.sorted().map { id -> SP4ALeg in
            guard let rule = Phase0Registry.legRules[id], let path = SP4ADirectoryLayout.legArtifacts[id] else {
                throw SP4AProbeError.registryMismatch
            }
            return SP4ALeg(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true,
                verdict: .pass, blocker: nil, runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, command: ["Phase0Probe", "sp4a", "fixture", id], exitStatus: 0,
                artifactPath: path, artifactSha256: hashes[path]
            )
        }
        let evidence = SP4AEvidence(legs: legs, verdict: aggregate(legs.map(\.verdict)), runnerSourceSha256: identity.sourceSha256)
        try evidence.validate()
        try publish(evidence: evidence, artifacts: artifacts, facts: facts, output: output)
        print("SP4A=\(evidence.verdict.rawValue) pass=\(legs.count) definitionOnly=true output=\(output.path)")
    }

    private static func publish(
        evidence: SP4AEvidence,
        artifacts: [String: Data],
        facts: SP4ASourceFactsArtifact,
        output: URL
    ) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp4a.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = SP4ASignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP4A_TEST_DELAY_AFTER_TEMP"], let delay = Double(value) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try encoded(evidence).write(to: temporary.appendingPathComponent("evidence.json"))
            for (name, data) in artifacts { try data.write(to: temporary.appendingPathComponent(name)) }
            let rows = evidence.legs.sorted { $0.legID < $1.legID }.map { "- `\($0.legID)`: \($0.verdict.rawValue) (`\($0.artifactPath ?? "missing")`)" }.joined(separator: "\n")
            let citations = facts.citations.map { "- `\($0.path)` SHA-256 `\($0.sha256)`" }.joined(separator: "\n")
            let conclusion = """
            # SP-4A conclusion

            Verdict: **\(evidence.verdict.rawValue)**

            This definition-only fixture result identifies the pinned VIA V2 and V3 definition schemas. It proves bounded parsing and byte-identical preservation outside the selected `name` scalar, including opaque unknown and macro subtrees. It makes no device-protocol, keycode-dialect, layout-backup, official-importer, HID, EEPROM, or device-behavior claim.

            Official definitions are repository-served; manufacturer-provided custom definitions use VIA's Design tab, as stated by the pinned sources below.

            \(rows)

            ## Source citations

            \(citations)
            """ + "\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-4A-CONCLUSION.md"))
            try writeManifest(temporary)
            try FileManager.default.moveItem(at: temporary, to: output)
            cleanup.complete()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            cleanup.complete()
            throw error
        }
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func writeManifest(_ directory: URL) throws {
        let rows = try SP4ADirectoryLayout.artifactNames.sorted().map { name in
            "\(ViaDefinitionDigest.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))  \(name)"
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp4a.") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
    private static func boundedFile(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximum else {
            throw SP4AProbeError.invalidFile
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private static func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) { return candidate }
            candidate.deleteLastPathComponent()
        }
        throw SP4AProbeError.repositoryNotFound
    }
    private static func aggregate(_ verdicts: [Verdict]) -> Verdict {
        verdicts.max { precedence($0) < precedence($1) } ?? .blocked
    }
    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

private enum SP4AProbeError: Error { case fixtureAssertionFailed, invalidFile, registryMismatch, repositoryNotFound }

private final class SP4ASignalCleanup: @unchecked Sendable {
    private let paths: [URL]
    private var sources: [DispatchSourceSignal] = []
    init(paths: [URL]) {
        self.paths = paths
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { [paths] in
                paths.forEach { try? FileManager.default.removeItem(at: $0) }
                Foundation.exit(Int32(item.1))
            }
            source.resume(); sources.append(source)
        }
    }
    func complete() {
        sources.forEach { $0.cancel() }; sources.removeAll()
        signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL)
    }
}

import Darwin
import Foundation
import Phase0Support

enum SP5AProbe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(sourcePaths: SP5ARunnerBinding.sourcePaths.sorted())
    ) throws {
        guard arguments.count == 5, arguments[0] == "sp5a", arguments[1] == "--environment", arguments[3] == "--output" else {
            throw ProbeError.usage
        }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try boundedFile(environmentURL, maximum: 1_048_576)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        let identity = try identityProvider.resolve()
        let repository = try repositoryRoot()
        let roundTrip = try SP5AFixtureScenarios.roundTrip(repository: repository)
        let uid = try SP5AFixtureScenarios.uidBinding(repository: repository)
        let bounds = try SP5AFixtureScenarios.bounds()
        let facts = try SP5AFixtureScenarios.sourceFacts(repository: repository)
        guard SP5AFixtureScenarios.validates(roundTrip), SP5AFixtureScenarios.validates(uid), SP5AFixtureScenarios.validates(bounds) else {
            throw SP5AProbeError.fixtureAssertionFailed
        }
        let artifacts = [
            "round-trip.json": try encoded(roundTrip),
            "uid-binding.json": try encoded(uid),
            "bounds.json": try encoded(bounds),
            "format-facts.json": try encoded(facts),
        ]
        let hashes = artifacts.mapValues(ViaDefinitionDigest.sha256)
        let environmentHash = ViaDefinitionDigest.sha256(environmentData)
        let vialAbsent = environment.applications.first(where: { $0.name == "Vial" })?.status == .absent
        guard vialAbsent else { throw SP5AProbeError.liveImporterExecutionForbidden }
        let legs = try SP5AEvidence.requiredLegIDs.sorted().map { id -> SP5ALeg in
            guard let rule = Phase0Registry.legRules[id] else { throw SP5AProbeError.registryMismatch }
            if id == "sp5a.importer" {
                return SP5ALeg(
                    legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: false,
                    verdict: .blocked,
                    blocker: SP1Blocker(
                        blockedBy: "vial_gui_absent", detectCommand: ["environment-inventory", "Vial"],
                        prerequisite: "supported official Vial GUI installed with a matching approved device",
                        unblockAction: "Install and authorize Vial only under a separately approved live-import procedure, then import the bound artifact without KeyRecord device writes"
                    ),
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha, environmentSha256: environmentHash,
                    command: [], exitStatus: nil, artifactPath: nil, artifactSha256: nil
                )
            }
            guard let path = SP5ADirectoryLayout.legArtifacts[id] else { throw SP5AProbeError.registryMismatch }
            return SP5ALeg(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID, detectorAvailable: true,
                verdict: .pass, blocker: nil, runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, command: ["Phase0Probe", "sp5a", rule.evidenceKind.rawValue, id],
                exitStatus: 0, artifactPath: path, artifactSha256: hashes[path]
            )
        }
        let evidence = SP5AEvidence(legs: legs, verdict: aggregate(legs.map(\.verdict)), runnerSourceSha256: identity.sourceSha256)
        try evidence.validate()
        try publish(evidence: evidence, artifacts: artifacts, facts: facts, output: output)
        print("SP5A=\(evidence.verdict.rawValue) pass=\(legs.filter { $0.verdict == .pass }.count) blocked=\(legs.filter { $0.verdict == .blocked }.count) importerExecuted=false output=\(output.path)")
    }

    private static func publish(evidence: SP5AEvidence, artifacts: [String: Data], facts: SP5AFormatFactsArtifact, output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp5a.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = SP5ASignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP5A_TEST_DELAY_AFTER_TEMP"], let delay = Double(value) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try encoded(evidence).write(to: temporary.appendingPathComponent("evidence.json"))
            for (name, data) in artifacts { try data.write(to: temporary.appendingPathComponent(name)) }
            let rows = evidence.legs.sorted { $0.legID < $1.legID }.map { leg in
                leg.verdict == .blocked
                    ? "- `\(leg.legID)`: BLOCKED (`\(leg.blocker?.blockedBy ?? "missing")`)"
                    : "- `\(leg.legID)`: PASS (`\(leg.artifactPath ?? "missing")`)"
            }.joined(separator: "\n")
            let citations = facts.citations.map { "- `\($0.path)` SHA-256 `\($0.sha256)`" }.joined(separator: "\n")
            let conclusion = """
            # SP-5A conclusion

            Verdict: **\(evidence.verdict.rawValue)**

            The exact deterministic synthetic `.vil` fixture proves only bounded version-1 parsing, one selected layout-slot raw splice, byte-identical preservation everywhere else including unsupported advanced fields, and UID mismatch rejection. It is synthetic, not sourced or live, and does not prove official-importer, device-compatibility, HID, firmware, or real-device behavior.

            Official Vial GUI import remains **BLOCKED** because D7 is false: the recorded environment inventory reports Vial absent. No GUI was launched and no device or HID interaction occurred.

            `vial.json` is a firmware-embedded keyboard definition consumed by the Vial QMK definition generator. It is not interchangeable with a `.vil` keymap export or a VIA definition.

            \(rows)

            ## Pinned source citations

            \(citations)
            """ + "\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-5A-CONCLUSION.md"))
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
        let rows = try SP5ADirectoryLayout.artifactNames.sorted().map { name in
            "\(ViaDefinitionDigest.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))  \(name)"
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp5a.") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
    private static func boundedFile(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximum else {
            throw SP5AProbeError.invalidFile
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private static func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) { return candidate }
            candidate.deleteLastPathComponent()
        }
        throw SP5AProbeError.repositoryNotFound
    }
    private static func aggregate(_ verdicts: [Verdict]) -> Verdict {
        verdicts.max { precedence($0) < precedence($1) } ?? .blocked
    }
    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

private enum SP5AProbeError: Error { case fixtureAssertionFailed, invalidFile, liveImporterExecutionForbidden, registryMismatch, repositoryNotFound }

private final class SP5ASignalCleanup: @unchecked Sendable {
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

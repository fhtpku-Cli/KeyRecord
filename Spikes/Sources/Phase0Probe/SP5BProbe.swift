import Darwin
import Foundation
import Phase0Support

enum SP5BProbe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(sourcePaths: SP5BRunnerBinding.sourcePaths.sorted())
    ) throws {
        guard arguments.count == 5, arguments[0] == "sp5b", arguments[1] == "--environment",
              arguments[3] == "--output" else { throw ProbeError.usage }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try bounded(environmentURL, maximum: 1_048_576)
        try PrivacySafeEnvironmentValidator.validateJSON(environmentData)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        guard environment.applications.first(where: { $0.name == "Vial" })?.status == .absent,
              !environment.hidSummary.devices.contains(where: { $0.product?.contains("Vial-approved") == true }) else {
            throw SP5BProbeError.liveExecutionForbidden
        }
        let identity = try identityProvider.resolve()
        let repository = try repositoryRoot()
        let facts = try SP5BScenarios.sourceFacts(repository: repository)
        let replay = try SP5BScenarios.replay(repository: repository)
        let deny = try SP5BScenarios.denyMutation(repository: repository)
        guard SP5BScenarios.validates(facts), SP5BScenarios.validates(replay),
              SP5BScenarios.validates(deny) else { throw SP5BProbeError.scenarioAssertionFailed }
        let artifacts = [
            "source-facts.json": try encoded(facts), "replay.json": try encoded(replay),
            "deny-mutation.json": try encoded(deny),
        ]
        let hashes = artifacts.mapValues(ViaDefinitionDigest.sha256)
        let environmentHash = ViaDefinitionDigest.sha256(environmentData)
        let legs = try SP5BEvidence.requiredLegIDs.sorted().map { id -> SP5BLeg in
            guard let rule = Phase0Registry.legRules[id] else { throw SP5BProbeError.registryMismatch }
            if let artifact = SP5BDirectoryLayout.legArtifacts[id] {
                return .init(
                    legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                    detectorAvailable: true, verdict: .pass, blocker: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash,
                    command: ["Phase0Probe", "sp5b", rule.evidenceKind.rawValue, id], exitStatus: 0,
                    artifactPath: artifact, artifactSha256: hashes[artifact]
                )
            }
            return .init(
                legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                detectorAvailable: false, verdict: .blocked,
                blocker: SP1Blocker(
                    blockedBy: "approved_vial_device_capture_absent",
                    detectCommand: ["environment-inventory", "approved-vial-device"],
                    prerequisite: "an explicitly approved Vial keyboard, capture authorization, and reviewed non-changing query procedure",
                    unblockAction: "Under separate approval, capture the same whitelist-constrained report bytes on that keyboard without unlock or device writes"
                ), runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, command: [], exitStatus: nil,
                artifactPath: nil, artifactSha256: nil
            )
        }
        let evidence = SP5BEvidence(legs: legs, verdict: .blocked, runnerSourceSha256: identity.sourceSha256)
        try evidence.validate()
        try publish(evidence, artifacts: artifacts, output: output)
        print("SP5B=BLOCKED pass=3 blocked=1 replayReports=\(replay.reportCount) transportCallsForRejected=0 liveCapture=false deviceAccess=false output=\(output.path)")
    }

    private static func publish(_ evidence: SP5BEvidence, artifacts: [String: Data], output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp5b.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = SP5BSignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let raw = ProcessInfo.processInfo.environment["KEYRECORD_SP5B_TEST_DELAY_AFTER_TEMP"], let delay = Double(raw) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try encoded(evidence).write(to: temporary.appendingPathComponent("evidence.json"))
            for (name, data) in artifacts { try data.write(to: temporary.appendingPathComponent(name)) }
            let conclusion = """
            # SP-5B conclusion

            Verdict: **BLOCKED**

            Pinned source and the exact deterministic synthetic recorded-response fixture prove only whitelist-constrained non-changing queries and replay reconstruction of protocol version, UID, firmware-embedded definition pages, and keymap. Outbound HID reports are not literally read-only, and synthetic replay does not prove device-side behavior or device compatibility.

            The closed public report API has only protocolVersion, uid, definition, and keymapRead cases with no raw-byte initializer. Deny-all source and fake-transport tests make unknown operations and unlock, reset, bootloader, EEPROM, macro, encoder, settings, dynamic-entry, and keymap writes unrepresentable; rejected attempts made zero transport calls.

            Live HID capture remains **BLOCKED** because the exact environment inventory has no approved Vial device and Vial is absent. No IOHID API was called, no device was enumerated or opened, no GUI was launched, and no report was sent to a real device.
            """ + "\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-5B-CONCLUSION.md"))
            try writeManifest(temporary)
            try FileManager.default.moveItem(at: temporary, to: output)
            cleanup.complete()
        } catch {
            try? FileManager.default.removeItem(at: temporary); cleanup.complete(); throw error
        }
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
    }
    private static func writeManifest(_ directory: URL) throws {
        let rows = try SP5BDirectoryLayout.artifactNames.sorted().map {
            "\(ViaDefinitionDigest.sha256(try Data(contentsOf: directory.appendingPathComponent($0))))  \($0)"
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp5b.") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
    private static func bounded(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= maximum else { throw SP5BProbeError.invalidFile }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private static func repositoryRoot() throws -> URL {
        var value = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        while value.path != "/" {
            if FileManager.default.fileExists(atPath: value.appendingPathComponent(".git").path) { return value }
            value.deleteLastPathComponent()
        }
        throw SP5BProbeError.repositoryNotFound
    }
}

private enum SP5BProbeError: Error { case invalidFile, liveExecutionForbidden, registryMismatch, repositoryNotFound, scenarioAssertionFailed }

private final class SP5BSignalCleanup: @unchecked Sendable {
    private let paths: [URL]
    private var sources: [DispatchSourceSignal] = []
    init(paths: [URL]) {
        self.paths = paths
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { [paths] in paths.forEach { try? FileManager.default.removeItem(at: $0) }; Foundation.exit(Int32(item.1)) }
            source.resume(); sources.append(source)
        }
    }
    func complete() {
        sources.forEach { $0.cancel() }; sources.removeAll()
        signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL)
    }
}

import Darwin
import Foundation
import Phase0Support

enum SP4BProbe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(sourcePaths: SP4BRunnerBinding.sourcePaths.sorted())
    ) throws {
        guard arguments.count == 5, arguments[0] == "sp4b", arguments[1] == "--environment", arguments[3] == "--output" else {
            throw ProbeError.usage
        }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try boundedFile(environmentURL, maximum: 1_048_576)
        try PrivacySafeEnvironmentValidator.validateJSON(environmentData)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        guard environment.applications.first(where: { $0.name == "VIA" })?.status == .absent else {
            throw SP4BProbeError.liveImporterExecutionForbidden
        }
        guard !environment.hidSummary.devices.contains(where: { $0.product?.contains("VIA-approved") == true }) else {
            throw SP4BProbeError.liveDeviceExecutionForbidden
        }
        let identity = try identityProvider.resolve()
        let repository = try repositoryRoot()
        let roundTrip = try SP4BScenarios.roundTrip(repository: repository)
        let bounds = try SP4BScenarios.bounds()
        let axes = try SP4BScenarios.axes(repository: repository)
        let facts = try SP4BScenarios.sourceFacts(repository: repository)
        guard SP4BScenarios.validates(roundTrip), bounds.results.count == 4,
              bounds.results.allSatisfy(\.exactAccepted), axes.axes.count == 5,
              axes.axes.allSatisfy({ ($0.evidence != nil) != ($0.blocker != nil) }) else {
            throw SP4BProbeError.fixtureAssertionFailed
        }
        let artifacts = [
            "round-trip.json": try encoded(roundTrip), "bounds.json": try encoded(bounds),
            "axes.json": try encoded(axes), "source-facts.json": try encoded(facts),
        ]
        let hashes = artifacts.mapValues(ViaDefinitionDigest.sha256)
        let environmentHash = ViaDefinitionDigest.sha256(environmentData)
        let legs = try SP4BEvidence.requiredLegIDs.sorted().map { id -> SP4BLeg in
            guard let rule = Phase0Registry.legRules[id] else { throw SP4BProbeError.registryMismatch }
            if let path = SP4BDirectoryLayout.legArtifacts[id] {
                return SP4BLeg(
                    legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
                    detectorAvailable: true, verdict: .pass, blocker: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, command: ["Phase0Probe", "sp4b", rule.evidenceKind.rawValue, id],
                    exitStatus: 0, artifactPath: path, artifactSha256: hashes[path]
                )
            }
            return blockedLeg(id: id, rule: rule, identity: identity, environmentHash: environmentHash)
        }
        let evidence = SP4BEvidence(legs: legs, verdict: .blocked, runnerSourceSha256: identity.sourceSha256)
        try evidence.validate()
        try publish(evidence: evidence, artifacts: artifacts, output: output)
        print("SP4B=BLOCKED pass=2 blocked=3 importerExecuted=false deviceAccess=false deploymentExported=false output=\(output.path)")
    }

    private static func blockedLeg(
        id: String, rule: Phase0Registry.LegRule, identity: AtomicityRunnerIdentity, environmentHash: String
    ) -> SP4BLeg {
        let blocker: SP1Blocker
        switch id {
        case "sp4b.deviceProtocol":
            blocker = SP1Blocker(
                blockedBy: "approved_via_device_absent", detectCommand: ["environment-inventory", "approved-via-device"],
                prerequisite: "an explicitly approved VIA-capable keyboard and separately authorized non-mutating protocol procedure",
                unblockAction: "Inventory and approve a VIA keyboard, then capture protocol without writing the device"
            )
        case "sp4b.keycodeDialect":
            blocker = SP1Blocker(
                blockedBy: "firmware_keycode_dictionary_unobserved", detectCommand: ["environment-inventory", "approved-via-device"],
                prerequisite: "an approved VIA device with observed firmware protocol and QMK keycode version",
                unblockAction: "Observe the approved device protocol and firmware-selected keycode dictionary without device writes"
            )
        default:
            blocker = SP1Blocker(
                blockedBy: "via_app_absent_and_approved_device_absent", detectCommand: ["environment-inventory", "VIA"],
                prerequisite: "official VIA app installed plus an explicitly approved matching keyboard under a separate import procedure",
                unblockAction: "Install official VIA and approve a matching device, then test import separately without exporting a deployment"
            )
        }
        return SP4BLeg(
            legID: id, evidenceKind: rule.evidenceKind, detectorID: rule.detectorID,
            detectorAvailable: false, verdict: .blocked, blocker: blocker,
            runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
            environmentSha256: environmentHash, command: [], exitStatus: nil, artifactPath: nil, artifactSha256: nil
        )
    }

    private static func publish(evidence: SP4BEvidence, artifacts: [String: Data], output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp4b.\(UUID().uuidString).tmp", isDirectory: true)
        let cleanup = SP4BSignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let raw = ProcessInfo.processInfo.environment["KEYRECORD_SP4B_TEST_DELAY_AFTER_TEMP"], let delay = Double(raw) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try encoded(evidence).write(to: temporary.appendingPathComponent("evidence.json"))
            for (name, bytes) in artifacts { try bytes.write(to: temporary.appendingPathComponent(name)) }
            let conclusion = """
            # SP-4B conclusion

            Verdict: **BLOCKED**

            The exact deterministic synthetic `.layout.json` fixture proves only bounded parsing and one selected-slot raw splice with every non-selected byte and opaque macro/encoder subtree preserved. It is synthetic, not sourced, pinned, or live. The layout artifact is not claimed as a stable interchange standard and no deployment was exported.

            Five independent axes are recorded with evidence XOR a complete blocker: definition schema PASS from SP-4A evidence; layout format PASS from the exact synthetic fixture; device protocol, firmware-selected keycode dialect, and official importer compatibility BLOCKED. Protocol and keycode dictionaries are firmware-dependent. VIA protocol 13 is not Vial-GUI compatible.

            Official VIA import and device behavior remain **BLOCKED** because the exact environment inventory reports VIA absent and no approved VIA device. No GUI was launched and no HID/device access or write occurred.
            """ + "\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-4B-CONCLUSION.md"))
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
        let rows = try SP4BDirectoryLayout.artifactNames.sorted().map { name in
            "\(ViaDefinitionDigest.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))  \(name)"
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }
    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp4b.") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
    private static func boundedFile(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= maximum else { throw SP4BProbeError.invalidFile }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private static func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) { return candidate }
            candidate.deleteLastPathComponent()
        }
        throw SP4BProbeError.repositoryNotFound
    }
}

private enum SP4BProbeError: Error {
    case fixtureAssertionFailed, invalidFile, liveDeviceExecutionForbidden
    case liveImporterExecutionForbidden, registryMismatch, repositoryNotFound
}

private final class SP4BSignalCleanup: @unchecked Sendable {
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

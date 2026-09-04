import CoreGraphics
import Darwin
import Foundation
import Phase0Support

enum SP1Probe {
    static func run(arguments: [String], identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider()) throws {
        guard arguments.count == 5, arguments[0] == "sp1", arguments[1] == "--environment", arguments[3] == "--output" else { throw ProbeError.usage }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try boundedFile(environmentURL)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        let identity = try identityProvider.resolve()
        let environmentHash = AtomicityDigest.sha256(environmentData)
        let karabinerInstalled = environment.applications.contains { $0.name == "Karabiner-Elements" && $0.status == .installed }
        let d1 = environment.guiSession.status == .available && environment.listenEventAccess == .available
            && environment.guiSession.tapCreate == .available
        let d2 = d1 && karabinerInstalled

        if d1 { try preflightListenOnlyCandidates() }
        let matrixBlocker = SP1Blocker(
            blockedBy: [d1 ? nil : "input_monitoring_denied", karabinerInstalled ? nil : "karabiner_absent"].compactMap { $0 }.joined(separator: ";"),
            detectCommand: ["CGPreflightListenEventAccess", "environment.json applications[name=Karabiner-Elements]"],
            prerequisite: "Input Monitoring granted and a separately authorized supported Karabiner installation with controlled OFF/ON mapping",
            unblockAction: "Grant Input Monitoring and install/configure Karabiner only through separate user-authorized actions, then rerun both OFF/ON legs"
        )
        let d1Blocker = SP1Blocker(
            blockedBy: "input_monitoring_denied",
            detectCommand: ["CGPreflightListenEventAccess", "environment.json guiSession.tapCreate"],
            prerequisite: "GUI session with Input Monitoring already granted for this executable",
            unblockAction: "Grant Input Monitoring outside this probe, then rerun; this probe never prompts"
        )
        let legs = SP1Evidence.requiredLegIDs.sorted().map { legID -> SP1Leg in
            let isMatrix = legID == "sp1.tap.session.matrix" || legID == "sp1.tap.annotated.matrix"
            let available = isMatrix ? d2 : d1
            return SP1Leg(
                legID: legID, verdict: available ? .inconclusive : .blocked, detectorAvailable: available,
                blocker: available ? nil : (isMatrix ? matrixBlocker : d1Blocker), identity: nil,
                runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, artifactSha256: available ? AtomicityDigest.sha256(Data(legID.utf8)) : nil,
                matrix: nil, aggregateCount: available ? 0 : nil
            )
        }
        let report = SP1Evidence(
            selectedTapIdentity: nil, legs: legs,
            verdict: legs.contains(where: { $0.verdict == .blocked }) ? .blocked : .inconclusive,
            g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: identity.sourceSha256
        )
        try report.validate()
        try publish(report: report, output: output)
        print("SP1=\(report.verdict.rawValue) selectedTapIdentity=NONE g0=OPEN output=\(output.path)")
    }

    private static func preflightListenOnlyCandidates() throws {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        for tapType in [CGEventTapLocation.cgSessionEventTap, .cgAnnotatedSessionEventTap] {
            guard let tap = CGEvent.tapCreate(tap: tapType, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: sp1Callback, userInfo: nil) else {
                throw SP1ProbeError.listenOnlyTapUnavailable
            }
            CFMachPortInvalidate(tap)
        }
    }

    private static func publish(report: SP1Evidence, output: URL) throws {
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".sp1.\(UUID().uuidString).tmp", isDirectory: true)
        let signalCleanup = SP1SignalCleanup(paths: [temporary, output])
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            if let value = ProcessInfo.processInfo.environment["KEYRECORD_SP1_TEST_DELAY_AFTER_TEMP"], let delay = Double(value) {
                Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
            }
            try writeJSON(report, to: temporary.appendingPathComponent("evidence.json"))
            var synthetic = InputObservationState()
            for kind in InputEventKind.allCases {
                try synthetic.observe(.init(kind: kind, keyCode: 4, isAutoRepeat: false, marker: ProductSyntheticMarker.value))
            }
            try writeJSON(SP1SyntheticArtifact(records: synthetic.productStampedRecords), to: temporary.appendingPathComponent("product-stamped-synthetic.json"))
            try writeJSON(SP1LiveAggregateArtifact(systemShortcutObservedCount: 0, unmarkedObservedCount: 0), to: temporary.appendingPathComponent("live-aggregate-counts.json"))
            try Data(("# O7 addendum\n\n" + O7Boundary.guarantee + "\n\nNo source-field exclusion beyond aggregate observation is claimed.\n").utf8)
                .write(to: temporary.appendingPathComponent("O7-ADDENDUM.md"))
            let blockers = report.legs.map { "- `\($0.legID)`: \($0.verdict.rawValue) (`\($0.blocker?.blockedBy ?? "executed")`)" }.joined(separator: "\n")
            let conclusion = "# SP-1 conclusion\n\nVerdict: **\(report.verdict.rawValue)**\n\nSelected tap identity: **NONE**\n\nG0: **OPEN**\n\nHID tap is unavailable to a normal non-root menu-bar process and was not attempted. Session and annotated-session candidates are listen-only. No live assertion was inferred from an unexecuted check.\n\n\(blockers)\n"
            try Data(conclusion.utf8).write(to: temporary.appendingPathComponent("SP-1-CONCLUSION.md"))
            try writeManifest(in: temporary)
            try FileManager.default.moveItem(at: temporary, to: output)
            signalCleanup.complete()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            signalCleanup.complete()
            throw error
        }
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); try data.write(to: url)
    }

    private static func writeManifest(in directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "manifest.sha256" }.sorted()
        let lines = try names.map { name in "\(AtomicityDigest.sha256(try Data(contentsOf: directory.appendingPathComponent(name))))  \(name)" }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("manifest.sha256"))
    }

    private static func boundedFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_048_576 else { throw SP1ProbeError.invalidEnvironment }
        return try Data(contentsOf: url)
    }

    private static func invalidate(_ output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let parent = output.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) || FileManager.default.fileExists(atPath: parent.deletingLastPathComponent().path) else {
            throw SP1ProbeError.invalidOutput
        }
        if FileManager.default.fileExists(atPath: parent.path) {
            for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) where name.hasPrefix(".sp1.") && name.hasSuffix(".tmp") {
                try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
            }
        }
    }
}

private enum SP1ProbeError: Error { case invalidEnvironment, invalidOutput, listenOnlyTapUnavailable }

private final class SP1SignalCleanup: @unchecked Sendable {
    private let paths: [URL]
    private var sources: [DispatchSourceSignal] = []
    init(paths: [URL]) {
        self.paths = paths
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { [paths] in
                for path in paths { try? FileManager.default.removeItem(at: path) }
                Foundation.exit(Int32(item.1))
            }
            source.resume()
            sources.append(source)
        }
    }
    func complete() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGHUP, SIG_DFL)
    }
}

private func sp1Callback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    Unmanaged.passUnretained(event)
}

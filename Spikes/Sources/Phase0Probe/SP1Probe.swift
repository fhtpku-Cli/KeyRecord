import CoreGraphics
import Darwin
import Foundation
import Phase0Support

protocol SP1PreflightProviding: Sendable {
    func preflightListenOnlyCandidates() throws
}

struct CoreGraphicsSP1PreflightProvider: SP1PreflightProviding {
    func preflightListenOnlyCandidates() throws {
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
}

enum SP1Probe {
    static func run(
        arguments: [String],
        identityProvider: any AtomicityRunnerIdentityProviding = GitAtomicityRunnerIdentityProvider(sourcePaths: SP1RunnerBinding.sourcePaths.sorted()),
        preflightProvider: any SP1PreflightProviding = CoreGraphicsSP1PreflightProvider()
    ) throws {
        guard arguments.count == 5, arguments[0] == "sp1", arguments[1] == "--environment", arguments[3] == "--output" else { throw ProbeError.usage }
        let environmentURL = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[4])
        try invalidate(output)
        let environmentData = try boundedFile(environmentURL)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: environmentData)
        let identity = try identityProvider.resolve()
        let environmentHash = AtomicityDigest.sha256(environmentData)
        let karabinerInstalled = environment.applications.contains { $0.name == "Karabiner-Elements" && $0.status == .installed }
        let d1Failure = SP1CanonicalBlockers.d1Failure(for: environment)
        let d1 = d1Failure == nil

        if d1 { try preflightProvider.preflightListenOnlyCandidates() }
        let synthetic = d1 ? try SP1SyntheticScenarios.run() : nil
        let syntheticBytes = try synthetic?.canonicalJSON() ?? SP1CanonicalArtifacts.v1Synthetic
        let syntheticHash = AtomicityDigest.sha256(syntheticBytes)
        let liveBytes = try canonicalJSON(SP1LiveAggregateArtifact(systemShortcutObservedCount: 0, unmarkedObservedCount: 0))

        let matrixBlocker = !d1
            ? SP1CanonicalBlockers.legacyV1Matrix(environment: environment, karabinerAbsent: !karabinerInstalled)
            : karabinerInstalled ? SP1CanonicalBlockers.v2MatrixExecutionNotImplemented : SP1CanonicalBlockers.v2KarabinerAbsent
        let assertions = Dictionary(uniqueKeysWithValues: (synthetic?.assertions ?? []).map { ($0.legID, $0.passed) })
        let legs = SP1Evidence.requiredLegIDs.sorted().map { legID -> SP1Leg in
            if !d1 {
                guard let d1Failure else { preconditionFailure("D1 failure blocker missing") }
                let legBlocker = Self.matrixLegIDs.contains(legID) ? matrixBlocker : d1Failure
                return SP1Leg(
                    legID: legID, verdict: .blocked, detectorAvailable: false, blocker: legBlocker, identity: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: nil, matrix: nil, aggregateCount: nil
                )
            }
            if let passed = assertions[legID] {
                return SP1Leg(
                    legID: legID, verdict: passed ? .pass : .fail, detectorAvailable: true, blocker: nil, identity: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: syntheticHash, matrix: nil, aggregateCount: nil
                )
            }
            if legID == "sp1.systemShortcut" {
                return SP1Leg(
                    legID: legID, verdict: .blocked, detectorAvailable: false,
                    blocker: SP1CanonicalBlockers.systemShortcutExecutionNotImplemented, identity: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: nil,
                    matrix: nil, aggregateCount: nil
                )
            }
            return SP1Leg(
                legID: legID, verdict: .blocked, detectorAvailable: false, blocker: matrixBlocker, identity: nil,
                runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, artifactSha256: nil, matrix: nil, aggregateCount: nil
            )
        }
        var report = SP1Evidence(
            selectedTapIdentity: nil, legs: legs,
            verdict: legs.map(\.verdict).max { precedence($0) < precedence($1) } ?? .blocked,
            g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: identity.sourceSha256
        )
        report.schemaVersion = d1 ? 2 : 1
        try report.validate()
        try publish(report: report, synthetic: syntheticBytes, live: liveBytes, output: output)
        print("SP1=\(report.verdict.rawValue) selectedTapIdentity=NONE g0=OPEN output=\(output.path)")
    }

    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }

    private static let matrixLegIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]

    private static func publish(report: SP1Evidence, synthetic syntheticBytes: Data, live liveBytes: Data, output: URL) throws {
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
            try syntheticBytes.write(to: temporary.appendingPathComponent("product-stamped-synthetic.json"))
            try liveBytes.write(to: temporary.appendingPathComponent("live-aggregate-counts.json"))
            try SP1CanonicalNarratives.o7().write(to: temporary.appendingPathComponent("O7-ADDENDUM.md"))
            try SP1CanonicalNarratives.conclusion(for: report).write(to: temporary.appendingPathComponent("SP-1-CONCLUSION.md"))
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
        try canonicalJSON(value).write(to: url)
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value); data.append(10); return data
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

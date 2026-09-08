import CoreGraphics
import Darwin
import Foundation
import Phase0Support

protocol SP1PreflightProviding: Sendable {
    func preflightListenOnlyCandidates() throws
}

protocol SP1ShortcutExecuting: Sendable {
    func execute() throws -> SP1ShortcutExecution
}

protocol SP1MatrixExecuting: Sendable {
    func execute(tapType: String) throws -> SP1MatrixExecution
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
        preflightProvider: any SP1PreflightProviding = CoreGraphicsSP1PreflightProvider(),
        shortcutExecutor: any SP1ShortcutExecuting = ProcessEnvironmentSP1ShortcutExecutor(),
        matrixExecutor: any SP1MatrixExecuting = ProcessEnvironmentSP1MatrixExecutor()
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
        let shortcut = d1 ? try shortcutExecutor.execute() : nil
        let sessionMatrix = d1 && karabinerInstalled ? try matrixExecutor.execute(tapType: "session") : nil
        let annotatedMatrix = d1 && karabinerInstalled ? try matrixExecutor.execute(tapType: "annotated") : nil
        let liveObserved = shortcut?.observedCount ?? 0
        let liveUnmarked = shortcut?.unmarkedCount ?? 0
        let liveBytes = try canonicalJSON(SP1LiveAggregateArtifact(
            systemShortcutObservedCount: liveObserved, unmarkedObservedCount: liveUnmarked
        ))
        let liveHash = AtomicityDigest.sha256(liveBytes)

        let matrixBlocker = !d1
            ? SP1CanonicalBlockers.legacyV1Matrix(environment: environment, karabinerAbsent: !karabinerInstalled)
            : karabinerInstalled ? SP1CanonicalBlockers.liveExecutionNotArmed : SP1CanonicalBlockers.v2KarabinerAbsent
        let assertions = Dictionary(uniqueKeysWithValues: (synthetic?.assertions ?? []).map { ($0.legID, $0.passed) })
        let selectedType = SP1TapSelection.select(
            sessionPasses: shortcut?.isPass == true && sessionMatrix?.passes == true,
            annotatedPasses: shortcut?.isPass == true && annotatedMatrix?.passes == true
        )
        let selectedIdentity: SelectedTapIdentity? = selectedType.map { tapType in
            let tapConfig = SP1TapConfiguration.sha256(tapType: tapType)
            return SelectedTapIdentity(
                tapType: tapType,
                attemptID: SP1AttemptIdentity.attemptID(
                    runnerCommitSha: identity.commitSha,
                    runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash,
                    tapConfigSha256: tapConfig,
                    nonce: "phase0-sp1-attempt"
                ),
                runnerCommitSha: identity.commitSha,
                runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash,
                tapConfigSha256: tapConfig
            )
        }

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
            let boundIdentity = selectedIdentity.flatMap { selected in
                legID == "sp1.tap.\(selected.tapType).matrix" || !Self.matrixLegIDs.contains(legID) ? selected : nil
            }
            if let passed = assertions[legID] {
                return SP1Leg(
                    legID: legID, verdict: passed ? .pass : .fail, detectorAvailable: true, blocker: nil,
                    identity: boundIdentity,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: syntheticHash, matrix: nil, aggregateCount: nil
                )
            }
            if legID == "sp1.systemShortcut" {
                if shortcut?.isPass == true {
                    return SP1Leg(
                        legID: legID, verdict: .pass, detectorAvailable: true, blocker: nil,
                        identity: boundIdentity,
                        runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                        environmentSha256: environmentHash, artifactSha256: liveHash,
                        matrix: nil, aggregateCount: shortcut?.observedCount
                    )
                }
                if shortcut?.armed == true {
                    return SP1Leg(
                        legID: legID, verdict: .inconclusive, detectorAvailable: true, blocker: nil,
                        identity: nil,
                        runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                        environmentSha256: environmentHash, artifactSha256: liveHash,
                        matrix: nil, aggregateCount: shortcut?.observedCount
                    )
                }
                return SP1Leg(
                    legID: legID, verdict: .blocked, detectorAvailable: false,
                    blocker: SP1CanonicalBlockers.liveExecutionNotArmed, identity: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: nil,
                    matrix: nil, aggregateCount: nil
                )
            }
            let execution = legID == "sp1.tap.session.matrix" ? sessionMatrix : annotatedMatrix
            if !karabinerInstalled {
                return SP1Leg(
                    legID: legID, verdict: .blocked, detectorAvailable: false,
                    blocker: SP1CanonicalBlockers.v2KarabinerAbsent, identity: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: nil, matrix: nil, aggregateCount: nil
                )
            }
            if execution?.passes == true, shortcut?.isPass == true {
                return SP1Leg(
                    legID: legID, verdict: .pass, detectorAvailable: true, blocker: nil,
                    identity: boundIdentity,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: liveHash,
                    matrix: execution?.observation, aggregateCount: nil
                )
            }
            if execution?.armed == true {
                let inconclusive = execution?.completed != true
                    || ((execution?.observation?.offCount ?? 0) + (execution?.observation?.onCount ?? 0) == 0)
                return SP1Leg(
                    legID: legID, verdict: inconclusive ? .inconclusive : .fail, detectorAvailable: true, blocker: nil,
                    identity: nil,
                    runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                    environmentSha256: environmentHash, artifactSha256: liveHash,
                    matrix: execution?.observation, aggregateCount: nil
                )
            }
            return SP1Leg(
                legID: legID, verdict: .blocked, detectorAvailable: false,
                blocker: SP1CanonicalBlockers.liveExecutionNotArmed, identity: nil,
                runnerCommitSha: identity.commitSha, runnerTreeSha: identity.treeSha,
                environmentSha256: environmentHash, artifactSha256: nil, matrix: nil, aggregateCount: nil
            )
        }
        var report = SP1Evidence(
            selectedTapIdentity: selectedIdentity, legs: legs,
            verdict: {
                if let selectedIdentity {
                    let selectedLegID = "sp1.tap.\(selectedIdentity.tapType).matrix"
                    return legs.filter { $0.legID == selectedLegID || !Self.matrixLegIDs.contains($0.legID) }
                        .map(\.verdict).max { precedence($0) < precedence($1) } ?? .blocked
                }
                return legs.map(\.verdict).max { precedence($0) < precedence($1) } ?? .blocked
            }(),
            g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: identity.sourceSha256
        )
        report.schemaVersion = d1 ? 3 : 1
        try report.validate()
        try publish(report: report, synthetic: syntheticBytes, live: liveBytes, output: output)
        let selectedLabel = selectedIdentity?.tapType.uppercased() ?? "NONE"
        print("SP1=\(report.verdict.rawValue) selectedTapIdentity=\(selectedLabel) g0=OPEN output=\(output.path)")
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

struct ProcessEnvironmentSP1ShortcutExecutor: SP1ShortcutExecuting {
    func execute() throws -> SP1ShortcutExecution {
        guard SP1LiveArming.isArmed else {
            return SP1ShortcutExecution(observedCount: 0, absentCount: 0, unmarkedCount: 0, armed: false, completed: false)
        }
        return try ListenOnlySP1ShortcutExecutor().execute()
    }
}

struct ProcessEnvironmentSP1MatrixExecutor: SP1MatrixExecuting {
    func execute(tapType: String) throws -> SP1MatrixExecution {
        guard SP1LiveArming.isArmed else {
            return SP1MatrixExecution(observation: nil, armed: false, completed: false)
        }
        return try ListenOnlySP1MatrixExecutor().execute(tapType: tapType)
    }
}

struct ListenOnlySP1ShortcutExecutor: SP1ShortcutExecuting {
    func execute() throws -> SP1ShortcutExecution {
        guard let events = SP1ListenOnlyRuntime.collectKeyDowns(tapType: .cgSessionEventTap) else {
            return SP1ShortcutExecution(observedCount: 0, absentCount: 0, unmarkedCount: 0, armed: true, completed: false)
        }
        var shiftCommand3 = 0
        var controlUp = 0
        var unmarked = 0
        for event in events {
            switch SP1ListenOnlyRuntime.classify(event) {
            case .shiftCommand3: shiftCommand3 += 1
            case .controlUp: controlUp += 1
            case .unmarked: unmarked += 1
            }
        }
        let observed = (shiftCommand3 > 0 ? 1 : 0) + (controlUp > 0 ? 1 : 0)
        let absent = SP1IsolatedKarabinerMapping.controlledShortcutCount - observed
        return SP1ShortcutExecution(observedCount: observed, absentCount: absent, unmarkedCount: unmarked, armed: true, completed: true)
    }
}

struct ListenOnlySP1MatrixExecutor: SP1MatrixExecuting {
    func execute(tapType: String) throws -> SP1MatrixExecution {
        let location: CGEventTapLocation = tapType == "annotated" ? .cgAnnotatedSessionEventTap : .cgSessionEventTap
        guard let offEvents = SP1ListenOnlyRuntime.collectKeyDowns(tapType: location),
              let onEvents = SP1ListenOnlyRuntime.collectKeyDowns(tapType: location) else {
            return SP1MatrixExecution(observation: nil, armed: true, completed: false)
        }
        let physical = SP1IsolatedKarabinerMapping.expectedPhysicalCode
        let transformed = SP1IsolatedKarabinerMapping.expectedTransformedCode
        let off = offEvents.filter { $0.keyCode == physical }
        let on = onEvents.filter { $0.keyCode == transformed }
        return SP1MatrixExecution(
            observation: TapMatrixObservation(
                offObservedCode: off.first?.keyCode,
                offCount: off.count,
                onObservedCode: on.first?.keyCode,
                onCount: on.count,
                expectedPhysicalCode: physical,
                expectedTransformedCode: transformed
            ),
            armed: true,
            completed: true
        )
    }
}

private struct SP1ObservedKey {
    let keyCode: UInt16
    let flags: CGEventFlags
}

private enum SP1ShortcutClass { case shiftCommand3, controlUp, unmarked }

private enum SP1ListenOnlyRuntime {
    static func windowSeconds() -> CFTimeInterval {
        let raw = ProcessInfo.processInfo.environment["KEYRECORD_SP1_WINDOW_SECONDS"].flatMap(Double.init) ?? 10
        return min(max(raw, 1), 30)
    }

    static func classify(_ event: SP1ObservedKey) -> SP1ShortcutClass {
        let significant = event.flags.intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate])
        if event.keyCode == 20, significant == [.maskShift, .maskCommand] { return .shiftCommand3 }
        if event.keyCode == 126, significant == [.maskControl] { return .controlUp }
        return .unmarked
    }

    static func collectKeyDowns(tapType: CGEventTapLocation) -> [SP1ObservedKey]? {
        guard CGPreflightListenEventAccess() else { return nil }
        let box = SP1ListenBox()
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: tapType,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: sp1ListenCallback,
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ) else { return nil }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let deadline = CFAbsoluteTimeGetCurrent() + windowSeconds()
        while CFAbsoluteTimeGetCurrent() < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(tap)
        return box.keyDowns
    }
}

private final class SP1ListenBox: @unchecked Sendable {
    var keyDowns: [SP1ObservedKey] = []
}

private func sp1ListenCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .keyDown, let userInfo {
        let box = Unmanaged<SP1ListenBox>.fromOpaque(userInfo).takeUnretainedValue()
        box.keyDowns.append(SP1ObservedKey(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags
        ))
    }
    return Unmanaged.passUnretained(event)
}

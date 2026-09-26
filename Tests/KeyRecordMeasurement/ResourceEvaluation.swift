import Foundation

/// Offline accounting for one process-resource window.
///
/// A completed window is `measured`. Sleep, exit, PID reuse, session change,
/// a missing sample, or a short window is `interrupted` or `invalid`.
/// This type never emits a product-performance pass.
public enum ResourceProtocolKind: String, Codable, Sendable {
    case exploratory
    case pausedMonitorCandidate
    case formalFRS2
}

public struct ProcessResourceSample: Equatable, Sendable, Codable {
    public var uptimeSeconds: Double
    public var monotonicSeconds: Double
    public var cpuNanoseconds: UInt64
    public var childCPUNanoseconds: UInt64
    public var footprintBytes: UInt64
    public var pid: Int32
    public var startAbstime: UInt64
    public var executablePath: String
    public var consoleUID: Int?
    public var failed: Bool
    public var exited: Bool

    public init(uptimeSeconds: Double, monotonicSeconds: Double, cpuNanoseconds: UInt64,
                childCPUNanoseconds: UInt64, footprintBytes: UInt64, pid: Int32,
                startAbstime: UInt64, executablePath: String, consoleUID: Int?,
                failed: Bool = false, exited: Bool = false) {
        self.uptimeSeconds = uptimeSeconds
        self.monotonicSeconds = monotonicSeconds
        self.cpuNanoseconds = cpuNanoseconds
        self.childCPUNanoseconds = childCPUNanoseconds
        self.footprintBytes = footprintBytes
        self.pid = pid
        self.startAbstime = startAbstime
        self.executablePath = executablePath
        self.consoleUID = consoleUID
        self.failed = failed
        self.exited = exited
    }
}

public struct ResourceWindowRequest: Equatable, Sendable {
    public var protocolKind: ResourceProtocolKind
    public var phase: String
    public var warmupSeconds: Double
    public var measureSeconds: Double
    public var intervalSeconds: Double
    public var samples: [ProcessResourceSample]

    public init(protocolKind: ResourceProtocolKind, phase: String, warmupSeconds: Double,
                measureSeconds: Double, intervalSeconds: Double, samples: [ProcessResourceSample]) {
        self.protocolKind = protocolKind
        self.phase = phase
        self.warmupSeconds = warmupSeconds
        self.measureSeconds = measureSeconds
        self.intervalSeconds = intervalSeconds
        self.samples = samples
    }
}

public struct ResourceWindowResult: Equatable, Sendable, Codable {
    public var outcome: String
    public var reason: String?
    public var qualification: String
    public var protocolKind: String
    public var phase: String
    public var cpuPercentOfOneLogicalCore: Double?
    public var footprintMeanBytes: Double?
    public var footprintSampledPeakBytes: UInt64?
    public var footprintSampleCount: Int
    public var childCPUNanosecondsDelta: UInt64
    public var productProcessOnly: Bool
    public var rssUsedAsFootprint: Bool
    public var sleepPrevented: Bool
    public var observerIncludedInTarget: Bool
    public var substitutesForIntel: Bool
    public var substitutesForOtherOS: Bool
    public var formalFRS2Qualification: Bool
    public var formula: String
}

public enum ResourceEvaluator {
    public static let formula = "100 * (delta target user+system nanoseconds) / 1e9 / delta CLOCK_MONOTONIC seconds; one logical core. Physical footprint is proc_pid_rusage ri_phys_footprint. Warmup samples are excluded. Sampled peak is the maximum retained sample, not proof that no higher value occurred between samples."

    public static func evaluate(_ request: ResourceWindowRequest) -> ResourceWindowResult {
        func finish(_ outcome: String, _ reason: String?, cpu: Double? = nil, mean: Double? = nil,
                    peak: UInt64? = nil, count: Int = 0, child: UInt64 = 0, productOnly: Bool = false) -> ResourceWindowResult {
            ResourceWindowResult(
                outcome: outcome, reason: reason, qualification: "not-a-product-pass",
                protocolKind: request.protocolKind.rawValue, phase: request.phase,
                cpuPercentOfOneLogicalCore: cpu, footprintMeanBytes: mean,
                footprintSampledPeakBytes: peak, footprintSampleCount: count,
                childCPUNanosecondsDelta: child, productProcessOnly: productOnly,
                rssUsedAsFootprint: false, sleepPrevented: false, observerIncludedInTarget: false,
                substitutesForIntel: false, substitutesForOtherOS: false, formalFRS2Qualification: false,
                formula: formula)
        }

        if request.protocolKind == .formalFRS2,
           request.warmupSeconds != 60 || request.measureSeconds != 600 || request.samples.isEmpty {
            return finish("invalid", "formal-protocol-requires-60s-warmup-and-600s-measure")
        }
        if request.protocolKind == .pausedMonitorCandidate,
           (request.warmupSeconds < 60 || request.measureSeconds < 600) {
            return finish("invalid", "paused-monitor-candidate-requires-60s-warmup-and-600s-measure")
        }
        guard request.intervalSeconds > 0, request.warmupSeconds >= 0, request.measureSeconds > 0 else {
            return finish("invalid", "bad-duration")
        }
        guard let first = request.samples.first, !first.failed, !first.exited else {
            return finish("invalid", "sample-missing")
        }
        var childDelta: UInt64 = 0
        for index in request.samples.indices {
            let sample = request.samples[index]
            if sample.failed { return finish("invalid", "sample-missing") }
            if sample.exited { return finish("interrupted", "process-exited") }
            if sample.pid != first.pid || sample.startAbstime != first.startAbstime || sample.executablePath != first.executablePath {
                return finish("invalid", "pid-reused")
            }
            if sample.consoleUID == nil || sample.consoleUID != first.consoleUID {
                return finish("interrupted", "session-changed")
            }
            if index > 0 {
                let previous = request.samples[index - 1]
                let uptime = sample.uptimeSeconds - previous.uptimeSeconds
                let monotonic = sample.monotonicSeconds - previous.monotonicSeconds
                if monotonic - uptime > 0.5 { return finish("interrupted", "sleep") }
                if uptime > request.intervalSeconds * 2.5 && monotonic > request.intervalSeconds * 2.5 {
                    return finish("invalid", "sample-missing")
                }
                if sample.childCPUNanoseconds >= previous.childCPUNanoseconds {
                    childDelta = sample.childCPUNanoseconds - request.samples[0].childCPUNanoseconds
                }
            }
        }
        let origin = first.uptimeSeconds
        let measureStart = origin + request.warmupSeconds
        let measureEnd = measureStart + request.measureSeconds
        let measured = request.samples.filter { $0.uptimeSeconds >= measureStart && $0.uptimeSeconds <= measureEnd + request.intervalSeconds * 0.25 }
        guard measured.count >= 2, let start = measured.first, let end = measured.last else {
            return finish("invalid", "sample-missing", child: childDelta)
        }
        let covered = end.uptimeSeconds - measureStart
        if covered + request.intervalSeconds * 0.5 < request.measureSeconds {
            return finish("interrupted", "duration-short", child: childDelta)
        }
        let elapsed = end.monotonicSeconds - start.monotonicSeconds
        guard elapsed > 0, end.cpuNanoseconds >= start.cpuNanoseconds else {
            return finish("invalid", "sample-missing", child: childDelta)
        }
        let cpu = 100 * Double(end.cpuNanoseconds - start.cpuNanoseconds) / 1e9 / elapsed
        let bytes = measured.map(\.footprintBytes)
        let mean = Double(bytes.reduce(0, +)) / Double(bytes.count)
        let peak = bytes.max() ?? 0
        return finish("measured", nil, cpu: cpu, mean: mean, peak: peak, count: bytes.count,
                      child: childDelta, productOnly: childDelta == 0)
    }

    public static func recompute(_ archive: ResourceMeasurementArchive) -> ResourceWindowResult {
        evaluate(ResourceWindowRequest(
            protocolKind: archive.protocolKind, phase: archive.phase,
            warmupSeconds: archive.requestedWarmupSeconds, measureSeconds: archive.requestedMeasureSeconds,
            intervalSeconds: archive.requestedIntervalSeconds, samples: archive.samples))
    }
}

public struct ResourceMeasurementArchive: Equatable, Sendable, Codable {
    public var protocolKind: ResourceProtocolKind
    public var phase: String
    public var requestedWarmupSeconds: Double
    public var requestedMeasureSeconds: Double
    public var requestedIntervalSeconds: Double
    public var effectiveMeasureSeconds: Double?
    public var retainedSampleCount: Int
    public var interruptReason: String?
    public var pid: Int32
    public var executablePath: String
    public var architecture: String
    public var operatingSystem: String
    public var diagnosticsEnabled: Bool
    public var diagnosticsIncludedInOverhead: Bool
    public var formula: String
    public var rssUsedAsFootprint: Bool
    public var samples: [ProcessResourceSample]
    public var result: ResourceWindowResult

    public init(request: ResourceWindowRequest, result: ResourceWindowResult, architecture: String,
                operatingSystem: String, diagnosticsEnabled: Bool) {
        protocolKind = request.protocolKind
        phase = request.phase
        requestedWarmupSeconds = request.warmupSeconds
        requestedMeasureSeconds = request.measureSeconds
        requestedIntervalSeconds = request.intervalSeconds
        samples = request.samples
        retainedSampleCount = request.samples.count
        interruptReason = result.reason
        pid = request.samples.first?.pid ?? -1
        executablePath = request.samples.first?.executablePath ?? ""
        self.architecture = architecture
        self.operatingSystem = operatingSystem
        self.diagnosticsEnabled = diagnosticsEnabled
        diagnosticsIncludedInOverhead = diagnosticsEnabled
        formula = result.formula
        rssUsedAsFootprint = false
        self.result = result
        if result.outcome == "measured", let first = request.samples.first,
           let last = request.samples.last(where: {
               $0.uptimeSeconds >= first.uptimeSeconds + request.warmupSeconds
                   && $0.uptimeSeconds <= first.uptimeSeconds + request.warmupSeconds + request.measureSeconds + request.intervalSeconds * 0.25
           }) {
            effectiveMeasureSeconds = last.uptimeSeconds - (first.uptimeSeconds + request.warmupSeconds)
        } else {
            effectiveMeasureSeconds = nil
        }
    }
}

public struct PrivacyIntervalMark: Equatable, Sendable, Decodable {
    public var seq: Int
    public var role: String
    public var phase: String
    public var captureSessionLive: Bool
    public var sensitiveContentVisible: Bool
    public var expectedCollecting: Bool?
    public var aggregateDelta: Int64
    public var handoffAccepted: Int64
    public var handoffClosed: Int64
    public var normalizationOutput: Int64
    public var flushDurable: Int64
    public var flushInvalidated: Int64
    public var protectedSnapshotAttempts: Int64
    public var protectedSnapshotRejected: Int64
    public var protectedAnalysisAttempts: Int64
    public var protectedAnalysisRejected: Int64
    public var snapshotPublicationCount: Int64

    public var lockReadStatus: String
    public var secureInputReadStatus: String
    public var countersAreAtomicSnapshot: Bool
    public var action: String?
    public var actionSeq: Int?
    public var boundaryCause: String?

    public init(seq: Int, phase: String, captureSessionLive: Bool, sensitiveContentVisible: Bool,
                expectedCollecting: Bool?, aggregateDelta: Int64, handoffAccepted: Int64,
                handoffClosed: Int64, normalizationOutput: Int64, flushDurable: Int64,
                flushInvalidated: Int64, protectedSnapshotAttempts: Int64, protectedSnapshotRejected: Int64,
                protectedAnalysisAttempts: Int64, protectedAnalysisRejected: Int64,
                snapshotPublicationCount: Int64, role: String = "change",
                lockReadStatus: String = "notChecked", secureInputReadStatus: String = "notChecked",
                countersAreAtomicSnapshot: Bool = false, action: String? = nil,
                actionSeq: Int? = nil, boundaryCause: String? = nil) {
        self.seq = seq
        self.actionSeq = actionSeq
        self.boundaryCause = boundaryCause
        self.role = role
        self.lockReadStatus = lockReadStatus
        self.secureInputReadStatus = secureInputReadStatus
        self.countersAreAtomicSnapshot = countersAreAtomicSnapshot
        self.action = action
        self.phase = phase
        self.captureSessionLive = captureSessionLive
        self.sensitiveContentVisible = sensitiveContentVisible
        self.expectedCollecting = expectedCollecting
        self.aggregateDelta = aggregateDelta
        self.handoffAccepted = handoffAccepted
        self.handoffClosed = handoffClosed
        self.normalizationOutput = normalizationOutput
        self.flushDurable = flushDurable
        self.flushInvalidated = flushInvalidated
        self.protectedSnapshotAttempts = protectedSnapshotAttempts
        self.protectedSnapshotRejected = protectedSnapshotRejected
        self.protectedAnalysisAttempts = protectedAnalysisAttempts
        self.protectedAnalysisRejected = protectedAnalysisRejected
        self.snapshotPublicationCount = snapshotPublicationCount
    }
}

public struct PrivacySpanDelta: Equatable, Sendable, Codable {
    public var fromSeq: Int
    public var toSeq: Int
    public var phase: String
    public var captureSessionLive: Bool
    public var sensitiveContentVisible: Bool
    public var expectedCollecting: Bool?
    public var aggregateDelta: Int64
    public var handoffAccepted: Int64
    public var normalizationOutput: Int64
    public var flushDurable: Int64
    public var flushInvalidated: Int64
    public var protectedSnapshotAttempts: Int64
    public var protectedSnapshotRejected: Int64
    public var protectedAnalysisAttempts: Int64
    public var snapshotPublicationCount: Int64
}

public struct PrivacyIntervalReport: Equatable, Sendable, Codable {
    public var outcome: String
    public var reason: String?
    public var spans: [PrivacySpanDelta]
    public var closedSpanCount: Int
    public var unexpectedCollectingWhilePaused: Bool
    public var provesContinuousClosedInterval: Bool
    public var provesRendering: Bool
    public var provesEveryProtectedRead: Bool
    /// Late completions of writes issued before the boundary; not closed-interval input.
    public var inFlightCompletionsAtBoundary: Int64 = 0
    public var beginCause: String?
    public var endCause: String?
    public var countersAreAtomicSnapshot = false
}

public enum PrivacyIntervalEvaluator {
    public static func evaluate(_ marks: [PrivacyIntervalMark]) -> PrivacyIntervalReport {
        guard marks.count >= 2, marks.map(\.seq) == marks.map(\.seq).sorted(), Set(marks.map(\.seq)).count == marks.count else {
            return PrivacyIntervalReport(outcome: "inconclusive", reason: "need-ordered-interval-marks",
                spans: [], closedSpanCount: 0, unexpectedCollectingWhilePaused: false,
                provesContinuousClosedInterval: false, provesRendering: false, provesEveryProtectedRead: false)
        }
        var spans: [PrivacySpanDelta] = []
        var paused = false
        var unexpected = false
        for index in 0..<(marks.count - 1) {
            let start = marks[index]
            let end = marks[index + 1]
            if start.expectedCollecting == false { paused = true }
            if paused && end.captureSessionLive && end.expectedCollecting == false { unexpected = true }
            func delta(_ later: Int64, _ earlier: Int64) -> Int64 { later - earlier }
            spans.append(PrivacySpanDelta(
                fromSeq: start.seq, toSeq: end.seq, phase: start.phase,
                captureSessionLive: start.captureSessionLive,
                sensitiveContentVisible: start.sensitiveContentVisible,
                expectedCollecting: start.expectedCollecting,
                aggregateDelta: delta(end.aggregateDelta, start.aggregateDelta),
                handoffAccepted: delta(end.handoffAccepted, start.handoffAccepted),
                normalizationOutput: delta(end.normalizationOutput, start.normalizationOutput),
                flushDurable: delta(end.flushDurable, start.flushDurable),
                flushInvalidated: delta(end.flushInvalidated, start.flushInvalidated),
                protectedSnapshotAttempts: delta(end.protectedSnapshotAttempts, start.protectedSnapshotAttempts),
                protectedSnapshotRejected: delta(end.protectedSnapshotRejected, start.protectedSnapshotRejected),
                protectedAnalysisAttempts: delta(end.protectedAnalysisAttempts, start.protectedAnalysisAttempts),
                snapshotPublicationCount: delta(end.snapshotPublicationCount, start.snapshotPublicationCount)))
        }
        let closed = spans.filter { !$0.captureSessionLive && !$0.sensitiveContentVisible }
        if closed.isEmpty {
            return PrivacyIntervalReport(outcome: "inconclusive", reason: "no-closed-to-next-span",
                spans: spans, closedSpanCount: 0, unexpectedCollectingWhilePaused: unexpected,
                provesContinuousClosedInterval: false, provesRendering: false, provesEveryProtectedRead: false)
        }
        return PrivacyIntervalReport(outcome: "observed", reason: nil, spans: spans, closedSpanCount: closed.count,
            unexpectedCollectingWhilePaused: unexpected, provesContinuousClosedInterval: false,
            provesRendering: false, provesEveryProtectedRead: false)
    }

    /// End causes recorded at the product step that re-authorizes input or display, before
    /// that step can move a counter. Other causes mean the boundary position is unknown.
    public static let reliableEndCauses: Set<String> = ["captureSessionStarting", "protectedDisplayReauthorized"]

    /// Evaluates the last closed interval opened by `beginCause` (nil accepts any cause).
    /// Requires begin, at least one observe and the first end after that begin. Deltas are
    /// end minus begin. Counters are not an atomic snapshot, and a finite observe sample
    /// does not prove every moment was closed.
    public static func evaluateClosed(_ marks: [PrivacyIntervalMark], journalWriteFailed: Bool,
                                      beginCause: String? = "protectedStateClosed") -> PrivacyIntervalReport {
        func report(_ outcome: String, _ reason: String?, spans: [PrivacySpanDelta] = [],
                    begin: PrivacyIntervalMark? = nil, end: PrivacyIntervalMark? = nil,
                    inFlight: Int64 = 0) -> PrivacyIntervalReport {
            PrivacyIntervalReport(outcome: outcome, reason: reason, spans: spans, closedSpanCount: spans.isEmpty ? 0 : 1,
                unexpectedCollectingWhilePaused: false, provesContinuousClosedInterval: false,
                provesRendering: false, provesEveryProtectedRead: false,
                inFlightCompletionsAtBoundary: inFlight, beginCause: begin?.boundaryCause,
                endCause: end?.boundaryCause, countersAreAtomicSnapshot: false)
        }
        if journalWriteFailed { return report("invalid", "journal-write-failed") }
        guard marks.map(\.seq) == marks.map(\.seq).sorted(), Set(marks.map(\.seq)).count == marks.count else {
            return report("inconclusive", "need-ordered-interval-marks")
        }
        guard let begin = marks.last(where: {
            $0.role == "begin" && (beginCause == nil || $0.boundaryCause == beginCause)
        }) else { return report("inconclusive", "missing-boundary") }
        guard let end = marks.first(where: { $0.role == "end" && $0.seq > begin.seq }) else {
            return report("inconclusive", "interval-not-ended", begin: begin)
        }
        guard let cause = end.boundaryCause, reliableEndCauses.contains(cause) else {
            return report("inconclusive", "end-boundary-unattributable", begin: begin, end: end)
        }
        let during = marks.filter { $0.role == "observe" && $0.seq > begin.seq && $0.seq < end.seq }
        guard !during.isEmpty else { return report("inconclusive", "missing-boundary", begin: begin, end: end) }
        if end.aggregateDelta < begin.aggregateDelta || end.handoffAccepted < begin.handoffAccepted
            || end.normalizationOutput < begin.normalizationOutput
            || end.flushDurable < begin.flushDurable || end.flushInvalidated < begin.flushInvalidated
            || end.protectedSnapshotAttempts < begin.protectedSnapshotAttempts
            || end.protectedAnalysisAttempts < begin.protectedAnalysisAttempts {
            return report("invalid", "counter-decreased", begin: begin, end: end)
        }
        func delta(_ later: Int64, _ earlier: Int64) -> Int64 { later - earlier }
        func span(_ from: PrivacyIntervalMark, _ to: PrivacyIntervalMark) -> PrivacySpanDelta {
            PrivacySpanDelta(
                fromSeq: from.seq, toSeq: to.seq, phase: from.phase,
                captureSessionLive: from.captureSessionLive, sensitiveContentVisible: from.sensitiveContentVisible,
                expectedCollecting: from.expectedCollecting,
                aggregateDelta: delta(to.aggregateDelta, from.aggregateDelta),
                handoffAccepted: delta(to.handoffAccepted, from.handoffAccepted),
                normalizationOutput: delta(to.normalizationOutput, from.normalizationOutput),
                flushDurable: delta(to.flushDurable, from.flushDurable),
                flushInvalidated: delta(to.flushInvalidated, from.flushInvalidated),
                protectedSnapshotAttempts: delta(to.protectedSnapshotAttempts, from.protectedSnapshotAttempts),
                protectedSnapshotRejected: delta(to.protectedSnapshotRejected, from.protectedSnapshotRejected),
                protectedAnalysisAttempts: delta(to.protectedAnalysisAttempts, from.protectedAnalysisAttempts),
                snapshotPublicationCount: delta(to.snapshotPublicationCount, from.snapshotPublicationCount))
        }
        let closed = span(begin, end)
        var spans = [closed]
        if let after = marks.last, after.seq > end.seq { spans.append(span(end, after)) }
        let analysisRejected = delta(end.protectedAnalysisRejected, begin.protectedAnalysisRejected)
        let protectedReadsSucceeded = (closed.protectedSnapshotAttempts - closed.protectedSnapshotRejected)
            + (closed.protectedAnalysisAttempts - analysisRejected)
        var violations: [String] = []
        if closed.aggregateDelta > 0 || closed.normalizationOutput > 0 { violations.append("closed-interval-input-counted") }
        if protectedReadsSucceeded > 0 { violations.append("closed-interval-protected-read-succeeded") }
        if closed.snapshotPublicationCount > 0 { violations.append("closed-interval-publication") }
        if closed.flushDurable > 0 { violations.append("closed-interval-durable-acknowledgment") }
        let inFlight = closed.flushInvalidated
        if !violations.isEmpty {
            return report("observed", violations.joined(separator: ","), spans: spans, begin: begin, end: end,
                          inFlight: inFlight)
        }
        if closed.handoffAccepted > 0 {
            // A queue acceptance counted after revocation with no reducer effect can be a
            // straddling copy of pre-boundary work. The copies are not atomic.
            return report("inconclusive", "handoff-count-not-attributable", spans: spans, begin: begin, end: end,
                          inFlight: inFlight)
        }
        return report("observed", nil, spans: spans, begin: begin, end: end, inFlight: inFlight)
    }
}

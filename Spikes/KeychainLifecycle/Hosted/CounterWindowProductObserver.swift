#if DEBUG
import Foundation
import KeyRecordCore
import LifecyclePreflight

/// Measures the instrumented product boundaries over a closed window. It does not
/// establish OS lock authority, rendered pixels, or uninstrumented read coverage.
public final class CounterWindowProductObserver: HostedProductObserver, @unchecked Sendable {
    private let lock = NSLock()
    private let read: @Sendable () -> CaptureRunSummary
    private let wait: @Sendable () -> Void
    private var previous: LockChallenge?

    public convenience init?(recorder: CaptureDiagnosticsRecorder, interval: TimeInterval = 1) {
        guard interval.isFinite, interval > 0 else { return nil }
        self.init(read: { recorder.runSummary }, wait: { Thread.sleep(forTimeInterval: interval) })
    }

    init(read: @escaping @Sendable () -> CaptureRunSummary, wait: @escaping @Sendable () -> Void) {
        self.read = read
        self.wait = wait
    }

    public func observe(step: LifecycleStep, transition: LockTransition) -> HostedProductObservation? {
        lock.withLock {
            guard transition.previous.process == transition.current.process,
                  transition.previous.generation != transition.current.generation,
                  previous == nil || previous == transition.previous else { return nil }
            switch step {
            case .lockBackground, .sleepClosed:
                guard !transition.unlocked else { return nil }
            case .unlockRevalidate, .wakeRevalidate:
                guard transition.unlocked else { return nil }
            default: return nil
            }
            previous = transition.current
            let first = read()
            guard Self.closed(first), Self.idle(first.protectedReadActivity) else { return nil }
            wait()
            let last = read()
            if transition.unlocked && !Self.closed(last) { return nil }
            guard last.countersInstrumented,
                  let reads = Self.readDelta(first.protectedReadActivity, last.protectedReadActivity),
                  let published = Self.sumDeltas(
                    [Int64(first.snapshotPublicationCount), Int64(first.analysisPublicationCount)],
                    [Int64(last.snapshotPublicationCount), Int64(last.analysisPublicationCount)]),
                  let aggregate = Self.sumDeltas([first.aggregateDelta], [last.aggregateDelta]),
                  let admissions = Self.sumDeltas([first.handoffAccepted, first.normalizationOutput],
                                                 [last.handoffAccepted, last.normalizationOutput]),
                  let firstGate = first.protectedGateEntries,
                  let lastGate = last.protectedGateEntries,
                  let entries = Self.sumDeltas([firstGate], [lastGate]),
                  admissions == 0, entries == 0 else { return nil }
            return HostedProductObservation(protectedReadDelta: reads,
                publishDelta: published, aggregateDelta: aggregate,
                captureClosed: Self.closed(last))
        }
    }

    private static func closed(_ value: CaptureRunSummary) -> Bool {
        value.countersInstrumented && value.captureQueueOpen == false && value.keyGateOpen == false
            && !value.captureSessionLive && !value.sensitiveContentVisible
    }

    private static func values(_ value: ProtectedReadActivitySnapshot) -> [Int64] {
        [value.decryptionStarted, value.decryptionCompleted,
         value.keychainReadStarted, value.keychainReadCompleted,
         value.storeCacheReadStarted, value.storeCacheReadCompleted,
         value.aggregateReadStarted, value.aggregateReadCompleted,
         value.plaintextProcessingStarted, value.plaintextProcessingCompleted]
    }

    private static func idle(_ value: ProtectedReadActivitySnapshot?) -> Bool {
        guard let value else { return false }
        let counters = values(value)
        return stride(from: 0, to: counters.count, by: 2).allSatisfy {
            counters[$0] >= 0 && counters[$0] == counters[$0 + 1]
        }
    }

    private static func readDelta(_ first: ProtectedReadActivitySnapshot?,
                                  _ last: ProtectedReadActivitySnapshot?) -> Int? {
        guard let first, let last else { return nil }
        let before = values(first)
        let after = values(last)
        let starts = stride(from: 0, to: before.count, by: 2)
        guard zip(before, after).allSatisfy({ $0 >= 0 && $1 >= $0 }),
              starts.allSatisfy({ after[$0 + 1] <= after[$0] }) else { return nil }
        return sumDeltas(starts.map { before[$0] }, starts.map { after[$0] })
    }

    private static func sumDeltas(_ first: [Int64], _ last: [Int64]) -> Int? {
        var total: Int64 = 0
        for (before, after) in zip(first, last) {
            guard before >= 0, after >= before else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(after - before)
            guard !overflow else { return nil }
            total = sum
        }
        return Int(exactly: total)
    }
}
#endif

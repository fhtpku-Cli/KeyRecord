#if DEBUG
import Foundation

/// DEBUG-only layered diagnostics (plan batch 6).
///
/// Purpose: make "capture doesn't work" impossible to say. Every counter names one layer,
/// so a zero can be attributed to a specific stage instead of the whole pipeline:
///
///   tap callback → queue handoff → normalization → aggregate → flush → durable
///
/// Live verification on 2026-09-18 ended with capture provably not starting and **no
/// observable signal at all** (the app printed nothing on stderr). That is what this type
/// exists to prevent.
///
/// Privacy contract, enforced by `CaptureDiagnosticsPrivacyTests`:
/// every stored field is a count, a coarse enum, or a generation number. There is no field
/// capable of holding typed text, key codes, raw event sequences, or per-event timestamps.
public struct CaptureDiagnostics: Equatable, Sendable {
    // Layer 1 — did a keyboard event reach this process at all?
    /// Whether the per-layer counters below are actually written in this build.
    ///
    /// Composition sets this only after installing the counter hooks.
    public var countersInstrumented = false
    public var tapCallbackKeyDown = 0
    public var tapCallbackKeyUp = 0
    public var tapCallbackFlagsChanged = 0
    public var tapDisabledEvents = 0

    // Layer 2 — did the bounded queue accept it?
    public var handoffAccepted = 0
    public var handoffClosed = 0
    public var handoffOverflow = 0

    // Layer 3/4 — did normalization emit, and did the aggregate move?
    public var normalizationOutput = 0
    public var aggregateDelta = 0

    // Layer 5 — persistence.
    public var flushIssued = 0
    public var flushDurable = 0
    public var flushFailed = 0
    public var flushTimedOut = 0
    /// Issued tasks that returned, including thrown/cancelled writes. Issued minus
    /// returned in the cumulative run summary measures outstanding physical tasks.
    public var flushWriteReturned = 0
    /// Writer returned normally; this is not a current-generation durable acknowledgment.
    public var flushWriteSucceeded = 0
    /// Logical completion revoked without a saved, failed, or timed-out acknowledgment.
    public var flushInvalidated = 0

    // Session identity and the last reason a session was torn down.
    public var sessionGeneration: UInt64 = 0
    public var lastInvalidation: CaptureInvalidationReason?

    // Presented state, so a "nothing is counted" report can distinguish
    // "never captured" from "captured but hidden".
    public var phase: LifecyclePhase = .unstarted
    public var blockedReason: BlockedReason?
    /// Typed lifecycle failure, rendered as its case description.
    ///
    /// Separate from `blockedReason` because the reducer records them on different paths:
    /// `enterFailure` sets `failure` only. Reading just `blockedReason` reported a real,
    /// already-recorded cause as "no reason recorded" during live verification.
    /// A closed enum of failure cases — structurally incapable of carrying free-form
    /// text, so it cannot become a channel for captured input.
    public var failure: LifecycleFailure?
    public var sensitiveContentVisible = false
    public var captureSessionLive = false

    // Startup-time facts. Without these a `layer 0` report cannot say WHICH precondition
    // was missing, which is what stalled the 2026-09-18/20 investigation: the diagnosis
    // named the failure (protectedDataUnavailable) but not the input that caused it.
    /// DEBUG capture armament actually observed by `make()`.
    public var armedAtStartup: Bool?
    /// Session-lock state observed by `boot()` before preferences were reloaded.
    public var lockStateAtStartup: SessionLockState?
    /// Whether `boot()` actually opened the key gate.
    public var keyGatePrimed: Bool?
    /// The real store/keyring failure behind a collapsed `protectedDataUnavailable`.
    ///
    /// A closed enum, not a string: error descriptions can embed filesystem paths, so a
    /// free-form field would widen the diagnostics surface beyond counts and coarse state.
    public var underlyingLoadFailure: LoadFailureKind?
    /// Whether the key gate was still open at the moment `load()` failed. Distinguishes
    /// "gate closed between boot and load" from "gate open but versions still unreadable".
    public var keyGateOpenAtLoadFailure: Bool?
    /// How many key versions the keyring enumerated at load failure. `envelopeKeyMissing`
    /// with an open gate means this set did not contain the envelope's version; the count
    /// separates "enumeration returned nothing" from "returned the wrong versions".
    public var enumeratedKeyVersionCount: Int?
    /// The envelope's declared key version, and whether enumeration produced it.
    public var envelopeKeyVersion: UInt32?
    /// What the loaded preferences said about resuming collection. A boot that loads
    /// `expectedCollecting == false` never emits a start effect and therefore records no
    /// blocked reason — indistinguishable, without this field, from a silent failure.
    public var loadedExpectedCollecting: Bool?
    /// The recovery coordinator's last verdict. It keeps its own `lastOutcome`, which no
    /// diagnostic consulted: when the coordinator closed a session that `start()` had
    /// legitimately opened, the reducer stayed in `.collecting` with nothing recorded, so
    /// layer 0 reported "no reason" while the real reason sat one actor away.
    /// Mirrored as a Core-local enum because Core cannot import KeyRecordCapture.
    public var runtimeBlockReason: RuntimeBlockReason?
    /// Lock state re-read at snapshot time, so a released lock is visibly distinct from
    /// the boot-time sample rather than silently contradicting it.
    public var currentLockState: SessionLockState?

    /// Mirrors `CaptureRuntimeBlockReason`; a compile-time test pins the two together.
    public enum RuntimeBlockReason: String, Sendable, Equatable, CaseIterable {
        case userStopped, notExpectingCollecting, permissionRequired
        case privacyChecksFailed, startFailed
    }

    /// Why loading protected preferences failed.
    ///
    /// Corruption is NOT collapsed into one case: the store distinguishes twelve causes
    /// with completely different remedies (a missing manifest, an unreadable manifest and
    /// a symlinked root are not the same problem). Reporting them all as
    /// "storeCorruption" repeats exactly the flattening this diagnostic exists to fix —
    /// which is what happened on the first pass of this investigation.
    public enum LoadFailureKind: String, Sendable, Equatable, CaseIterable {
        case keyGateLocked, storeNotInitialized, decodeFailed, freshInstall, other
        case envelopeOrLocator
        // Corruption causes, kept distinct.
        case rootReplacedBySymlink, rootNotDirectory, insecureRoot
        case manifestMissing, manifestUnreadable, unknownManifestSchemaVersion
        case unexpectedEntry, symlinkEncountered, referencedObjectMissing
        case envelopeKeyMissing, unindexedDataWithNamespaceKey, resetJournalUnreadable
        case otherCorruption
    }

    public init() {}

    public var totalTapCallbacks: Int {
        tapCallbackKeyDown + tapCallbackKeyUp + tapCallbackFlagsChanged
    }

    /// Names the first layer that stopped, so a report never degenerates into
    /// "capture doesn't work".
    public var diagnosis: String {
        if !captureSessionLive {
            // Consult BOTH records: the reducer writes blockedReason on blocking
            // transitions and `failure` on failing ones.
            // A boot that loaded `expectedCollecting == false` is not a failure at all:
            // no start was ever attempted, so no reason exists to record. Saying "no
            // reason recorded" there frames normal paused state as a swallowed error.
            var cause = blockedReason.map(String.init(describing:))
                ?? failure.map(String.init(describing:))
                ?? runtimeBlockReason.map { "coordinator closed session: \($0.rawValue)" }
                ?? (loadedExpectedCollecting == false
                    ? "not resuming: preferences say collection is off"
                    : "no reason recorded")
            // Attach the startup inputs so the cause is actionable rather than merely named.
            if let armed = armedAtStartup, let primed = keyGatePrimed {
                let lock = lockStateAtStartup.map(String.init(describing:)) ?? "unread"
                // Labelled atBoot: these are sampled once during boot and never refreshed.
                // Unlabelled, a lock that has since been released still reads "locked".
                cause += "; atBoot[armed=\(armed) lock=\(lock) keyGateOpen=\(primed)]"
                if let liveLock = currentLockState {
                    cause += " now[lock=\(liveLock)]"
                }
            }
            if let underlying = underlyingLoadFailure {
                cause += "; underlying=\(underlying.rawValue)"
            }
            if let openAtFailure = keyGateOpenAtLoadFailure {
                cause += " gateOpenAtFailure=\(openAtFailure)"
            }
            if let runtimeBlock = runtimeBlockReason {
                cause += "; coordinator=\(runtimeBlock.rawValue)"
            }
            if let expected = loadedExpectedCollecting {
                cause += " expectedCollecting=\(expected)"
            }
            if let count = enumeratedKeyVersionCount {
                cause += " enumeratedVersions=\(count)"
            }
            if let envelopeVersion = envelopeKeyVersion {
                cause += " envelopeVersion=\(envelopeVersion)"
            }
            // `phase` was recorded but never printed — yet it is what separates "the start
            // effect was never emitted" from "it was emitted and something later undid it".
            return "layer 0: no capture session is live (\(cause); phase=\(phase))"
        }
        guard countersInstrumented else {
            return "capture session is live; per-layer counters are not instrumented in "
                + "this build, so no claim is made about event flow"
        }
        if totalTapCallbacks == 0 {
            return "layer 1: tap callback never fired — no keyboard event reached this process"
        }
        if handoffAccepted == 0 {
            return handoffClosed > 0
                ? "layer 2: every event was rejected by the queue gate"
                : "layer 2: events fired but none were handed off"
        }
        if normalizationOutput == 0 {
            return "layer 3: events accepted but normalization produced no output"
        }
        if aggregateDelta == 0 {
            return "layer 4: normalization ran but the aggregate never moved"
        }
        if flushDurable == 0 {
            if flushTimedOut > 0 { return "layer 5: flush timed out; nothing is durable" }
            if flushFailed > 0 { return "layer 5: flush failed; nothing is durable" }
            return "layer 5: aggregate moved but no durable commit completed yet"
        }
        if !sensitiveContentVisible {
            return "layers 1-5 OK but the UI is hiding results (visibility gate closed)"
        }
        return "layers 1-5 OK: tap → queue → normalization → aggregate → durable"
    }
}

/// Why a capture session ended. Mirrors the Capture-layer reasons without importing it,
/// so Core stays dependency-free.
public enum CaptureInvalidationReason: String, Sendable, Equatable, CaseIterable {
    case foregroundChanged, secureInputChanged, sessionChanged
    case permissionRevoked, sleep, tapDisabled
}

/// Numeric-only diagnostic counters that may be incremented from callback paths.
public enum CaptureDiagnosticCounter: Int, CaseIterable, Sendable {
    case tapCallbackKeyDown
    case tapCallbackKeyUp
    case tapCallbackFlagsChanged
    case tapDisabledEvent
    case handoffAccepted
    case handoffClosed
    case handoffOverflow
    case normalizationOutput
    case aggregateDelta
    case flushIssued
    case flushDurable
    case flushFailed
    case flushTimedOut
    case flushWriteReturned
    case flushWriteSucceeded
    case flushInvalidated
}

private final class CaptureDiagnosticCounterStorage: @unchecked Sendable {
    private let values: UnsafeMutablePointer<Int64>

    init() {
        values = .allocate(capacity: CaptureDiagnosticCounter.allCases.count)
        values.initialize(repeating: 0, count: CaptureDiagnosticCounter.allCases.count)
    }

    deinit {
        values.deinitialize(count: CaptureDiagnosticCounter.allCases.count)
        values.deallocate()
    }

    func increment(_ counter: CaptureDiagnosticCounter) {
        _ = OSAtomicAdd64Barrier(1, values.advanced(by: counter.rawValue))
    }

    func snapshot() -> [Int64] {
        CaptureDiagnosticCounter.allCases.map {
            OSAtomicAdd64Barrier(0, values.advanced(by: $0.rawValue))
        }
    }
}

public struct CaptureRunSummary: Encodable, Sendable {
    public var tapCallbackKeyDown: Int64 = 0
    public var tapCallbackKeyUp: Int64 = 0
    public var tapCallbackFlagsChanged: Int64 = 0
    public var tapDisabledEvents: Int64 = 0
    public var handoffAccepted: Int64 = 0
    public var handoffClosed: Int64 = 0
    public var handoffOverflow: Int64 = 0
    public var normalizationOutput: Int64 = 0
    public var aggregateDelta: Int64 = 0
    public var flushIssued: Int64 = 0
    public var flushDurable: Int64 = 0
    public var flushFailed: Int64 = 0
    public var flushTimedOut: Int64 = 0
    /// Issued tasks that have returned; may include an invalidated or timed-out write.
    public var flushWriteReturned: Int64 = 0
    /// Normal writer returns only; does not assert current-generation durability.
    public var flushWriteSucceeded: Int64 = 0
    /// Revoked logical outcomes, disjoint from durable, failed and timed out.
    public var flushInvalidated: Int64 = 0
    public var sessionCount = 0
    public var snapshotPublicationCount = 0
    public var snapshotReadFailureCount = 0
    public var lastPublishedShortcutTotal: Int64?
    public var lastPublishedBareKeyTotal: Int64?
    public var countersInstrumented = false
    public var captureSessionLive = false
    public var sensitiveContentVisible = false
}

/// Thread-safe collector. DEBUG-only by construction: the product wires it in `#if DEBUG`
/// blocks, and `Phase1ReleaseIsolationTests` asserts Release cannot reach a control entry.
///
/// `increment(_:)` is safe for callback paths. `record(_:)` remains for lifecycle state and
/// must not be called from a capture callback.
public final class CaptureDiagnosticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counters = CaptureDiagnostics()
    private let atomicCounters = CaptureDiagnosticCounterStorage()
    private var counterBaseline: [Int64]
    private var counterInstrumentationConfigured = false
    private var run = CaptureRunSummary()

    public init() {
        counterBaseline = atomicCounters.snapshot()
    }

    public var snapshot: CaptureDiagnostics {
        let state = lock.withLock { (counters, counterBaseline) }
        var result = state.0
        let atomicValues = atomicCounters.snapshot()
        result.tapCallbackKeyDown += Int(atomicValues[CaptureDiagnosticCounter.tapCallbackKeyDown.rawValue] - state.1[CaptureDiagnosticCounter.tapCallbackKeyDown.rawValue])
        result.tapCallbackKeyUp += Int(atomicValues[CaptureDiagnosticCounter.tapCallbackKeyUp.rawValue] - state.1[CaptureDiagnosticCounter.tapCallbackKeyUp.rawValue])
        result.tapCallbackFlagsChanged += Int(atomicValues[CaptureDiagnosticCounter.tapCallbackFlagsChanged.rawValue] - state.1[CaptureDiagnosticCounter.tapCallbackFlagsChanged.rawValue])
        result.tapDisabledEvents += Int(atomicValues[CaptureDiagnosticCounter.tapDisabledEvent.rawValue] - state.1[CaptureDiagnosticCounter.tapDisabledEvent.rawValue])
        result.handoffAccepted += Int(atomicValues[CaptureDiagnosticCounter.handoffAccepted.rawValue] - state.1[CaptureDiagnosticCounter.handoffAccepted.rawValue])
        result.handoffClosed += Int(atomicValues[CaptureDiagnosticCounter.handoffClosed.rawValue] - state.1[CaptureDiagnosticCounter.handoffClosed.rawValue])
        result.handoffOverflow += Int(atomicValues[CaptureDiagnosticCounter.handoffOverflow.rawValue] - state.1[CaptureDiagnosticCounter.handoffOverflow.rawValue])
        result.normalizationOutput += Int(atomicValues[CaptureDiagnosticCounter.normalizationOutput.rawValue] - state.1[CaptureDiagnosticCounter.normalizationOutput.rawValue])
        result.aggregateDelta += Int(atomicValues[CaptureDiagnosticCounter.aggregateDelta.rawValue] - state.1[CaptureDiagnosticCounter.aggregateDelta.rawValue])
        result.flushIssued += Int(atomicValues[CaptureDiagnosticCounter.flushIssued.rawValue] - state.1[CaptureDiagnosticCounter.flushIssued.rawValue])
        result.flushDurable += Int(atomicValues[CaptureDiagnosticCounter.flushDurable.rawValue] - state.1[CaptureDiagnosticCounter.flushDurable.rawValue])
        result.flushFailed += Int(atomicValues[CaptureDiagnosticCounter.flushFailed.rawValue] - state.1[CaptureDiagnosticCounter.flushFailed.rawValue])
        result.flushTimedOut += Int(atomicValues[CaptureDiagnosticCounter.flushTimedOut.rawValue] - state.1[CaptureDiagnosticCounter.flushTimedOut.rawValue])
        result.flushWriteReturned += Int(atomicValues[CaptureDiagnosticCounter.flushWriteReturned.rawValue] - state.1[CaptureDiagnosticCounter.flushWriteReturned.rawValue])
        result.flushWriteSucceeded += Int(atomicValues[CaptureDiagnosticCounter.flushWriteSucceeded.rawValue] - state.1[CaptureDiagnosticCounter.flushWriteSucceeded.rawValue])
        result.flushInvalidated += Int(atomicValues[CaptureDiagnosticCounter.flushInvalidated.rawValue] - state.1[CaptureDiagnosticCounter.flushInvalidated.rawValue])
        return result
    }

    public func record(_ body: (inout CaptureDiagnostics) -> Void) {
        lock.withLock { body(&counters) }
    }

    public var runSummary: CaptureRunSummary {
        var result = lock.withLock {
            var result = run
            result.countersInstrumented = counters.countersInstrumented
            result.captureSessionLive = counters.captureSessionLive
            result.sensitiveContentVisible = counters.sensitiveContentVisible
            return result
        }
        let values = atomicCounters.snapshot()
        result.tapCallbackKeyDown = values[CaptureDiagnosticCounter.tapCallbackKeyDown.rawValue]
        result.tapCallbackKeyUp = values[CaptureDiagnosticCounter.tapCallbackKeyUp.rawValue]
        result.tapCallbackFlagsChanged = values[CaptureDiagnosticCounter.tapCallbackFlagsChanged.rawValue]
        result.tapDisabledEvents = values[CaptureDiagnosticCounter.tapDisabledEvent.rawValue]
        result.handoffAccepted = values[CaptureDiagnosticCounter.handoffAccepted.rawValue]
        result.handoffClosed = values[CaptureDiagnosticCounter.handoffClosed.rawValue]
        result.handoffOverflow = values[CaptureDiagnosticCounter.handoffOverflow.rawValue]
        result.normalizationOutput = values[CaptureDiagnosticCounter.normalizationOutput.rawValue]
        result.aggregateDelta = values[CaptureDiagnosticCounter.aggregateDelta.rawValue]
        result.flushIssued = values[CaptureDiagnosticCounter.flushIssued.rawValue]
        result.flushDurable = values[CaptureDiagnosticCounter.flushDurable.rawValue]
        result.flushFailed = values[CaptureDiagnosticCounter.flushFailed.rawValue]
        result.flushTimedOut = values[CaptureDiagnosticCounter.flushTimedOut.rawValue]
        result.flushWriteReturned = values[CaptureDiagnosticCounter.flushWriteReturned.rawValue]
        result.flushWriteSucceeded = values[CaptureDiagnosticCounter.flushWriteSucceeded.rawValue]
        result.flushInvalidated = values[CaptureDiagnosticCounter.flushInvalidated.rawValue]
        return result
    }

    /// Records assignment to the presentation model, not proof of screen rendering.
    public func recordPublication(shortcutTotal: Int64, bareKeyTotal: Int64) {
        lock.withLock {
            run.snapshotPublicationCount += 1
            run.lastPublishedShortcutTotal = shortcutTotal
            run.lastPublishedBareKeyTotal = bareKeyTotal
        }
    }

    public func recordSnapshotReadFailure() {
        lock.withLock { run.snapshotReadFailureCount += 1 }
    }

    public func writeRunSummary(to path: String?) throws {
        guard let path, !path.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(runSummary).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Marks that composition has installed every counter-producing hook.
    public func configureCounterInstrumentation() {
        lock.withLock {
            counterInstrumentationConfigured = true
            counters.countersInstrumented = true
        }
    }

    /// Increments a numeric-only counter without acquiring the lifecycle-state lock.
    public func increment(_ counter: CaptureDiagnosticCounter) {
        atomicCounters.increment(counter)
    }

    /// Starts a new diagnostic session without discarding lifetime atomic totals.
    public func beginSession(generation: UInt64) {
        let baseline = atomicCounters.snapshot()
        lock.withLock {
            run.sessionCount += 1
            counters.tapCallbackKeyDown = 0
            counters.tapCallbackKeyUp = 0
            counters.tapCallbackFlagsChanged = 0
            counters.tapDisabledEvents = 0
            counters.handoffAccepted = 0
            counters.handoffClosed = 0
            counters.handoffOverflow = 0
            counters.normalizationOutput = 0
            counters.aggregateDelta = 0
            counters.flushIssued = 0
            counters.flushDurable = 0
            counters.flushFailed = 0
            counters.flushTimedOut = 0
            counters.flushWriteReturned = 0
            counters.flushWriteSucceeded = 0
            counters.flushInvalidated = 0
            counters.sessionGeneration = generation
            counterBaseline = baseline
        }
    }
}
#endif

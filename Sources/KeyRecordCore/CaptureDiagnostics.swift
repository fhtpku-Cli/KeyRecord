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
    /// The harness increments them; the production App does not. Reading an unwritten
    /// counter as a measured zero made the menu claim "no keyboard event reached this
    /// process" while capture was in fact running — a fabricated finding. A gauge that is
    /// not wired must say so rather than report a reading.
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

/// Thread-safe collector. DEBUG-only by construction: the product wires it in `#if DEBUG`
/// blocks, and `Phase1ReleaseIsolationTests` asserts Release cannot reach a control entry.
///
/// Every mutation is a bounded counter bump, so it is safe to call from the tap callback,
/// which must not perform disk, Keychain, process, network or UI work.
public final class CaptureDiagnosticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counters = CaptureDiagnostics()

    public init() {}

    public var snapshot: CaptureDiagnostics { lock.withLock { counters } }

    public func record(_ body: (inout CaptureDiagnostics) -> Void) {
        lock.withLock { body(&counters) }
    }

    /// Resets counts for a new session while retaining the new generation.
    public func beginSession(generation: UInt64) {
        lock.withLock {
            counters = CaptureDiagnostics()
            counters.sessionGeneration = generation
        }
    }
}
#endif

import XCTest
import KeyRecordCore
import KeyRecordTestSupport

/// Batch 6: layered diagnostics must (a) name the failing layer and (b) be structurally
/// incapable of recording what the user typed.
final class CaptureDiagnosticsTests: XCTestCase {

    /// Release isolation: diagnostics must not exist outside DEBUG.
    ///
    /// The first implementation put `CaptureDiagnostics` in Core WITHOUT a `#if DEBUG`
    /// guard. Core is a product library, so a Release build of the app linked it and the
    /// binary carried 157 diagnostic symbols — a direct breach of the Release-isolation
    /// contract. Source-level assertion, because the test bundle itself is always DEBUG.
    func testDiagnosticsSourceIsGuardedSoReleaseCannotContainIt() throws {
        let source = try String(
            contentsOf: SourceInspection.root
                .appendingPathComponent("Sources/KeyRecordCore/CaptureDiagnostics.swift"),
            encoding: .utf8)
        let code = SourceInspection.codeOnly(source)
        XCTAssertTrue(code.hasPrefix("#if DEBUG"),
                      "diagnostics must be DEBUG-gated or Release will link them")
        XCTAssertTrue(code.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("#endif"))
        // The declarations themselves must sit inside that guard.
        let guardIndex = try XCTUnwrap(code.range(of: "#if DEBUG")).lowerBound
        for declaration in ["struct CaptureDiagnostics", "class CaptureDiagnosticsRecorder",
                            "enum CaptureInvalidationReason"] {
            let found = try XCTUnwrap(code.range(of: declaration), declaration)
            XCTAssertTrue(found.lowerBound > guardIndex, "\(declaration) escapes the guard")
        }
    }


    // MARK: - Privacy is enforced structurally, not by convention

    func testDiagnosticsStoreOnlyCountsAndCoarseStateFields() throws {
        var diagnostics = CaptureDiagnostics()
        diagnostics.tapCallbackKeyDown = 3
        diagnostics.lastInvalidation = .tapDisabled
        diagnostics.phase = .collecting
        diagnostics.blockedReason = .sessionLocked

        // Every stored field must be a count, a generation, a Bool, or a coarse enum.
        // Anything capable of carrying text or a key code fails this check.
        for child in Mirror(reflecting: diagnostics).children {
            let label = try XCTUnwrap(child.label)
            let type = String(describing: Swift.type(of: child.value))
            let allowed = type.contains("Int") || type.contains("UInt64")
                || type.contains("Bool")
                || type.contains("LifecyclePhase") || type.contains("BlockedReason")
                || type.contains("CaptureInvalidationReason")
                || type.contains("LifecycleFailure")
                || type.contains("SessionLockState")
                || type.contains("LoadFailureKind")
                // Closed enum of coordinator verdicts; pinned below to stay free of text.
                || type.contains("RuntimeBlockReason")
            XCTAssertTrue(allowed, "\(label) has disallowed type \(type)")
            // Explicitly forbid the shapes that could carry user input.
            XCTAssertFalse(type.contains("String"), "\(label) must not be a String")
            XCTAssertFalse(type.contains("Date"), "\(label) must not carry a timestamp")
            XCTAssertFalse(type.contains("KeyCode"), "\(label) must not carry a key code")
            XCTAssertFalse(type.contains("Array") || type.contains("["),
                           "\(label) must not be a sequence of events")
        }
    }

    func testNoStoredFieldCanHoldAnEventSequence() {
        // A per-event log is the specific thing the privacy contract forbids.
        let fields = Mirror(reflecting: CaptureDiagnostics()).children.compactMap(\.label)
        XCTAssertFalse(fields.contains { $0.lowercased().contains("log") })
        XCTAssertFalse(fields.contains { $0.lowercased().contains("sequence") })
        XCTAssertFalse(fields.contains { $0.lowercased().contains("timestamp") })
        XCTAssertFalse(fields.isEmpty)
    }

    // MARK: - The diagnosis names the layer that stopped

    private func diagnostics(live: Bool = true, tapDown: Int = 0, accepted: Int = 0,
                             closed: Int = 0, normalized: Int = 0, delta: Int = 0,
                             durable: Int = 0, timedOut: Int = 0, failed: Int = 0,
                             visible: Bool = true) -> CaptureDiagnostics {
        var value = CaptureDiagnostics()
        // This helper populates the per-layer counters, so it models an instrumented
        // build by definition; layered assertions below depend on that.
        value.countersInstrumented = true
        value.captureSessionLive = live
        value.tapCallbackKeyDown = tapDown
        value.handoffAccepted = accepted
        value.handoffClosed = closed
        value.normalizationOutput = normalized
        value.aggregateDelta = delta
        value.flushDurable = durable
        value.flushTimedOut = timedOut
        value.flushFailed = failed
        value.sensitiveContentVisible = visible
        return value
    }

    func testLayerZeroReportsATypedFailureNotJustABlockedReason() {
        // Live 2026-09-18: the menu read "layer 0 ... (no reason recorded)" while the
        // lifecycle actually held a typed `failure` (.preferencesLoadFailed). The
        // diagnosis only consulted `blockedReason`, so a genuine, already-recorded cause
        // was reported as "no reason recorded" — the diagnostic's own blind spot, which
        // sent the investigation toward the wrong layer.
        var value = CaptureDiagnostics()
        value.captureSessionLive = false
        value.blockedReason = nil
        value.failure = .preferencesLoadFailed(.protectedDataUnavailable)
        XCTAssertTrue(value.diagnosis.contains("preferencesLoadFailed"), value.diagnosis)
        XCTAssertFalse(value.diagnosis.contains("no reason recorded"), value.diagnosis)
    }

    func testUnderlyingStoreFailureIsNamedRatherThanCollapsed() {
        // `LifecycleOrchestrator.reload` folds every non-PreferencesRepositoryError into
        // `.protectedDataUnavailable`. Live verification therefore reported a specific
        // store failure as a generic one, hiding which step broke. The diagnosis must name
        // the underlying classification.
        var value = CaptureDiagnostics()
        value.captureSessionLive = false
        value.failure = .preferencesLoadFailed(.protectedDataUnavailable)
        value.armedAtStartup = true
        value.keyGatePrimed = true
        value.lockStateAtStartup = .unlocked
        value.underlyingLoadFailure = .manifestUnreadable
        XCTAssertTrue(value.diagnosis.contains("manifestUnreadable"), value.diagnosis)
        // The startup inputs stay visible so a healthy-looking precondition set cannot
        // be mistaken for the cause.
        XCTAssertTrue(value.diagnosis.contains("keyGateOpen=true"), value.diagnosis)
    }

    func testCorruptionCausesAreNotCollapsedIntoOneValue() {
        // Twelve store corruption causes have different remedies; reporting them all as
        // one value repeats the flattening this diagnostic exists to eliminate.
        let distinct: [CaptureDiagnostics.LoadFailureKind] = [
            .rootReplacedBySymlink, .rootNotDirectory, .insecureRoot,
            .manifestMissing, .manifestUnreadable, .unknownManifestSchemaVersion,
            .unexpectedEntry, .symlinkEncountered, .referencedObjectMissing,
            .envelopeKeyMissing, .unindexedDataWithNamespaceKey, .resetJournalUnreadable,
        ]
        XCTAssertEqual(Set(distinct).count, distinct.count, "each cause must stay distinct")
        for cause in distinct {
            var value = CaptureDiagnostics()
            value.captureSessionLive = false
            value.underlyingLoadFailure = cause
            XCTAssertTrue(value.diagnosis.contains(cause.rawValue), value.diagnosis)
        }
    }

    func testNotResumingIsStatedRatherThanLookingLikeASilentFailure() {
        // Live: preferences loaded fine (enumeratedVersions=1, no failure, no blocked
        // reason) yet no session started, and layer 0 said "no reason recorded". A boot
        // that loads expectedCollecting == false legitimately emits no start effect and
        // records no reason, so the diagnosis must say so instead of looking like a
        // swallowed error.
        var value = CaptureDiagnostics()
        value.captureSessionLive = false
        value.armedAtStartup = true
        value.keyGatePrimed = true
        value.lockStateAtStartup = .unlocked
        value.enumeratedKeyVersionCount = 1
        value.loadedExpectedCollecting = false
        XCTAssertTrue(value.diagnosis.contains("expectedCollecting=false"), value.diagnosis)
        XCTAssertFalse(value.diagnosis.contains("no reason recorded"), value.diagnosis)
    }

    func testLayerZeroNamesThePhaseItStalledIn() {
        // Live: expectedCollecting=true, key present, no reason recorded. Whether the
        // reducer never emitted .startCapture or emitted it and lost the session is
        // invisible without the phase, so layer 0 must always name it.
        var value = CaptureDiagnostics()
        value.captureSessionLive = false
        value.loadedExpectedCollecting = true
        value.phase = .reopening
        XCTAssertTrue(value.diagnosis.contains("phase=reopening"), value.diagnosis)
    }

    func testCoordinatorBlockIsVisibleWhenPhaseClaimsCollecting() {
        // Live: phase=collecting with no session and no reason. The reducer records
        // nothing because the start effect DID succeed; the recovery coordinator closed
        // the session afterwards and kept its reason to itself. A phase that claims
        // collecting without a session must therefore surface the coordinator's verdict.
        var value = CaptureDiagnostics()
        value.captureSessionLive = false
        value.phase = .collecting
        value.loadedExpectedCollecting = true
        value.runtimeBlockReason = .privacyChecksFailed
        XCTAssertTrue(value.diagnosis.contains("privacyChecksFailed"), value.diagnosis)
        XCTAssertFalse(value.diagnosis.contains("no reason recorded"), value.diagnosis)
    }

    func testRuntimeBlockReasonMirrorsCoordinatorAndCarriesNoText() {
        // Core cannot import KeyRecordCapture, so this enum is a hand-kept mirror. If the
        // coordinator gains a verdict and this list does not, the new reason would render
        // as "no reason recorded" — the exact failure this field exists to remove.
        XCTAssertEqual(Set(CaptureDiagnostics.RuntimeBlockReason.allCases.map(\.rawValue)),
                       ["userStopped", "notExpectingCollecting", "permissionRequired",
                        "privacyChecksFailed", "startFailed"])
        for reason in CaptureDiagnostics.RuntimeBlockReason.allCases {
            XCTAssertFalse(reason.rawValue.contains("/"), reason.rawValue)
        }
    }

    func testStartupSnapshotIsNotPresentedAsCurrentState() {
        // Live: the Mac locked mid-session and was then unlocked, yet the menu still read
        // "lock=locked keyGateOpen=false". Those fields are written once during boot, so
        // rendering them as bare facts invites reading a stale snapshot as the present
        // state — the same mistake KR-08 fixed for the status title. Label them.
        var value = CaptureDiagnostics()
        value.captureSessionLive = false
        value.armedAtStartup = true
        value.keyGatePrimed = false
        value.lockStateAtStartup = .locked
        XCTAssertTrue(value.diagnosis.contains("atBoot"), value.diagnosis)
    }

    func testUnwiredCountersCannotMasqueradeAsAMeasuredZero() {
        // Live: the menu alternated between layer 0 and layer 1 as the session was torn
        // down and rebuilt. layer 1 was not evidence of anything — production never
        // increments the tap counters (only the harness does), so "0 callbacks" was an
        // unwired gauge, not a measurement. A diagnosis must not name a layer it cannot
        // actually observe; saying "no keyboard event reached this process" on the basis
        // of a counter nobody writes is exactly the false lead this tool exists to kill.
        var value = CaptureDiagnostics()
        value.captureSessionLive = true
        value.countersInstrumented = false
        XCTAssertTrue(value.diagnosis.contains("not instrumented"), value.diagnosis)
        XCTAssertFalse(value.diagnosis.contains("tap callback never fired"), value.diagnosis)

        // With instrumentation present, a real zero still reports layer 1.
        value.countersInstrumented = true
        XCTAssertTrue(value.diagnosis.contains("layer 1"), value.diagnosis)
    }

    func testLoadFailureKindCannotCarryFreeFormText() {
        // Closed enum: every case is a fixed token, so no path or user text can leak in.
        for kind in CaptureDiagnostics.LoadFailureKind.allCases {
            XCTAssertFalse(kind.rawValue.contains("/"), kind.rawValue)
            XCTAssertFalse(kind.rawValue.isEmpty)
        }
    }

    func testLayerZeroSaysNoReasonOnlyWhenThereGenuinelyIsNone() {
        var value = CaptureDiagnostics()
        value.captureSessionLive = false
        value.blockedReason = nil
        value.failure = nil
        XCTAssertTrue(value.diagnosis.contains("no reason recorded"), value.diagnosis)
    }

    func testNoLiveSessionIsReportedAsLayerZeroWithItsReason() {
        var value = diagnostics(live: false)
        value.blockedReason = .sessionLocked
        XCTAssertTrue(value.diagnosis.hasPrefix("layer 0"), value.diagnosis)
        XCTAssertTrue(value.diagnosis.contains("sessionLocked"), value.diagnosis)
    }

    func testSilentTapIsLayerOneNotAGenericFailure() {
        let value = diagnostics(tapDown: 0)
        XCTAssertTrue(value.diagnosis.hasPrefix("layer 1"), value.diagnosis)
        // Must not collapse into an unhelpful blanket statement.
        XCTAssertFalse(value.diagnosis.lowercased().contains("capture doesn't work"))
    }

    func testRejectedEventsAreLayerTwo() {
        let value = diagnostics(tapDown: 5, accepted: 0, closed: 5)
        XCTAssertTrue(value.diagnosis.hasPrefix("layer 2"), value.diagnosis)
        XCTAssertTrue(value.diagnosis.contains("rejected"), value.diagnosis)
    }

    func testNormalizationSilenceIsLayerThree() {
        let value = diagnostics(tapDown: 5, accepted: 5, normalized: 0)
        XCTAssertTrue(value.diagnosis.hasPrefix("layer 3"), value.diagnosis)
    }

    func testStuckAggregateIsLayerFour() {
        let value = diagnostics(tapDown: 5, accepted: 5, normalized: 5, delta: 0)
        XCTAssertTrue(value.diagnosis.hasPrefix("layer 4"), value.diagnosis)
    }

    func testFlushTimeoutAndFailureAreDistinguishedAtLayerFive() {
        let timedOut = diagnostics(tapDown: 1, accepted: 1, normalized: 1, delta: 1, timedOut: 1)
        XCTAssertTrue(timedOut.diagnosis.contains("timed out"), timedOut.diagnosis)
        let failed = diagnostics(tapDown: 1, accepted: 1, normalized: 1, delta: 1, failed: 1)
        XCTAssertTrue(failed.diagnosis.contains("failed"), failed.diagnosis)
        // Neither may claim durability.
        XCTAssertFalse(timedOut.diagnosis.contains("durable:"))
    }

    func testCapturedButHiddenIsDistinguishedFromNotCaptured() {
        // The KR-06 class of bug: everything worked, the UI hid it. That must not read
        // the same as "nothing was captured".
        let hidden = diagnostics(tapDown: 5, accepted: 5, normalized: 5, delta: 5,
                                 durable: 1, visible: false)
        XCTAssertTrue(hidden.diagnosis.contains("hiding"), hidden.diagnosis)
        XCTAssertFalse(hidden.diagnosis.hasPrefix("layer 1"))
    }

    func testFullyHealthyPipelineReportsAllLayersOK() {
        let ok = diagnostics(tapDown: 5, accepted: 5, normalized: 5, delta: 5, durable: 1)
        XCTAssertTrue(ok.diagnosis.contains("layers 1-5 OK"), ok.diagnosis)
    }

    // MARK: - Recorder

    func testRecorderIsThreadSafeUnderConcurrentCounterBumps() {
        let recorder = CaptureDiagnosticsRecorder()
        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            recorder.record { $0.tapCallbackKeyDown += 1 }
        }
        XCTAssertEqual(recorder.snapshot.tapCallbackKeyDown, 500)
    }

    func testBeginSessionResetsCountsButKeepsTheNewGeneration() {
        let recorder = CaptureDiagnosticsRecorder()
        recorder.record { $0.tapCallbackKeyDown = 9; $0.aggregateDelta = 4 }
        recorder.beginSession(generation: 7)
        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.tapCallbackKeyDown, 0, "stale counts must not cross sessions")
        XCTAssertEqual(snapshot.aggregateDelta, 0)
        XCTAssertEqual(snapshot.sessionGeneration, 7)
    }
}

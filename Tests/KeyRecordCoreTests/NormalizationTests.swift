import XCTest
import KeyRecordCore

final class NormalizationTests: XCTestCase {
    func testBareKeyOutputCannotCarryForegroundAttribution() throws {
        // Given: a reliable foreground and an authoritative empty modifier snapshot.
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let event = try NormalizationFixtures.event(generation: normalizer.gate.generation)
        // When: normalizing a bare key.
        let output = normalizer.process(event)
        // Then: the bare-key variant has no app field; only ordinary source contribution.
        XCTAssertEqual(output, .keyDown(.bare(try KeyCode(0)), .ordinaryObserved))
        XCTAssertEqual(try output.sourceDelta, try SourceCounts(ordinary: Count(1), suspectedInjection: Count(0)))
    }

    func testSuspectedInjectionHasSeparateSourceDeltaWithoutAuthenticityClaim() throws {
        // Given: an unmarked suspected event, not an authentic-event classification.
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown, isAutoRepeat: false,
            modifiers: NormalizationFixtures.empty, source: .suspectedInjection, generation: normalizer.gate.generation)
        // When: normalizing it.
        let output = normalizer.process(event)
        // Then: counted only in the suspected source seam, not an event log.
        XCTAssertEqual(output, .keyDown(.bare(try KeyCode(0)), .suspectedInjection))
        XCTAssertEqual(try output.sourceDelta, try SourceCounts(ordinary: Count(0), suspectedInjection: Count(1)))
    }

    func testProductMarkedEventCannotMutateHeldModifiersOrSourceDeltas() throws {
        // Given: a product event that would otherwise establish held command state.
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let event = ObservedKeyEvent(keyCode: try KeyCode(48), kind: .keyDown, isAutoRepeat: false,
            modifiers: ModifierSet(command: .left), source: .productMarked, generation: normalizer.gate.generation)
        // When: dropping it after the gate.
        let output = normalizer.process(event)
        // Then: no output, source deltas or state contamination.
        XCTAssertEqual(output, .none)
        XCTAssertEqual(try output.sourceDelta.total.value, 0)
        XCTAssertEqual(normalizer.gate.modifiers, ModifierSet())
        XCTAssertTrue(normalizer.gate.heldKeys.isEmpty)
    }

    func testEveryClosedCombinationClearsHeldStateAndProducesZeroDeltas() throws {
        // Given: every gate combination, after a held ordinary chord.
        for collecting in [false, true] {
            for key in [KeyAvailability.available, .unavailable, .unknown] {
                for lock in [SessionLockState.unlocked, .locked, .unknown] {
                    for secure in [SecureInputState.disabled, .enabled, .unknown] {
                        for foreground in [ForegroundState.attributable(bundleID: "test.app"), .reliablyUnattributable, .unknown] {
                            for exclusion in [ExclusionState.included, .excluded, .unknown] {
                                let inputs = GateInputs(collecting: collecting, keyAvailability: key,
                                    sessionLock: lock, secureInput: secure, foreground: foreground, exclusion: exclusion)
                                guard !(collecting && key == .available && lock == .unlocked && secure == .disabled
                                    && foreground != .unknown && exclusion == .included) else { continue }
                                try assertClosed(inputs)
                            }
                        }
                    }
                }
            }
        }
    }

    private func assertClosed(_ inputs: GateInputs) throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        _ = normalizer.process(try NormalizationFixtures.event(48, modifiers: ModifierSet(command: .left),
            generation: normalizer.gate.generation))
        XCTAssertFalse(normalizer.gate.heldKeys.isEmpty)
        // When: the control state closes before any source classification.
        normalizer.update(inputs)
        for source in [EventSourceClass.ordinaryObserved, .suspectedInjection, .productMarked] {
            let event = ObservedKeyEvent(keyCode: try KeyCode(48), kind: .keyDown, isAutoRepeat: false,
                modifiers: ModifierSet(command: .both), source: source, generation: normalizer.gate.generation)
            let output = normalizer.process(event)
            // Then: the entire output (including any event metadata) is absent, counters stay zero.
            XCTAssertEqual(output, .none)
            XCTAssertEqual(try output.sourceDelta.total.value, 0)
            XCTAssertEqual(normalizer.gate.modifiers, ModifierSet())
            XCTAssertTrue(normalizer.gate.heldKeys.isEmpty)
        }
    }

    func testResetAndReopenRejectStaleEventsAndClearState() throws {
        // Given: a held event from the prior generation.
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let event = try NormalizationFixtures.event(48, modifiers: ModifierSet(command: .left),
            generation: normalizer.gate.generation)
        _ = normalizer.process(event)
        // When: reset then reopen before an old queued event arrives.
        normalizer.reset()
        XCTAssertEqual(normalizer.process(event), .none)
        normalizer.update(NormalizationFixtures.open)
        let output = normalizer.process(event)
        // Then: no stale counters or held-state recovery.
        XCTAssertEqual(output, .none)
        XCTAssertEqual(try output.sourceDelta.total.value, 0)
        XCTAssertEqual(normalizer.gate.modifiers, ModifierSet())
        XCTAssertTrue(normalizer.gate.heldKeys.isEmpty)
    }

    func testReliablyUnattributableChordUsesUnknownBucket() throws {
        // Given: positive unattributable evidence, not detector failure.
        var normalizer = ChordNormalizer()
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
            secureInput: .disabled, foreground: .reliablyUnattributable, exclusion: .included))
        let modifiers = ModifierSet(command: .right, option: .none, control: .none, shift: .none, fn: .none)
        // When: normalizing an unmatched chord.
        let output = normalizer.process(try NormalizationFixtures.event(0, modifiers: modifiers,
            generation: normalizer.gate.generation))
        // Then: preserve exact chord identity with unknown attribution and ordinary/discrete fallback.
        XCTAssertEqual(output, .keyDown(.chord(ChordBucket(chord: Chord(keyCode: try KeyCode(0),
            modifiers: modifiers), appBucket: .unknown), ShortcutClassification(kind: .discrete, scope: .normal)), .ordinaryObserved))
    }

    func testInvalidKeyCodesCannotConstructNormalizationInput() {
        // Given / When: all unassigned holes and out-of-range inputs cross the typed boundary.
        for code in [-1, 52, 66, 68, 70, 77, 108, 112, 127, Int.max] {
            // Then: no malformed code can reach the normalizer.
            XCTAssertThrowsError(try KeyCode(code))
        }
    }
}

import XCTest
import KeyRecordCore

final class PrivacyGateTests: XCTestCase {
    func testEveryInputCombinationUsesOrderedFailureClosedPredicate() {
        // Given: all 486 boolean/tri-state combinations, with both reliable foreground variants.
        for collecting in [false, true] {
            for key in [KeyAvailability.available, .unavailable, .unknown] {
                for lock in [SessionLockState.unlocked, .locked, .unknown] {
                    for secure in [SecureInputState.disabled, .enabled, .unknown] {
                        for foreground in [ForegroundState.attributable(bundleID: "test.app"), .reliablyUnattributable, .unknown] {
                            for exclusion in [ExclusionState.included, .excluded, .unknown] {
                                let inputs = GateInputs(collecting: collecting, keyAvailability: key,
                                    sessionLock: lock, secureInput: secure, foreground: foreground, exclusion: exclusion)
                                let expected: PrivacyGate.ClosureReason?
                                if !collecting { expected = .notCollecting }
                                else if key != .available { expected = .keyUnavailable }
                                else if lock != .unlocked { expected = .sessionLocked }
                                else if secure != .disabled { expected = .secureInput }
                                else if foreground == .unknown { expected = .foregroundUnreliable }
                                else if exclusion != .included { expected = .excluded }
                                else { expected = nil }
                                var gate = PrivacyGate()
                                // When: evaluating a fresh gate.
                                gate.update(inputs)
                                // Then: only fully affirmative states open, with ordered diagnostics.
                                XCTAssertEqual(gate.closureReason, expected)
                                XCTAssertEqual(gate.isOpen, expected == nil)
                            }
                        }
                    }
                }
            }
        }
    }

    func testGenerationChangesOnCloseReopenAndResetButNotStableUpdates() {
        // Given: an open generation.
        var gate = PrivacyGate()
        gate.update(NormalizationFixtures.open)
        let first = gate.generation
        gate.update(NormalizationFixtures.open)
        XCTAssertEqual(gate.generation, first)
        // When: closing, reopening and resetting.
        gate.update(GateInputs())
        let closed = gate.generation
        gate.update(NormalizationFixtures.open)
        let reopened = gate.generation
        gate.reset()
        // Then: each boundary fences all earlier events; reset stays closed.
        XCTAssertNotEqual(first, closed)
        XCTAssertNotEqual(closed, reopened)
        XCTAssertNotEqual(reopened, gate.generation)
        XCTAssertFalse(gate.isOpen)
        XCTAssertFalse(gate.accepts(reopened))
    }

    func testExhaustedGenerationPermanentlyFailsClosedWithoutWrapping() {
        // Given: no fresh generation can be allocated.
        var gate = PrivacyGate(generation: CaptureGeneration(rawValue: .max))
        // When: opening is requested repeatedly.
        gate.update(NormalizationFixtures.open)
        gate.reset()
        gate.update(NormalizationFixtures.open)
        // Then: never reuse an old generation.
        XCTAssertFalse(gate.isOpen)
        XCTAssertEqual(gate.closureReason, .generationExhausted)
        XCTAssertEqual(gate.generation.rawValue, .max)
    }

    func testStartupHasUnknownModifiersAndNoHeldKeys() {
        // Given / When: fresh privacy state.
        let gate = PrivacyGate()
        // Then: startup is not a fabricated authoritative release.
        XCTAssertFalse(gate.isOpen)
        XCTAssertEqual(gate.modifiers, ModifierSet())
        XCTAssertTrue(gate.heldKeys.isEmpty)
    }
}

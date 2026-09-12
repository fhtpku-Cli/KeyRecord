import XCTest
import KeyRecordCore

extension NormalizationTests {
    func testVersionOneControlledRulesReplayExactlyTwice() throws {
        // G0 source: Spikes/Sources/Phase0Probe/SP1Probe.swift:368-372;
        // evidence/phase0/sp1/evidence.json:56-71 binds the controlled systemShortcut leg.
        // Only Shift-Cmd-3 (20) and Ctrl-Up (126); Fn is outside the four significant flags.
        let cases: [(Int, ModifierSet, ShortcutClassification)] = [
            (48, mods(command: .left), .init(kind: .stateful, scope: .normal)),
            (48, mods(command: .right, shift: .both), .init(kind: .stateful, scope: .normal)),
            (20, mods(command: .both, shift: .left), .init(kind: .discrete, scope: .system)),
            (126, mods(control: .right), .init(kind: .discrete, scope: .system)),
            (20, mods(command: .left, shift: .right, fn: .active), .init(kind: .discrete, scope: .system)),
            (21, mods(command: .left, shift: .left), .init(kind: .discrete, scope: .normal)),
            (20, mods(command: .left, option: .left, shift: .left), .init(kind: .discrete, scope: .normal)),
            (126, mods(control: .left, shift: .left), .init(kind: .discrete, scope: .normal)),
            (48, mods(command: .left, control: .left), .init(kind: .discrete, scope: .normal)),
        ]
        XCTAssertEqual(ChordRuleTable.v1.version, 1)
        var replays: [[NormalizationOutput]] = []
        for _ in 0..<2 {
            var normalizer = ChordNormalizer()
            normalizer.update(NormalizationFixtures.open)
            var outputs: [NormalizationOutput] = []
            for (code, modifiers, classification) in cases {
                let output = normalizer.process(try NormalizationFixtures.event(code, modifiers: modifiers,
                    generation: normalizer.gate.generation))
                XCTAssertEqual(output, .keyDown(.chord(ChordBucket(chord: Chord(keyCode: try KeyCode(code),
                    modifiers: modifiers), appBucket: .bundleID("test.app")), classification), .ordinaryObserved))
                outputs.append(output)
            }
            replays.append(outputs)
        }
        XCTAssertEqual(replays[0], replays[1])
    }

    func testAllFiveSidesAndIndependentFnRecovery() {
        // SP2 port vectors: ModifierReconstruction.swift:23-53 and ModifierReconstructionTests.swift:5-71.
        for family in ModifierFamily.allCases {
            var model = ModifierReconstructor()
            XCTAssertEqual(model.snapshot, ModifierSet())
            for (left, right, expected) in [(false, false, ModifierSideState.none),
                (true, false, .left), (false, true, .right), (true, true, .both)] {
                model.recover(family: family, left: left, right: right)
                XCTAssertEqual(model[family], expected)
                XCTAssertEqual(model.snapshot.fn, .unknown)
            }
            model.recoverFn(active: true)
            model.markLoss(affected: [family])
            XCTAssertEqual(model[family], .activeSideUnknown)
            XCTAssertEqual(model.snapshot.fn, .unknown)
            model.recoverFn(active: false)
            XCTAssertEqual(model.snapshot.fn, .none)
            model.reset()
            XCTAssertEqual(model.snapshot, ModifierSet())
        }
    }

    func testFlagsChangedSequenceRecoversSidesWithoutGuessingAfterLoss() throws {
        for (family, left, right) in [(ModifierFamily.command, 55, 54), (.option, 58, 61),
            (.control, 59, 62), (.shift, 56, 60)] {
            var model = ModifierReconstructor()
            model.observeFlags(active: [], fn: .unknown, changedKey: nil)
            XCTAssertEqual(model.snapshot.fn, .unknown)
            model.observeFlags(active: [family], fn: .none, changedKey: try KeyCode(left))
            XCTAssertEqual(model[family], .left)
            model.observeFlags(active: [family], fn: .none, changedKey: try KeyCode(right))
            XCTAssertEqual(model[family], .both)
            model.observeFlags(active: [family], fn: .active, changedKey: try KeyCode(left))
            XCTAssertEqual(model[family], .right)
            model.observeFlags(active: [], fn: .none, changedKey: try KeyCode(right))
            XCTAssertEqual(model[family], .none)
            model.reset()
            model.observeFlags(active: [family], fn: .unknown, changedKey: try KeyCode(left))
            XCTAssertEqual(model[family], .activeSideUnknown)
            XCTAssertEqual(model.snapshot.fn, .unknown)
        }
    }

    func testPartialLossAndInconsistentSequenceNeverInventSides() throws {
        var model = ModifierReconstructor()
        model.recover(family: .command, left: true, right: false)
        model.recover(family: .option, left: false, right: true)
        model.markLoss(affected: [.option])
        XCTAssertEqual(model[.command], .left)
        XCTAssertEqual(model[.option], .activeSideUnknown)
        model.observeFlags(active: [.command], fn: .unknown, changedKey: try KeyCode(55))
        XCTAssertEqual(model[.command], .activeSideUnknown)
        XCTAssertEqual(model.snapshot.fn, .unknown)
    }

    func testUnknownFnCannotEscapeIntoNormalizedOutput() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let output = normalizer.process(try NormalizationFixtures.event(48,
            modifiers: mods(command: .left, fn: .unknown), generation: normalizer.gate.generation))
        XCTAssertEqual(output, .none)
        XCTAssertEqual(try output.sourceDelta.total.value, 0)
    }

    func testUnknownSideIsPreservedAsDistinctChordIdentity() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let modifiers = mods(command: .activeSideUnknown)
        let output = normalizer.process(try NormalizationFixtures.event(0,
            modifiers: modifiers, generation: normalizer.gate.generation))
        XCTAssertEqual(output, .keyDown(.chord(ChordBucket(chord: Chord(keyCode: try KeyCode(0),
            modifiers: modifiers), appBucket: .bundleID("test.app")),
            .init(kind: .discrete, scope: .normal)), .ordinaryObserved))
    }

    func testKeyUpAndRepeatAreNonCountingReducerSignals() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        for kind in [KeyEventKind.keyDown, .keyUp, .flagsChanged] {
            let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: kind, isAutoRepeat: true,
                modifiers: NormalizationFixtures.empty, source: .ordinaryObserved, generation: normalizer.gate.generation)
            let output = normalizer.process(event)
            XCTAssertEqual(try output.sourceDelta.total.value, 0)
            switch kind {
            case .keyDown: XCTAssertEqual(output, .repeatedKeyDown(try KeyCode(0)))
            case .keyUp: XCTAssertEqual(output, .keyUp(try KeyCode(0)))
            case .flagsChanged: XCTAssertEqual(output, .none)
            }
        }
        XCTAssertTrue(normalizer.gate.heldKeys.isEmpty)
    }

    func testEmptyAttributableIdentityClosesRatherThanBecomingUnknown() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
            secureInput: .disabled, foreground: .attributable(bundleID: ""), exclusion: .included))
        XCTAssertFalse(normalizer.gate.isOpen)
        XCTAssertEqual(normalizer.process(try NormalizationFixtures.event(generation: normalizer.gate.generation)), .none)
    }

    private func mods(command: ModifierSideState = .none, option: ModifierSideState = .none,
                      control: ModifierSideState = .none, shift: ModifierSideState = .none,
                      fn: FnState = .none) -> ModifierSet {
        ModifierSet(command: command, option: option, control: control, shift: shift, fn: fn)
    }
}

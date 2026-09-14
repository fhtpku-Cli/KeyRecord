import Foundation
import XCTest
import KeyRecordCore
import KeyRecordTestSupport

extension NormalizationTests {
    func testFlagSequenceRecoveryIsInsideGateAndCannotSurviveClosure() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let released = ObservedKeyEvent(keyCode: try KeyCode(55), kind: .flagsChanged, isAutoRepeat: false,
            modifiers: NormalizationFixtures.empty, source: .ordinaryObserved, generation: normalizer.gate.generation)
        XCTAssertEqual(normalizer.process(released, activeModifierFamilies: []), .none)
        let pressed = ObservedKeyEvent(keyCode: try KeyCode(55), kind: .flagsChanged, isAutoRepeat: false,
            modifiers: ModifierSet(fn: .none), source: .ordinaryObserved, generation: normalizer.gate.generation)
        XCTAssertEqual(normalizer.process(pressed, activeModifierFamilies: [.command]), .none)
        XCTAssertEqual(normalizer.gate.modifiers.command, .left)
        let terminal = try NormalizationFixtures.event(0, modifiers: ModifierSet(fn: .none),
            generation: normalizer.gate.generation)
        let recovered = ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none)
        XCTAssertEqual(normalizer.process(terminal, activeModifierFamilies: [.command]),
            .keyDown(.chord(ChordBucket(chord: Chord(keyCode: try KeyCode(0), modifiers: recovered),
                appBucket: .bundleID("test.app")), .init(kind: .discrete, scope: .normal)), .ordinaryObserved))
        normalizer.update(GateInputs())
        XCTAssertEqual(normalizer.process(pressed, activeModifierFamilies: [.command]), .none)
        normalizer.update(NormalizationFixtures.open)
        let fresh = try NormalizationFixtures.event(0, modifiers: ModifierSet(fn: .unknown),
            generation: normalizer.gate.generation)
        XCTAssertEqual(normalizer.process(fresh, activeModifierFamilies: [.command]), .none)
        XCTAssertEqual(normalizer.gate.modifiers.command, .activeSideUnknown)
        XCTAssertEqual(normalizer.gate.modifiers.fn, .unknown)
    }

    func testNormalizationBoundariesRejectPersistenceAttributionAndRawFlags() throws {
        let scratch = try SourceInspection.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let positive = try SourceInspection.compileCoreProbe("func probe() { _ = ChordNormalizer() }", in: scratch)
        XCTAssertEqual(positive.status, 0, positive.output)
        let probes = [
            ("func persist<T: Encodable>(_: T.Type) {}\nfunc probe() { persist(NormalizationOutput.self) }", "Encodable"),
            ("func restore<T: Decodable>(_: T.Type) {}\nfunc probe() { restore(NormalizationOutput.self) }", "Decodable"),
            ("func probe(_ key: KeyCode) { _ = NormalizedKey.bare(key, appBucket: .unknown) }", "extra argument"),
            ("func probe() { var model = ModifierReconstructor(); model.observeFlags(active: UInt64.max, fn: .none, changedKey: nil) }", "cannot convert"),
            ("func probe(_ output: NormalizationOutput) { _ = output.timestamp }", "timestamp"),
            ("func probe(_ output: NormalizationOutput) { _ = output.metadata }", "metadata"),
        ]
        for (source, diagnostic) in probes {
            let result = try SourceInspection.compileCoreProbe(source, in: scratch)
            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(result.output.contains(diagnostic), result.output)
        }
    }

    func testClosureReopenRejectsOldEventsButAcceptsFreshRecovery() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let stale = try NormalizationFixtures.event(generation: normalizer.gate.generation)
        _ = normalizer.process(stale)
        normalizer.update(GateInputs())
        let closedGeneration = normalizer.gate.generation
        normalizer.update(NormalizationFixtures.open)
        XCTAssertNotEqual(normalizer.gate.generation, closedGeneration)
        XCTAssertEqual(normalizer.process(stale), .none)
        XCTAssertEqual(normalizer.gate.modifiers, ModifierSet())
        let fresh = try NormalizationFixtures.event(generation: normalizer.gate.generation)
        XCTAssertEqual(normalizer.process(fresh), .keyDown(.bare(try KeyCode(0)), .ordinaryObserved))
    }

    func testForegroundAttributionIsChosenAtTerminalKeyBoundary() throws {
        var normalizer = ChordNormalizer()
        normalizer.update(NormalizationFixtures.open)
        let modifiers = ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none)
        let flags = ObservedKeyEvent(keyCode: try KeyCode(55), kind: .flagsChanged, isAutoRepeat: false,
            modifiers: modifiers, source: .ordinaryObserved, generation: normalizer.gate.generation)
        XCTAssertEqual(normalizer.process(flags), .none)
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
            secureInput: .disabled, foreground: .attributable(bundleID: "test.second"), exclusion: .included))
        let output = normalizer.process(try NormalizationFixtures.event(0, modifiers: modifiers,
            generation: normalizer.gate.generation))
        XCTAssertEqual(output, .keyDown(.chord(ChordBucket(chord: Chord(keyCode: try KeyCode(0),
            modifiers: modifiers), appBucket: .bundleID("test.second")),
            .init(kind: .discrete, scope: .normal)), .ordinaryObserved))
    }
}

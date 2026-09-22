import Foundation
import KeyRecordCore

/// Known scalar fixtures, never CGEvents or observations from the user's session.
func runOfflineChecks() throws -> Int {
    var checks = 0
    for source: EventSourceClass in [.productMarked, .ordinaryObserved, .suspectedInjection] {
        var normalizer = ChordNormalizer()
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available,
                                    sessionLock: .unlocked, secureInput: .disabled,
                                    foreground: .attributable(bundleID: "offline.fixture"), exclusion: .included))
        var aggregate = AggregationReducer(cycleID: CycleID(rawValue: "offline-fixture"))
        aggregate.update(normalizer.gate)
        let event = ObservedKeyEvent(keyCode: try KeyCode(105), kind: .keyDown,
                                    isAutoRepeat: false,
                                    modifiers: ModifierSet(command: .none, option: .none, control: .none,
                                                           shift: .none, fn: .none),
                                    source: source, generation: normalizer.gate.generation)
        let output = normalizer.process(event)
        let expected: NormalizationOutput
        switch source {
        case .productMarked: expected = .none
        case .ordinaryObserved: expected = .keyDown(.bare(try KeyCode(105)), .ordinaryObserved)
        case .suspectedInjection: expected = .keyDown(.bare(try KeyCode(105)), .suspectedInjection)
        }
        guard output == expected else { throw HarnessFailure.offlineCheckFailed("source classification") }
        try aggregate.process(output, generation: event.generation, clock: OfflineClock())
        let total = aggregate.bareKeys.reduce(0) { $0 + $1.sourceCounts.total.value }
        let expectedTotal = source == .productMarked ? 0 : 1
        guard total == expectedTotal else { throw HarnessFailure.offlineCheckFailed("aggregate count") }
        checks += 2
    }
    return checks
}

private struct OfflineClock: LocalClock {
    var calendar: Calendar { Calendar(identifier: .gregorian) }
    var timeZone: TimeZone { TimeZone.gmt }
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

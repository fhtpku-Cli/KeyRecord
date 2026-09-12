import KeyRecordCore

enum NormalizationFixtures {
    static let open = GateInputs(collecting: true, keyAvailability: .available,
        sessionLock: .unlocked, secureInput: .disabled,
        foreground: .attributable(bundleID: "test.app"), exclusion: .included)
    static let empty = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)

    static func event(_ code: Int = 0, modifiers: ModifierSet = empty,
                      generation: CaptureGeneration) throws -> ObservedKeyEvent {
        ObservedKeyEvent(keyCode: try KeyCode(code), kind: .keyDown, isAutoRepeat: false,
            modifiers: modifiers, source: .ordinaryObserved, generation: generation)
    }
}

import Foundation

public enum KeyEventKind: Sendable { case keyDown, keyUp, flagsChanged }
public enum EventSourceClass: Sendable { case ordinaryObserved, productMarked, suspectedInjection }

public struct CaptureGeneration: Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Architecture §4.2 and plan contract 5: transient, no timestamp, no serialization or storage capability.
public struct ObservedKeyEvent: Sendable {
    public let keyCode: KeyCode
    public let kind: KeyEventKind
    public let isAutoRepeat: Bool
    public let modifiers: ModifierSet
    public let source: EventSourceClass
    public let generation: CaptureGeneration

    public init(
        keyCode: KeyCode, kind: KeyEventKind, isAutoRepeat: Bool,
        modifiers: ModifierSet, source: EventSourceClass, generation: CaptureGeneration
    ) {
        self.keyCode = keyCode
        self.kind = kind
        self.isAutoRepeat = isAutoRepeat
        self.modifiers = modifiers
        self.source = source
        self.generation = generation
    }
}

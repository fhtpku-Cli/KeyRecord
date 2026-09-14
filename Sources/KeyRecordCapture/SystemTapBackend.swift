import CoreGraphics
import KeyRecordCore

private final class TapContext: Sendable {
    let queue: CaptureQueue
    let handoff: @Sendable (ObservedKeyEvent) -> EventHandoffResult
    let invalidate: @Sendable (CaptureInvalidation) -> Void

    init(queue: CaptureQueue, handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult,
         invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) {
        self.queue = queue
        self.handoff = handoff
        self.invalidate = invalidate
    }
}

private let captureCallback: CGEventTapCallBack = { _, type, event, pointer in
    guard let pointer else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(pointer).takeUnretainedValue()
    let generation = context.queue.generation
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        context.invalidate(.tapDisabled)
        return Unmanaged.passUnretained(event)
    }
    if let observed = decodeCaptureEvent(type: type, event: event, generation: generation) {
        _ = context.handoff(observed)
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class SystemTapBackend: CaptureTapBackend {
    private let queue: CaptureQueue
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var context: TapContext?
    private var workspaceFence: CaptureWorkspaceFence?
    private var invalidate: (@Sendable (CaptureInvalidation) -> Void)?
    private nonisolated let cached = CaptureLock(CaptureProviderSnapshot.unknown)

    init(queue: CaptureQueue) { self.queue = queue }

    isolated deinit {
        workspaceFence?.stop()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }

    func subscribe(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) {
        workspaceFence?.stop()
        let cached = self.cached
        let receive: @Sendable (CaptureInvalidation) -> Void = { reason in
            cached.withLock { $0 = .unknown }
            invalidate(reason)
        }
        self.invalidate = receive
        workspaceFence = CaptureWorkspaceFence(invalidate: receive)
    }

    func readProviders() async -> CaptureProviderSnapshot {
        guard workspaceFence != nil, CGPreflightListenEventAccess() else {
            invalidate?(.permissionRevoked)
            return .unknown
        }
        let generation = queue.generation
        let foreground = await SystemForegroundProvider().foregroundState()
        let secure = await SystemSecureInputProvider().secureInputState()
        // No qualified initial lock witness or complete security-change feed exists yet.
        // Unknown keeps this backend closed; cached samples alone cannot authorize live capture.
        let lock = await UnqualifiedSessionLockProvider().sessionLockState()
        let current = CaptureProviderSnapshot(GateInputs(sessionLock: lock, secureInput: secure, foreground: foreground))
        guard queue.generation == generation else { return .unknown }
        cached.withLock { $0 = current }
        return current
    }

    nonisolated func cachedProviders() -> CaptureProviderSnapshot { cached.withLock { $0 } }

    func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) throws {
        guard tap == nil else { throw CaptureStartError.alreadyStarted }
        guard workspaceFence != nil, let invalidate,
              queue.validate(queue.snapshot, current: cachedProviders()) else { throw CaptureStartError.closed }
        guard CGPreflightListenEventAccess() else {
            invalidate(.permissionRevoked)
            throw CaptureStartError.revoked
        }
        let context = TapContext(queue: queue, handoff: handoff, invalidate: invalidate)
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: captureCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()) else { throw CaptureStartError.unavailable }
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw CaptureStartError.unavailable
        }
        self.context = context
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        queue.revoke()
        workspaceFence?.stop()
        workspaceFence = nil
        invalidate = nil
        cached.withLock { $0 = .unknown }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        context = nil
    }
}

private func decodeCaptureEvent(type: CGEventType, event: CGEvent,
                                generation: CaptureGeneration) -> ObservedKeyEvent? {
    let kind: KeyEventKind
    switch type {
    case .keyDown: kind = .keyDown
    case .keyUp: kind = .keyUp
    case .flagsChanged: kind = .flagsChanged
    default: return nil
    }
    guard let key = try? KeyCode(Int(event.getIntegerValueField(.keyboardEventKeycode))) else { return nil }
    let flags = event.flags
    let modifiers = ModifierSet(
        command: flags.contains(.maskCommand) ? .activeSideUnknown : .none,
        option: flags.contains(.maskAlternate) ? .activeSideUnknown : .none,
        control: flags.contains(.maskControl) ? .activeSideUnknown : .none,
        shift: flags.contains(.maskShift) ? .activeSideUnknown : .none,
        fn: flags.contains(.maskSecondaryFn) ? .active : .none)
    let marker = event.getIntegerValueField(.eventSourceUserData)
    let source: EventSourceClass = marker == 0x4b_52_53_50_31_54_45_53 ? .productMarked
        : marker == 0 ? .ordinaryObserved : .suspectedInjection
    return ObservedKeyEvent(keyCode: key, kind: kind,
        isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        modifiers: modifiers, source: source, generation: generation)
}

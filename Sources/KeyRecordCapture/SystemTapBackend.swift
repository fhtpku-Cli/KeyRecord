import Foundation
import CoreGraphics
import KeyRecordCore

private final class TapContext: Sendable {
    let queue: CaptureQueue
    let handoff: @Sendable (ObservedKeyEvent) -> EventHandoffResult
    let invalidate: @Sendable (CaptureInvalidation) -> Void

    #if DEBUG
    let diagnostics: CaptureDiagnosticsRecorder?
    init(queue: CaptureQueue, handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult,
         invalidate: @escaping @Sendable (CaptureInvalidation) -> Void,
         diagnostics: CaptureDiagnosticsRecorder?) {
        self.diagnostics = diagnostics
        self.queue = queue
        self.handoff = handoff
        self.invalidate = invalidate
    }
    #else
    init(queue: CaptureQueue, handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult,
         invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) {
        self.queue = queue
        self.handoff = handoff
        self.invalidate = invalidate
    }
    #endif
}

private let captureCallback: CGEventTapCallBack = { _, type, event, pointer in
    guard let pointer else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(pointer).takeUnretainedValue()
    #if DEBUG
    switch type {
    case .keyDown: context.diagnostics?.increment(.tapCallbackKeyDown)
    case .keyUp: context.diagnostics?.increment(.tapCallbackKeyUp)
    case .flagsChanged: context.diagnostics?.increment(.tapCallbackFlagsChanged)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        context.diagnostics?.increment(.tapDisabledEvent)
    default: break
    }
    #endif
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
    private let sessionLock: any SessionLockProvider
    private let permission: any InputMonitoringPermission
    #if DEBUG
    private var diagnostics: CaptureDiagnosticsRecorder?

    func setDiagnostics(_ recorder: CaptureDiagnosticsRecorder) {
        diagnostics = recorder
    }
    #endif

    init(queue: CaptureQueue, sessionLock: any SessionLockProvider = UnqualifiedSessionLockProvider(),
         permission: any InputMonitoringPermission = SystemInputMonitoringPermission()) {
        self.queue = queue
        self.sessionLock = sessionLock
        self.permission = permission
    }

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
        // Read-only: preflight never prompts. Requesting the grant is the exclusive job of
        // the user-initiated start path (KR-07), so a provider read can never pop a dialog.
        guard workspaceFence != nil, permission.preflight() == .granted else {
            invalidate?(.permissionRevoked)
            return .unknown
        }
        let generation = queue.generation
        let foreground = await SystemForegroundProvider().foregroundState()
        let secure = await SystemSecureInputProvider().secureInputState()
        // Default witness stays .unknown (gate closed); only an explicit caller injects a real lock witness.
        let lock = await sessionLock.sessionLockState()
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
        // Final fail-closed re-check immediately before the tap is created. The prompt is
        // NOT shown here: by this point an explicit user start has already handled the
        // denied case. A revocation between entry and here must close, not re-prompt.
        guard permission.preflight() == .granted else {
            invalidate(.permissionRevoked)
            throw CaptureStartError.revoked
        }
        #if DEBUG
        let context = TapContext(queue: queue, handoff: handoff, invalidate: invalidate,
                                 diagnostics: diagnostics)
        #else
        let context = TapContext(queue: queue, handoff: handoff, invalidate: invalidate)
        #endif
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
        // Apple documents that "event taps are normally enabled when created", so this is a
        // defensive no-op on a fresh tap, NOT an explanation for missing callbacks. It is
        // retained because re-enabling is genuinely required after a
        // tapDisabledByTimeout/UserInput event.
        CGEvent.tapEnable(tap: tap, enable: true)
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

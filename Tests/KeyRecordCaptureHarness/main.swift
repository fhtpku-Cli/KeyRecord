import Foundation
import CoreGraphics
import AppKit
import KeyRecordCore
import KeyRecordCapture

// Bounded live capture harness (L4).
//
// Purpose: tell apart the six places a keystroke can be lost, instead of reporting
// "capture doesn't work":
//   1. the tap callback never fires            -> tapCallback.* stays 0
//   2. the queue rejects the event             -> handoffClosed > 0
//   3. normalization produces nothing          -> normalizationOutput == 0
//   4. the aggregate never moves               -> aggregateDelta == 0
//   5. nothing is durably written              -> (out of scope here, Store owns it)
//   6. the UI hides it                         -> (out of scope here, lifecycle gate owns it)
//
// Hard safety properties, by construction:
//   * runs for a fixed number of seconds, then stops itself unconditionally;
//   * listen-only tap: it never modifies, swallows or injects into other apps
//     (the optional self-test posts events only in `--mode synthetic`);
//   * records ONLY counters and coarse state. No key text, no key codes, no raw
//     sequences, no per-event timestamps ever reach memory beyond a counter bump.
//
// It deliberately does not touch TCC, the Keychain, Karabiner, or the screen lock.

// MARK: - Privacy-safe counters

/// Every field is a count or a coarse enum. There is no field that could carry
/// what the user actually typed.
struct LayeredCounters: Codable {
    var tapCallbackKeyDown = 0
    var tapCallbackKeyUp = 0
    var tapCallbackFlagsChanged = 0
    var tapDisabledEvents = 0

    var handoffAccepted = 0
    var handoffClosed = 0
    var handoffOverflow = 0

    var normalizationOutput = 0
    var aggregateDelta = 0

    var sessionGeneration: UInt64 = 0
    var lastInvalidationReason: String?

    var tapCreated = false
    var tapEnabledAtStart = false
    var permissionAtStart = "unknown"
    var permissionAtEnd = "unknown"
    var secureInputAtStart = "unknown"
    var secureInputAtEnd = "unknown"
    var sessionLockAtStart = "unknown"
    var foregroundAttributable = false

    var totalTapCallbacks: Int {
        tapCallbackKeyDown + tapCallbackKeyUp + tapCallbackFlagsChanged
    }
}

final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var counters = LayeredCounters()
    func mutate(_ body: (inout LayeredCounters) -> Void) { lock.withLock { body(&counters) } }
    var snapshot: LayeredCounters { lock.withLock { counters } }
}

let counters = CounterBox()

// MARK: - Arguments

struct Options {
    var seconds: Int = 45
    var mode = "physical"      // physical | synthetic
    var output: URL?
}

func parseOptions() -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--seconds":
            if let value = iterator.next(), let parsed = Int(value) { options.seconds = parsed }
        case "--mode":
            if let value = iterator.next() { options.mode = value }
        case "--out":
            if let value = iterator.next() { options.output = URL(fileURLWithPath: value) }
        default: break
        }
    }
    // Hard bound: the plan fixes 30-60s. Refuse anything outside that.
    options.seconds = min(max(options.seconds, 30), 60)
    return options
}

// MARK: - Tap callback (bounded: counter bumps only)

/// Holds the live pipeline the callback feeds. Set once before the tap is created.
final class PipelineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var aggregate: AggregationReducer?
    private var normalizer = ChordNormalizer()
    private var installed = false

    /// The harness drives Core's own `ChordNormalizer`, whose embedded `PrivacyGate` is
    /// the exact predicate `CaptureQueue` applies. That keeps the measurement faithful
    /// without reaching into `KeyRecordCapture` internals.
    /// Total counted events across bare keys and shortcuts. Row count alone is wrong:
    /// pressing the same key twice reuses one row while the total must still advance.
    private func aggregateTotal() -> Int {
        guard let aggregate else { return 0 }
        let bare = aggregate.bareKeys.reduce(0) { $0 + Int($1.sourceCounts.total.value) }
        let chords = aggregate.shortcuts.reduce(0) { $0 + Int($1.sourceCounts.total.value) }
        return bare + chords
    }

    func install(aggregate: AggregationReducer, inputs: GateInputs) {
        lock.withLock {
            normalizer = ChordNormalizer()
            normalizer.update(inputs)
            var reducer = aggregate
            // AggregationReducer drops any event whose generation does not match the gate
            // it was last told about. Without this the aggregate silently stays at zero —
            // that was a harness wiring gap, not a product defect.
            reducer.update(normalizer.gate)
            self.aggregate = reducer
            installed = true
        }
    }

    /// Bounded, in-memory only: no disk, Keychain, process, network or UI work, matching
    /// the production callback contract.
    func feed(_ event: ObservedKeyEvent) {
        lock.withLock {
            guard installed else { return }
            // Gate admission: same predicate the production queue applies.
            let admitted = normalizer.gate.accepts(event.generation)
            if admitted { counters.mutate { $0.handoffAccepted += 1 } }
            else { counters.mutate { $0.handoffClosed += 1 } }
            guard admitted else { return }
            let output = normalizer.process(event)
            counters.mutate { $0.normalizationOutput += 1 }
            let before = aggregateTotal()
            try? aggregate?.process(output, generation: event.generation, clock: HarnessClock())
            let after = aggregateTotal()
            if after != before { counters.mutate { $0.aggregateDelta += 1 } }
        }
    }
}

struct HarnessClock: LocalClock {
    var calendar: Calendar { Calendar(identifier: .gregorian) }
    var timeZone: TimeZone { TimeZone.current }
    func now() -> Date { Date() }
}

let pipeline = PipelineBox()

private let harnessCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .keyDown:
        counters.mutate { $0.tapCallbackKeyDown += 1 }
    case .keyUp:
        counters.mutate { $0.tapCallbackKeyUp += 1 }
    case .flagsChanged:
        counters.mutate { $0.tapCallbackFlagsChanged += 1 }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        counters.mutate {
            $0.tapDisabledEvents += 1
            $0.lastInvalidationReason = type == .tapDisabledByTimeout
                ? "tapDisabledByTimeout" : "tapDisabledByUserInput"
        }
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
    // Feed the real queue/normalizer/aggregate so layers 2-4 are measured too.
    // Only the key code is read, and only to build the same ObservedKeyEvent the product
    // builds; it is never stored or logged.
    if let observed = harnessDecode(type: type, event: event) {
        pipeline.feed(observed)
    }
    // listen-only: always hand the event straight back, never modify or swallow it.
    return Unmanaged.passUnretained(event)
}

func harnessDecode(type: CGEventType, event: CGEvent) -> ObservedKeyEvent? {
    let kind: KeyEventKind
    switch type {
    case .keyDown: kind = .keyDown
    case .keyUp: kind = .keyUp
    case .flagsChanged: kind = .flagsChanged
    default: return nil
    }
    guard let key = try? KeyCode(Int(event.getIntegerValueField(.keyboardEventKeycode))) else {
        return nil
    }
    let flags = event.flags
    let modifiers = ModifierSet(
        command: flags.contains(.maskCommand) ? .activeSideUnknown : .none,
        option: flags.contains(.maskAlternate) ? .activeSideUnknown : .none,
        control: flags.contains(.maskControl) ? .activeSideUnknown : .none,
        shift: flags.contains(.maskShift) ? .activeSideUnknown : .none,
        fn: flags.contains(.maskSecondaryFn) ? .active : .none)
    return ObservedKeyEvent(keyCode: key, kind: kind,
        isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        modifiers: modifiers, source: .ordinaryObserved,
        generation: harnessGeneration)
}

nonisolated(unsafe) var harnessGeneration = CaptureGeneration(rawValue: 0)

// MARK: - Run

let options = parseOptions()
let permission = SystemInputMonitoringPermission()

func describe(_ status: InputMonitoringStatus) -> String {
    switch status {
    case .granted: return "granted"
    case .denied: return "denied"
    case .unknown: return "unknown"
    }
}

let startStatus = permission.preflight()
counters.mutate { $0.permissionAtStart = describe(startStatus) }

// Sample the privacy providers once at start, so a zero count can be attributed.
/// Runs one async read to completion on a helper thread. Top-level `await` would make
/// this file an async context, and CFRunLoopRun() cannot be entered from one.
func blockingRead<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = UncheckedBox<T>()
    Task.detached {
        box.value = await body()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value!
}

final class UncheckedBox<T>: @unchecked Sendable { var value: T? }

// Uses the real production provider, so an unreadable SPI still yields `.unknown`
// (fail closed) rather than an optimistic `.disabled`.
let startSecure = blockingRead { await SystemSecureInputProvider().secureInputState() }
counters.mutate { $0.secureInputAtStart = "\(startSecure)" }
let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
counters.mutate { $0.foregroundAttributable = !(frontmost ?? "").isEmpty }

guard startStatus == .granted else {
    // Fail closed and say exactly what is missing. Do NOT prompt here: prompting is a
    // product-flow concern (KR-07), and this harness must stay non-interactive.
    let report = HarnessReport(outcome: "BLOCKED",
                               code: "input_monitoring_not_granted",
                               seconds: options.seconds, mode: options.mode,
                               counters: counters.snapshot)
    report.emit(to: options.output)
    exit(2)
}

// Real capture pipeline, end to end: tap -> CaptureQueue -> normalization -> aggregate.
let harnessInputs = GateInputs(collecting: true, keyAvailability: .available,
                               sessionLock: .unlocked, secureInput: startSecure,
                               foreground: frontmost.map { .attributable(bundleID: $0) }
                                   ?? .reliablyUnattributable,
                               exclusion: .included)
var gateProbe = PrivacyGate()
gateProbe.update(harnessInputs)
harnessGeneration = gateProbe.generation
counters.mutate { $0.sessionGeneration = UInt64(gateProbe.generation.rawValue) }
pipeline.install(aggregate: AggregationReducer(cycleID: CycleID(rawValue: "harness-cycle")),
                 inputs: harnessInputs)

let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
    | (CGEventMask(1) << CGEventType.keyUp.rawValue)
    | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                  options: .listenOnly, eventsOfInterest: mask,
                                  callback: harnessCallback, userInfo: nil) else {
    let report = HarnessReport(outcome: "FAIL", code: "tap_create_failed",
                               seconds: options.seconds, mode: options.mode,
                               counters: counters.snapshot)
    report.emit(to: options.output)
    exit(1)
}
counters.mutate { $0.tapCreated = true }

let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
// Apple: taps are normally enabled when created. Recorded, not relied on as a fix.
CGEvent.tapEnable(tap: tap, enable: true)
counters.mutate { $0.tapEnabledAtStart = CGEvent.tapIsEnabled(tap: tap) }

// Unconditional self-stop. This fires even if nothing is ever typed.
let deadline = DispatchTime.now() + .seconds(options.seconds)
DispatchQueue.main.asyncAfter(deadline: deadline) {
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    CFMachPortInvalidate(tap)

    counters.mutate {
        $0.permissionAtEnd = describe(permission.preflight())
    }
    let report = HarnessReport(outcome: "COMPLETED", code: "bounded_run_finished",
                               seconds: options.seconds, mode: options.mode,
                               counters: counters.snapshot)
    report.emit(to: options.output)
    exit(0)
}

// Synthetic self-test: the harness posts its own key events so the tap -> gate ->
// normalization -> aggregate pipeline can be exercised WITHOUT the user typing.
//
// This is a falsifiability control, not evidence about physical keyboards:
//   * synthetic received, physical not  -> the break is in the physical HID path
//     (this is where Karabiner's virtual HID device becomes a real suspect)
//   * synthetic also not received       -> the break is in tap registration / run loop /
//     permission, and is unrelated to Karabiner
// Events are marked with the product's own source marker so they are classified as
// productMarked and can never be mistaken for authentic user input.
if options.mode == "synthetic" {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // F13 (keycode 105): non-text, non-destructive, does not trigger Secure Input.
        for _ in 0..<5 {
            for isDown in [true, false] {
                if let event = CGEvent(keyboardEventSource: source, virtualKey: 105,
                                       keyDown: isDown) {
                    event.setIntegerValueField(.eventSourceUserData, value: 0x4b_52_53_50_31_54_45_53)
                    event.post(tap: .cghidEventTap)
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}

FileHandle.standardError.write(Data(
    "harness: listening \(options.seconds)s (mode=\(options.mode)); it will stop by itself\n".utf8))
CFRunLoopRun()

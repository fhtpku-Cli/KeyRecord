import AppKit
import CoreGraphics
import Darwin
import Foundation
import Phase0Support

struct ListenOnlySP2LiveExecutor: SP2LiveScenarioExecuting {
    func execute(d1: Bool, d3: Bool, d4: Bool, secureHelper: SecureInputState?) -> SP2LiveExecution {
        _ = secureHelper
        guard SP2LiveArming.isArmed else {
            return SP2LiveExecution(armed: false, completed: false, secureInputEnabled: false, sleepWakeConfirmed: false)
        }
        guard d1 else {
            return SP2LiveExecution(armed: true, completed: false, secureInputEnabled: false, sleepWakeConfirmed: false)
        }
        let completed = SP2LiveListenRuntime.run(d3Allowed: d3, d4Allowed: d4)
        return SP2LiveExecution(
            aggregate: completed.aggregate,
            armed: true,
            completed: completed.finished,
            secureInputEnabled: completed.secureInputEnabled,
            sleepWakeConfirmed: completed.sleepWakeConfirmed
        )
    }
}

struct ProcessEnvironmentSP2LiveExecutor: SP2LiveScenarioExecuting {
    func execute(d1: Bool, d3: Bool, d4: Bool, secureHelper: SecureInputState?) -> SP2LiveExecution {
        ListenOnlySP2LiveExecutor().execute(d1: d1, d3: d3, d4: d4, secureHelper: secureHelper)
    }
}

private enum SP2LiveListenRuntime {
    struct Result {
        var aggregate: SP2LiveAggregateV2
        var finished: Bool
        var secureInputEnabled: Bool
        var sleepWakeConfirmed: Bool
    }

    static let secureHelperPath = "/usr/local/libexec/keyrecord-secure-input-status"

    static func windowSeconds() -> CFTimeInterval {
        let raw = ProcessInfo.processInfo.environment["KEYRECORD_SP2_WINDOW_SECONDS"].flatMap(Double.init) ?? 15
        return min(max(raw, 1), 30)
    }

    static func d3Seconds() -> CFTimeInterval {
        let raw = ProcessInfo.processInfo.environment["KEYRECORD_SP2_D3_SECONDS"].flatMap(Double.init) ?? 15
        return min(max(raw, 1), 60)
    }

    static func run(d3Allowed: Bool, d4Allowed: Bool) -> Result {
        guard CGPreflightListenEventAccess() else {
            return Result(aggregate: SP2LiveAggregateV2(), finished: false, secureInputEnabled: false, sleepWakeConfirmed: false)
        }

        var reducer = SP2LiveAggregateV2Reducer()
        var privacy = PrivacyTransitionModel()
        var modifiers = ModifierReconstructionModel()

        func secureInput() -> SecureInputState {
            readSecureInputHelper(at: secureHelperPath) ?? .unknown
        }

        func observeTerminalKeyDown() {
            let gateOpen = privacy.gateOpen
            let secure = secureInput()
            let frontmost = SP2Probe.boundedFrontmostMetadataPreflightForExecutor()
            let attribution = frontmostAttribution(frontmost)
            _ = privacy.observeTerminalKeyDown(
                frontmost: frontmost,
                secureInput: secure,
                excludedBundleIDs: []
            )
            reducer.recordTerminalKeyDown(gateOpen: gateOpen, secureInput: secure, frontmost: attribution)
        }

        func observeFlagsChanged(_ flags: CGEventFlags) {
            let fnActive = flags.contains(.maskSecondaryFn)
            modifiers.applyFn(active: fnActive)
            let gateOpen = privacy.gateOpen
            let secure = secureInput()
            reducer.recordFnRecoverySnapshot(modifiers.fn, gateOpen: gateOpen, secureInput: secure)
        }

        func performTapReset() {
            let gateOpen = privacy.gateOpen
            let secure = secureInput()
            _ = privacy.tapReset()
            modifiers.invalidate(for: .tapReset)
            reducer.recordTapReset(gateOpen: gateOpen, secureInput: secure)
            reducer.recordFnRecoverySnapshot(modifiers.fn, gateOpen: gateOpen, secureInput: secure)
        }

        guard collectEvents(
            for: windowSeconds(),
            onKeyDown: { _ in observeTerminalKeyDown() },
            onFlagsChanged: { _ in }
        ) else { return Result(aggregate: reducer.aggregate, finished: false, secureInputEnabled: false, sleepWakeConfirmed: false) }

        guard collectEvents(
            for: windowSeconds(),
            onKeyDown: { _ in observeTerminalKeyDown() },
            onFlagsChanged: { _ in }
        ) else { return Result(aggregate: reducer.aggregate, finished: false, secureInputEnabled: false, sleepWakeConfirmed: false) }

        guard collectEvents(
            for: windowSeconds(),
            onKeyDown: { _ in },
            onFlagsChanged: { flags in observeFlagsChanged(flags) }
        ) else { return Result(aggregate: reducer.aggregate, finished: false, secureInputEnabled: false, sleepWakeConfirmed: false) }

        performTapReset()

        guard collectEvents(
            for: windowSeconds(),
            onKeyDown: { _ in },
            onFlagsChanged: { flags in observeFlagsChanged(flags) }
        ) else { return Result(aggregate: reducer.aggregate, finished: false, secureInputEnabled: false, sleepWakeConfirmed: false) }

        let secureInputEnabled = d3Allowed ? pollSecureInputEnabled(seconds: d3Seconds()) : false
        let sleepWakeConfirmed = d4Allowed ? confirmSleepWakeCycle() : false

        return Result(
            aggregate: reducer.aggregate,
            finished: true,
            secureInputEnabled: secureInputEnabled,
            sleepWakeConfirmed: sleepWakeConfirmed
        )
    }

    private static func pollSecureInputEnabled(seconds: CFTimeInterval) -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + seconds
        while CFAbsoluteTimeGetCurrent() < deadline {
            if readSecureInputHelper(at: secureHelperPath) == .enabled { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return readSecureInputHelper(at: secureHelperPath) == .enabled
    }

    private static func confirmSleepWakeCycle() -> Bool {
        guard ProcessInfo.processInfo.environment["KEYRECORD_SP2_D4_LIVE"] == "1" else { return false }
        let box = SleepWakeWitnessBox()
        let center = NSWorkspace.shared.notificationCenter
        let sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { _ in box.markSleep() }
        let wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { _ in box.markWake() }
        defer {
            center.removeObserver(sleepObserver)
            center.removeObserver(wakeObserver)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", "/usr/bin/pmset", "sleepnow"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }

        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if box.didSleep, box.didWake { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return box.didSleep && box.didWake
    }

    private static func frontmostAttribution(_ state: FrontmostState) -> SP2FrontmostAttribution {
        switch state {
        case let .known(bundleID):
            return bundleID.isEmpty ? .knownUnattributable : .knownAttributable
        case .knownUnattributable:
            return .knownUnattributable
        case .indeterminate:
            return .indeterminate
        }
    }

    private static func readSecureInputHelper(at path: String) -> SecureInputState? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--once"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        switch String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
        case "enabled": return .enabled
        case "disabled": return .disabled
        case "unknown": return .unknown
        default: return nil
        }
    }

    private static func collectEvents(
        for seconds: CFTimeInterval,
        onKeyDown: @escaping (CGEvent) -> Void,
        onFlagsChanged: @escaping (CGEventFlags) -> Void
    ) -> Bool {
        guard CGPreflightListenEventAccess() else { return false }
        let box = SP2ListenBox(onKeyDown: onKeyDown, onFlagsChanged: onFlagsChanged)
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: sp2ListenCallback,
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let deadline = CFAbsoluteTimeGetCurrent() + seconds
        while CFAbsoluteTimeGetCurrent() < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        CFMachPortInvalidate(tap)
        return true
    }
}

private final class SleepWakeWitnessBox: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _didSleep = false
    private var _didWake = false

    var didSleep: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _didSleep
    }

    var didWake: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _didWake
    }

    func markSleep() {
        os_unfair_lock_lock(&lock)
        _didSleep = true
        os_unfair_lock_unlock(&lock)
    }

    func markWake() {
        os_unfair_lock_lock(&lock)
        _didWake = true
        os_unfair_lock_unlock(&lock)
    }
}

private final class SP2ListenBox: @unchecked Sendable {
    let onKeyDown: (CGEvent) -> Void
    let onFlagsChanged: (CGEventFlags) -> Void
    init(onKeyDown: @escaping (CGEvent) -> Void, onFlagsChanged: @escaping (CGEventFlags) -> Void) {
        self.onKeyDown = onKeyDown
        self.onFlagsChanged = onFlagsChanged
    }
}

private func sp2ListenCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<SP2ListenBox>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .keyDown:
        if !event.isAutoRepeat { box.onKeyDown(event) }
    case .flagsChanged:
        box.onFlagsChanged(event.flags)
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

private extension CGEvent {
    var isAutoRepeat: Bool {
        getIntegerValueField(.keyboardEventAutorepeat) != 0
    }
}

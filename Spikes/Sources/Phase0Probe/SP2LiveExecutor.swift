import AppKit
import CoreGraphics
import Darwin
import Foundation
import Phase0Support

struct ListenOnlySP2LiveExecutor: SP2LiveScenarioExecuting {
    func execute(d1: Bool, d3: Bool, d4: Bool, secureHelper: SecureInputState?) -> SP2LiveExecution {
        guard SP2LiveArming.isArmed else {
            return SP2LiveExecution(armed: false, completed: false, secureInputEnabled: false, sleepWakeConfirmed: false)
        }
        guard d1 else {
            return SP2LiveExecution(armed: true, completed: false, secureInputEnabled: false, sleepWakeConfirmed: false)
        }
        let secureInputEnabled = d3 && secureHelper == .enabled
        let completed = SP2LiveListenRuntime.run(secureInputEnabled: secureInputEnabled, sleepWakeAllowed: d4)
        return SP2LiveExecution(
            aggregate: completed.aggregate,
            armed: true,
            completed: completed.finished,
            secureInputEnabled: secureInputEnabled,
            sleepWakeConfirmed: false
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
    }

    static func windowSeconds() -> CFTimeInterval {
        let raw = ProcessInfo.processInfo.environment["KEYRECORD_SP2_WINDOW_SECONDS"].flatMap(Double.init) ?? 15
        return min(max(raw, 1), 30)
    }

    static func run(secureInputEnabled: Bool, sleepWakeAllowed: Bool) -> Result {
        _ = sleepWakeAllowed
        guard CGPreflightListenEventAccess() else {
            return Result(aggregate: SP2LiveAggregateV2(), finished: false)
        }

        var reducer = SP2LiveAggregateV2Reducer()
        var privacy = PrivacyTransitionModel()
        var modifiers = ModifierReconstructionModel()
        let helperPath = "/usr/local/libexec/keyrecord-secure-input-status"

        func secureInput() -> SecureInputState {
            if secureInputEnabled { return .enabled }
            return readSecureInputHelper(at: helperPath) ?? .unknown
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
        ) else { return Result(aggregate: reducer.aggregate, finished: false) }

        guard collectEvents(
            for: windowSeconds(),
            onKeyDown: { _ in observeTerminalKeyDown() },
            onFlagsChanged: { _ in }
        ) else { return Result(aggregate: reducer.aggregate, finished: false) }

        guard collectEvents(
            for: windowSeconds(),
            onKeyDown: { _ in },
            onFlagsChanged: { flags in observeFlagsChanged(flags) }
        ) else { return Result(aggregate: reducer.aggregate, finished: false) }

        performTapReset()

        guard collectEvents(
            for: windowSeconds(),
            onKeyDown: { _ in },
            onFlagsChanged: { flags in observeFlagsChanged(flags) }
        ) else { return Result(aggregate: reducer.aggregate, finished: false) }

        return Result(aggregate: reducer.aggregate, finished: true)
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

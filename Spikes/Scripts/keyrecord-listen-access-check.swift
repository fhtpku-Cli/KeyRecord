import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst()
let mode = args.first ?? "check"

@discardableResult
func tryTap() -> Bool {
    let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
        userInfo: nil
    ) else { return false }
    CFMachPortInvalidate(tap)
    return true
}

switch mode {
case "listen":
    let seconds = Double(args.dropFirst().first ?? "10") ?? 10
    let tapName = args.dropFirst().dropFirst().first ?? "session"
    let location: CGEventTapLocation = tapName == "annotated" ? .cgAnnotatedSessionEventTap : .cgSessionEventTap
    guard CGPreflightListenEventAccess() else { print("preflight=false"); exit(1) }
    final class Box { var keys: [UInt16] = [] }
    let box = Box()
    let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
    let callback: CGEventTapCallBack = { _, type, event, ref in
        if type == .keyDown, let ref {
            let box = Unmanaged<Box>.fromOpaque(ref).takeUnretainedValue()
            box.keys.append(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        }
        return Unmanaged.passUnretained(event)
    }
    guard let tap = CGEvent.tapCreate(
        tap: location,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: Unmanaged.passUnretained(box).toOpaque()
    ) else { print("tap_create=false tap=\(tapName)"); exit(1) }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    let deadline = CFAbsoluteTimeGetCurrent() + min(max(seconds, 1), 30)
    while CFAbsoluteTimeGetCurrent() < deadline {
        _ = CFRunLoopRunInMode(.defaultMode, 0.05, true)
    }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
    CFMachPortInvalidate(tap)
    print("tap=\(tapName) keys=\(box.keys)")
case "request":
    let before = CGPreflightListenEventAccess()
    let granted = CGRequestListenEventAccess()
    let after = CGPreflightListenEventAccess()
    print("preflight_before=\(before)")
    print("request=\(granted)")
    print("preflight_after=\(after)")
    print("tap_create=\(tryTap())")
case "check":
    fallthrough
default:
    print("preflight=\(CGPreflightListenEventAccess())")
    print("tap_create=\(tryTap())")
    if let exe = Bundle.main.executableURL {
        print("executable=\(exe.path)")
    } else {
        print("executable=\(CommandLine.arguments[0])")
    }
}

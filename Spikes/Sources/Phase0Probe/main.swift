import CoreGraphics
import Darwin
import Foundation
import IOKit.hid
import Phase0Support

public enum Phase0ProbeCommand {
    public static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["help"] || arguments.isEmpty {
                print("Phase0Probe development spike harness; supported commands: preflight, atomicity, sp1, sp2, sp3, sp4a, sp4b, sp5a, sp6a, sp6b")
                return
            }
            if arguments.first == "atomicity" {
                try AtomicityProbe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp1" {
                try SP1Probe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp2" {
                try SP2Probe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp3" {
                try SP3Probe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp4a" {
                try SP4AProbe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp4b" {
                try SP4BProbe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp5a" {
                try SP5AProbe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp6a" {
                try SP6AProbe.run(arguments: arguments)
                return
            }
            if arguments.first == "sp6a-history-anchor" {
                try SP6AHistoryAnchorProbe.reserve(arguments: arguments)
                return
            }
            if arguments.first == "sp6a-keychain" {
                try SP6AKeychainProbe.command(arguments: arguments)
                return
            }
            if arguments.first == "sp6b" {
                try SP6BProbe.run(arguments: arguments)
                return
            }
            guard arguments.count == 3, arguments[0] == "preflight", arguments[1] == "--output" else {
                throw ProbeError.usage
            }
            try writePreflight(to: URL(fileURLWithPath: arguments[2]))
        } catch ProbeError.usage {
            FileHandle.standardError.write(Data("Usage: Phase0Probe preflight --output <path> | atomicity --output <path> --environment <path> --iterations 100 | sp1|sp2|sp3|sp4a|sp4b|sp5a|sp6a|sp6b --environment <path> --output <directory>\n".utf8))
            Foundation.exit(64)
        } catch let error as AtomicityRunnerIdentityError {
            FileHandle.standardError.write(Data("ERROR \(error.code) \(error.description)\n".utf8))
            Foundation.exit(1)
        } catch {
            FileHandle.standardError.write(Data("Phase0Probe preflight failed: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func writePreflight(to output: URL) throws {
        let listenAccess: DetectionState = CGPreflightListenEventAccess() ? .available : .denied
        let guiStatus = guiSessionStatus()
        let evidence = EnvironmentEvidence(
            macOS: OperatingSystemEvidence(version: command("/usr/bin/sw_vers", ["-productVersion"]), build: command("/usr/bin/sw_vers", ["-buildVersion"])),
            architecture: command("/usr/bin/uname", ["-m"]),
            swift: command("/usr/bin/xcrun", ["swift", "--version"]),
            xcode: command("/usr/bin/xcodebuild", ["-version"]).replacingOccurrences(of: "\n", with: " "),
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            guiSession: GUISessionEvidence(status: guiStatus, tapCreate: tapCreateStatus(gui: guiStatus, listen: listenAccess)),
            listenEventAccess: listenAccess,
            hidAccess: hidAccessStatus(),
            sudoNonInteractive: commandStatus("/usr/bin/sudo", ["-n", "/usr/bin/true"]),
            applications: applicationInventory(),
            hidSummary: hidSummary(),
            sourceReachability: sourceReachability()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(evidence)
        try PrivacySafeEnvironmentValidator.validateJSON(data)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
        print("PREFLIGHT=PASS output=\(output.path)")
    }

    private static func command(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "unknown" }
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return "unknown" }
    }

    private static func commandStatus(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
    }

    private static func guiSessionStatus() -> DetectionState {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any],
              let onConsole = dictionary[kCGSessionOnConsoleKey as String] as? Bool else { return .unknown }
        return onConsole ? .available : .unavailable
    }

    private static func tapCreateStatus(gui: DetectionState, listen: DetectionState) -> DetectionState {
        guard gui == .available else { return gui == .unknown ? .unknown : .unavailable }
        guard listen == .available else { return .denied }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: probeTapCallback, userInfo: nil) else { return .unavailable }
        CFMachPortInvalidate(tap)
        return .available
    }

    private static func hidAccessStatus() -> DetectionState {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let symbol = dlsym(handle, "IOHIDCheckAccess") else { return .unavailable }
        defer { dlclose(handle) }
        typealias CheckAccess = @convention(c) (UInt32) -> UInt32
        switch unsafeBitCast(symbol, to: CheckAccess.self)(1) {
        case 0: return .available
        case 1: return .denied
        case 2: return .unknown
        default: return .unknown
        }
    }

    private static func applicationInventory() -> [ApplicationEvidence] {
        [
            application("Karabiner-Elements", at: "/Applications/Karabiner-Elements.app"),
            application("VIA", at: "/Applications/VIA.app"),
            application("Vial", at: "/Applications/Vial.app"),
        ]
    }

    private static func application(_ name: String, at path: String) -> ApplicationEvidence {
        guard FileManager.default.fileExists(atPath: path) else { return ApplicationEvidence(name: name, status: .absent, version: nil) }
        guard let version = Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return ApplicationEvidence(name: name, status: .unknown, version: nil)
        }
        return ApplicationEvidence(name: name, status: .installed, version: version)
    }

    private static func hidSummary() -> HIDSummaryEvidence {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match = [kIOHIDDeviceUsagePageKey as String: 1, kIOHIDDeviceUsageKey as String: 6] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, match)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).map { device in
            HIDDeviceEvidence(
                vendorID: property(device, kIOHIDVendorIDKey) as? Int,
                productID: property(device, kIOHIDProductIDKey) as? Int,
                manufacturer: property(device, kIOHIDManufacturerKey) as? String,
                product: property(device, kIOHIDProductKey) as? String,
                transport: property(device, kIOHIDTransportKey) as? String
            )
        }.sorted { ($0.vendorID ?? -1, $0.productID ?? -1, $0.product ?? "") < ($1.vendorID ?? -1, $1.productID ?? -1, $1.product ?? "") }
        return HIDSummaryEvidence(deviceCount: devices.count, devices: devices)
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private static func sourceReachability() -> SourceReachabilityEvidence {
        let value = command("/usr/bin/curl", ["--head", "--silent", "--location", "--connect-timeout", "5", "--max-time", "10", "--output", "/dev/null", "--write-out", "%{http_code}", "https://github.com"])
        guard let status = Int(value), status > 0 else { return SourceReachabilityEvidence(status: .unavailable, httpStatus: nil) }
        return SourceReachabilityEvidence(status: (200..<400).contains(status) ? .available : .denied, httpStatus: status)
    }
}

enum ProbeError: Error { case usage }

private func probeTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    Unmanaged.passUnretained(event)
}

Phase0ProbeCommand.main()

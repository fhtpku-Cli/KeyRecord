import Foundation

public struct PerformanceWindowSummary: Equatable, Sendable {
    public let phase: String
    public let architecture: String
    public let macOS: String
    public let machineModel: String
    public let chip: String
    public let machineRAM: UInt64
    public let bundleID: String
    public let executableSHA256: String
    public let productCodeSHA256: String
    public let executablePath: String
    public let pid: Int32
    public let startAbstime: UInt64
    public let cpuPercent: Double
    public let footprintMeanBytes: Double
    public let footprintPeakBytes: UInt64
    public let effectiveMeasureSeconds: Double
    public let acceptedEvents: Int64
    public let durableKeyDownTotal: Int64

    public init(phase: String, architecture: String, macOS: String, machineModel: String,
                chip: String, machineRAM: UInt64, bundleID: String,
                executableSHA256: String, productCodeSHA256: String, executablePath: String,
                pid: Int32, startAbstime: UInt64,
                cpuPercent: Double, footprintMeanBytes: Double, footprintPeakBytes: UInt64,
                effectiveMeasureSeconds: Double, acceptedEvents: Int64, durableKeyDownTotal: Int64) {
        self.phase = phase
        self.architecture = architecture
        self.macOS = macOS
        self.machineModel = machineModel
        self.chip = chip
        self.machineRAM = machineRAM
        self.bundleID = bundleID
        self.executableSHA256 = executableSHA256
        self.productCodeSHA256 = productCodeSHA256
        self.executablePath = executablePath
        self.pid = pid
        self.startAbstime = startAbstime
        self.cpuPercent = cpuPercent
        self.footprintMeanBytes = footprintMeanBytes
        self.footprintPeakBytes = footprintPeakBytes
        self.effectiveMeasureSeconds = effectiveMeasureSeconds
        self.acceptedEvents = acceptedEvents
        self.durableKeyDownTotal = durableKeyDownTotal
    }
}

public enum PerformanceHostError: Error, Equatable {
    case windowCount
    case phaseCount
    case identityMismatch
    case invalidWindow
    case reusedProcessWindow
}

public struct PerformanceHostResult: Equatable, Sendable, Encodable {
    public let kind = "performance-host-evaluation"
    public let productPass = false
    public let outcome: String
    public let architecture: String
    public let macOS: String
    public let machineModel: String
    public let chip: String
    public let machineRAM: UInt64
    public let bundleID: String
    public let executableSHA256: String
    public let productCodeSHA256: String
    public let executablePath: String
    public let typingCPUPercent: Double
    public let idleCPUPercent: Double
    public let highestWindowFootprintMeanBytes: Double
    public let highestWindowFootprintPeakBytes: UInt64
    public let windowCount: Int

    public var withinBudget: Bool { outcome == "within-budget" }
}

public enum PerformanceHostEvaluator {
    private struct ProcessIdentity: Hashable {
        let pid: Int32
        let startAbstime: UInt64
    }

    public static func evaluate(_ windows: [PerformanceWindowSummary]) throws -> PerformanceHostResult {
        guard windows.count == 2, let first = windows.first else { throw PerformanceHostError.windowCount }
        let typing = windows.filter { $0.phase == "typing" }
        let idle = windows.filter { $0.phase == "idle" }
        guard typing.count == 1, idle.count == 1 else { throw PerformanceHostError.phaseCount }
        let expectedTyping = Int64(ReplayWorkload.expectedTypingEvents)
        for window in windows {
            guard window.architecture == first.architecture, window.macOS == first.macOS,
                  window.machineModel == first.machineModel, window.chip == first.chip,
                  window.machineRAM == first.machineRAM,
                  window.bundleID == first.bundleID,
                  window.executableSHA256 == first.executableSHA256,
                  window.productCodeSHA256 == first.productCodeSHA256,
                  window.executablePath == first.executablePath else {
                throw PerformanceHostError.identityMismatch
            }
            let expectedEvents = window.phase == "typing" ? expectedTyping : 0
            guard ["arm64", "x86_64"].contains(window.architecture),
                  !window.macOS.isEmpty, !window.machineModel.isEmpty, !window.chip.isEmpty,
                  window.machineRAM > 0, window.executableSHA256.count == 64,
                  window.productCodeSHA256.count == 64,
                  window.bundleID.hasPrefix("com.keyrecord.trial.performance"),
                  window.executableSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  window.productCodeSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  !window.executablePath.isEmpty,
                  window.pid > 0, window.startAbstime > 0,
                  window.cpuPercent.isFinite, window.cpuPercent >= 0,
                  window.footprintMeanBytes.isFinite, window.footprintMeanBytes > 0,
                  Double(window.footprintPeakBytes) >= window.footprintMeanBytes,
                  window.effectiveMeasureSeconds.isFinite, window.effectiveMeasureSeconds >= ReplayWorkload.measureSeconds,
                  window.acceptedEvents == expectedEvents,
                  window.durableKeyDownTotal == expectedEvents / 2 else {
                throw PerformanceHostError.invalidWindow
            }
        }
        let processes = Set(windows.map { ProcessIdentity(pid: $0.pid, startAbstime: $0.startAbstime) })
        guard processes.count == windows.count else { throw PerformanceHostError.reusedProcessWindow }
        let typingCPU = typing[0].cpuPercent
        let idleCPU = idle[0].cpuPercent
        let highestMean = windows.map(\.footprintMeanBytes).max() ?? .infinity
        let highestPeak = windows.map(\.footprintPeakBytes).max() ?? UInt64.max
        let withinBudget = typingCPU < 1 && idleCPU < 0.1
            && highestMean < 100_000_000 && highestPeak < 100_000_000
        return PerformanceHostResult(outcome: withinBudget ? "within-budget" : "over-budget",
            architecture: first.architecture, macOS: first.macOS,
            machineModel: first.machineModel, chip: first.chip, machineRAM: first.machineRAM,
            bundleID: first.bundleID,
            executableSHA256: first.executableSHA256, productCodeSHA256: first.productCodeSHA256,
            executablePath: first.executablePath,
            typingCPUPercent: typingCPU, idleCPUPercent: idleCPU,
            highestWindowFootprintMeanBytes: highestMean,
            highestWindowFootprintPeakBytes: highestPeak, windowCount: windows.count)
    }
}

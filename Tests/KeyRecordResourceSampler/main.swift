import Darwin
import Foundation
import KeyRecordMeasurement

#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

struct CollectedSample {
    var uptimeSeconds: Double
    var monotonicSeconds: Double
    var cpuNanoseconds: UInt64
    var childCPUNanoseconds: UInt64
    var footprintBytes: UInt64
    var pid: Int32
    var startAbstime: UInt64
    var executablePath: String
    var consoleUID: Int?
    var failed: Bool
    var exited: Bool
}

enum SamplerCLI {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--self-check") {
            try selfCheck()
            return
        }
        if let index = arguments.firstIndex(of: "--recompute"), arguments.indices.contains(index + 1) {
            try recompute(path: arguments[index + 1])
            return
        }
        if arguments.isEmpty || arguments.contains("--help") {
            print(usage)
            return
        }
        let options = try Options(arguments)
        guard options.protocolKind != .formalFRS2 || (options.warmup == 60 && options.measure == 600) else {
            throw SamplerFailure("formal-fr-s2 refuses short windows")
        }
        let samples = try sample(options)
        let request = ResourceWindowRequest(
            protocolKind: options.protocolKind, phase: options.phase,
            warmupSeconds: options.warmup, measureSeconds: options.measure,
            intervalSeconds: options.interval,
            samples: samples.map {
                ProcessResourceSample(uptimeSeconds: $0.uptimeSeconds, monotonicSeconds: $0.monotonicSeconds,
                    cpuNanoseconds: $0.cpuNanoseconds, childCPUNanoseconds: $0.childCPUNanoseconds,
                    footprintBytes: $0.footprintBytes, pid: $0.pid, startAbstime: $0.startAbstime,
                    executablePath: $0.executablePath, consoleUID: $0.consoleUID,
                    failed: $0.failed, exited: $0.exited)
            })
        let result = ResourceEvaluator.evaluate(request)
        let archive = ResourceMeasurementArchive(request: request, result: result,
            architecture: architecture(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            diagnosticsEnabled: options.diagnosticsEnabled)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        try data.write(to: URL(fileURLWithPath: options.output), options: .atomic)
        FileHandle.standardOutput.write(data)
        fputs("\n", stdout)
        if result.outcome != "measured" { throw SamplerFailure(result.reason ?? result.outcome) }
    }

    static let usage = """
    KeyRecordResourceSampler samples one existing process. It does not launch KeyRecord, inject input, or prevent sleep.
    --pid <pid> --expect-path <executable> --protocol exploratory|pausedMonitorCandidate|formalFRS2 \
    --phase <label> --warmup-seconds <n> --measure-seconds <n> --interval-seconds <n> --output <file> [--diagnostics-enabled]
    --recompute <archive.json> repeats the saved-sample calculation.
    --self-check runs the offline fixture and does not attach to KeyRecord.
    --diagnostics-enabled means the target process is writing diagnostics, so that overhead is inside the measurement.
    Short windows stay exploratory. formalFRS2 requires 60s warmup and 600s measure. Outcome is never a product pass.
    """

    static func selfCheck() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kr-resource-\(getpid())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("hold.swift")
        let program = """
        import Foundation
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 32 * 1024 * 1024, alignment: 16)
        pointer.initializeMemory(as: UInt8.self, repeating: 1, count: 32 * 1024 * 1024)
        Thread.sleep(forTimeInterval: 8)
        pointer.deallocate()
        """
        try program.write(to: source, atomically: true, encoding: .utf8)
        let binary = directory.appendingPathComponent("hold")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        compile.arguments = [source.path, "-o", binary.path]
        try compile.run()
        compile.waitUntilExit()
        guard compile.terminationStatus == 0 else { throw SamplerFailure("fixture-compile-failed") }
        let child = Process()
        child.executableURL = binary
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let output = directory.appendingPathComponent("sample.json")
        let options = Options(pid: child.processIdentifier, path: binary.path, protocolKind: .exploratory,
                              phase: "synthetic-fixture", warmup: 0.4, measure: 1.2, interval: 0.2, output: output.path)
        let samples = try sample(options)
        let result = ResourceEvaluator.evaluate(ResourceWindowRequest(
            protocolKind: .exploratory, phase: "synthetic-fixture", warmupSeconds: 0.4, measureSeconds: 1.2,
            intervalSeconds: 0.2, samples: samples.map {
                ProcessResourceSample(uptimeSeconds: $0.uptimeSeconds, monotonicSeconds: $0.monotonicSeconds,
                    cpuNanoseconds: $0.cpuNanoseconds, childCPUNanoseconds: $0.childCPUNanoseconds,
                    footprintBytes: $0.footprintBytes, pid: $0.pid, startAbstime: $0.startAbstime,
                    executablePath: $0.executablePath, consoleUID: $0.consoleUID, failed: $0.failed, exited: $0.exited)
            }))
        let archive = ResourceMeasurementArchive(request: ResourceWindowRequest(
            protocolKind: .exploratory, phase: "synthetic-fixture", warmupSeconds: 0.4, measureSeconds: 1.2,
            intervalSeconds: 0.2, samples: samples.map(sampleRecord)), result: result,
            architecture: architecture(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            diagnosticsEnabled: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: output, options: .atomic)
        let again = ResourceEvaluator.recompute(archive)
        guard result.outcome == "measured", again.outcome == result.outcome,
              again.footprintMeanBytes == result.footprintMeanBytes,
              let mean = result.footprintMeanBytes, mean > 1_000_000,
              result.rssUsedAsFootprint == false, result.formalFRS2Qualification == false else {
            throw SamplerFailure("self-check-rejected \(result.outcome) \(result.reason ?? "") mean=\(result.footprintMeanBytes ?? -1)")
        }
        print("self-check outcome=measured footprintMeanBytes=\(mean) qualification=not-a-product-pass recomputed=match")
    }

    static func recompute(path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let archive = try JSONDecoder().decode(ResourceMeasurementArchive.self, from: data)
        let again = ResourceEvaluator.recompute(archive)
        guard again.outcome == archive.result.outcome,
              again.cpuPercentOfOneLogicalCore == archive.result.cpuPercentOfOneLogicalCore,
              again.footprintMeanBytes == archive.result.footprintMeanBytes,
              again.footprintSampledPeakBytes == archive.result.footprintSampledPeakBytes else {
            throw SamplerFailure("recompute-mismatch")
        }
        print("recompute outcome=\(again.outcome) match=true")
    }
}

func architecture() -> String {
    var system = utsname()
    uname(&system)
    return withUnsafeBytes(of: &system.machine) { raw in
        let bytes = raw.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}

func sampleRecord(_ sample: CollectedSample) -> ProcessResourceSample {
    ProcessResourceSample(uptimeSeconds: sample.uptimeSeconds, monotonicSeconds: sample.monotonicSeconds,
        cpuNanoseconds: sample.cpuNanoseconds, childCPUNanoseconds: sample.childCPUNanoseconds,
        footprintBytes: sample.footprintBytes, pid: sample.pid, startAbstime: sample.startAbstime,
        executablePath: sample.executablePath, consoleUID: sample.consoleUID,
        failed: sample.failed, exited: sample.exited)
}

struct Options {
    var pid: Int32
    var path: String
    var protocolKind: ResourceProtocolKind
    var phase: String
    var warmup: Double
    var measure: Double
    var interval: Double
    var output: String
    var diagnosticsEnabled: Bool

    init(pid: Int32, path: String, protocolKind: ResourceProtocolKind, phase: String,
         warmup: Double, measure: Double, interval: Double, output: String, diagnosticsEnabled: Bool = false) {
        self.pid = pid
        self.path = path
        self.protocolKind = protocolKind
        self.phase = phase
        self.warmup = warmup
        self.measure = measure
        self.interval = interval
        self.output = output
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    init(_ arguments: [String]) throws {
        func value(_ name: String) throws -> String {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
                throw SamplerFailure("missing \(name)")
            }
            return arguments[index + 1]
        }
        guard let pid = Int32(try value("--pid")),
              let warmup = Double(try value("--warmup-seconds")),
              let measure = Double(try value("--measure-seconds")),
              let interval = Double(try value("--interval-seconds")),
              let kind = ResourceProtocolKind(rawValue: try value("--protocol")) else {
            throw SamplerFailure("bad arguments")
        }
        self.init(pid: pid, path: try value("--expect-path"), protocolKind: kind,
                  phase: try value("--phase"), warmup: warmup, measure: measure,
                  interval: interval, output: try value("--output"),
                  diagnosticsEnabled: arguments.contains("--diagnostics-enabled"))
    }
}

func sample(_ options: Options) throws -> [CollectedSample] {
    let deadline = clock(.uptime) + options.warmup + options.measure + options.interval
    var samples: [CollectedSample] = []
    while clock(.uptime) <= deadline {
        samples.append(readSample(pid: options.pid, expectedPath: options.path))
        if samples.last?.exited == true || samples.last?.failed == true { break }
        usleep(useconds_t(options.interval * 1_000_000))
    }
    return samples
}

enum ClockKind { case uptime, monotonic }

func clock(_ kind: ClockKind) -> Double {
    var value = timespec()
    let id: clockid_t = kind == .uptime ? CLOCK_UPTIME_RAW : CLOCK_MONOTONIC
    let status = clock_gettime(id, &value)
    if status != 0 {
        fputs("clock_gettime failed kind=\(kind) errno=\(errno)\n", stderr)
        fatalError("clock_gettime")
    }
    return Double(value.tv_sec) + Double(value.tv_nsec) / 1e9
}

func readSample(pid: Int32, expectedPath: String) -> CollectedSample {
    var info = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    var pathBuffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
    let path = length > 0 ? String(decoding: pathBuffer.prefix(Int(length)), as: UTF8.self) : ""
    let uid = consoleUID()
    let actual = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    let expected = URL(fileURLWithPath: expectedPath).resolvingSymlinksInPath().path
    if status != 0 || actual != expected {
        let exited = kill(pid, 0) != 0
        return CollectedSample(uptimeSeconds: clock(.uptime), monotonicSeconds: clock(.monotonic),
            cpuNanoseconds: 0, childCPUNanoseconds: 0, footprintBytes: 0, pid: pid, startAbstime: 0,
            executablePath: path, consoleUID: uid, failed: !exited, exited: exited)
    }
    let exited = info.ri_proc_exit_abstime != 0
    return CollectedSample(uptimeSeconds: clock(.uptime), monotonicSeconds: clock(.monotonic),
        cpuNanoseconds: info.ri_user_time &+ info.ri_system_time,
        childCPUNanoseconds: info.ri_child_user_time &+ info.ri_child_system_time,
        footprintBytes: info.ri_phys_footprint, pid: pid, startAbstime: info.ri_proc_start_abstime,
        executablePath: path, consoleUID: uid, failed: false, exited: exited)
}

func consoleUID() -> Int? {
    #if canImport(SystemConfiguration)
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) != nil else { return nil }
    return Int(uid)
    #else
    return Int(getuid())
    #endif
}

struct SamplerFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

do {
    try SamplerCLI.main()
} catch {
    fputs("KeyRecordResourceSampler \(error)\n", stderr)
    exit(2)
}

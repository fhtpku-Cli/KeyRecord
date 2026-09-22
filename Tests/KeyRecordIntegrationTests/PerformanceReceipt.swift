import CryptoKit
import Foundation

enum PerformanceError: Error { case invalidReceipt, invalidSample, systemCall, translatedHost }

struct PerformanceWindow: Codable, Equatable {
    let warmup: Double
    let window: Double
    let repeats: Int
    static let authorized = Self(warmup: 60, window: 600, repeats: 3)
    static let compressed = Self(warmup: 0.2, window: 1, repeats: 2)
}

struct PerformanceSample: Codable, Equatable {
    var typingCPU: Double
    var idleCPU: Double
    let typingWall: Double
    let idleWall: Double
    let ramMean: Double
    var ramPeak: Double

    static func memory(typing: [Double], idle: [Double]) throws -> (mean: Double, peak: Double) {
        let samples = typing + idle
        guard !typing.isEmpty, !idle.isEmpty,
              samples.allSatisfy({ $0.isFinite && $0 > 0 }),
              let peak = samples.max() else { throw PerformanceError.invalidSample }
        return (samples.reduce(0, +) / Double(samples.count), peak)
    }

    static func percent(cpuSeconds: Double, wallSeconds: Double) throws -> Double {
        guard cpuSeconds.isFinite, wallSeconds.isFinite, cpuSeconds >= 0, wallSeconds > 0 else {
            throw PerformanceError.invalidSample
        }
        return 100 * cpuSeconds / wallSeconds
    }
}

struct PerformanceReceipt: Codable, Equatable {
    let model: String
    let arch: String
    let macOS: String
    let chip: String
    let machineRAM: UInt64
    let configuration: PerformanceWindow
    let compressedWindow: Bool
    let method: String
    let binaryHash: String
    let binaryPath: String
    var workloadHash: String
    var cpuSamples: [PerformanceSample]
    let ramMean: Double
    let ramPeak: Double

    static let workload = Data("[[0,1,2,3,0,1,2,3],[0],[1],[2],[3],[0],[1],[2],[3],[0]]".utf8)
    static func parseWorkload(_ data: Data) throws -> [[Int]] {
        guard data == workload else { throw PerformanceError.invalidReceipt }
        return try JSONDecoder().decode([[Int]].self, from: data)
    }
    func verifyBinary(at url: URL) throws {
        guard url.path == binaryPath, Self.hash(try Data(contentsOf: url)) == binaryHash else {
            throw PerformanceError.invalidReceipt
        }
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let ordered = values.sorted()
        return (ordered[(ordered.count - 1) / 2] + ordered[ordered.count / 2]) / 2
    }
    var typingMedian: Double { Self.median(cpuSamples.map(\.typingCPU)) }
    var idleMedian: Double { Self.median(cpuSamples.map(\.idleCPU)) }
    var withinBudget: Bool {
        typingMedian < 1 && idleMedian < 0.1 && ramMean < 100_000_000 && ramPeak < 100_000_000
        && cpuSamples.allSatisfy { $0.ramPeak < 100_000_000 }
    }

    func validate(nativeArch: String, full: Bool) throws {
        guard ["arm64", "x86_64"].contains(arch), arch == nativeArch,
              !model.isEmpty, !macOS.isEmpty, !chip.isEmpty, machineRAM > 0,
              binaryHash.count == 64, binaryHash.allSatisfy({ "0123456789abcdef".contains($0) }),
              !binaryPath.isEmpty, workloadHash == Self.hash(Self.workload),
              configuration == (compressedWindow ? .compressed : .authorized),
              !full || !compressedWindow, cpuSamples.count == configuration.repeats,
              cpuSamples.allSatisfy({ sample in
                  [sample.typingCPU, sample.idleCPU, sample.typingWall, sample.idleWall,
                   sample.ramMean, sample.ramPeak].allSatisfy { $0.isFinite && $0 >= 0 }
                  && sample.typingWall >= configuration.window && sample.idleWall >= configuration.window
                  && sample.ramMean > 0 && sample.ramPeak >= sample.ramMean
              }), ramMean == cpuSamples.map(\.ramMean).reduce(0, +) / Double(cpuSamples.count),
              ramPeak == cpuSamples.map(\.ramPeak).max() else { throw PerformanceError.invalidReceipt }
    }

    static func fixture() -> Self {
        let sample = PerformanceSample(typingCPU: 0.5, idleCPU: 0.01, typingWall: 1, idleWall: 1,
            ramMean: 10_000_000, ramPeak: 12_000_000)
        return Self(model: "injected", arch: "arm64", macOS: "injected", chip: "injected", machineRAM: 1,
            configuration: .compressed, compressedWindow: true, method: "injected", binaryHash: hash(Data()),
            binaryPath: "fixture", workloadHash: hash(workload), cpuSamples: [sample, sample],
            ramMean: sample.ramMean, ramPeak: sample.ramPeak)
    }
}

extension PerformanceReceipt {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case model, arch, macOS, chip, machineRAM, configuration, compressedWindow, method
        case binaryHash, binaryPath, workloadHash, cpuSamples, ramMean, ramPeak
    }
    struct Field: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func requireFields(_ names: Set<String>, from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        guard Set(fields.allKeys.map(\.stringValue)) == names else { throw PerformanceError.invalidReceipt }
    }
    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        guard Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw PerformanceError.invalidReceipt
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model = try values.decode(String.self, forKey: .model)
        arch = try values.decode(String.self, forKey: .arch)
        macOS = try values.decode(String.self, forKey: .macOS)
        chip = try values.decode(String.self, forKey: .chip)
        machineRAM = try values.decode(UInt64.self, forKey: .machineRAM)
        configuration = try values.decode(PerformanceWindow.self, forKey: .configuration)
        compressedWindow = try values.decode(Bool.self, forKey: .compressedWindow)
        method = try values.decode(String.self, forKey: .method)
        binaryHash = try values.decode(String.self, forKey: .binaryHash)
        binaryPath = try values.decode(String.self, forKey: .binaryPath)
        workloadHash = try values.decode(String.self, forKey: .workloadHash)
        cpuSamples = try values.decode([PerformanceSample].self, forKey: .cpuSamples)
        ramMean = try values.decode(Double.self, forKey: .ramMean)
        ramPeak = try values.decode(Double.self, forKey: .ramPeak)
        try validate(nativeArch: arch, full: false)
    }
}

extension PerformanceWindow {
    enum CodingKeys: String, CodingKey { case warmup, window, repeats }
    init(from decoder: any Decoder) throws {
        try PerformanceReceipt.requireFields(["warmup", "window", "repeats"], from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        warmup = try values.decode(Double.self, forKey: .warmup)
        window = try values.decode(Double.self, forKey: .window)
        repeats = try values.decode(Int.self, forKey: .repeats)
    }
}

extension PerformanceSample {
    enum CodingKeys: String, CodingKey { case typingCPU, idleCPU, typingWall, idleWall, ramMean, ramPeak }
    init(from decoder: any Decoder) throws {
        try PerformanceReceipt.requireFields(["typingCPU", "idleCPU", "typingWall", "idleWall", "ramMean", "ramPeak"], from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        typingCPU = try values.decode(Double.self, forKey: .typingCPU)
        idleCPU = try values.decode(Double.self, forKey: .idleCPU)
        typingWall = try values.decode(Double.self, forKey: .typingWall)
        idleWall = try values.decode(Double.self, forKey: .idleWall)
        ramMean = try values.decode(Double.self, forKey: .ramMean)
        ramPeak = try values.decode(Double.self, forKey: .ramPeak)
    }
}

import Foundation
import Phase0Support

struct SP6BSampleReceipt: Decodable {
    let index: Int
    let startNanoseconds: UInt64
    let endNanoseconds: UInt64
    let milliseconds: Double
    let observedTag: String
}

struct SP6BArmArtifact: Decodable {
    let schemaVersion: Int; let generatedAt: String; let recommendedCandidate: String
    let commit: String; let tree: String; let archiveSha256: String; let environmentSha256: String
    let harnessSourceSha256: String; let executableSha256: String; let compilerIdentity: String
    let compilerFlags: [String]; let command: [String]; let host: Host
    let sampleReceipts: [SP6BSampleReceipt]; let samplesMilliseconds: [Double]
    let medianMilliseconds: Double; let p95Milliseconds: Double
    let memoryKiB: Int; let iterations: Int; let parallelism: Int; let saltLength: Int
    let sampleCount: Int; let targetMilliseconds: Target; let withinTarget: Bool
    struct Host: Decodable { let architecture: String; let macOS: String; let build: String; let swift: String }
    struct Target: Decodable { let minimum: Double; let maximum: Double }
}

enum SP6BBenchmarkValidator {
    static func validate(
        directory: URL, repository: URL, evidence: SP6BEvidence,
        contract: SP6BSourceContractDocument, build: SP6BBuildArtifact
    ) throws -> SP6BArmArtifact {
        let url = directory.appendingPathComponent("arm-benchmark.json")
        guard let arm = try? JSONDecoder().decode(SP6BArmArtifact.self, from: Data(contentsOf: url)),
              let phc = contract.candidates.first(where: { $0.id == "phc" }),
              let runner = evidence.legs.first?.runnerCommitSha else { throw ValidatorError("sp6b_arm_receipt") }
        let flags = ["-arch", "arm64", "-mmacosx-version-min=14.0", "-std=c89", "-O3", "-fno-strict-aliasing"]
        guard arm.schemaVersion == 2, arm.generatedAt == build.generatedAt, arm.recommendedCandidate == "phc",
              arm.commit == phc.commit, arm.tree == phc.tree, arm.archiveSha256 == build.archiveSha256,
              arm.environmentSha256 == evidence.legs[0].environmentSha256,
              SP6BDirectoryValidator.isSHA256(arm.executableSha256),
              Canonical.sha256(Data(arm.compilerIdentity.utf8)) == contract.compilerIdentitySha256,
              arm.compilerFlags == flags, arm.command == ["argon-bench", "524288", "5", "4"],
              arm.host.architecture == "arm64", !arm.host.macOS.isEmpty, !arm.host.build.isEmpty, !arm.host.swift.isEmpty,
              arm.sampleCount == arm.sampleReceipts.count, arm.samplesMilliseconds.count == arm.sampleCount,
              (5...15).contains(arm.sampleCount), arm.memoryKiB == 524_288, arm.iterations == 5,
              arm.parallelism == 4, arm.saltLength == 16, arm.targetMilliseconds.minimum == 300,
              arm.targetMilliseconds.maximum == 500, arm.withinTarget else { throw ValidatorError("sp6b_arm_receipt") }
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        let harness = try git.run(["cat-file", "blob", "\(runner):Spikes/Scripts/argon-bench.c"]).stdout
        guard arm.harnessSourceSha256 == Canonical.sha256(harness) else { throw ValidatorError("sp6b_arm_harness") }
        var priorEnd: UInt64 = 0; var observedTag: String?
        for (index, receipt) in arm.sampleReceipts.enumerated() {
            let duration = Double(receipt.endNanoseconds - receipt.startNanoseconds) / 1_000_000
            guard receipt.index == index, receipt.startNanoseconds >= priorEnd,
                  receipt.endNanoseconds > receipt.startNanoseconds,
                  abs(duration - receipt.milliseconds) <= 0.001,
                  receipt.milliseconds == arm.samplesMilliseconds[index],
                  receipt.observedTag == contract.benchmarkExpectedTag,
                  observedTag == nil || observedTag == receipt.observedTag else {
                throw ValidatorError("sp6b_arm_sample", "\(index)")
            }
            priorEnd = receipt.endNanoseconds; observedTag = receipt.observedTag
        }
        let sorted = arm.samplesMilliseconds.sorted()
        guard arm.medianMilliseconds == sorted[sorted.count / 2],
              arm.p95Milliseconds == sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1],
              (300...500).contains(arm.medianMilliseconds) else { throw ValidatorError("sp6b_arm_statistics") }
        return arm
    }
}

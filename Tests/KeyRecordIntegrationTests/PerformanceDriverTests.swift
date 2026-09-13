import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore
@testable import KeyRecordCapture

@MainActor
final class PerformanceDriverTests: XCTestCase {
    func testCompressedMeasurementWhenSyntheticWorkloadRuns() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        let clock = SystemFlushClock()
        let scheduler = FlushScheduler(gate: fixture.gate,
            writer: FencedObjectWriter(store: fixture.store, gate: fixture.gate), clock: clock)
        try await scheduler.reopen()
        let sampler = PerformanceSystemSampler()
        let configuration = PerformanceWindow.compressed
        var samples: [PerformanceSample] = []
        // When
        for _ in 0..<configuration.repeats {
            try await runWindow(seconds: configuration.warmup, typing: true, fixture: fixture, scheduler: scheduler)
            let start = try sampler.sample()
            _ = try await runWindow(seconds: configuration.window, typing: true, fixture: fixture, scheduler: scheduler)
            let end = try sampler.sample()
            let flushed = await scheduler.completion()
            XCTAssertEqual(flushed, .saved)
            try await runWindow(seconds: configuration.warmup, typing: false, fixture: fixture, scheduler: scheduler)
            let idleStart = try sampler.sample()
            let ram = try await runWindow(seconds: configuration.window, typing: false, fixture: fixture, scheduler: scheduler)
            let idleEnd = try sampler.sample()
            samples.append(PerformanceSample(
                typingCPU: try PerformanceSample.percent(cpuSeconds: end.cpu - start.cpu, wallSeconds: end.wall - start.wall),
                idleCPU: try PerformanceSample.percent(cpuSeconds: idleEnd.cpu - idleStart.cpu, wallSeconds: idleEnd.wall - idleStart.wall),
                typingWall: end.wall - start.wall, idleWall: idleEnd.wall - idleStart.wall,
                ramMean: ram.reduce(0, +) / Double(ram.count), ramPeak: try XCTUnwrap(ram.max())))
        }
        await scheduler.close()
        await scheduler.waitForIssuedWrite()
        let binary = Bundle(for: Self.self).executableURL
        let binaryURL = try XCTUnwrap(binary)
        let receipt = PerformanceReceipt(model: try PerformanceSystemSampler.sysctl("hw.model"),
            arch: try PerformanceSystemSampler.nativeArch(), macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            chip: try PerformanceSystemSampler.sysctl("machdep.cpu.brand_string"), machineRAM: ProcessInfo.processInfo.physicalMemory,
            configuration: configuration, compressedWindow: true,
            method: "XCTest process CLOCK_PROCESS_CPUTIME_ID/CLOCK_MONOTONIC; TASK_VM_INFO.phys_footprint sampled at 100ms; includes harness overhead",
            binaryHash: PerformanceReceipt.hash(try Data(contentsOf: binaryURL)), binaryPath: binaryURL.path,
            workloadHash: PerformanceReceipt.hash(PerformanceReceipt.workload), cpuSamples: samples,
            ramMean: samples.map(\.ramMean).reduce(0, +) / Double(samples.count),
            ramPeak: try XCTUnwrap(samples.map(\.ramPeak).max()))
        // Then
        try receipt.validate(nativeArch: PerformanceSystemSampler.nativeArch(), full: false)
        try receipt.verifyBinary(at: binaryURL)
        XCTAssertFalse(fixture.aggregate.bareKeys.isEmpty)
        XCTAssertFalse(fixture.aggregate.shortcuts.isEmpty)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipt)
        XCTAssertEqual(try JSONDecoder().decode(PerformanceReceipt.self, from: data), receipt)
        print("PERFORMANCE_RECEIPT=" + String(decoding: data, as: UTF8.self))
        print("PERFORMANCE_BUDGET=\(receipt.withinBudget ? "PASS" : "FAIL") compressedWindow=true fullQualification=BLOCKED")
    }

    @discardableResult
    private func runWindow(seconds: Double, typing: Bool, fixture: IntegrationFixture,
                           scheduler: FlushScheduler) async throws -> [Double] {
        let clock = ContinuousClock()
        let start = clock.now
        let ticks = Int((seconds * 10).rounded())
        let workload = try PerformanceReceipt.parseWorkload(PerformanceReceipt.workload)
        var footprints: [Double] = []
        for tick in 0..<ticks {
            if typing {
                for keyCode in workload[tick % workload.count] {
                    let modifiers = ModifierSet(command: tick.isMultiple(of: 3) ? .left : .none,
                        option: .none, control: .none, shift: .none, fn: .none)
                    for kind in [KeyEventKind.keyDown, .keyUp] {
                        let event = ObservedKeyEvent(keyCode: try KeyCode(keyCode), kind: kind,
                            isAutoRepeat: false, modifiers: modifiers, source: .ordinaryObserved, generation: fixture.queue.generation)
                        guard fixture.queue.handoff(event) == .accepted, let output = fixture.queue.reduceOne() else {
                            throw PerformanceError.invalidSample
                        }
                        try fixture.aggregate.process(output.output, generation: output.generation, clock: IntegrationClock())
                    }
                }
                try await scheduler.stage(AggregatePersistence.objects(fixture.aggregate))
            }
            await scheduler.tick()
            footprints.append(try PerformanceSystemSampler().sample().footprint)
            try await clock.sleep(until: start.advanced(by: .milliseconds((tick + 1) * 100)))
        }
        footprints.append(try PerformanceSystemSampler().sample().footprint)
        return footprints
    }
}

import XCTest
import KeyRecordMeasurement

final class PerformanceHostEvaluationTests: XCTestCase {
    private func window(phase: String, cpu: Double, model: String = "Mac15,12",
                        digest: String = String(repeating: "a", count: 64),
                        codeDigest: String = String(repeating: "c", count: 64),
                        seconds: Double = 600.1, mean: Double = 50_000_000,
                        peak: UInt64 = 60_000_000) -> PerformanceWindowSummary {
        let events = phase == "typing" ? Int64(ReplayWorkload.expectedTypingEvents) : 0
        return PerformanceWindowSummary(phase: phase, architecture: "arm64", macOS: "fixture",
            machineModel: model, chip: "Apple M3", machineRAM: 16_000_000_000,
            bundleID: "com.keyrecord.trial.performance.fixture",
            executableSHA256: digest, productCodeSHA256: codeDigest,
            executablePath: "/private/tmp/trial/KeyRecordApp",
            cpuPercent: cpu, footprintMeanBytes: mean, footprintPeakBytes: peak,
            effectiveMeasureSeconds: seconds, acceptedEvents: events,
            durableKeyDownTotal: events / 2)
    }

    func testSixMatchingWindowsUsePerModeMediansAndEveryWindowMemory() throws {
        let windows = [
            window(phase: "typing", cpu: 0.3), window(phase: "idle", cpu: 0.02),
            window(phase: "typing", cpu: 0.8), window(phase: "idle", cpu: 0.06),
            window(phase: "typing", cpu: 1.2), window(phase: "idle", cpu: 0.08)
        ]
        let result = try PerformanceHostEvaluator.evaluate(windows)
        XCTAssertTrue(result.withinBudget)
        XCTAssertEqual(result.productPass, false)
        XCTAssertEqual(result.windowCount, 6)
        XCTAssertEqual(result.typingMedianCPUPercent, 0.8)
        XCTAssertEqual(result.idleMedianCPUPercent, 0.06)

        var over = windows
        over[0] = window(phase: "typing", cpu: 0.3, peak: 100_000_000)
        XCTAssertEqual(try PerformanceHostEvaluator.evaluate(over).outcome, "over-budget")
        over[0] = window(phase: "typing", cpu: 1.0)
        over[2] = window(phase: "typing", cpu: 1.1)
        XCTAssertEqual(try PerformanceHostEvaluator.evaluate(over).outcome, "over-budget")
    }

    func testMixedIdentityAndIncompleteWindowsCannotFormHostResult() {
        let windows = (0..<6).map { index in
            window(phase: index.isMultiple(of: 2) ? "typing" : "idle", cpu: 0.05)
        }
        XCTAssertThrowsError(try PerformanceHostEvaluator.evaluate(Array(windows.dropLast()))) {
            XCTAssertEqual($0 as? PerformanceHostError, .windowCount)
        }
        var mixed = windows
        mixed[1] = window(phase: "idle", cpu: 0.05, model: "OtherMac")
        XCTAssertThrowsError(try PerformanceHostEvaluator.evaluate(mixed)) {
            XCTAssertEqual($0 as? PerformanceHostError, .identityMismatch)
        }
        mixed[1] = window(phase: "idle", cpu: 0.05, digest: String(repeating: "b", count: 64))
        XCTAssertThrowsError(try PerformanceHostEvaluator.evaluate(mixed)) {
            XCTAssertEqual($0 as? PerformanceHostError, .identityMismatch)
        }
        mixed[1] = window(phase: "idle", cpu: 0.05, codeDigest: String(repeating: "d", count: 64))
        XCTAssertThrowsError(try PerformanceHostEvaluator.evaluate(mixed)) {
            XCTAssertEqual($0 as? PerformanceHostError, .identityMismatch)
        }
        mixed[1] = window(phase: "idle", cpu: 0.05, seconds: 599.8)
        XCTAssertThrowsError(try PerformanceHostEvaluator.evaluate(mixed)) {
            XCTAssertEqual($0 as? PerformanceHostError, .invalidWindow)
        }
        mixed[1] = window(phase: "typing", cpu: 0.05)
        XCTAssertThrowsError(try PerformanceHostEvaluator.evaluate(mixed)) {
            XCTAssertEqual($0 as? PerformanceHostError, .phaseCount)
        }
    }
}

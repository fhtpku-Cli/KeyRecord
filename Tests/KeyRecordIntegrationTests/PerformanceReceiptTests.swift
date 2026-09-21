import Foundation
import XCTest

final class PerformanceReceiptTests: XCTestCase {
    func testMemoryIncludesTypingPeakWhenIdleFootprintIsLower() throws {
        // Given: only the typing window exceeds the memory budget.
        let typing = [10_000_000.0, 120_000_000.0]
        let idle = [10_000_000.0, 20_000_000.0]
        // When
        let memory = try PerformanceSample.memory(typing: typing, idle: idle)
        // Then
        XCTAssertEqual(memory.peak, 120_000_000)
        XCTAssertEqual(memory.mean, 40_000_000)
    }

    func testMemoryRejectsMissingOrInvalidWindowSamples() {
        XCTAssertThrowsError(try PerformanceSample.memory(typing: [], idle: [1]))
        XCTAssertThrowsError(try PerformanceSample.memory(typing: [1], idle: []))
        XCTAssertThrowsError(try PerformanceSample.memory(typing: [.nan], idle: [1]))
        XCTAssertThrowsError(try PerformanceSample.memory(typing: [1], idle: [0]))
    }

    func testRoundTripWhenCompressedReceiptIsValid() throws {
        // Given
        let receipt = PerformanceReceipt.fixture()
        // When
        let decoded = try JSONDecoder().decode(PerformanceReceipt.self, from: JSONEncoder().encode(receipt))
        // Then
        XCTAssertEqual(decoded, receipt)
        XCTAssertThrowsError(try decoded.validate(nativeArch: "arm64", full: true))
    }

    func testOneCoreArithmeticWhenMachineHasManyCores() throws {
        // Given / When
        let percent = try PerformanceSample.percent(cpuSeconds: 0.005, wallSeconds: 1)
        // Then
        XCTAssertEqual(percent, 0.5)
        XCTAssertThrowsError(try PerformanceSample.percent(cpuSeconds: 1, wallSeconds: 0))
    }

    func testThresholdsWhenEqualOrExceeded() throws {
        // Given
        var receipt = PerformanceReceipt.fixture()
        XCTAssertTrue(receipt.withinBudget)
        // When / Then
        receipt.cpuSamples[0].typingCPU = 1
        receipt.cpuSamples[1].typingCPU = 1
        XCTAssertFalse(receipt.withinBudget)
        receipt.cpuSamples[0].typingCPU = 0.5
        receipt.cpuSamples[1].typingCPU = 0.5
        receipt.cpuSamples[0].idleCPU = 0.1
        receipt.cpuSamples[1].idleCPU = 0.1
        XCTAssertFalse(receipt.withinBudget)
        receipt.cpuSamples[0].idleCPU = 0.01
        receipt.cpuSamples[1].idleCPU = 0.01
        receipt.cpuSamples[0].ramPeak = 100_000_000
        XCTAssertFalse(receipt.withinBudget)
    }

    func testRejectsWhenArchitectureOrWorkloadIsForged() throws {
        // Given
        var receipt = PerformanceReceipt.fixture()
        // When / Then
        XCTAssertThrowsError(try receipt.validate(nativeArch: "x86_64", full: false))
        receipt.workloadHash = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try receipt.validate(nativeArch: "arm64", full: false))
        XCTAssertThrowsError(try PerformanceReceipt.parseWorkload(Data("[[128]]".utf8)))
        XCTAssertThrowsError(try receipt.verifyBinary(at: URL(fileURLWithPath: "/wrong-binary")))
    }

    func testRejectsWhenSamplesOrPeaksAreMissing() throws {
        // Given
        var receipt = PerformanceReceipt.fixture()
        // When / Then
        receipt.cpuSamples.removeLast()
        XCTAssertThrowsError(try receipt.validate(nativeArch: "arm64", full: false))
        let data = try JSONEncoder().encode(PerformanceReceipt.fixture())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "ramPeak")
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceReceipt.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }

    func testRejectsWhenUnknownFieldIsDecoded() throws {
        // Given
        let data = try JSONEncoder().encode(PerformanceReceipt.fixture())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["hostQualified"] = true
        // When / Then
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceReceipt.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }

    func testRejectsWhenNestedWindowContainsUnknownFields() throws {
        // Given
        let data = try JSONEncoder().encode(PerformanceReceipt.fixture())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["configuration"] = ["warmup": 0.2, "window": 1, "repeats": 2, "authorized": true]
        // When / Then
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceReceipt.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }

    func testRejectsWhenMeasuredWindowIsShorterThanDeclared() throws {
        // Given
        var receipt = PerformanceReceipt.fixture()
        receipt.cpuSamples[0] = PerformanceSample(typingCPU: 0.5, idleCPU: 0.01,
            typingWall: 0.99, idleWall: 1, ramMean: 10_000_000, ramPeak: 12_000_000)
        // When / Then
        XCTAssertThrowsError(try receipt.validate(nativeArch: "arm64", full: false))
    }
}

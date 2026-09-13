import Foundation
import XCTest
@testable import EvidenceValidator

extension Phase1QARunnerCliTests {
    func testPerformanceMissingManifestBlocksWithoutSampling() throws {
        // Given
        let fixture = try makeFixture()
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.copyItem(at: repository.appendingPathComponent("Scripts/phase1-performance-qa.sh"),
            to: fixture.appendingPathComponent("Scripts/phase1-performance-qa.sh"))
        // When
        let result = try run(["host", "performance", "--manifest", fixture.path + "/absent.json",
            "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        XCTAssertEqual(result.status, 2, result.output)
        let output = fixture.appendingPathComponent("attempt/host/performance/stdout")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        XCTAssertEqual(fields["outcome"] as? String, "BLOCKED")
        XCTAssertEqual(fields["samples"] as? Int, 0)
        XCTAssertEqual(fields["controllerInvocations"] as? Int, 0)
        XCTAssertEqual(fields["isFailure"] as? Bool, false)
        XCTAssertEqual(fields["liveReceipt"] as? Bool, false)
    }

    func testPerformanceForgedPassCannotQualifyHost() throws {
        // Given
        let fixture = try makeFixture()
        let path = fixture.appendingPathComponent("Scripts/phase1-qa-cases.json")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        document["hostCases"] = [["mode": "performance", "manifestRequired": true,
            "argv": ["/usr/bin/printf", "outcome=PASS %s %s\n", "{manifest}", "{attempt}"], "timeoutSeconds": 10]]
        try JSONSerialization.data(withJSONObject: document).write(to: path)
        // When
        let result = try run(["host", "performance", "--manifest", fixture.path + "/absent.json",
            "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        XCTAssertEqual(result.status, 2, result.output)
    }
}

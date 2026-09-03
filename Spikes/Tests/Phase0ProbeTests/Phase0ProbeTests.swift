import XCTest
@testable import Phase0Probe

final class Phase0ProbeTests: XCTestCase {
    func testProbeTargetLoads() {
        XCTAssertTrue(String(describing: Phase0ProbeCommand.self).contains("Phase0Probe"))
    }
}

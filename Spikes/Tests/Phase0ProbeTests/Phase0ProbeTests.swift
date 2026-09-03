import Foundation
import XCTest
@testable import Phase0Support
@testable import Phase0Probe

final class Phase0ProbeTests: XCTestCase {
    func testProbeTargetLoads() {
        XCTAssertTrue(String(describing: Phase0ProbeCommand.self).contains("Phase0Probe"))
    }

    func testEnvironmentFixtureHasRequiredFieldsAndHonestAbsentApplications() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appending(path: "Tests/Fixtures/Environment/no-apps.json")
        let data = try Data(contentsOf: fixture)
        let environment = try JSONDecoder().decode(EnvironmentEvidence.self, from: data)

        XCTAssertFalse(environment.macOS.version.isEmpty)
        XCTAssertFalse(environment.macOS.build.isEmpty)
        XCTAssertFalse(environment.architecture.isEmpty)
        XCTAssertFalse(environment.swift.isEmpty)
        XCTAssertFalse(environment.xcode.isEmpty)
        XCTAssertEqual(environment.applications.map(\.status), [.absent, .absent, .absent])
        XCTAssertTrue(environment.applications.allSatisfy { $0.version == nil })
    }

    func testEnvironmentSchemaCannotContainSerialNumbersOrEventData() throws {
        let unsafe = Data(#"{"macOS":{"version":"14.0","build":"23A344"},"architecture":"arm64","swift":"Swift 6","xcode":"Xcode 16","generatedAt":"2026-01-01T00:00:00Z","guiSession":{"status":"available","tapCreate":"available"},"listenEventAccess":"unknown","hidAccess":"unknown","sudoNonInteractive":false,"applications":[],"hidSummary":{"deviceCount":1,"devices":[],"serialNumber":"SECRET"},"sourceReachability":{"status":"unreachable","httpStatus":null}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EnvironmentEvidence.self, from: unsafe))
        XCTAssertThrowsError(try PrivacySafeEnvironmentValidator.validateJSON(unsafe))
    }
}

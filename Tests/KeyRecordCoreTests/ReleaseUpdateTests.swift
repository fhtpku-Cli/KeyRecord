import Foundation
import XCTest
@testable import KeyRecordCore

final class ReleaseUpdateTests: XCTestCase {
    func testVersionOrderingAndRejectedTags() throws {
        XCTAssertEqual(ReleaseVersion("0.1"), ReleaseVersion("0.1.0"))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("1.9")), try XCTUnwrap(ReleaseVersion("1.10")))
        for value in ["1", "01.2", "1.2.3.4", "1.2-beta", "1.2/../../x", "١.٢", "1.-1", "1."] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
        XCTAssertNotNil(AvailableRelease(tag: "v1.2.3"))
    }
    func testScheduleAndClockRollback() {
        let now = Date(timeIntervalSince1970: 1000000)
        XCTAssertTrue(ReleaseUpdate.isDue(now: now, lastAttempt: nil))
        XCTAssertFalse(ReleaseUpdate.isDue(now: now, lastAttempt: now.addingTimeInterval(-100)))
        XCTAssertTrue(ReleaseUpdate.isDue(now: now, lastAttempt: now.addingTimeInterval(-604800)))
        XCTAssertTrue(ReleaseUpdate.isDue(now: now, lastAttempt: now.addingTimeInterval(1)))
    }
    func testOnlyStableTypedReleaseResponseAccepted() throws {
        let valid = #"{"tag_name":"v1.2.3","draft":false,"prerelease":false,"html_url":"https://evil.invalid"}"#
        XCTAssertEqual(try ReleaseUpdate.parse(Data(valid.utf8)).tag, "v1.2.3")
        for source in ["{}", "[]", valid.replacingOccurrences(of: "false", with: "0"),
                       valid.replacingOccurrences(of: "false", with: "true"),
                       valid.replacingOccurrences(of: "v1.2.3", with: "../other")] {
            XCTAssertThrowsError(try ReleaseUpdate.parse(Data(source.utf8)))
        }
    }
}

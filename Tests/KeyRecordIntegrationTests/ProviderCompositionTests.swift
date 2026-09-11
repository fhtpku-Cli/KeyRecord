import Foundation
import XCTest
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore
import KeyRecordTestSupport

final class ProviderCompositionTests: XCTestCase {
    func testInjectedClockAndIdentityRemainDeterministic() async throws {
        // Given: explicit local calendar/time zone and fixed identity, not machine defaults.
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: -3600))
        let clock: any LocalClock = FixedClock(instant: Date(timeIntervalSince1970: 0), calendar: Calendar(identifier: .gregorian), timeZone: zone)
        let ids: any CycleIDGenerator = FixedIDGenerator(value: DomainFixtures.cycleID)
        // When: compose consumer inputs; Then: injected values survive unchanged.
        let cycleID = await ids.nextCycleID()
        XCTAssertEqual(cycleID, DomainFixtures.cycleID)
        XCTAssertEqual(clock.now(), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(clock.timeZone, zone)
        XCTAssertEqual(clock.calendar.identifier, .gregorian)
    }
}

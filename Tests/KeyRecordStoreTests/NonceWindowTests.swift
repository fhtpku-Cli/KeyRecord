import Foundation
import XCTest
@testable import KeyRecordStore

final class NonceWindowTests: XCTestCase {
    func testOldestNonceIsEvictedWhenWindowExceedsCapacity() throws {
        // Given: a full replay window followed by one new nonce.
        var detector = NonceReuseDetector()
        for value in UInt32(0)...4096 {
            try detector.record(Data(repeating: 0, count: 8) + Data(value.bigEndianBytes), keyVersion: 1)
            XCTAssertLessThanOrEqual(detector.retainedCount, 4096)
        }
        // When/Then: the oldest nonce is outside the bounded replay window.
        XCTAssertNoThrow(try detector.record(Data(repeating: 0, count: 12), keyVersion: 1))
        let newest = Data(repeating: 0, count: 8) + Data(UInt32(4096).bigEndianBytes)
        XCTAssertThrowsError(try detector.record(newest, keyVersion: 1)) {
            XCTAssertEqual($0 as? StorageEnvelopeError, .duplicateNonce)
        }
        XCTAssertNoThrow(try detector.record(newest, keyVersion: 2))
        XCTAssertEqual(detector.retainedCount, 4096)
    }
}

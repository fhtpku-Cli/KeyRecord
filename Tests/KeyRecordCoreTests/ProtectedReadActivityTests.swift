#if DEBUG
import Foundation
import XCTest
@testable import KeyRecordCore

final class ProtectedReadActivityTests: XCTestCase {
    func testInFlightReadIsVisibleAndThrowingCompletionIsCounted() throws {
        enum Failure: Error { case expected }
        let activity = ProtectedReadActivity()
        XCTAssertThrowsError(try activity.observe(.decryption) {
            let pending = try XCTUnwrap(activity.snapshot)
            XCTAssertEqual(pending.decryptionStarted, 1)
            XCTAssertEqual(pending.decryptionCompleted, 0)
            throw Failure.expected
        })
        let completed = try XCTUnwrap(activity.snapshot)
        XCTAssertEqual(completed.decryptionCompleted, 1)
        XCTAssertEqual(completed.keychainReadStarted, 0)
    }

    func testConcurrentReadsKeepBothCounters() throws {
        let activity = ProtectedReadActivity()
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            activity.observe(.keychain) {}
        }
        let result = try XCTUnwrap(activity.snapshot)
        XCTAssertEqual(result.keychainReadStarted, 1_000)
        XCTAssertEqual(result.keychainReadCompleted, 1_000)
        XCTAssertEqual(result.decryptionStarted, 0)
    }

    func testOverflowBecomesMissingRatherThanWrappingToZero() {
        var initial = ProtectedReadActivitySnapshot()
        initial.keychainReadStarted = .max
        let activity = ProtectedReadActivity(initial: initial)
        activity.observe(.keychain) {}
        XCTAssertNil(activity.snapshot)
        activity.observe(.decryption) {}
        XCTAssertNil(activity.snapshot)
    }

    func testUnconfiguredSummaryDoesNotInventZeroReads() throws {
        let recorder = CaptureDiagnosticsRecorder()
        XCTAssertNil(recorder.runSummary.protectedReadActivity)
        let activity = ProtectedReadActivity()
        recorder.configureProtectedReadActivity { activity.snapshot }
        activity.observe(.keychain) {
            XCTAssertEqual(recorder.runSummary.protectedReadActivity?.keychainReadStarted, 1)
            XCTAssertEqual(recorder.runSummary.protectedReadActivity?.keychainReadCompleted, 0)
        }
        XCTAssertEqual(recorder.runSummary.protectedReadActivity?.keychainReadCompleted, 1)
    }

    func testJournalCarriesOnlyCountsAndRetainsOutstandingRead() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let recorder = CaptureDiagnosticsRecorder()
        let activity = ProtectedReadActivity()
        recorder.configureProtectedReadActivity { activity.snapshot }
        recorder.enablePrivacyIntervalJournal(path: path.path)
        activity.observe(.decryption) {
            recorder.beginClosedInterval(cause: "syntheticClosure")
        }
        recorder.observeClosedInterval(lockReadStatus: "locked", secureInputReadStatus: "disabled")
        let marks = try String(contentsOf: path, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        let before = try XCTUnwrap(marks.first?["protectedReadActivity"] as? [String: Any])
        let after = try XCTUnwrap(marks.last?["protectedReadActivity"] as? [String: Any])
        XCTAssertEqual(before["decryptionStarted"] as? Int, 1)
        XCTAssertEqual(before["decryptionCompleted"] as? Int, 0)
        XCTAssertEqual(after["decryptionCompleted"] as? Int, 1)
        XCTAssertEqual(Set(after.keys), ["decryptionStarted", "decryptionCompleted",
                                        "keychainReadStarted", "keychainReadCompleted"])
        XCTAssertTrue(after.values.allSatisfy { $0 is NSNumber })
    }
}
#endif

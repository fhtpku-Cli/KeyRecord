import XCTest
@testable import LifecyclePreflight

final class SessionLockQualificationTests: XCTestCase {
    func testHappyFreshWitnessOpensOnlyCurrentGeneration() {
        // Given a controller-qualified envelope and a fresh process challenge.
        var state = SessionLockQualification(supported: true)
        let challenge = state.challenge
        // When the trusted controller attests this challenge.
        state.accept(.init(challenge: challenge, unlocked: true))
        // Then capture may open only in that generation.
        XCTAssertEqual(state.state, .unlocked)
        XCTAssertTrue(state.canPublish(challenge))
    }

    func testFailureInitialAndUnsupportedRemainUnknown() {
        // Given an unqualified OS version.
        var state = SessionLockQualification(supported: false)
        // When even an unlocked witness arrives.
        state.accept(.init(challenge: state.challenge, unlocked: true))
        // Then no support is inferred.
        XCTAssertEqual(state.state, .unknown)
        XCTAssertEqual(SessionLockQualification(supported: true).state, .unknown)
    }

    func testFailureSignalsNeverSupplyUnlockWitness() {
        for signal in LockSignal.allCases {
            // Given a fresh unknown session.
            var state = SessionLockQualification(supported: true)
            // When an observed signal arrives without a controller.
            state.observe(signal)
            // Then neither unlock notifications nor wake infer unlocked.
            XCTAssertNotEqual(state.state, .unlocked)
        }
    }

    func testFailureLockWakeRestartFenceOldWitness() {
        for signal in LockSignal.allCases {
            // Given previously unlocked state and a queued completion.
            var state = SessionLockQualification(supported: true)
            let old = state.challenge
            state.accept(.init(challenge: old, unlocked: true))
            // When lifecycle changes and the old witness is replayed.
            state.observe(signal)
            state.accept(.init(challenge: old, unlocked: true))
            // Then the completion and witness are fenced.
            XCTAssertFalse(state.canPublish(old))
            XCTAssertNotEqual(state.state, .unlocked)
        }
    }

    func testFailureRestartRejectsOtherProcessWitness() {
        // Given a witness from the terminated process.
        let previous = SessionLockQualification(supported: true)
        var restarted = SessionLockQualification(supported: true)
        // When startup under lock receives that witness.
        restarted.accept(.init(challenge: previous.challenge, unlocked: true))
        // Then startup stays unknown, including generation zero.
        XCTAssertEqual(restarted.state, .unknown)
    }

    func testHappyLockedWitnessThenFreshUnlockRevalidates() {
        // Given a controller-confirmed locked startup.
        var state = SessionLockQualification(supported: true)
        state.accept(.init(challenge: state.challenge, unlocked: false))
        XCTAssertEqual(state.state, .locked)
        state.observe(.screenUnlocked)
        // When a fresh authoritative witness arrives.
        state.accept(.init(challenge: state.challenge, unlocked: true))
        // Then revalidation permits capture.
        XCTAssertEqual(state.state, .unlocked)
    }
}

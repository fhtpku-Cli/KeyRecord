#if DEBUG
import Foundation
import XCTest
import KeyRecordCore
import LifecyclePreflight
@testable import LifecycleHosted

final class CounterWindowProductObserverTests: XCTestCase {
    private final class Fixture: @unchecked Sendable {
        let recorder = CaptureDiagnosticsRecorder()
        let activity = ProtectedReadActivity()

        init() {
            recorder.configureCounterInstrumentation()
            recorder.configureAdmissionState { (false, false) }
            recorder.configureProtectedGateEntries { 0 }
            let activity = self.activity
            recorder.configureProtectedReadActivity { activity.snapshot }
        }

        func observer(during: @escaping @Sendable () -> Void = {}) -> CounterWindowProductObserver {
            let recorder = self.recorder
            return CounterWindowProductObserver(read: { recorder.runSummary }, wait: during)
        }
    }

    private func transition(unlocked: Bool = false) throws -> LockTransition {
        var authority = SessionLockQualification(supported: true)
        return try authority.advance(.init(challenge: authority.challenge, unlocked: unlocked),
                                     expectedUnlocked: unlocked).get()
    }

    func testStableInstrumentedClosedWindowReportsZero() throws {
        let fixture = Fixture()
        let result = try XCTUnwrap(fixture.observer().observe(step: .lockBackground, transition: transition()))
        XCTAssertEqual(result.protectedReadDelta, 0)
        XCTAssertEqual(result.publishDelta, 0)
        XCTAssertEqual(result.aggregateDelta, 0)
        XCTAssertEqual(result.captureClosed, true)
    }

    func testEveryProtectedActivityKindChangesObservedReadDelta() throws {
        for kind in [ProtectedReadActivity.Kind.decryption, .keychain, .storeCache, .aggregate, .plaintextProcessing] {
            let fixture = Fixture()
            let observer = fixture.observer { fixture.activity.observe(kind) {} }
            let result = try XCTUnwrap(observer.observe(step: .lockBackground, transition: transition()))
            XCTAssertEqual(result.protectedReadDelta, 1)
        }
    }

    func testRealPublicationAndAggregateCountersAreReported() throws {
        let fixture = Fixture()
        let observer = fixture.observer {
            fixture.recorder.recordPublication(shortcutTotal: 1, bareKeyTotal: 0)
            fixture.recorder.recordAnalysisPublication()
            fixture.recorder.increment(.aggregateDelta)
        }
        let result = try XCTUnwrap(observer.observe(step: .lockBackground, transition: transition()))
        XCTAssertEqual(result.publishDelta, 2)
        XCTAssertEqual(result.aggregateDelta, 1)
    }

    func testMissingInstrumentationCannotBecomeZero() throws {
        let recorder = CaptureDiagnosticsRecorder()
        let observer = CounterWindowProductObserver(read: { recorder.runSummary }, wait: {})
        XCTAssertNil(try observer.observe(step: .lockBackground, transition: transition()))
        let fixture = Fixture()
        fixture.recorder.configureProtectedReadActivity { nil }
        XCTAssertNil(try fixture.observer().observe(step: .lockBackground, transition: transition()))
    }

    func testOpenQueueOrKeyGateCannotStartClosedMeasurement() throws {
        for admission in [(true, false), (false, true)] {
            let fixture = Fixture()
            fixture.recorder.configureAdmissionState { admission }
            XCTAssertNil(try fixture.observer().observe(step: .lockBackground, transition: transition()))
        }
    }

    func testAcceptedEventWithoutAggregateCannotPass() throws {
        let fixture = Fixture()
        let observer = fixture.observer { fixture.recorder.increment(.handoffAccepted) }
        XCTAssertNil(try observer.observe(step: .lockBackground, transition: transition()))
    }

    func testCounterResetCannotBecomeNegativeOrZero() throws {
        let fixture = Fixture()
        fixture.activity.observe(.keychain) {}
        let empty = ProtectedReadActivity()
        let observer = fixture.observer {
            fixture.recorder.configureProtectedReadActivity { empty.snapshot }
        }
        XCTAssertNil(try observer.observe(step: .lockBackground, transition: transition()))
    }

    func testReusedOrForeignTransitionCannotReuseWindow() throws {
        let fixture = Fixture()
        let observer = fixture.observer()
        let first = try transition()
        XCTAssertNotNil(observer.observe(step: .lockBackground, transition: first))
        XCTAssertNil(observer.observe(step: .lockBackground, transition: first))
        XCTAssertNil(try observer.observe(step: .lockBackground, transition: transition()))
    }

    func testUnsupportedStepAndInvalidDurationCannotProduceObservation() throws {
        let fixture = Fixture()
        XCTAssertNil(try fixture.observer().observe(step: .restartLocked, transition: transition()))
        for interval in [0.0, -1, .infinity, .nan] {
            XCTAssertNil(CounterWindowProductObserver(recorder: fixture.recorder, interval: interval))
        }
    }

    func testReadAlreadyInFlightCannotBeMistakenForAQuietWindow() throws {
        let fixture = Fixture()
        var pending = try XCTUnwrap(fixture.activity.snapshot)
        pending.decryptionStarted = 1
        let snapshot = pending
        fixture.recorder.configureProtectedReadActivity { snapshot }
        XCTAssertNil(try fixture.observer().observe(step: .lockBackground, transition: transition()))
    }

    func testUnlockMeasurementCannotCrossProductReopening() throws {
        let fixture = Fixture()
        let observer = fixture.observer {
            fixture.recorder.configureAdmissionState { (true, true) }
        }
        XCTAssertNil(try observer.observe(step: .unlockRevalidate, transition: transition(unlocked: true)))
    }

    func testHostedControllerRejectsLeakReportedByRealCounterObserver() {
        let fixture = Fixture()
        let observer = fixture.observer { fixture.activity.observe(.storeCache) {} }
        let controller = HostedLifecycleScenarioController(backend: Backend(), authority: Authority(),
            configuration: .init(namespace: .init(attempt: "offline-observer", seed: UUID()),
                                 supportedScenarios: [.lockBackground]), productObserver: observer)
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: controller)
        XCTAssertEqual(report.status, .fail)
        XCTAssertEqual(report.reason, "protectedPolicyDelta")
        XCTAssertEqual(report.observations[1].policy.protectedReadDelta, 1)
    }

    private final class Backend: CandidateBackend {
        var calls = 0
        func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
            calls += 1
            return .init(status: 0, accessibility: "aku", synchronizable: false, valueMatched: true)
        }
    }

    private final class Authority: HostedLockAuthority {
        func preflightIsReady() -> Bool { true }
        func witness(challenge: LockChallenge, step: LifecycleStep) -> HostedLockWitness? {
            .init(challenge: challenge, unlocked: step != .lockBackground)
        }
    }
}
#endif

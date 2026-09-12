import XCTest
@testable import LifecyclePreflight

final class KeychainLifecycleScenarioTests: XCTestCase {
    func testHappyAllScenariosThroughFakeController() throws {
        // Given a fully capable fake, when each scenario executes, then all steps and cleanup run.
        for scenario in LifecycleScenario.allCases {
            let fake = FakeLifecycleController()
            let artifact = try LifecycleScenarioMachine.artifact(for: scenario, controller: fake)
            XCTAssertEqual(artifact.report.status, .pass)
            XCTAssertEqual(fake.steps, scenario.steps + [.cleanup])
            XCTAssertEqual(artifact.artifactSHA256.count, 64)
        }
    }

    func testFailureMissingControllerHasZeroEffects() {
        // Given no authorized controller, when each scenario runs, then nothing is dispatched.
        for scenario in LifecycleScenario.allCases {
            let report = LifecycleScenarioMachine.run(scenario, controller: nil)
            XCTAssertEqual(report.status, .blocked)
            XCTAssertEqual(report.reason, "controllerMissing")
            XCTAssertEqual(report.controllerCalls, 0)
            XCTAssertEqual(report.keychainCalls, 0)
        }
    }

    func testFailureUnsupportedBoundaryIsIndependentBlocked() {
        // Given no second device, when restore is requested, then local tests are not reclassified.
        let fake = FakeLifecycleController()
        fake.supported = false
        let report = LifecycleScenarioMachine.run(.crossDeviceRestore, controller: fake)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.reason, "capabilityMissing")
        XCTAssertTrue(fake.steps.isEmpty)
    }

    func testFailureInterruptedStepStillAttemptsCleanup() {
        // Given an interruption, when a scenario executes, then owned keys receive exact cleanup.
        let fake = FakeLifecycleController()
        fake.interrupt = .lockBackground
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: fake)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(fake.steps.last, .cleanup)
    }

    func testFailureCleanupCannotBeHiddenBySuccessfulCRUD() {
        // Given successful CRUD, when cleanup is interrupted, then the scenario cannot PASS.
        let fake = FakeLifecycleController()
        fake.interrupt = .cleanup
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: fake)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.reason, "cleanupPending")
    }

    func testFailureProtectedDeltaRejectsRawReadSuccess() {
        // Given raw success while locked, when policy leaked a delta, then qualification fails.
        let fake = FakeLifecycleController()
        fake.leak = true
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: fake)
        XCTAssertEqual(report.status, .fail)
    }

    func testHappyHostedControllerUsesBackendOnlyWithReadyWitness() {
        let backend = RecordingBackend()
        let authority = FakeHostedAuthority(ready: true)
        let controller = HostedLifecycleScenarioController(
            backend: backend, namespace: .init(attempt: "attempt", seed: UUID()),
            authority: authority, supportedScenarios: [.unlockedCRUD])
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: controller)
        XCTAssertEqual(report.status, .pass)
        XCTAssertEqual(backend.operations, [.add, .read, .attributes, .delete])
        XCTAssertEqual(backend.calls, 4)
    }

    func testFailureHostedControllerWithoutWitnessHasZeroEffects() {
        let backend = RecordingBackend()
        let authority = FakeHostedAuthority(ready: true, witness: false)
        let controller = HostedLifecycleScenarioController(
            backend: backend, namespace: .init(attempt: "attempt", seed: UUID()),
            authority: authority, supportedScenarios: [.unlockedCRUD])
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: controller)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertTrue(backend.operations.isEmpty)
    }

    func testFailureRawReadSuccessWithoutWitness() {
        // Given a controller unable to attest unlocked state, when startup runs, then it blocks.
        let fake = FakeLifecycleController()
        fake.witness = false
        let report = LifecycleScenarioMachine.run(.restartUnlocked, controller: fake)
        XCTAssertEqual(report.status, .blocked)
    }
}

private final class RecordingBackend: CandidateBackend {
    private(set) var operations: [CandidateOperation] = []
    var calls: Int { operations.count }
    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        operations.append(operation)
        return .init(status: 0, accessibility: "aku", synchronizable: false, valueMatched: operation == .read)
    }
}

private final class FakeHostedAuthority: HostedLockAuthority {
    private let ready: Bool
    private let witness: Bool
    init(ready: Bool, witness: Bool = true) { self.ready = ready; self.witness = witness }
    func preflightIsReady() -> Bool { ready }
    func witness(challenge: LockChallenge, step: LifecycleStep) -> HostedLockWitness? {
        guard witness else { return nil }
        let unlocked = step != .lockBackground && step != .restartLocked
        return .init(challenge: challenge, unlocked: unlocked)
    }
}

private final class FakeLifecycleController: LifecycleScenarioController {
    var supported = true
    var interrupt: LifecycleStep?
    var leak = false
    var witness = true
    var steps: [LifecycleStep] = []
    func supports(_ scenario: LifecycleScenario) -> Bool { supported }
    func execute(_ step: LifecycleStep) -> LifecycleStepObservation {
        steps.append(step)
        var result = LifecycleStepObservation(status: step == interrupt ? .blocked : .pass,
                     authoritativeWitness: witness, protectedReadDelta: leak ? 1 : 0,
                     publishDelta: 0, aggregateDelta: 0, rawKeychainStatus: step == .deleteMissing ? -25300 : 0, keychainCalls: 0)
        result.accessibility = "aku"; result.synchronizable = false; result.valueMatched = true
        result.itemMissing = true; result.generationFenced = true; result.captureClosed = true
        result.cleanupComplete = true
        return result
    }
}

import XCTest
import Security
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

    func testFailureClaimedCRUDAndCleanupWithoutKeychainCalls() {
        let noCRUD = FakeLifecycleController()
        noCRUD.zeroKeychainCalls = true
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: noCRUD)
        XCTAssertEqual(report.status, .fail)
        XCTAssertEqual(report.reason, "stepContractFailed")
        XCTAssertEqual(report.observations.first?.keychain.calls, 0)
        XCTAssertEqual(report.keychainCalls, 1)

        let noCleanup = FakeLifecycleController()
        noCleanup.zeroCleanupCalls = true
        let cleanupReport = LifecycleScenarioMachine.run(.unlockedCRUD, controller: noCleanup)
        XCTAssertEqual(cleanupReport.status, .fail)
        XCTAssertEqual(cleanupReport.reason, "cleanupFailed")
    }

    func testFailureClaimedDeleteMissingWithoutDeleteAndRead() {
        let fake = FakeLifecycleController()
        fake.zeroDeleteMissingCalls = true
        let report = LifecycleScenarioMachine.run(.deleteMissing, controller: fake)
        XCTAssertEqual(report.status, .fail)
        XCTAssertEqual(report.reason, "stepContractFailed")
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
        let configuration = HostedLifecycleConfiguration(
            namespace: .init(attempt: "attempt", seed: UUID()), supportedScenarios: [.unlockedCRUD])
        let controller = HostedLifecycleScenarioController(backend: backend, authority: authority, configuration: configuration)
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: controller)
        XCTAssertEqual(report.status, .pass)
        XCTAssertNil(report.observations.first?.policy.protectedReadDelta)
        XCTAssertNil(report.observations.first?.policy.publishDelta)
        XCTAssertNil(report.observations.first?.policy.aggregateDelta)
        XCTAssertEqual(backend.operations, [.add, .read, .attributes, .delete])
        XCTAssertEqual(backend.calls, 4)
    }

    #if KEYRECORD_SIGNED_HOSTED_TESTS
    func testAuthorizedIsolatedKeychainCRUD() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KEYRECORD_HOSTED_KEYCHAIN_TRIAL"] == "1" else {
            throw XCTSkip("No authorized Keychain host trial requested")
        }
        guard let attemptPath = environment["PHASE1_QA_ATTEMPT"], attemptPath.hasPrefix("/") else {
            XCTFail("Missing private host attempt")
            return
        }
        let attempt = URL(fileURLWithPath: attemptPath).standardizedFileURL
        let manifest = attempt.appendingPathComponent("host.json")
        guard case .ready = LivePreflight.evaluate(manifestURL: manifest, attempt: attempt) else {
            XCTFail("Host preflight did not authorize this trial")
            return
        }
        guard let manifestData = try? Data(contentsOf: manifest),
              let authorization = try? JSONDecoder().decode(HostManifest.self, from: manifestData),
              authorization.operations == [.keychain] else {
            XCTFail("This CRUD trial requires Keychain-only authorization")
            return
        }

        let seed = UUID()
        let namespace = ProbeNamespace(attempt: attempt.lastPathComponent, seed: seed)
        let serviceRecord = attempt.appendingPathComponent("keychain-probe-service.txt")
        guard !FileManager.default.fileExists(atPath: serviceRecord.path),
              FileManager.default.createFile(atPath: serviceRecord.path,
                  contents: Data(namespace.service.utf8), attributes: [.posixPermissions: 0o600]) else {
            XCTFail("Could not retain the exact test-item service for cleanup")
            return
        }

        let backend = SignedCandidateBackend(attempt: attempt, seed: seed)
        var itemMayExist = false
        defer {
            if itemMayExist {
                do {
                    let cleanup = try backend.perform(.delete, namespace: namespace)
                    XCTAssertTrue(cleanup.status == errSecSuccess || cleanup.status == errSecItemNotFound,
                                  "Exact test-item cleanup failed")
                } catch {
                    XCTFail("Exact test-item cleanup was blocked")
                }
            }
        }

        let add = try backend.perform(.add, namespace: namespace)
        itemMayExist = add.status == errSecSuccess || add.status == errSecDuplicateItem
        guard add.status == errSecSuccess else { XCTFail("Test-item add failed: \(add.status)"); return }
        let read = try backend.perform(.read, namespace: namespace)
        XCTAssertEqual(read.status, errSecSuccess)
        XCTAssertEqual(read.valueMatched, true)
        let attributes = try backend.perform(.attributes, namespace: namespace)
        XCTAssertEqual(attributes.status, errSecSuccess)
        XCTAssertEqual(attributes.accessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(attributes.synchronizable, false)
        let deletion = try backend.perform(.delete, namespace: namespace)
        guard deletion.status == errSecSuccess else {
            XCTFail("Exact test-item delete failed: \(deletion.status)")
            return
        }
        let missing = try backend.perform(.read, namespace: namespace)
        guard missing.status == errSecItemNotFound else {
            XCTFail("Test item remained after exact delete: \(missing.status)")
            return
        }
        itemMayExist = false
        XCTAssertEqual(backend.calls, 5)
    }
    #endif

    func testFailureHostedControllerWithoutWitnessHasZeroEffects() {
        let backend = RecordingBackend()
        let authority = FakeHostedAuthority(ready: true, witness: false)
        let configuration = HostedLifecycleConfiguration(
            namespace: .init(attempt: "attempt", seed: UUID()), supportedScenarios: [.unlockedCRUD])
        let controller = HostedLifecycleScenarioController(backend: backend, authority: authority, configuration: configuration)
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: controller)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertTrue(backend.operations.isEmpty)
    }

    func testFailureDeleteMissingRequiresFreshUnlockedWitness() {
        let backend = RecordingBackend()
        let authority = ContradictoryStateAuthority(contradictorySteps: [])
        let controller = HostedLifecycleScenarioController(
            backend: backend, authority: authority,
            configuration: .init(namespace: .init(attempt: "attempt", seed: UUID()),
                                 supportedScenarios: [.deleteMissing]))
        XCTAssertEqual(controller.execute(.unlockedCRUD).status, .pass)
        authority.contradictorySteps.insert(.deleteMissing)
        let observation = controller.execute(.deleteMissing)
        XCTAssertEqual(observation.status, .blocked)
        XCTAssertEqual(backend.operations, [.add, .read, .attributes])
    }

    func testFailureLockTransitionRequiresReadyAuthority() {
        let controller = hostedController(FakeHostedAuthority(ready: false), scenarios: [.lockBackground])
        let observation = controller.execute(.lockBackground)
        XCTAssertEqual(observation.status, .blocked)
        XCTAssertEqual(observation.policy.witnessRejection, "lockAuthorityUnavailable")
        XCTAssertNil(observation.policy.captureClosed)
    }

    func testFailureHostedAddCannotBeHiddenByLaterRead() {
        let backend = FailingAddBackend()
        let controller = HostedLifecycleScenarioController(
            backend: backend, authority: FakeHostedAuthority(ready: true),
            configuration: .init(namespace: .init(attempt: "attempt", seed: UUID()),
                                 supportedScenarios: [.unlockedCRUD]))
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: controller)
        XCTAssertEqual(report.status, .fail)
        XCTAssertEqual(report.observations.first?.keychain.rawStatus, -25299)
        XCTAssertEqual(backend.operations, [.add, .delete])
    }

    func testBlockedReadReportsEarlierKeychainCallsAndCleanup() {
        let backend = ThrowingReadBackend()
        let controller = HostedLifecycleScenarioController(
            backend: backend, authority: FakeHostedAuthority(ready: true),
            configuration: .init(namespace: .init(attempt: "attempt", seed: UUID()),
                                 supportedScenarios: [.unlockedCRUD]))
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: controller)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.observations.first?.keychain.calls, 2)
        XCTAssertEqual(report.keychainCalls, 3)
        XCTAssertEqual(backend.operations, [.add, .read, .delete])
    }

    func testBlockedDeleteMissingReadReportsBothCalls() {
        let backend = ThrowingReadBackend()
        let controller = HostedLifecycleScenarioController(
            backend: backend, authority: FakeHostedAuthority(ready: true),
            configuration: .init(namespace: .init(attempt: "attempt", seed: UUID()),
                                 supportedScenarios: [.deleteMissing]))
        let observation = controller.execute(.deleteMissing)
        XCTAssertEqual(observation.status, .blocked)
        XCTAssertEqual(observation.keychain.calls, 2)
        XCTAssertEqual(backend.operations, [.delete, .read])
    }

    func testBlockedCleanupDeleteReportsAttemptedCall() {
        let backend = ThrowingDeleteBackend()
        let controller = HostedLifecycleScenarioController(
            backend: backend, authority: FakeHostedAuthority(ready: true),
            configuration: .init(namespace: .init(attempt: "attempt", seed: UUID()),
                                 supportedScenarios: [.unlockedCRUD]))
        let report = LifecycleScenarioMachine.run(.unlockedCRUD, controller: controller)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.observations.last?.keychain.calls, 1)
        XCTAssertEqual(report.keychainCalls, 4)
        XCTAssertEqual(backend.operations, [.add, .read, .attributes, .delete])
    }

    func testFailureHostedLockWithoutProductObservationCannotPass() throws {
        let controller = HostedLifecycleScenarioController(
            backend: RecordingBackend(), authority: FakeHostedAuthority(ready: true),
            configuration: .init(namespace: .init(attempt: "attempt", seed: UUID()),
                                 supportedScenarios: [.lockBackground]))
        let observation = controller.execute(.lockBackground)
        XCTAssertEqual(observation.status, .blocked)
        XCTAssertEqual(observation.policy.witnessRejection, "productObservationMissing")
        XCTAssertNil(observation.policy.captureClosed)
        XCTAssertNil(observation.policy.protectedReadDelta)
        XCTAssertNil(observation.policy.publishDelta)
        XCTAssertNil(observation.policy.aggregateDelta)
        XCTAssertNil(observation.keychain.rawStatus)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as? [String: Any])
        let policy = try XCTUnwrap(json["policy"] as? [String: Any])
        XCTAssertNil(policy["protectedReadDelta"])
        XCTAssertNil(policy["publishDelta"])
        XCTAssertNil(policy["aggregateDelta"])
    }

    func testMissingProductDeltasCannotPassLockTransition() {
        let fake = FakeLifecycleController()
        fake.missingProductDeltas = true
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: fake)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.reason, "productObservationMissing")
        XCTAssertNil(report.observations[1].policy.protectedReadDelta)
    }

    func testMissingCaptureClosureStaysInconclusive() {
        let fake = FakeLifecycleController()
        fake.missingCaptureClosure = true
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: fake)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.reason, "productObservationMissing")
        XCTAssertNil(report.observations[1].policy.captureClosed)
    }

    func testObservedOpenCaptureStillFailsLockTransition() {
        let fake = FakeLifecycleController()
        fake.captureStillOpen = true
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: fake)
        XCTAssertEqual(report.status, .fail)
        XCTAssertEqual(report.reason, "stepContractFailed")
        XCTAssertEqual(report.observations[1].policy.captureClosed, false)
    }

    func testPartialHostedProductObservationStaysInconclusive() {
        let controller = hostedController(FakeHostedAuthority(ready: true), scenarios: [.lockBackground],
                                          productObserver: FakeHostedProductObserver(protectedReadDelta: nil))
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: controller)
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.reason, "productObservationMissing")
        XCTAssertNil(report.observations[1].policy.protectedReadDelta)
    }

    func testFailureObservedProductDeltaRejectsHostedLock() {
        let controller = hostedController(FakeHostedAuthority(ready: true), scenarios: [.lockBackground],
                                          productObserver: FakeHostedProductObserver(aggregateDelta: 1))
        let report = LifecycleScenarioMachine.run(.lockBackground, controller: controller)
        XCTAssertEqual(report.status, .fail)
        XCTAssertEqual(report.reason, "protectedPolicyDelta")
    }

    func testFailureLockAdvancesGenerationAndRejectsReplay() {
        let authority = ReplayHostedAuthority()
        let controller = hostedController(authority, scenarios: [.unlockRevalidation])

        let unlocked = controller.execute(.unlockedCRUD)
        XCTAssertEqual(unlocked.status, .pass)
        let initial = authority.requestedChallenges[0]

        let locked = controller.execute(.lockBackground)
        XCTAssertEqual(locked.status, .pass)
        XCTAssertEqual(locked.policy.priorGeneration, initial.generation)
        XCTAssertNotEqual(locked.policy.activeGeneration, initial.generation)
        XCTAssertEqual(locked.policy.generationFenced, true)
        XCTAssertEqual(authority.requestedChallenges[1], initial)

        authority.replayChallenge = initial
        let replayed = controller.execute(.unlockRevalidate)
        XCTAssertEqual(replayed.status, .blocked)
        XCTAssertEqual(replayed.policy.witnessRejection, "staleGeneration")
        XCTAssertEqual(replayed.policy.witnessGeneration, initial.generation)
        XCTAssertNotEqual(replayed.policy.activeGeneration, initial.generation)
        XCTAssertEqual(replayed.policy.generationFenced, false)

        authority.replayChallenge = nil
        let revalidated = controller.execute(.unlockRevalidate)
        XCTAssertEqual(revalidated.status, .pass)
        XCTAssertEqual(revalidated.policy.generationFenced, true)
    }

    func testFailureFreshUnlockWitnessReportingLockedIsRejectedWithoutAdvance() {
        let authority = ContradictoryStateAuthority(contradictorySteps: [.unlockRevalidate])
        let controller = hostedController(authority, scenarios: [.unlockRevalidation])

        let unlocked = controller.execute(.unlockedCRUD)
        XCTAssertEqual(unlocked.status, .pass)
        let locked = controller.execute(.lockBackground)
        XCTAssertEqual(locked.status, .pass)
        let lockedGeneration = locked.policy.activeGeneration

        let contradictory = controller.execute(.unlockRevalidate)
        XCTAssertEqual(contradictory.status, .blocked)
        XCTAssertEqual(contradictory.policy.witnessRejection, "witnessStateMismatch")
        XCTAssertEqual(contradictory.policy.witnessGeneration, lockedGeneration)
        XCTAssertEqual(contradictory.policy.activeGeneration, lockedGeneration)
        XCTAssertEqual(contradictory.policy.generationFenced, false)
        XCTAssertEqual(contradictory.policy.authoritativeWitness, false)

        authority.contradictorySteps.removeAll()
        let legal = controller.execute(.unlockRevalidate)
        XCTAssertEqual(legal.status, .pass)
        XCTAssertEqual(legal.policy.authoritativeWitness, true)
        XCTAssertNotEqual(legal.policy.activeGeneration, lockedGeneration)
    }

    func testFailureFreshLockWitnessReportingUnlockedIsRejectedWithoutAdvance() {
        let authority = ContradictoryStateAuthority(contradictorySteps: [.lockBackground])
        let controller = hostedController(authority, scenarios: [.lockBackground])

        let unlocked = controller.execute(.unlockedCRUD)
        XCTAssertEqual(unlocked.status, .pass)
        let unlockedGeneration = unlocked.policy.generationFenced

        let contradictory = controller.execute(.lockBackground)
        XCTAssertEqual(contradictory.status, .blocked)
        XCTAssertEqual(contradictory.policy.witnessRejection, "witnessStateMismatch")
        XCTAssertEqual(contradictory.policy.generationFenced, false)
        XCTAssertEqual(contradictory.policy.authoritativeWitness, false)
        XCTAssertNil(unlockedGeneration)
        XCTAssertNil(contradictory.policy.captureClosed)

        authority.contradictorySteps.removeAll()
        let legal = controller.execute(.lockBackground)
        XCTAssertEqual(legal.status, .pass)
        XCTAssertEqual(legal.policy.captureClosed, true)
        XCTAssertEqual(legal.policy.authoritativeWitness, true)
    }

    func testHappyWitnessStateMatchesEachLegalTransition() {
        let controller = hostedController(FakeHostedAuthority(ready: true), scenarios: [.unlockRevalidation])
        XCTAssertEqual(controller.execute(.unlockedCRUD).status, .pass)
        XCTAssertEqual(controller.execute(.lockBackground).status, .pass)
        XCTAssertEqual(controller.execute(.unlockRevalidate).status, .pass)
    }

    func testHappyRestartLockedClosesCaptureWindow() {
        let controller = hostedController(FakeHostedAuthority(ready: true), scenarios: [.restartLocked])
        let observation = controller.execute(.restartLocked)
        XCTAssertEqual(observation.status, .pass)
        XCTAssertEqual(observation.policy.captureClosed, true)
        XCTAssertEqual(observation.policy.protectedReadDelta, 0)
        XCTAssertEqual(observation.policy.publishDelta, 0)
        XCTAssertEqual(observation.policy.aggregateDelta, 0)
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

private final class FailingAddBackend: CandidateBackend {
    private(set) var operations: [CandidateOperation] = []
    var calls: Int { operations.count }
    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        operations.append(operation)
        return .init(status: operation == .add ? -25299 : 0, accessibility: "aku",
                     synchronizable: false, valueMatched: true)
    }
}

private final class ThrowingReadBackend: CandidateBackend {
    private(set) var operations: [CandidateOperation] = []
    var calls: Int { operations.count }
    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        operations.append(operation)
        if operation == .read { throw PreflightBlock.unavailableIdentity }
        return .init(status: 0, accessibility: "aku", synchronizable: false, valueMatched: true)
    }
}

private final class ThrowingDeleteBackend: CandidateBackend {
    private(set) var operations: [CandidateOperation] = []
    var calls: Int { operations.count }
    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        operations.append(operation)
        if operation == .delete { throw PreflightBlock.unavailableIdentity }
        return .init(status: 0, accessibility: "aku", synchronizable: false, valueMatched: true)
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

private func hostedController(_ authority: HostedLockAuthority, scenarios: Set<LifecycleScenario>,
                              productObserver: HostedProductObserver = FakeHostedProductObserver()) -> HostedLifecycleScenarioController {
    HostedLifecycleScenarioController(
        backend: RecordingBackend(), authority: authority,
        configuration: .init(namespace: .init(attempt: "attempt", seed: UUID()), supportedScenarios: scenarios),
        productObserver: productObserver)
}

private final class FakeHostedProductObserver: HostedProductObserver {
    private let protectedReadDelta: Int?
    private let aggregateDelta: Int
    init(protectedReadDelta: Int? = 0, aggregateDelta: Int = 0) {
        self.protectedReadDelta = protectedReadDelta
        self.aggregateDelta = aggregateDelta
    }
    func observe(step: LifecycleStep, transition: LockTransition) -> HostedProductObservation? {
        let closed = step == .lockBackground || step == .restartLocked || step == .sleepWake
        return .init(protectedReadDelta: protectedReadDelta, publishDelta: 0, aggregateDelta: aggregateDelta,
                     captureClosed: closed)
    }
}

private final class ContradictoryStateAuthority: HostedLockAuthority {
    var contradictorySteps: Set<LifecycleStep>
    init(contradictorySteps: Set<LifecycleStep>) { self.contradictorySteps = contradictorySteps }
    func preflightIsReady() -> Bool { true }
    func witness(challenge: LockChallenge, step: LifecycleStep) -> HostedLockWitness? {
        let expectedUnlocked = step == .unlockedCRUD || step == .deleteMissing || step == .cleanup
            || step == .unlockRevalidate || step == .restartUnlocked
        let unlocked = contradictorySteps.contains(step) ? !expectedUnlocked : expectedUnlocked
        return .init(challenge: challenge, unlocked: unlocked)
    }
}

private final class ReplayHostedAuthority: HostedLockAuthority {
    var replayChallenge: LockChallenge?
    private(set) var requestedChallenges: [LockChallenge] = []
    func preflightIsReady() -> Bool { true }
    func witness(challenge: LockChallenge, step: LifecycleStep) -> HostedLockWitness? {
        requestedChallenges.append(challenge)
        let challenge = replayChallenge ?? challenge
        return .init(challenge: challenge, unlocked: step == .unlockedCRUD || step == .deleteMissing
                     || step == .cleanup || step == .unlockRevalidate || step == .restartUnlocked)
    }
}

private final class FakeLifecycleController: LifecycleScenarioController {
    var supported = true
    var interrupt: LifecycleStep?
    var leak = false
    var missingProductDeltas = false
    var missingCaptureClosure = false
    var captureStillOpen = false
    var witness = true
    var zeroKeychainCalls = false
    var zeroDeleteMissingCalls = false
    var zeroCleanupCalls = false
    var steps: [LifecycleStep] = []
    func supports(_ scenario: LifecycleScenario) -> Bool { supported }
    func execute(_ step: LifecycleStep) -> LifecycleStepObservation {
        steps.append(step)
        let calls: Int
        switch step {
        case .unlockedCRUD: calls = zeroKeychainCalls ? 0 : 3
        case .deleteMissing: calls = zeroDeleteMissingCalls ? 0 : 2
        case .cleanup: calls = zeroCleanupCalls ? 0 : 1
        default: calls = 0
        }
        let keychain = LifecycleKeychainEvidence(
            rawStatus: step == .deleteMissing ? -25300 : 0, calls: calls,
            accessibility: "aku", synchronizable: false, valueMatched: true,
            itemMissing: true, cleanupComplete: true)
        let policy = LifecyclePolicyEvidence(
            authoritativeWitness: witness, protectedReadDelta: missingProductDeltas ? nil : (leak ? 1 : 0),
            publishDelta: missingProductDeltas ? nil : 0, aggregateDelta: missingProductDeltas ? nil : 0,
            generationFenced: true, captureClosed: missingCaptureClosure ? nil : !captureStillOpen)
        return LifecycleStepObservation(status: step == interrupt ? .blocked : .pass, keychain: keychain, policy: policy)
    }
}

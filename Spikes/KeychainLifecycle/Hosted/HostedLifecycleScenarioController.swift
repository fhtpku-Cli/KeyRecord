import Foundation
import LifecyclePreflight

public struct HostedLockWitness: Sendable {
    public let challenge: LockChallenge
    public let unlocked: Bool
    public init(challenge: LockChallenge, unlocked: Bool) {
        self.challenge = challenge; self.unlocked = unlocked
    }
}

public protocol HostedLockAuthority {
    func preflightIsReady() -> Bool
    func witness(challenge: LockChallenge, step: LifecycleStep) -> HostedLockWitness?
}

public final class HostedLifecycleScenarioController: LifecycleScenarioController {
    private let backend: any CandidateBackend
    private let namespace: ProbeNamespace
    private let authority: any HostedLockAuthority
    private let supportedScenarios: Set<LifecycleScenario>
    private var qualification = SessionLockQualification(supported: true)

    public init(backend: any CandidateBackend, namespace: ProbeNamespace,
                authority: any HostedLockAuthority, supportedScenarios: Set<LifecycleScenario>) {
        self.backend = backend
        self.namespace = namespace
        self.authority = authority
        self.supportedScenarios = supportedScenarios
    }

    public func supports(_ scenario: LifecycleScenario) -> Bool { supportedScenarios.contains(scenario) }

    public func execute(_ step: LifecycleStep) -> LifecycleStepObservation {
        switch step {
        case .unlockedCRUD: return crud()
        case .deleteMissing: return deleteMissing()
        case .cleanup: return cleanup()
        case .lockBackground, .unlockRevalidate, .restartLocked, .restartUnlocked, .logoutLogin, .sleepWake, .crossDeviceRestore:
            return transition(step)
        }
    }

    private func crud() -> LifecycleStepObservation {
        guard authorized(unlocked: true) else { return blocked(step: .unlockedCRUD) }
        let observations: [CandidateObservation]
        do { observations = try [.add, .read, .attributes].map { try backend.perform($0, namespace: namespace) } }
        catch { return blocked(step: .unlockedCRUD) }
        return .init(status: .pass, authoritativeWitness: true, protectedReadDelta: 0, publishDelta: 0,
                     aggregateDelta: 0, rawKeychainStatus: observations.last?.status, keychainCalls: observations.count,
                     accessibility: observations.compactMap(\.accessibility).last,
                     synchronizable: observations.compactMap(\.synchronizable).last,
                     valueMatched: observations.contains { $0.valueMatched == true }, generationFenced: true)
    }

    private func deleteMissing() -> LifecycleStepObservation {
        guard authority.preflightIsReady() else { return blocked(step: .deleteMissing) }
        let observations: [CandidateObservation]
        do { observations = try [.delete, .read].map { try backend.perform($0, namespace: namespace) } }
        catch { return blocked(step: .deleteMissing) }
        guard observations.first?.status == 0 || observations.first?.status == -25300,
              observations.last?.status == -25300 else { return failed(step: .deleteMissing) }
        return .init(status: .pass, authoritativeWitness: false, protectedReadDelta: 0, publishDelta: 0,
                     aggregateDelta: 0, rawKeychainStatus: -25300, keychainCalls: observations.count,
                     itemMissing: true, generationFenced: true)
    }

    private func cleanup() -> LifecycleStepObservation {
        guard authorized(unlocked: true) else { return blocked(step: .cleanup) }
        let observation: CandidateObservation
        do { observation = try backend.perform(.delete, namespace: namespace) }
        catch { return blocked(step: .cleanup) }
        guard observation.status == 0 || observation.status == -25300 else { return failed(step: .cleanup) }
        return .init(status: .pass, authoritativeWitness: false, protectedReadDelta: 0, publishDelta: 0,
                     aggregateDelta: 0, rawKeychainStatus: observation.status, keychainCalls: 1, cleanupComplete: true)
    }

    private func transition(_ step: LifecycleStep) -> LifecycleStepObservation {
        let expectedUnlocked = step != .lockBackground && step != .restartLocked
        guard let witness = authority.witness(challenge: qualification.challenge, step: step),
              witness.challenge == qualification.challenge, witness.unlocked == expectedUnlocked else {
            return blocked(step: step)
        }
        qualification.accept(.init(challenge: witness.challenge, unlocked: witness.unlocked))
        let closed = step == .lockBackground || step == .sleepWake
        return .init(status: .pass, authoritativeWitness: true, protectedReadDelta: 0, publishDelta: 0,
                     aggregateDelta: 0, rawKeychainStatus: 0, keychainCalls: 0,
                     generationFenced: true, captureClosed: closed)
    }

    private func authorized(unlocked: Bool) -> Bool {
        guard authority.preflightIsReady(),
              let witness = authority.witness(challenge: qualification.challenge, step: .unlockedCRUD),
              witness.challenge == qualification.challenge, witness.unlocked == unlocked else { return false }
        qualification.accept(.init(challenge: witness.challenge, unlocked: unlocked))
        return qualification.state == (unlocked ? .unlocked : .locked)
    }

    private func blocked(step: LifecycleStep) -> LifecycleStepObservation {
        .init(status: .blocked, authoritativeWitness: false, protectedReadDelta: 0, publishDelta: 0,
              aggregateDelta: 0, rawKeychainStatus: nil, keychainCalls: 0, generationFenced: true,
              captureClosed: step == .lockBackground || step == .sleepWake)
    }

    private func failed(step: LifecycleStep) -> LifecycleStepObservation {
        .init(status: .fail, authoritativeWitness: false, protectedReadDelta: 0, publishDelta: 0,
              aggregateDelta: 0, rawKeychainStatus: nil, keychainCalls: 0, generationFenced: true,
              captureClosed: step == .lockBackground || step == .sleepWake)
    }
}

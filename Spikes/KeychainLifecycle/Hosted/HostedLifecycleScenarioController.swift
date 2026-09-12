import Foundation
import LifecyclePreflight

public struct HostedLockWitness: Sendable {
    public let challenge: LockChallenge
    public let unlocked: Bool
    public init(challenge: LockChallenge, unlocked: Bool) {
        self.challenge = challenge; self.unlocked = unlocked
    }
}

public struct HostedLifecycleConfiguration: Sendable {
    public let namespace: ProbeNamespace
    public let supportedScenarios: Set<LifecycleScenario>
    public init(namespace: ProbeNamespace, supportedScenarios: Set<LifecycleScenario>) {
        self.namespace = namespace; self.supportedScenarios = supportedScenarios
    }
}

public protocol HostedLockAuthority {
    func preflightIsReady() -> Bool
    func witness(challenge: LockChallenge, step: LifecycleStep) -> HostedLockWitness?
}

public final class HostedLifecycleScenarioController: LifecycleScenarioController {
    private let backend: any CandidateBackend
    private let configuration: HostedLifecycleConfiguration
    private let authority: any HostedLockAuthority
    private var qualification = SessionLockQualification(supported: true)

    public init(backend: any CandidateBackend, authority: any HostedLockAuthority, configuration: HostedLifecycleConfiguration) {
        self.backend = backend; self.authority = authority; self.configuration = configuration
    }

    public func supports(_ scenario: LifecycleScenario) -> Bool { configuration.supportedScenarios.contains(scenario) }

    public func execute(_ step: LifecycleStep) -> LifecycleStepObservation {
        switch step {
        case .unlockedCRUD: crud()
        case .deleteMissing: deleteMissing()
        case .cleanup: cleanup()
        case .lockBackground, .unlockRevalidate, .restartLocked, .restartUnlocked, .logoutLogin, .sleepWake, .crossDeviceRestore:
            transition(step)
        }
    }

    private func crud() -> LifecycleStepObservation {
        guard authorized() else { return blocked(step: .unlockedCRUD) }
        let observations: [CandidateObservation]
        do { observations = try [.add, .read, .attributes].map { try backend.perform($0, namespace: configuration.namespace) } }
        catch { return blocked(step: .unlockedCRUD) }
        let keychain = LifecycleKeychainEvidence(rawStatus: observations.last?.status, calls: observations.count,
                                                 accessibility: observations.compactMap(\.accessibility).last,
                                                 synchronizable: observations.compactMap(\.synchronizable).last,
                                                 valueMatched: observations.contains { $0.valueMatched == true },
                                                 itemMissing: nil, cleanupComplete: nil)
        return observation(.pass, keychain: keychain, policy: policy(witness: true, fenced: true))
    }

    private func deleteMissing() -> LifecycleStepObservation {
        guard authority.preflightIsReady() else { return blocked(step: .deleteMissing) }
        let observations: [CandidateObservation]
        do { observations = try [.delete, .read].map { try backend.perform($0, namespace: configuration.namespace) } }
        catch { return blocked(step: .deleteMissing) }
        guard observations.first?.status == 0 || observations.first?.status == -25300,
              observations.last?.status == -25300 else { return failed(step: .deleteMissing) }
        let keychain = LifecycleKeychainEvidence(rawStatus: -25300, calls: observations.count, accessibility: nil,
                                                 synchronizable: nil, valueMatched: nil, itemMissing: true, cleanupComplete: nil)
        return observation(.pass, keychain: keychain, policy: policy(witness: false, fenced: true))
    }

    private func cleanup() -> LifecycleStepObservation {
        guard authorized() else { return blocked(step: .cleanup) }
        let result: CandidateObservation
        do { result = try backend.perform(.delete, namespace: configuration.namespace) }
        catch { return blocked(step: .cleanup) }
        guard result.status == 0 || result.status == -25300 else { return failed(step: .cleanup) }
        let keychain = LifecycleKeychainEvidence(rawStatus: result.status, calls: 1, accessibility: nil,
                                                 synchronizable: nil, valueMatched: nil, itemMissing: nil, cleanupComplete: true)
        return observation(.pass, keychain: keychain, policy: policy(witness: false, fenced: true))
    }

    private func transition(_ step: LifecycleStep) -> LifecycleStepObservation {
        let unlocked = step != .lockBackground && step != .restartLocked
        guard let witness = authority.witness(challenge: qualification.challenge, step: step) else {
            return blocked(step: step, active: qualification.challenge.generation)
        }
        let activeBefore = qualification.challenge.generation
        let result = qualification.advance(.init(challenge: witness.challenge, unlocked: unlocked))
        switch result {
        case .failure(let rejection):
            return blocked(step: step, rejection: rejection.rawValue,
                           witness: witness.challenge.generation, active: activeBefore)
        case .success(let transition):
            let closed = step == .lockBackground || step == .restartLocked || step == .sleepWake
            let policy = LifecyclePolicyEvidence(
                authoritativeWitness: true, protectedReadDelta: 0, publishDelta: 0, aggregateDelta: 0,
                generationFenced: transition.previous.generation != transition.current.generation,
                captureClosed: closed, witnessGeneration: witness.challenge.generation,
                activeGeneration: transition.current.generation, priorGeneration: transition.previous.generation)
            return observation(.pass, keychain: Self.zeroKeychain(rawStatus: 0), policy: policy)
        }
    }

    private func authorized() -> Bool {
        guard authority.preflightIsReady(),
              let witness = authority.witness(challenge: qualification.challenge, step: .unlockedCRUD),
              witness.challenge == qualification.challenge, witness.unlocked else { return false }
        qualification.accept(.init(challenge: witness.challenge, unlocked: true))
        return qualification.state == .unlocked
    }

    private func observation(_ status: LifecycleStatus, keychain: LifecycleKeychainEvidence, policy: LifecyclePolicyEvidence) -> LifecycleStepObservation {
        .init(status: status, keychain: keychain, policy: policy)
    }
    private static func zeroKeychain(rawStatus: Int32?) -> LifecycleKeychainEvidence {
        .init(rawStatus: rawStatus, calls: 0, accessibility: nil, synchronizable: nil, valueMatched: nil, itemMissing: nil, cleanupComplete: nil)
    }
    private func policy(witness: Bool, fenced: Bool, closed: Bool? = nil) -> LifecyclePolicyEvidence {
        .init(authoritativeWitness: witness, protectedReadDelta: 0, publishDelta: 0, aggregateDelta: 0,
              generationFenced: fenced, captureClosed: closed)
    }
    private func blocked(step: LifecycleStep, rejection: String? = nil,
                         witness: UUID? = nil, active: UUID? = nil) -> LifecycleStepObservation {
        observation(.blocked, keychain: Self.zeroKeychain(rawStatus: nil),
                    policy: .init(authoritativeWitness: false, protectedReadDelta: 0, publishDelta: 0,
                                  aggregateDelta: 0, generationFenced: false,
                                  captureClosed: step == .lockBackground || step == .restartLocked || step == .sleepWake,
                                  witnessGeneration: witness, activeGeneration: active,
                                  priorGeneration: nil, witnessRejection: rejection))
    }
    private func failed(step: LifecycleStep) -> LifecycleStepObservation {
        observation(.fail, keychain: Self.zeroKeychain(rawStatus: nil),
                    policy: policy(witness: false, fenced: true, closed: step == .lockBackground || step == .sleepWake))
    }
}

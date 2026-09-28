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

public struct HostedProductObservation: Sendable {
    public let protectedReadDelta: Int
    public let publishDelta: Int
    public let aggregateDelta: Int
    public let captureClosed: Bool?

    public init(protectedReadDelta: Int, publishDelta: Int, aggregateDelta: Int, captureClosed: Bool?) {
        self.protectedReadDelta = protectedReadDelta
        self.publishDelta = publishDelta
        self.aggregateDelta = aggregateDelta
        self.captureClosed = captureClosed
    }
}

public protocol HostedProductObserver {
    func observe(step: LifecycleStep, transition: LockTransition) -> HostedProductObservation?
}

public final class HostedLifecycleScenarioController: LifecycleScenarioController {
    private let backend: any CandidateBackend
    private let configuration: HostedLifecycleConfiguration
    private let authority: any HostedLockAuthority
    private let productObserver: (any HostedProductObserver)?
    private var qualification = SessionLockQualification(supported: true)

    public init(backend: any CandidateBackend, authority: any HostedLockAuthority,
                configuration: HostedLifecycleConfiguration, productObserver: (any HostedProductObserver)? = nil) {
        self.backend = backend; self.authority = authority; self.configuration = configuration
        self.productObserver = productObserver
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
        guard authorized(step: .unlockedCRUD) else { return blocked(step: .unlockedCRUD) }
        let callsBefore = backend.calls
        var observations: [CandidateObservation] = []
        for operation in [CandidateOperation.add, .read, .attributes] {
            let next: CandidateObservation
            do { next = try backend.perform(operation, namespace: configuration.namespace) }
            catch { return blocked(step: .unlockedCRUD, keychainCalls: backend.calls - callsBefore) }
            observations.append(next)
            if next.status != 0 {
                let keychain = LifecycleKeychainEvidence(rawStatus: next.status, calls: backend.calls - callsBefore,
                                                         accessibility: nil, synchronizable: nil,
                                                         valueMatched: nil, itemMissing: nil, cleanupComplete: nil)
                return observation(.fail, keychain: keychain, policy: policy(witness: true, fenced: nil))
            }
        }
        let keychain = LifecycleKeychainEvidence(rawStatus: observations[2].status, calls: backend.calls - callsBefore,
                                                 accessibility: observations[2].accessibility,
                                                 synchronizable: observations[2].synchronizable,
                                                 valueMatched: observations[1].valueMatched,
                                                 itemMissing: nil, cleanupComplete: nil)
        return observation(.pass, keychain: keychain, policy: policy(witness: true, fenced: nil))
    }

    private func deleteMissing() -> LifecycleStepObservation {
        guard authorized(step: .deleteMissing) else { return blocked(step: .deleteMissing) }
        let callsBefore = backend.calls
        let observations: [CandidateObservation]
        do { observations = try [.delete, .read].map { try backend.perform($0, namespace: configuration.namespace) } }
        catch { return blocked(step: .deleteMissing, keychainCalls: backend.calls - callsBefore) }
        guard observations.first?.status == 0 || observations.first?.status == -25300,
              observations.last?.status == -25300 else {
            return failed(step: .deleteMissing, keychainCalls: backend.calls - callsBefore)
        }
        let keychain = LifecycleKeychainEvidence(rawStatus: -25300, calls: backend.calls - callsBefore, accessibility: nil,
                                                 synchronizable: nil, valueMatched: nil, itemMissing: true, cleanupComplete: nil)
        return observation(.pass, keychain: keychain, policy: policy(witness: false, fenced: nil))
    }

    private func cleanup() -> LifecycleStepObservation {
        guard authorized(step: .cleanup) else { return blocked(step: .cleanup) }
        let callsBefore = backend.calls
        let result: CandidateObservation
        do { result = try backend.perform(.delete, namespace: configuration.namespace) }
        catch { return blocked(step: .cleanup, keychainCalls: backend.calls - callsBefore) }
        guard result.status == 0 || result.status == -25300 else {
            return failed(step: .cleanup, keychainCalls: backend.calls - callsBefore)
        }
        let keychain = LifecycleKeychainEvidence(rawStatus: result.status, calls: backend.calls - callsBefore, accessibility: nil,
                                                 synchronizable: nil, valueMatched: nil, itemMissing: nil, cleanupComplete: true)
        return observation(.pass, keychain: keychain, policy: policy(witness: false, fenced: nil))
    }

    private func transition(_ step: LifecycleStep) -> LifecycleStepObservation {
        guard let productObserver else {
            return blocked(step: step, rejection: "productObservationMissing", active: qualification.challenge.generation)
        }
        guard authority.preflightIsReady() else {
            return blocked(step: step, rejection: "lockAuthorityUnavailable", active: qualification.challenge.generation)
        }
        let unlocked = step != .lockBackground && step != .restartLocked
        guard let witness = authority.witness(challenge: qualification.challenge, step: step) else {
            return blocked(step: step, active: qualification.challenge.generation)
        }
        let activeBefore = qualification.challenge.generation
        let result = qualification.advance(.init(challenge: witness.challenge, unlocked: witness.unlocked),
                                           expectedUnlocked: unlocked)
        switch result {
        case .failure(let rejection):
            return blocked(step: step, rejection: rejection.rawValue,
                           witness: witness.challenge.generation, active: activeBefore)
        case .success(let transition):
            guard let observed = productObserver.observe(step: step, transition: transition) else {
                return blocked(step: step, rejection: "productObservationMissing",
                               witness: witness.challenge.generation, active: transition.current.generation)
            }
            let policy = LifecyclePolicyEvidence(
                authoritativeWitness: true,
                protectedReadDelta: observed.protectedReadDelta,
                publishDelta: observed.publishDelta,
                aggregateDelta: observed.aggregateDelta,
                generationFenced: transition.previous.generation != transition.current.generation,
                captureClosed: observed.captureClosed, witnessGeneration: witness.challenge.generation,
                activeGeneration: transition.current.generation, priorGeneration: transition.previous.generation)
            return observation(.pass, keychain: Self.zeroKeychain(rawStatus: nil), policy: policy)
        }
    }

    private func authorized(step: LifecycleStep) -> Bool {
        guard authority.preflightIsReady(),
              let witness = authority.witness(challenge: qualification.challenge, step: step),
              witness.challenge == qualification.challenge, witness.unlocked else { return false }
        qualification.accept(.init(challenge: witness.challenge, unlocked: true))
        return qualification.state == .unlocked
    }

    private func observation(_ status: LifecycleStatus, keychain: LifecycleKeychainEvidence, policy: LifecyclePolicyEvidence) -> LifecycleStepObservation {
        .init(status: status, keychain: keychain, policy: policy)
    }
    private static func zeroKeychain(rawStatus: Int32?, calls: Int = 0) -> LifecycleKeychainEvidence {
        .init(rawStatus: rawStatus, calls: calls, accessibility: nil, synchronizable: nil, valueMatched: nil, itemMissing: nil, cleanupComplete: nil)
    }
    private func policy(witness: Bool, fenced: Bool?) -> LifecyclePolicyEvidence {
        .init(authoritativeWitness: witness, protectedReadDelta: nil, publishDelta: nil, aggregateDelta: nil,
              generationFenced: fenced, captureClosed: nil)
    }
    private func blocked(step: LifecycleStep, rejection: String? = nil,
                         witness: UUID? = nil, active: UUID? = nil, keychainCalls: Int = 0) -> LifecycleStepObservation {
        observation(.blocked, keychain: Self.zeroKeychain(rawStatus: nil, calls: keychainCalls),
                    policy: .init(authoritativeWitness: false, protectedReadDelta: nil, publishDelta: nil,
                                  aggregateDelta: nil, generationFenced: false,
                                  captureClosed: nil,
                                  witnessGeneration: witness, activeGeneration: active,
                                  priorGeneration: nil, witnessRejection: rejection))
    }
    private func failed(step: LifecycleStep, keychainCalls: Int = 0) -> LifecycleStepObservation {
        observation(.fail, keychain: Self.zeroKeychain(rawStatus: nil, calls: keychainCalls),
                    policy: policy(witness: false, fenced: nil))
    }
}

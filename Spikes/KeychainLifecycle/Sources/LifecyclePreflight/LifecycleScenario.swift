import Foundation
import CryptoKit

public enum LifecycleStatus: String, Codable, Sendable { case pass = "PASS", fail = "FAIL", blocked = "BLOCKED" }
public enum LifecycleStep: String, Codable, Sendable {
    case unlockedCRUD, lockBackground, unlockRevalidate, restartLocked, restartUnlocked
    case logoutLogin, sleepWake, deleteMissing, cleanup, crossDeviceRestore
    var needsWitness: Bool {
        switch self {
        case .unlockedCRUD, .unlockRevalidate, .restartLocked, .restartUnlocked, .logoutLogin, .sleepWake: true
        case .lockBackground, .deleteMissing, .cleanup, .crossDeviceRestore: false
        }
    }
}
public enum LifecycleScenario: String, CaseIterable, Codable, Sendable {
    case unlockedCRUD, lockBackground, unlockRevalidation, restartLocked, restartUnlocked
    case logoutLogin, sleepWake, deleteMissing, crossDeviceRestore
    public var steps: [LifecycleStep] {
        switch self {
        case .unlockedCRUD: [.unlockedCRUD]
        case .lockBackground: [.unlockedCRUD, .lockBackground]
        case .unlockRevalidation: [.unlockedCRUD, .lockBackground, .unlockRevalidate]
        case .restartLocked: [.unlockedCRUD, .lockBackground, .restartLocked]
        case .restartUnlocked: [.unlockedCRUD, .restartUnlocked]
        case .logoutLogin: [.unlockedCRUD, .logoutLogin]
        case .sleepWake: [.unlockedCRUD, .sleepWake]
        case .deleteMissing: [.unlockedCRUD, .deleteMissing]
        case .crossDeviceRestore: [.crossDeviceRestore]
        }
    }
}

public struct LifecycleKeychainEvidence: Codable, Sendable {
    public let rawStatus: Int32?
    public let calls: Int
    public let accessibility: String?
    public let synchronizable: Bool?
    public let valueMatched: Bool?
    public let itemMissing: Bool?
    public let cleanupComplete: Bool?
}

public struct LifecyclePolicyEvidence: Codable, Sendable {
    public let authoritativeWitness: Bool
    public let protectedReadDelta: Int
    public let publishDelta: Int
    public let aggregateDelta: Int
    public let generationFenced: Bool?
    public let captureClosed: Bool?
}

public struct LifecycleStepObservation: Codable, Sendable {
    public let status: LifecycleStatus
    public let keychain: LifecycleKeychainEvidence
    public let policy: LifecyclePolicyEvidence
}

// Only an authorized hosted implementation may dispatch effects, using SignedCandidateBackend
// and a fresh SignedEffectGate check per operation. This pure runner owns no Security API.
public protocol LifecycleScenarioController {
    func supports(_ scenario: LifecycleScenario) -> Bool
    func execute(_ step: LifecycleStep) -> LifecycleStepObservation
}

public struct LifecycleScenarioReport: Codable, Sendable {
    public let scenario: LifecycleScenario
    public let status: LifecycleStatus
    public let reason: String
    public let observations: [LifecycleStepObservation]
    public let controllerCalls: Int
    public let keychainCalls: Int
}

public struct LifecycleScenarioArtifact: Codable, Sendable {
    public let report: LifecycleScenarioReport
    public let artifactSHA256: String
}

public enum LifecycleScenarioMachine {
    public static func artifact(for scenario: LifecycleScenario, controller: (any LifecycleScenarioController)?) throws -> LifecycleScenarioArtifact {
        let report = run(scenario, controller: controller)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let hash = SHA256.hash(data: try encoder.encode(report)).map { String(format: "%02x", $0) }.joined()
        return .init(report: report, artifactSHA256: hash)
    }

    public static func run(_ scenario: LifecycleScenario, controller: (any LifecycleScenarioController)?) -> LifecycleScenarioReport {
        guard let controller else {
            return .init(scenario: scenario, status: .blocked, reason: "controllerMissing",
                         observations: [], controllerCalls: 0, keychainCalls: 0)
        }
        guard controller.supports(scenario) else {
            return .init(scenario: scenario, status: .blocked, reason: "capabilityMissing",
                         observations: [], controllerCalls: 0, keychainCalls: 0)
        }
        var observations: [LifecycleStepObservation] = []
        var status = LifecycleStatus.pass
        var reason = "observed"
        for step in scenario.steps {
            let observation = controller.execute(step)
            observations.append(observation)
            switch observation.status {
            case .blocked: status = .blocked; reason = "observationUnavailable"
            case .fail: status = .fail; reason = "assertionFailed"
            case .pass:
                if !valid(step, observation) {
                    status = .fail; reason = "stepContractFailed"
                } else if observation.policy.protectedReadDelta != 0 || observation.policy.publishDelta != 0 || observation.policy.aggregateDelta != 0 {
                    status = .fail; reason = "protectedPolicyDelta"
                } else if step.needsWitness && !observation.policy.authoritativeWitness {
                    status = .blocked; reason = "noAuthoritativeWitness"
                }
            }
            if status != .pass { break }
        }
        let cleanup = controller.execute(.cleanup)
        observations.append(cleanup)
        switch cleanup.status {
        case .pass:
            if cleanup.keychain.cleanupComplete != true { status = .blocked; reason = "cleanupPending" }
        case .fail: status = .fail; reason = "cleanupFailed"
        case .blocked:
            if status != .fail { status = .blocked; reason = "cleanupPending" }
        }
        return .init(scenario: scenario, status: status, reason: reason, observations: observations,
                     controllerCalls: observations.count, keychainCalls: observations.reduce(0) { $0 + $1.keychain.calls })
    }

    private static func valid(_ step: LifecycleStep, _ value: LifecycleStepObservation) -> Bool {
        guard value.keychain.calls >= 0 else { return false }
        switch step {
        case .unlockedCRUD:
            return value.keychain.rawStatus == 0 && value.keychain.accessibility == "aku" &&
                value.keychain.synchronizable == false && value.keychain.valueMatched == true
        case .deleteMissing: return value.keychain.itemMissing == true && value.keychain.rawStatus == -25300
        case .lockBackground, .restartLocked, .sleepWake:
            return value.policy.generationFenced == true && value.policy.captureClosed == true
        case .restartUnlocked, .unlockRevalidate, .logoutLogin:
            return value.policy.generationFenced == true
        case .cleanup: return value.keychain.cleanupComplete == true
        case .crossDeviceRestore: return true
        }
    }
}

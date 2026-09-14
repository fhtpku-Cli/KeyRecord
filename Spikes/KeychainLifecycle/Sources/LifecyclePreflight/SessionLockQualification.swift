import Foundation

public enum LockSignal: String, CaseIterable, Codable, Sendable {
    case sessionResigned, sessionBecameActive, willSleep, didWake
    case screenLocked, screenUnlocked, processRestart
}

public struct LockChallenge: Equatable, Sendable {
    public let process: UUID
    public let generation: UUID
    public init(process: UUID, generation: UUID) {
        self.process = process; self.generation = generation
    }
}

// Trusted in-process controller port, deliberately not Decodable: notification payloads
// and receipt JSON cannot manufacture authority. Live endorsement belongs to host preflight.
public struct UnlockedWitness: Sendable {
    public let challenge: LockChallenge
    public let unlocked: Bool
    public init(challenge: LockChallenge, unlocked: Bool) {
        self.challenge = challenge; self.unlocked = unlocked
    }
}

public enum LockWitnessRejection: String, Codable, Sendable, Error {
    case unsupported, staleGeneration, witnessStateMismatch
}

public struct LockTransition: Equatable, Sendable {
    public let previous: LockChallenge
    public let current: LockChallenge
    public let unlocked: Bool
}

public struct SessionLockQualification: Sendable {
    public enum State: String, Codable, Sendable { case unknown, locked, unlocked }
    public private(set) var state = State.unknown
    public private(set) var challenge = LockChallenge(process: UUID(), generation: UUID())
    private let supported: Bool

    public init(supported: Bool = false) { self.supported = supported }

    public mutating func observe(_ signal: LockSignal) {
        let process: UUID
        switch signal {
        case .processRestart: process = UUID()
        case .sessionResigned, .sessionBecameActive, .willSleep, .didWake,
             .screenLocked, .screenUnlocked: process = challenge.process
        }
        challenge = LockChallenge(process: process, generation: UUID())
        guard supported else { state = .unknown; return }
        switch signal {
        case .sessionResigned, .willSleep, .screenLocked: state = .locked
        case .sessionBecameActive, .didWake, .screenUnlocked, .processRestart: state = .unknown
        }
    }

    public mutating func accept(_ witness: UnlockedWitness) {
        guard supported, witness.challenge == challenge else { return }
        state = witness.unlocked ? .unlocked : .locked
    }

    @discardableResult
    public mutating func advance(_ witness: UnlockedWitness, expectedUnlocked: Bool) -> Result<LockTransition, LockWitnessRejection> {
        guard supported else { return .failure(.unsupported) }
        let previous = challenge
        guard witness.challenge == previous else { return .failure(.staleGeneration) }
        guard witness.unlocked == expectedUnlocked else { return .failure(.witnessStateMismatch) }
        state = witness.unlocked ? .unlocked : .locked
        challenge = LockChallenge(process: previous.process, generation: UUID())
        return .success(.init(previous: previous, current: challenge, unlocked: witness.unlocked))
    }

    public func canPublish(_ issued: LockChallenge) -> Bool {
        state == .unlocked && issued == challenge
    }
}

import Foundation

public enum CandidateOperation: CaseIterable, Equatable, Sendable { case add, read, attributes, delete }

public struct CandidateObservation: Codable, Sendable {
    public let status: Int32
    public let accessibility: String?
    public let synchronizable: Bool?
    public let valueMatched: Bool?
    public init(status: Int32, accessibility: String?, synchronizable: Bool?, valueMatched: Bool?) {
        self.status = status; self.accessibility = accessibility
        self.synchronizable = synchronizable; self.valueMatched = valueMatched
    }
}

public protocol CandidateBackend {
    func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation
}

public struct CandidateReport: Codable, Sendable {
    public let observations: [CandidateObservation]
    public let keychainCalls: Int
    public let controllerCalls: Int
}

// Ports the historical SP6A add/read/attributes/exact-delete sequence, not its evidence contract.
// AfterFirstUnlockThisDeviceOnly remains comparison-only; it is never selected or used as fallback.
public enum KeychainLifecycleProbe {
    public static func exercise(backend: some CandidateBackend, namespace: ProbeNamespace,
                                preflight: () -> PreflightVerdict) throws -> CandidateReport {
        var observations: [CandidateObservation] = []
        for operation in CandidateOperation.allCases {
            switch preflight() {
            case .blocked(let reason): throw reason
            case .ready: observations.append(try backend.perform(operation, namespace: namespace))
            }
        }
        return CandidateReport(observations: observations, keychainCalls: observations.count, controllerCalls: 0)
    }
}

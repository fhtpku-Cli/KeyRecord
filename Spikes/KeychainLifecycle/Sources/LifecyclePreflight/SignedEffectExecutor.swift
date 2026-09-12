import Foundation

public enum CandidateQueryValue: Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case data(Data)

    public var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .bool(let value): value
        case .data(let value): value
        }
    }
}

public struct CandidateEffectRequest: Sendable {
    public let operation: CandidateOperation
    public let query: [String: CandidateQueryValue]
    public let expectedValue: Data

    init(intent: SignedEffectIntent, value: Data) {
        operation = intent.operation
        expectedValue = value
        // Security wire keys stay pure data here; unsigned tests compare every key/value against SDK constants.
        var query: [String: CandidateQueryValue] = [
            "class": .string("genp"), "svce": .string(intent.namespace.service), "acct": .string("when-unlocked"),
            "pdmn": .string("aku"), "sync": .bool(false), "nleg": .bool(true), "u_AuthUI": .string("u_AuthUIF"),
        ]
        switch operation {
        case .add: query["v_Data"] = .data(value)
        case .read:
            query["r_Data"] = .bool(true)
            query["m_Limit"] = .string("m_LimitOne")
        case .attributes:
            query["r_Attributes"] = .bool(true)
            query["m_Limit"] = .string("m_LimitOne")
        case .delete: break
        }
        self.query = query
    }

    public var foundationQuery: [String: Any] { query.mapValues(\.foundationValue) }
}

public protocol CandidateEffectStore {
    func perform(_ request: CandidateEffectRequest) throws -> CandidateObservation
}

public final class SignedEffectExecutor: CandidateBackend {
    private let namespace: ProbeNamespace
    private let store: any CandidateEffectStore
    private let evidence: () -> SignedEffectEvidence
    private var value = Data()
    public private(set) var calls = 0
    public private(set) var denials = 0
    public private(set) var lastDenial: PreflightBlock?

    public init(namespace: ProbeNamespace, store: any CandidateEffectStore, evidence: @escaping () -> SignedEffectEvidence) {
        self.namespace = namespace; self.store = store; self.evidence = evidence
    }

    public func perform(_ operation: CandidateOperation, namespace: ProbeNamespace) throws -> CandidateObservation {
        let intent = SignedEffectIntent(operation: operation, namespace: namespace)
        switch SignedEffectGate.evaluate(intent, evidence: evidence(), expectedNamespace: self.namespace) {
        case .deny(let reason):
            denials += 1
            lastDenial = reason
            throw reason
        case .allow(let approved):
            switch approved.operation {
            case .add: value = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
            case .read, .attributes, .delete: break
            }
            let request = CandidateEffectRequest(intent: approved, value: value)
            calls += 1
            let observation = try store.perform(request)
            switch approved.operation {
            case .delete:
                value.resetBytes(in: value.startIndex..<value.endIndex)
                value.removeAll()
            case .add, .read, .attributes: break
            }
            return observation
        }
    }
}

import Foundation
import KeyRecordCore

public enum PhysicalModelError: Error, Equatable, Sendable {
    case invalidPosition, duplicatePosition
}

public struct PhysicalPosition: Equatable, Sendable {
    public let id: String
    public let x: Double
    public let y: Double
    public let coordinateFrame: String

    public init(id: String, centerX: Double, centerY: Double, coordinateFrame: String) throws {
        guard !id.isEmpty, !coordinateFrame.isEmpty, centerX.isFinite, centerY.isFinite else {
            throw PhysicalModelError.invalidPosition
        }
        self.id = id
        x = centerX
        y = centerY
        self.coordinateFrame = coordinateFrame
    }
}

public struct CanonicalGeometry: Equatable, Sendable {
    public let positions: [String: PhysicalPosition]

    public init(positions: [PhysicalPosition]) throws {
        guard Set(positions.map(\.id)).count == positions.count else { throw PhysicalModelError.duplicatePosition }
        self.positions = Dictionary(uniqueKeysWithValues: positions.map { ($0.id, $0) })
    }
}

public enum PhysicalToken: Hashable, Sendable {
    case position(String)
    case hidUsage(UInt16)
    case observedKey(KeyCode)
}

public struct CanonicalTransform: Equatable, Sendable {
    public struct Mapping: Equatable, Sendable {
        public let input: [PhysicalToken]
        public let output: [PhysicalToken]
        public init(input: [PhysicalToken], output: [PhysicalToken]) {
            self.input = input
            self.output = output
        }
    }
    public let mappings: [Mapping]
    public let completeInverseFor: Set<[PhysicalToken]>
    public init(mappings: [Mapping], completeInverseFor: Set<[PhysicalToken]>) {
        self.mappings = mappings
        self.completeInverseFor = completeInverseFor
    }
}

public enum TransformLink: Equatable, Sendable { case firmware, software, macOS }
public enum TransformStatus: Equatable, Sendable {
    case verified, absent, ambiguous, unsupported, multiDeviceUncertain, externallyChanged
}

public struct TransformEvidence: Equatable, Sendable {
    public let link: TransformLink
    public let status: TransformStatus
    public let reference: String
    public let mapping: CanonicalTransform?

    public init(link: TransformLink, status: TransformStatus, reference: String, mapping: CanonicalTransform?) {
        self.link = link
        self.status = status
        self.reference = reference
        self.mapping = mapping
    }
}

public enum PhysicalDeviceEvidence: Equatable, Sendable { case singleVerified, unknown, multiDeviceUncertain }

public struct PhysicalEvidence: Equatable, Sendable {
    public let geometry: CanonicalGeometry?
    public let chain: [TransformEvidence]
    public let device: PhysicalDeviceEvidence
    public let scope: RecommendationScope

    public init(geometry: CanonicalGeometry?, chain: [TransformEvidence], device: PhysicalDeviceEvidence,
                scope: RecommendationScope) {
        self.geometry = geometry
        self.chain = chain
        self.device = device
        self.scope = scope
    }
}

public enum PhysicalFallbackReason: Equatable, Sendable {
    case missingEvidence, deviceUncertain, scopeMismatch, missingGeometry, incompleteChain
    case unavailableTransform(TransformLink, TransformStatus), missingMapping, unknownModifiers
    case noAction, ambiguousAction, missingPosition, incomparableGeometry, invalidGeometry
    case incompleteInverseCoverage, invalidTransform, unsupportedGesture
}

public struct ResolvedPhysicalGesture: Equatable, Sendable {
    public let presses: [PhysicalPosition]
}

public struct PhysicalActionCost: Equatable, Sendable {
    public let pressCount: Int
    public let positionDiameter: Double
}

public enum PhysicalCostComparison: Equatable, Sendable {
    case logical(sourceKeys: Int, triggerKeys: Int, reason: PhysicalFallbackReason)
    case physical(source: PhysicalActionCost, trigger: PhysicalActionCost)
}

public enum PhysicalAnalysis {
    public static func compare(source: Chord, trigger: Chord, scope: RecommendationScope,
                               evidence: PhysicalEvidence?) -> PhysicalCostComparison {
        func fallback(_ reason: PhysicalFallbackReason) -> PhysicalCostComparison {
            .logical(sourceKeys: LogicalPreviews.keyCount(source), triggerKeys: LogicalPreviews.keyCount(trigger), reason: reason)
        }
        guard let evidence else { return fallback(.missingEvidence) }
        guard evidence.scope == scope else { return fallback(.scopeMismatch) }
        switch (resolve(source, evidence: evidence), resolve(trigger, evidence: evidence)) {
        case (.success(let a), .success(let b)):
            guard Set((a.presses + b.presses).map(\.coordinateFrame)).count == 1 else { return fallback(.incomparableGeometry) }
            guard let sourceCost = cost(a), let triggerCost = cost(b) else { return fallback(.invalidGeometry) }
            return .physical(source: sourceCost, trigger: triggerCost)
        case (.failure(let reason), _): return fallback(reason.reason)
        case (_, .failure(let reason)): return fallback(reason.reason)
        }
    }

    public struct ResolutionFailure: Error, Equatable, Sendable {
        public let reason: PhysicalFallbackReason
    }

    public static func resolve(_ chord: Chord, evidence: PhysicalEvidence) -> Result<ResolvedPhysicalGesture, ResolutionFailure> {
        func fail(_ reason: PhysicalFallbackReason) -> Result<ResolvedPhysicalGesture, ResolutionFailure> { .failure(ResolutionFailure(reason: reason)) }
        guard evidence.device == .singleVerified else { return fail(.deviceUncertain) }
        guard let geometry = evidence.geometry else { return fail(.missingGeometry) }
        guard evidence.chain.first?.link == .firmware, evidence.chain.last?.link == .macOS,
              evidence.chain.count >= 3,
              evidence.chain.dropFirst().dropLast().allSatisfy({ $0.link == .software }) else { return fail(.incompleteChain) }
        guard ChordRuleTable.v1.classify(chord).kind == .discrete else { return fail(.unsupportedGesture) }
        let m = chord.modifiers
        guard m.fn != .unknown, ![m.command, m.option, m.control, m.shift].contains(.activeSideUnknown) else { return fail(.unknownModifiers) }
        var observed: [PhysicalToken] = []
        for (side, left, right) in [(m.command, 55, 54), (m.option, 58, 61), (m.control, 59, 62), (m.shift, 56, 60)] {
            if side == .left || side == .both, let key = try? KeyCode(left) { observed.append(.observedKey(key)) }
            if side == .right || side == .both, let key = try? KeyCode(right) { observed.append(.observedKey(key)) }
        }
        if m.fn == .active, let key = try? KeyCode(63) { observed.append(.observedKey(key)) }
        observed.append(.observedKey(chord.keyCode))
        var current = observed
        for segment in evidence.chain.reversed() {
            guard segment.status == .verified else { return fail(.unavailableTransform(segment.link, segment.status)) }
            guard !segment.reference.isEmpty, let mapping = segment.mapping else { return fail(.missingMapping) }
            guard mapping.mappings.allSatisfy({ valid($0, link: segment.link) }) else { return fail(.invalidTransform) }
            guard mapping.completeInverseFor.contains(current) else { return fail(.incompleteInverseCoverage) }
            let alternatives = Set(mapping.mappings.filter { $0.output == current }.map(\.input))
            guard !alternatives.isEmpty else { return fail(.noAction) }
            guard alternatives.count == 1, let sole = alternatives.first else { return fail(.ambiguousAction) }
            current = sole
        }
        var positions: [PhysicalPosition] = []
        for token in current {
            guard case .position(let id) = token, let position = geometry.positions[id] else { return fail(.missingPosition) }
            positions.append(position)
        }
        guard !positions.isEmpty else { return fail(.noAction) }
        return .success(ResolvedPhysicalGesture(presses: positions))
    }

    private static func valid(_ mapping: CanonicalTransform.Mapping, link: TransformLink) -> Bool {
        guard !mapping.input.isEmpty, !mapping.output.isEmpty else { return false }
        func positions(_ tokens: [PhysicalToken]) -> Bool { tokens.allSatisfy { if case .position = $0 { return true }; return false } }
        func hid(_ tokens: [PhysicalToken]) -> Bool { tokens.allSatisfy { if case .hidUsage = $0 { return true }; return false } }
        func observed(_ tokens: [PhysicalToken]) -> Bool { tokens.allSatisfy { if case .observedKey = $0 { return true }; return false } }
        switch link {
        case .firmware: return positions(mapping.input) && hid(mapping.output)
        case .software: return hid(mapping.input) && hid(mapping.output)
        case .macOS: return hid(mapping.input) && observed(mapping.output)
        }
    }

    private static func cost(_ gesture: ResolvedPhysicalGesture) -> PhysicalActionCost? {
        var diameter = 0.0
        for i in gesture.presses.indices {
            for j in gesture.presses.indices where j > i {
                let a = gesture.presses[i], b = gesture.presses[j]
                diameter = max(diameter, hypot(a.x - b.x, a.y - b.y))
            }
        }
        guard diameter.isFinite else { return nil }
        return PhysicalActionCost(pressCount: gesture.presses.count, positionDiameter: diameter)
    }
}

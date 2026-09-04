import Foundation

public enum SP2PrivacyAction: String, Codable, Sendable { case terminalKeyDown, tapReset, systemSleep }
public enum SP2FrontmostInput: String, Codable, Sendable { case known, knownUnattributable, indeterminate }

public struct SP2PrivacyInput: Codable, Equatable, Sendable {
    public let scenario: String
    public let action: SP2PrivacyAction
    public let frontmost: SP2FrontmostInput
    public let bundleID: String?
    public let secureInput: SecureInputState
    public let excludedBundleIDs: [String]
    public let seedAllowedCount: Int
    public let beginTransient: Bool
}

public struct SP2PrivacyObservation: Codable, Equatable, Sendable {
    public let outcome: String
    public let beforeTotals: PrivacyTotals
    public let afterTotals: PrivacyTotals
    public let transitionDelta: PrivacyTotals
    public let unknownBucketCount: Int
    public let heldTransientBefore: Int
    public let heldTransientAfter: Int
    public let gateOpenAfter: Bool
    public let generationAfter: UInt64
}

public struct SP2PrivacyCase: Codable, Equatable, Sendable {
    public let input: SP2PrivacyInput
    public let observation: SP2PrivacyObservation
}

public struct SP2PrivacyArtifact: Codable, Equatable, Sendable {
    public let evidenceKind: EvidenceKind
    public let cases: [SP2PrivacyCase]
    public init(cases: [SP2PrivacyCase]) { evidenceKind = .fixture; self.cases = cases }
}

public struct SP2SidedModifierCase: Codable, Equatable, Sendable {
    public let family: ModifierFamily
    public let left: Bool?
    public let right: Bool?
    public let observed: ModifierSideState
}

public struct SP2FnOperation: Codable, Equatable, Sendable {
    public let transition: RecoveryTransition?
    public let active: Bool?
}

public struct SP2FnCase: Codable, Equatable, Sendable {
    public let operations: [SP2FnOperation]
    public let observed: FnConfidence
}

public struct SP2RecoveryCase: Codable, Equatable, Sendable {
    public let transition: RecoveryTransition
    public let unknownStates: [String: ModifierSideState]
    public let recoveredStates: [String: ModifierSideState]
    public let fnBeforeRecovery: FnConfidence
    public let fnAfterRecovery: FnConfidence
}

public struct SP2ModifierArtifact: Codable, Equatable, Sendable {
    public let evidenceKind: EvidenceKind
    public let sidedCases: [SP2SidedModifierCase]
    public let fnCases: [SP2FnCase]
    public let recoveryCases: [SP2RecoveryCase]
    public let deterministicRecovery: Bool
}

public struct SP2ModelExecution: Equatable, Sendable {
    public let privacy: SP2PrivacyArtifact
    public let modifiers: SP2ModifierArtifact
    public let assertions: [String: Bool]
}

public enum SP2ModelScenarios {
    public static func run() -> SP2ModelExecution {
        let privacy = SP2PrivacyArtifact(cases: privacyInputs.map(execute))
        let modifiers = modifierArtifact()
        let privacyByName = Dictionary(uniqueKeysWithValues: privacy.cases.map { ($0.input.scenario, $0.observation) })
        let indeterminate = privacyByName["indeterminate"]
        let excluded = privacyByName["excludedApp"]
        let reset = privacyByName["tapReset"]
        let sidedPass = modifiers.sidedCases.count == ModifierFamily.allCases.count * 5
            && modifiers.sidedCases.allSatisfy { recompute($0) == $0.observed }
        let recoveryPass = modifiers.recoveryCases.count == RecoveryTransition.allCases.count
            && modifiers.recoveryCases.allSatisfy(recoveryPasses)
        let fnPass = modifiers.fnCases.count == 9
            && modifiers.fnCases.allSatisfy { recompute($0) == $0.observed }
            && modifiers.deterministicRecovery
        let assertions = [
            "sp2.frontmostIndeterminate": indeterminate?.outcome == "closed" && indeterminate?.transitionDelta == .zero && indeterminate?.unknownBucketCount == 0,
            "sp2.excludedApp": excluded?.outcome == "closed" && excluded?.transitionDelta == .zero,
            "sp2.tapReset": reset?.outcome == "closed" && reset?.transitionDelta == .zero && reset?.beforeTotals == reset?.afterTotals && reset?.heldTransientAfter == 0,
            "sp2.sidedModifiers": sidedPass,
            "sp2.sidedRecovery": recoveryPass,
            "sp2.fnRecoveryModel": fnPass,
        ]
        return SP2ModelExecution(privacy: privacy, modifiers: modifiers, assertions: assertions)
    }

    public static func execute(_ input: SP2PrivacyInput) -> SP2PrivacyCase {
        var model = PrivacyTransitionModel()
        for _ in 0..<input.seedAllowedCount {
            _ = model.observeTerminalKeyDown(frontmost: .known(bundleID: "test.seed"), secureInput: .disabled, excludedBundleIDs: [])
        }
        if input.beginTransient { model.beginTransientObservation() }
        let before = model.totals
        let heldBefore = model.heldTransientCount
        let frontmost: FrontmostState = switch input.frontmost {
        case .known: .known(bundleID: input.bundleID ?? "")
        case .knownUnattributable: .knownUnattributable
        case .indeterminate: .indeterminate
        }
        let decision: PrivacyDecision
        let transitionDelta: PrivacyTotals
        switch input.action {
        case .terminalKeyDown:
            decision = model.observeTerminalKeyDown(frontmost: frontmost, secureInput: input.secureInput, excludedBundleIDs: Set(input.excludedBundleIDs))
            transitionDelta = PrivacyTotals(data: model.totals.data - before.data, meta: model.totals.meta - before.meta)
        case .tapReset:
            transitionDelta = model.tapReset()
            decision = model.observeTerminalKeyDown(frontmost: frontmost, secureInput: input.secureInput, excludedBundleIDs: Set(input.excludedBundleIDs))
        case .systemSleep:
            transitionDelta = model.systemWillSleep()
            decision = model.observeTerminalKeyDown(frontmost: frontmost, secureInput: input.secureInput, excludedBundleIDs: Set(input.excludedBundleIDs))
        }
        let outcome: String = switch decision {
        case .dropped: "closed"
        case .counted(bucket: .unknown): "UNKNOWN"
        case .counted(bucket: .bundle): "bundle"
        }
        return SP2PrivacyCase(input: input, observation: SP2PrivacyObservation(
            outcome: outcome, beforeTotals: before, afterTotals: model.totals, transitionDelta: transitionDelta,
            unknownBucketCount: model.bucketCounts[.unknown] ?? 0, heldTransientBefore: heldBefore,
            heldTransientAfter: model.heldTransientCount, gateOpenAfter: model.gateOpen, generationAfter: model.generation
        ))
    }

    public static func recompute(_ item: SP2SidedModifierCase) -> ModifierSideState {
        var model = ModifierReconstructionModel()
        if let left = item.left, let right = item.right { model.apply(family: item.family, left: left, right: right) }
        return model[item.family]
    }

    public static func recompute(_ item: SP2FnCase) -> FnConfidence {
        var model = ModifierReconstructionModel()
        for operation in item.operations {
            if let transition = operation.transition { model.invalidate(for: transition) }
            if let active = operation.active { model.applyFn(active: active) }
        }
        return model.fn
    }

    private static let privacyInputs: [SP2PrivacyInput] = [
        .init(scenario: "known", action: .terminalKeyDown, frontmost: .known, bundleID: "test.allowed", secureInput: .disabled, excludedBundleIDs: [], seedAllowedCount: 0, beginTransient: false),
        .init(scenario: "knownUnattributable", action: .terminalKeyDown, frontmost: .knownUnattributable, bundleID: nil, secureInput: .disabled, excludedBundleIDs: [], seedAllowedCount: 0, beginTransient: false),
        .init(scenario: "indeterminate", action: .terminalKeyDown, frontmost: .indeterminate, bundleID: nil, secureInput: .disabled, excludedBundleIDs: [], seedAllowedCount: 0, beginTransient: false),
        .init(scenario: "excludedApp", action: .terminalKeyDown, frontmost: .known, bundleID: "test.excluded", secureInput: .disabled, excludedBundleIDs: ["test.excluded"], seedAllowedCount: 0, beginTransient: false),
        .init(scenario: "secureInputEnabled", action: .terminalKeyDown, frontmost: .known, bundleID: "test.allowed", secureInput: .enabled, excludedBundleIDs: [], seedAllowedCount: 0, beginTransient: false),
        .init(scenario: "secureInputUnknown", action: .terminalKeyDown, frontmost: .known, bundleID: "test.allowed", secureInput: .unknown, excludedBundleIDs: [], seedAllowedCount: 0, beginTransient: false),
        .init(scenario: "tapReset", action: .tapReset, frontmost: .known, bundleID: "test.allowed", secureInput: .disabled, excludedBundleIDs: [], seedAllowedCount: 1, beginTransient: true),
        .init(scenario: "sleepWake", action: .systemSleep, frontmost: .known, bundleID: "test.allowed", secureInput: .disabled, excludedBundleIDs: [], seedAllowedCount: 1, beginTransient: true),
    ]

    private static func modifierArtifact() -> SP2ModifierArtifact {
        let sided = ModifierFamily.allCases.flatMap { family in
            [SP2SidedModifierCase(family: family, left: nil, right: nil, observed: .activeSideUnknown)] +
            [(false, false), (true, false), (false, true), (true, true)].map { left, right in
                let input = SP2SidedModifierCase(family: family, left: left, right: right, observed: .activeSideUnknown)
                return SP2SidedModifierCase(family: family, left: left, right: right, observed: recompute(input))
            }
        }
        let fnOperations: [[SP2FnOperation]] = [[], [.init(transition: nil, active: false)], [.init(transition: nil, active: true)]]
            + RecoveryTransition.allCases.flatMap { transition in
                [[.init(transition: transition, active: nil)], [.init(transition: transition, active: nil), .init(transition: nil, active: false)]]
            }
        let fn = fnOperations.map { operations -> SP2FnCase in
            let input = SP2FnCase(operations: operations, observed: .unknown)
            return SP2FnCase(operations: operations, observed: recompute(input))
        }
        let recoveries = RecoveryTransition.allCases.map(recoveryCase)
        return SP2ModifierArtifact(evidenceKind: .fixture, sidedCases: sided, fnCases: fn, recoveryCases: recoveries, deterministicRecovery: recoveries == RecoveryTransition.allCases.map(recoveryCase))
    }

    private static func recoveryCase(_ transition: RecoveryTransition) -> SP2RecoveryCase {
        var model = ModifierReconstructionModel()
        for family in ModifierFamily.allCases { model.apply(family: family, left: true, right: false) }
        model.applyFn(active: true); model.invalidate(for: transition)
        let unknown = Dictionary(uniqueKeysWithValues: ModifierFamily.allCases.map { ($0.rawValue, model[$0]) })
        let before = model.fn
        for family in ModifierFamily.allCases { model.apply(family: family, left: false, right: true) }
        model.applyFn(active: false)
        let recovered = Dictionary(uniqueKeysWithValues: ModifierFamily.allCases.map { ($0.rawValue, model[$0]) })
        return SP2RecoveryCase(transition: transition, unknownStates: unknown, recoveredStates: recovered, fnBeforeRecovery: before, fnAfterRecovery: model.fn)
    }

    private static func recoveryPasses(_ item: SP2RecoveryCase) -> Bool {
        item.unknownStates.values.allSatisfy { $0 == .activeSideUnknown }
            && item.recoveredStates.values.allSatisfy { $0 == .right }
            && item.fnBeforeRecovery == .unknown && item.fnAfterRecovery == .knownNone
    }
}

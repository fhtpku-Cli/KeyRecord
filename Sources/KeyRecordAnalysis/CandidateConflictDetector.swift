import Foundation
import KeyRecordCore

public enum CandidateConflictDetector {
    public static let ruleVersion = "phase2-conflicts-v1"
    public static func hasMappingChain(_ input: CandidateCheckInput) -> Bool {
        guard let evidence = input.conflictEvidence, let backend = evidence.backendRules,
              evidence.profile == backend.profile else { return false }
        return backend.rules.contains { rule in
            guard rule.profile == backend.profile, domainsOverlap(input.scope, rule.scope),
                  devicesOverlap(evidence.devices, rule.devices) else { return false }
            if rule.anyModifiers ? rule.trigger.keyCode == input.source.keyCode : ChordOverlap.matches(rule.trigger, input.source) { return true }
            return rule.output.map { ChordOverlap.matches($0, input.trigger) } ?? false
        }
    }

    public static func evaluate(_ input: CandidateCheckInput) -> CandidateConflictReport {
        var conflicts: Set<CandidateConflict> = []
        var kinds: Set<String> = ["known-system-risk"]
        var limitations: Set<ConflictLimitation> = [.menuUnavailable]
        let evidence = input.conflictEvidence
        if let observations = evidence?.observations {
            kinds.insert("observed")
            for row in observations where ChordOverlap.matches(row.chord, input.trigger) {
                switch (input.scope, row.appBucket) {
                case (.global, _): conflicts.insert(.observedShortcut)
                case (.application(let selected), .bundleID(let app)) where app == selected:
                    conflicts.insert(.observedShortcut)
                case (.application, .unknown): limitations.insert(.unknownApplication)
                default: break
                }
            }
        } else { limitations.insert(.observationsUnavailable) }
        if ChordRuleTable.v1.classify(input.trigger).scope == .system {
            conflicts.insert(.knownSystemRisk)
        }
        if let rules = evidence?.backendRules, rules.backend == input.backend.kind {
            kinds.insert(rules.backend == .karabiner ? "karabiner-overlap" : "firmware-rules")
            if rules.origin == .selectedCopy { limitations.insert(.referenceOnly) }
            else if rules.backendVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                limitations.insert(.backendVersionUnknown)
            }
            if rules.unsupportedRuleCount != 0 { limitations.insert(.unsupportedRules) }
            if evidence?.profile != rules.profile { limitations.insert(.profileMismatch) }
            else {
                let selected = rules.rules.filter {
                    $0.profile == rules.profile && domainsOverlap(input.scope, $0.scope)
                        && devicesOverlap(evidence?.devices, $0.devices)
                }
                if selected.contains(where: { rule in
                    rule.anyModifiers ? rule.trigger.keyCode == input.trigger.keyCode : ChordOverlap.matches(rule.trigger, input.trigger)
                }) { conflicts.insert(.existingRuleOverlap) }
                if rules.protectedTriggers.contains(where: { ChordOverlap.matches($0, input.trigger) }) {
                    conflicts.insert(.protectedLayerEntry)
                }
                switch cycle(input: input, rules: selected, devices: evidence?.devices) {
                case .found: conflicts.insert(.mappingCycle)
                case .limit: limitations.insert(.traversalLimit)
                case .absent: break
                }
            }
        } else { limitations.insert(.backendRulesUnavailable) }
        let ordered = CandidateConflict.allCases.filter { conflicts.contains($0) }
        let complete = limitations.isDisjoint(with: [.observationsUnavailable, .unknownApplication,
            .backendRulesUnavailable, .referenceOnly, .unsupportedRules, .profileMismatch, .backendVersionUnknown, .traversalLimit])
        return CandidateConflictReport(check: CandidateConflictCheck(input: input, conflicts: ordered,
            evidenceKinds: kinds, isComplete: complete), findings: ordered.map { ConflictFinding(kind: $0) }, limitations: limitations)
    }

    private static func domainsOverlap(_ a: RecommendationScope, _ b: RecommendationScope) -> Bool {
        switch (a, b) {
        case (.application(let x), .application(let y)): return x == y
        default: return true
        }
    }

    private static func devicesOverlap(_ a: Set<String>?, _ b: Set<String>?) -> Bool {
        if let a, let b { return !a.isDisjoint(with: b) }
        return true
    }

    private enum CycleResult { case found, absent, limit }
    private struct Path: Hashable {
        let chord: Chord
        let application: String?
        let devices: Set<String>?
    }

    private static func cycle(input: CandidateCheckInput, rules: [BackendRule], devices: Set<String>?) -> CycleResult {
        let app: String? = if case .application(let id) = input.scope { id } else { nil }
        var pending = [Path(chord: input.source, application: app, devices: devices)]
        var seen: Set<Path> = []
        let edges = Dictionary(grouping: rules.filter { !$0.anyModifiers && $0.output != nil }, by: { $0.trigger.keyCode })
        while let path = pending.popLast() {
            guard seen.insert(path).inserted else { continue }
            if seen.count > 10_000 { return .limit }
            if ChordOverlap.matches(path.chord, input.trigger) { return .found }
            for rule in edges[path.chord.keyCode] ?? [] where ChordOverlap.matches(rule.trigger, path.chord) {
                guard let output = rule.output else { continue }
                let ruleApp: String? = if case .application(let id) = rule.scope { id } else { nil }
                if let a = path.application, let b = ruleApp, a != b { continue }
                if !devicesOverlap(path.devices, rule.devices) { continue }
                let narrowed: Set<String>? = if let a = path.devices, let b = rule.devices { a.intersection(b) } else { path.devices ?? rule.devices }
                pending.append(Path(chord: output, application: path.application ?? ruleApp, devices: narrowed))
                if pending.count + seen.count > 10_000 { return .limit }
            }
        }
        return .absent
    }
}

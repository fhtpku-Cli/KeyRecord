import Foundation
import KeyRecordCore
import KeyRecordAnalysis

public struct RecommendationDraft: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let backend: RecommendationBackend
    public let output: Chord
    public let trigger: Chord
    public let scope: RecommendationScope

    public init(backend: RecommendationBackend, output: Chord, trigger: Chord, scope: RecommendationScope) {
        id = UUID(); self.backend = backend; self.output = output; self.trigger = trigger; self.scope = scope
    }

    public enum Route: Equatable, Sendable {
        case karabiner
        case firmware(output: String)
        case unsupported(String)
    }

    public var route: Route {
        guard ChordRuleTable.v1.classify(output).kind == .discrete,
              ChordRuleTable.v1.classify(trigger).kind == .discrete,
              output != trigger else { return .unsupported("invalid") }
        if backend == .karabiner {
            let draft = KarabinerMappingDraft(name: "Recommendation", profile: "Pending selection", trigger: trigger,
                output: output, scope: { if case .application(let id) = scope { return .application(id) }; return .global }())
            return (try? draft.rule()) == nil ? .unsupported("invalid") : .karabiner
        }
        if case .application = scope { return .unsupported("application") }
        let bare = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        guard output.modifiers == bare, trigger.modifiers == bare else { return .unsupported("shortcut") }
        guard let token = VIAFileCompatibility.outputs.sorted().first(where: { VIAReferenceParser.standardKeyCode($0) == output.keyCode }),
              VIAFileCompatibility.outputs.contains(where: { VIAReferenceParser.standardKeyCode($0) == trigger.keyCode }) else {
            return .unsupported("key")
        }
        return .firmware(output: token)
    }
}

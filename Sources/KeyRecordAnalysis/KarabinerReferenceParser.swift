import Foundation
import KeyRecordCore
import KeyRecordConfigurationRead

public enum KarabinerReferenceError: Error, Equatable { case jsonProtection, invalidDocument }

public struct KarabinerProfileReference: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let evidence: BackendRuleEvidence
}

public struct KarabinerReference: Equatable, Sendable {
    public let profiles: [KarabinerProfileReference]
    public let selectedProfile: String?
}

public enum KarabinerReferenceParser {
    public static func parse(_ data: Data) throws -> KarabinerReference {
        do { try BoundedJSONPreflight.rejectDuplicateKeys(data) }
        catch { throw KarabinerReferenceError.jsonProtection }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty, profiles.count <= 128
        else { throw KarabinerReferenceError.invalidDocument }
        var selected: [String] = []
        let parsed = try profiles.enumerated().map { index, profile in
            guard let name = profile["name"] as? String, !name.isEmpty else { throw KarabinerReferenceError.invalidDocument }
            let id = String(index)
            if let value = profile["selected"] {
                guard let flag = boolean(value) else { throw KarabinerReferenceError.invalidDocument }
                if flag { selected.append(id) }
            }
            var rules: [BackendRule] = []
            var unsupported = 0
            func simple(_ value: Any?) {
                guard let value else { return }
                guard let entries = value as? [[String: Any]] else { unsupported += 1; return }
                for entry in entries {
                    guard let from = entry["from"] as? [String: Any], let keyName = from["key_code"] as? String,
                          from.count == 1, let code = KarabinerKeyCodes.values[keyName]
                    else { unsupported += 1; continue }
                    rules.append(BackendRule(trigger: Chord(keyCode: code, modifiers: emptyModifiers),
                        output: nil, profile: id, anyModifiers: true))
                    unsupported += 1
                }
            }
            simple(profile["simple_modifications"])
            simple(profile["fn_function_keys"])
            if let value = profile["complex_modifications"] {
                guard let complex = value as? [String: Any] else { throw KarabinerReferenceError.invalidDocument }
                if let value = complex["rules"] {
                    guard let entries = value as? [[String: Any]] else { throw KarabinerReferenceError.invalidDocument }
                    for entry in entries {
                        if let value = entry["enabled"] {
                            guard let flag = boolean(value) else { unsupported += 1; continue }
                            if !flag { continue }
                        }
                        guard let manipulators = entry["manipulators"] as? [[String: Any]] else { unsupported += 1; continue }
                        for manipulator in manipulators {
                            if let rule = basic(manipulator, profile: id) { rules.append(rule) }
                            else { unsupported += 1 }
                        }
                    }
                }
            }
            if let devices = profile["devices"] as? [[String: Any]] {
                for device in devices {
                    if device["simple_modifications"] != nil || device["fn_function_keys"] != nil { unsupported += 1 }
                }
            } else if profile["devices"] != nil { unsupported += 1 }
            return KarabinerProfileReference(id: id, name: String(name.prefix(128)),
                evidence: BackendRuleEvidence(backend: .karabiner, profile: id, rules: rules,
                    unsupportedRuleCount: unsupported, origin: .selectedCopy))
        }
        return KarabinerReference(profiles: parsed, selectedProfile: selected.count == 1 ? selected.first : parsed.count == 1 ? parsed.first?.id : nil)
    }

    private static let emptyModifiers = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)

    private static func boolean(_ value: Any) -> Bool? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return try? JSONDecoder().decode(Bool.self, from: data)
    }

    private static func basic(_ rule: [String: Any], profile: String) -> BackendRule? {
        guard Set(rule.keys).isSubset(of: ["type", "from", "to", "conditions", "description"]),
              rule["type"] as? String == "basic", let from = rule["from"] as? [String: Any],
              Set(from.keys).isSubset(of: ["key_code", "modifiers"]),
              let name = from["key_code"] as? String, let code = KarabinerKeyCodes.values[name],
              let to = rule["to"] as? [[String: Any]], to.count == 1,
              let output = chord(to[0]) else { return nil }
        let modifiers: ModifierSet
        if let value = from["modifiers"] {
            guard let object = value as? [String: Any], Set(object.keys).isSubset(of: ["mandatory", "optional"]),
                  object["optional"] == nil || (object["optional"] as? [String]) == [],
                  let names = object["mandatory"] as? [String] ?? (object["mandatory"] == nil ? [] : nil),
                  let parsed = modifierSet(names, generic: true) else { return nil }
            modifiers = parsed
        } else { modifiers = emptyModifiers }
        let scope: RecommendationScope
        if let value = rule["conditions"] {
            guard let conditions = value as? [[String: Any]] else { return nil }
            if conditions.isEmpty { scope = .global }
            else {
                guard conditions.count == 1, let condition = conditions.first,
                      Set(condition.keys) == ["type", "bundle_identifiers"],
                      condition["type"] as? String == "frontmost_application_if",
                      let patterns = condition["bundle_identifiers"] as? [String], patterns.count == 1,
                      let pattern = patterns.first, let app = literalApplication(pattern) else { return nil }
                scope = .application(app)
            }
        } else { scope = .global }
        return BackendRule(trigger: Chord(keyCode: code, modifiers: modifiers), output: output, scope: scope, profile: profile)
    }

    private static func chord(_ value: [String: Any]) -> Chord? {
        guard Set(value.keys).isSubset(of: ["key_code", "modifiers"]), let name = value["key_code"] as? String,
              let code = KarabinerKeyCodes.values[name],
              let names = value["modifiers"] as? [String] ?? (value["modifiers"] == nil ? [] : nil),
              let modifiers = modifierSet(names, generic: false) else { return nil }
        return Chord(keyCode: code, modifiers: modifiers)
    }

    private static func modifierSet(_ names: [String], generic: Bool) -> ModifierSet? {
        var families: [ModifierSideState] = [.none, .none, .none, .none]
        let labels = ["command", "option", "control", "shift"]
        var fn = false
        for name in names {
            if name == "fn" { fn = true; continue }
            var matched = false
            for (index, label) in labels.enumerated() {
                let state: ModifierSideState
                switch name {
                case "left_" + label: state = .left
                case "right_" + label: state = .right
                case label where generic: state = .activeSideUnknown
                default: continue
                }
                let old = families[index]
                if old == .none || old == state { families[index] = state }
                else if Set([old, state]) == [.left, .right] { families[index] = .both }
                else { return nil }
                matched = true
            }
            if !matched { return nil }
        }
        return ModifierSet(command: families[0], option: families[1], control: families[2], shift: families[3], fn: fn ? .active : .none)
    }

    private static func literalApplication(_ pattern: String) -> String? {
        guard pattern.hasPrefix("^"), pattern.hasSuffix("$"), pattern.count <= 256 else { return nil }
        let inner = String(pattern.dropFirst().dropLast())
        let value = inner.replacingOccurrences(of: "\\.", with: ".")
        guard !value.isEmpty, inner.replacingOccurrences(of: "\\.", with: "").allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return value
    }
}

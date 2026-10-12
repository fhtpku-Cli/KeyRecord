import Foundation
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordConfigurationRead

public enum MappingScope: Codable, Equatable, Sendable {
    case global, application(String)
    public var recommendation: RecommendationScope {
        switch self { case .global: .global; case .application(let id): .application(id) }
    }
}

public struct MappingDevice: Codable, Hashable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public init(vendorID: UInt16, productID: UInt16) { self.vendorID = vendorID; self.productID = productID }
    public var identity: String { "\(vendorID):\(productID)" }
}

public struct KarabinerMappingDraft: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var profile: String
    public var trigger: Chord
    public var output: Chord
    public var scope: MappingScope
    public var devices: Set<MappingDevice>?
    public var temporary: Bool
    public init(id: UUID = UUID(), name: String, profile: String, trigger: Chord, output: Chord,
                scope: MappingScope = .global, devices: Set<MappingDevice>? = nil, temporary: Bool = false) {
        self.id = id; self.name = name; self.profile = profile; self.trigger = trigger; self.output = output
        self.scope = scope; self.devices = devices; self.temporary = temporary
    }
    public func rule() throws -> Data {
        guard !profile.isEmpty, !name.isEmpty, name.utf8.count <= 256, devices?.isEmpty != true else {
            throw KarabinerMappingError.invalidDraft
        }
        guard let capabilities = BackendCapabilityCatalog.reference(.karabiner),
              case .unchecked = CandidateConstraints.assess(CandidateCheckInput(source: output, trigger: trigger,
                scope: scope.recommendation, backend: .connected(capabilities))) else { throw KarabinerMappingError.invalidDraft }
        var conditions: [[String: Any]] = []
        if case .application(let app) = scope {
            guard !app.isEmpty, app.utf8.count <= 256,
                  app.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }) else { throw KarabinerMappingError.invalidDraft }
            conditions.append(["type": "frontmost_application_if", "bundle_identifiers": ["^" + NSRegularExpression.escapedPattern(for: app) + "$"]])
        }
        if let devices {
            conditions.append(["type": "device_if", "identifiers": devices.sorted { $0.identity < $1.identity }.map {
                ["vendor_id": Int($0.vendorID), "product_id": Int($0.productID), "is_keyboard": true] as [String: Any]
            }])
        }
        var manipulator: [String: Any] = ["type": "basic", "from": try event(trigger, from: true), "to": [try event(output, from: false)]]
        if !conditions.isEmpty { manipulator["conditions"] = conditions }
        return try JSONSerialization.data(withJSONObject: ["description": "KeyRecord:" + id.uuidString + ":" + name,
            "manipulators": [manipulator]], options: [.sortedKeys])
    }
    private func event(_ chord: Chord, from: Bool) throws -> [String: Any] {
        guard let key = BackendCapabilityCatalog.karabinerName(for: chord.keyCode) else { throw KarabinerMappingError.invalidDraft }
        let families = [("command", chord.modifiers.command), ("option", chord.modifiers.option),
                        ("control", chord.modifiers.control), ("shift", chord.modifiers.shift)]
        var names: [String] = []
        for (name, side) in families {
            switch side {
            case .none: break
            case .left: names.append("left_" + name)
            case .right: names.append("right_" + name)
            case .both: names += ["left_" + name, "right_" + name]
            case .activeSideUnknown: throw KarabinerMappingError.invalidDraft
            }
        }
        if chord.modifiers.fn == .active { names.append("fn") }
        return ["key_code": key, "modifiers": from ? ["mandatory": names, "optional": []] as Any : names as Any]
    }
    var backendRule: BackendRule {
        BackendRule(trigger: trigger, output: output, scope: scope.recommendation,
                    devices: devices.map { Set($0.map(\.identity)) }, profile: profile)
    }
}

public enum KarabinerMappingError: Error, Equatable, Sendable {
    case invalidDraft, invalidConfiguration, ambiguousProfile, malformedManagedBlock
    case readOnlyVersion, externalChange, busy, riskConfirmationRequired, conflict, unavailable
}

public struct ManagedBlockDiff: Equatable, Sendable {
    public let profile: String
    public let range: Range<Int>
    public let removed: Data
    public let inserted: Data
    public let previousRuleCount: Int
    public let ruleCount: Int
}

public struct KarabinerPlan: Equatable, Sendable {
    public let base: Data
    public let bytes: Data
    public let diff: ManagedBlockDiff
    public let drafts: [KarabinerMappingDraft]
    public let userEvidence: BackendRuleEvidence
}

public enum KarabinerProfilePlanner {
    public static let start = "KeyRecord managed block start"
    public static let end = "KeyRecord managed block end"

    public static func plan(_ base: Data, profile name: String, drafts: [KarabinerMappingDraft], remove: Bool = false) throws -> KarabinerPlan {
        guard drafts.count <= 256, Set(drafts.map(\.id)).count == drafts.count,
              drafts.allSatisfy({ $0.profile == name }) else { throw KarabinerMappingError.invalidDraft }
        let tree = try JSONDocumentRanges(base).root
        guard let profiles = tree.members["profiles"]?.elements else { throw KarabinerMappingError.invalidConfiguration }
        let matches = profiles.filter { node in
            guard let range = node.members["name"]?.range,
                  let array = try? JSONSerialization.jsonObject(with: Data([91]) + base.subdata(in: range) + Data([93])) as? [String]
            else { return false }
            return array.first == name
        }
        guard matches.count == 1, let profile = matches.first else { throw KarabinerMappingError.ambiguousProfile }
        let complex = profile.members["complex_modifications"]
        if let complex, complex.elements != nil || complex.members.isEmpty && base[complex.range.lowerBound] != 123 {
            throw KarabinerMappingError.invalidConfiguration
        }
        let rules = complex?.members["rules"]
        if let rules, rules.elements == nil { throw KarabinerMappingError.invalidConfiguration }
        let entries = rules?.elements ?? []
        let objects = try entries.map { entry -> [String: Any] in
            guard let value = try JSONSerialization.jsonObject(with: base.subdata(in: entry.range)) as? [String: Any],
                  value["description"] is String, value["manipulators"] is [Any] else { throw KarabinerMappingError.invalidConfiguration }
            return value
        }
        let starts = objects.indices.filter { objects[$0]["description"] as? String == start }
        let ends = objects.indices.filter { objects[$0]["description"] as? String == end }
        guard starts.count == ends.count, starts.count <= 1 else { throw KarabinerMappingError.malformedManagedBlock }
        let owned: Range<Int>?
        if let a = starts.first, let b = ends.first {
            guard a < b, (objects[a]["manipulators"] as? [Any])?.isEmpty == true,
                  (objects[b]["manipulators"] as? [Any])?.isEmpty == true,
                  ((a + 1)..<b).allSatisfy({ (objects[$0]["description"] as? String)?.hasPrefix("KeyRecord:") == true })
            else { throw KarabinerMappingError.malformedManagedBlock }
            owned = a..<(b + 1)
        } else { owned = nil }
        for index in objects.indices where owned?.contains(index) != true {
            if (objects[index]["description"] as? String)?.hasPrefix("KeyRecord:") == true {
                throw KarabinerMappingError.malformedManagedBlock
            }
        }
        let marker: (String) throws -> Data = { try JSONSerialization.data(withJSONObject: ["description": $0, "manipulators": []], options: [.sortedKeys]) }
        let block = try ([marker(start)] + drafts.map { try $0.rule() } + [marker(end)])
            .reduce(into: Data()) { value, rule in if !value.isEmpty { value.append(Data(",\n".utf8)) }; value.append(rule) }
        let range: Range<Int>
        let inserted: Data
        if remove, owned == nil {
            range = profile.range.upperBound..<profile.range.upperBound
            inserted = Data()
        } else if let owned {
            var lower = entries[owned.lowerBound].range.lowerBound
            var upper = entries[owned.upperBound - 1].range.upperBound
            if remove, owned.upperBound < entries.count {
                upper = entries[owned.upperBound].range.lowerBound
            } else if remove, owned.lowerBound > 0 {
                lower = entries[owned.lowerBound - 1].range.upperBound
            }
            range = lower..<upper
            inserted = remove ? Data() : block
        } else if let rules {
            let offset = rules.range.upperBound - 1
            range = offset..<offset; inserted = Data((entries.isEmpty ? "" : ",").utf8) + block
        } else if let complex {
            let offset = complex.range.upperBound - 1
            range = offset..<offset
            inserted = Data((complex.members.isEmpty ? "" : ",").utf8) + Data("\"rules\":[".utf8) + block + Data("]".utf8)
        } else {
            let offset = profile.range.upperBound - 1
            range = offset..<offset
            inserted = Data(",\"complex_modifications\":{\"rules\":[".utf8) + block + Data("]}".utf8)
        }
        let bytes = Data(base.prefix(range.lowerBound)) + inserted + Data(base.suffix(base.count - range.upperBound))
        _ = try JSONDocumentRanges(bytes)
        guard var userProfile = try JSONSerialization.jsonObject(with: base.subdata(in: profile.range)) as? [String: Any] else {
            throw KarabinerMappingError.invalidConfiguration
        }
        var userComplex = userProfile["complex_modifications"] as? [String: Any] ?? [:]
        userComplex["rules"] = objects.enumerated().filter { owned?.contains($0.offset) != true }.map(\.element)
        userProfile["complex_modifications"] = userComplex
        let referenceBytes = try JSONSerialization.data(withJSONObject: ["profiles": [userProfile]])
        guard let evidence = try KarabinerReferenceParser.parse(referenceBytes).profiles.first?.evidence else { throw KarabinerMappingError.invalidConfiguration }
        let namedEvidence = BackendRuleEvidence(backend: .karabiner, profile: name,
            rules: evidence.rules.map { BackendRule(trigger: $0.trigger, output: $0.output, scope: $0.scope,
                devices: $0.devices, profile: name, anyModifiers: $0.anyModifiers) },
            unsupportedRuleCount: evidence.unsupportedRuleCount, origin: .selectedCopy)
        return KarabinerPlan(base: base, bytes: bytes,
            diff: ManagedBlockDiff(profile: name, range: range, removed: base.subdata(in: range), inserted: inserted,
                previousRuleCount: max(0, (owned?.count ?? 2) - 2), ruleCount: drafts.count),
            drafts: drafts, userEvidence: namedEvidence)
    }

    public static func adoptedDrafts(_ bytes: Data, profile: String) throws -> [KarabinerMappingDraft] {
        let plan = try plan(bytes, profile: profile, drafts: [])
        guard plan.diff.previousRuleCount > 0 else { return [] }
        let array = Data([91]) + plan.diff.removed + Data([93])
        guard let objects = try JSONSerialization.jsonObject(with: array) as? [[String: Any]] else { throw KarabinerMappingError.malformedManagedBlock }
        return try objects.dropFirst().dropLast().map { object in
            guard let description = object["description"] as? String else { throw KarabinerMappingError.invalidDraft }
            let fields = description.split(separator: ":", maxSplits: 2).map(String.init)
            guard fields.count == 3, fields[0] == "KeyRecord", let id = UUID(uuidString: fields[1]) else { throw KarabinerMappingError.invalidDraft }
            let synthetic = try JSONSerialization.data(withJSONObject: ["profiles": [["name": profile, "complex_modifications": ["rules": [object]]]]])
            guard let parsed = try KarabinerReferenceParser.parse(synthetic).profiles.first?.evidence,
                  parsed.unsupportedRuleCount == 0, parsed.rules.count == 1,
                  let rule = parsed.rules.first, let output = rule.output else { throw KarabinerMappingError.invalidDraft }
            let scope: MappingScope = if case .application(let app) = rule.scope { .application(app) } else { .global }
            let devices = try rule.devices.map { ids in
                try Set(ids.map { value in
                    let pair = value.split(separator: ":")
                    guard pair.count == 2, let vendor = UInt16(pair[0]), let product = UInt16(pair[1]) else { throw KarabinerMappingError.invalidDraft }
                    return MappingDevice(vendorID: vendor, productID: product)
                })
            }
            let draft = KarabinerMappingDraft(id: id, name: fields[2], profile: profile, trigger: rule.trigger, output: output, scope: scope, devices: devices)
            _ = try draft.rule()
            return draft
        }
    }
}

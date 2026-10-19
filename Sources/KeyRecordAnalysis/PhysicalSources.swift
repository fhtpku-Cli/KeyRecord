import Foundation
import KeyRecordCore

public struct PhysicalSoftwareReference: Equatable, Sendable {
    public let bytes: Data
    public let profile: String
    public let version: String?
    public init(bytes: Data, profile: String, version: String? = nil) {
        self.bytes = bytes; self.profile = profile; self.version = version
    }
}

public struct PhysicalSourceInput: Equatable, Sendable {
    public let backend: RecommendationBackend
    public let scope: RecommendationScope
    public let via: VIAImportedConfiguration?
    public let software: PhysicalSoftwareReference?
    public let firmware: PhysicalFirmwareReference?
    public init(backend: RecommendationBackend, scope: RecommendationScope,
                via: VIAImportedConfiguration?, software: PhysicalSoftwareReference?, firmware: PhysicalFirmwareReference? = nil) {
        self.backend = backend; self.scope = scope; self.via = via; self.software = software
        self.firmware = firmware
    }
}

public struct PhysicalSourceSummary: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case geometry, device, firmware, software, macOS }
    public enum Status: String, Sendable { case reference, collected, observed, missing, changed, unsupported }
    public let id: Kind
    public let status: Status
    public init(_ kind: Kind, _ status: Status) { id = kind; self.status = status }
}

public struct PhysicalSourceReport: Equatable, Sendable {
    public let evidence: PhysicalEvidence
    public let sources: [PhysicalSourceSummary]
    public init(evidence: PhysicalEvidence, sources: [PhysicalSourceSummary]) { self.evidence = evidence; self.sources = sources }

    public static func references(_ input: PhysicalSourceInput, changed: Bool = false) -> Self {
        // A VIA file never supplies Vial device geometry or a deployed firmware claim.
        let via = input.backend == .vial ? nil : input.via
        let software = input.software.flatMap { selected -> KarabinerProfileReference? in
            let profiles = (try? KarabinerReferenceParser.parse(selected.bytes))?.profiles ?? []
            let matches = profiles.filter { $0.identityName == selected.profile }
            return matches.count == 1 ? matches.first : nil
        }
        let rules = software?.evidence.rules ?? []
        let mappings = rules.compactMap { rule -> CanonicalTransform.Mapping? in
            guard rule.devices == nil, !rule.anyModifiers, rule.scope == .global || rule.scope == input.scope,
                  let output = rule.output, let from = hid(rule.trigger), let to = hid(output) else { return nil }
            return .init(input: from, output: to)
        }
        let state: TransformStatus = changed ? .externallyChanged : .absent
        let readback = input.backend == .vial ? input.firmware : nil
        let firmware = TransformEvidence(link: .firmware, status: state,
            reference: readback.map { "vial-readback:" + $0.device } ?? (via == nil ? "" : "via-file-reference"),
            mapping: readback?.mapping ?? via?.physicalEvidence.chain.first?.mapping)
        let softwareEvidence = TransformEvidence(link: .software, status: state,
            reference: software.map { "karabiner-profile:" + $0.identityName } ?? "",
            mapping: software == nil ? nil : CanonicalTransform(mappings: mappings, completeInverseFor: []))
        let evidence = PhysicalEvidence(geometry: via?.geometry,
            chain: [firmware, softwareEvidence, .init(link: .macOS, status: state, reference: "", mapping: nil)],
            device: .unknown, scope: input.scope)
        let softwareStatus: PhysicalSourceSummary.Status = software != nil ? .reference : input.software == nil ? .missing : .unsupported
        return Self(evidence: evidence, sources: [
            .init(.geometry, via?.geometry == nil ? .missing : .reference), .init(.device, .missing),
            .init(.firmware, readback != nil ? .collected : via == nil ? .missing : .reference), .init(.software, softwareStatus), .init(.macOS, .missing)
        ].map { changed ? .init($0.id, .changed) : $0 })
    }

    public static func observed(_ evidence: PhysicalEvidence) -> Self {
        func status(_ link: TransformLink) -> PhysicalSourceSummary.Status {
            let parts = evidence.chain.filter { $0.link == link }
            guard !parts.isEmpty else { return .missing }
            if parts.contains(where: { $0.status == .externallyChanged }) { return .changed }
            if parts.contains(where: { $0.status != .verified || $0.mapping == nil || $0.reference.isEmpty }) { return .unsupported }
            return .observed
        }
        return Self(evidence: evidence, sources: [
            .init(.geometry, evidence.geometry == nil ? .missing : .observed),
            .init(.device, evidence.device == .singleVerified ? .observed : .missing),
            .init(.firmware, status(.firmware)), .init(.software, status(.software)), .init(.macOS, status(.macOS))
        ])
    }

    private static func hid(_ chord: Chord) -> [PhysicalToken]? {
        let m = chord.modifiers
        guard m.fn == .none, let key = VIAReferenceParser.standardHIDUsage(chord.keyCode) else { return nil }
        var result: [PhysicalToken] = []
        for (side, left, right) in [(m.command, UInt16(0xe3), UInt16(0xe7)), (m.option, 0xe2, 0xe6),
                                   (m.control, 0xe0, 0xe4), (m.shift, 0xe1, 0xe5)] {
            guard side != .activeSideUnknown else { return nil }
            if side == .left || side == .both { result.append(.hidUsage(left)) }
            if side == .right || side == .both { result.append(.hidUsage(right)) }
        }
        return result + [.hidUsage(key)]
    }
}

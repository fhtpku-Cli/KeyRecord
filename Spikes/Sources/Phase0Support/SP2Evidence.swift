import Foundation

public enum SP2O6Status: String, Codable, Sendable { case open = "OPEN", resolved = "RESOLVED" }

public struct SP2Leg: Codable, Equatable, Sendable {
    public var legID: String
    public var evidenceKind: EvidenceKind
    public var detectorID: String
    public var detectorAvailable: Bool
    public var verdict: Verdict
    public var blocker: SP1Blocker?
    public var runnerCommitSha: String
    public var runnerTreeSha: String
    public var environmentSha256: String
    public var command: [String]
    public var exitStatus: Int32?
    public var artifactPath: String?
    public var artifactSha256: String?
    public var dataDelta: Int
    public var metaDelta: Int

    public init(legID: String, evidenceKind: EvidenceKind, detectorID: String, detectorAvailable: Bool,
                verdict: Verdict, blocker: SP1Blocker?, runnerCommitSha: String, runnerTreeSha: String,
                environmentSha256: String, command: [String], exitStatus: Int32?, artifactPath: String? = nil, artifactSha256: String?,
                dataDelta: Int, metaDelta: Int) {
        self.legID = legID; self.evidenceKind = evidenceKind; self.detectorID = detectorID
        self.detectorAvailable = detectorAvailable; self.verdict = verdict; self.blocker = blocker
        self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha
        self.environmentSha256 = environmentSha256; self.command = command; self.exitStatus = exitStatus; self.artifactPath = artifactPath
        self.artifactSha256 = artifactSha256; self.dataDelta = dataDelta; self.metaDelta = metaDelta
    }
}

public enum SP2ValidationError: String, Error, Equatable {
    case duplicateLeg, missingLeg, invalidRule, invalidVerdict, invalidBlocker, invalidProvenance
    case invalidDelta, invalidAggregate, invalidGate, invalidRunnerSourceSet
}

public struct SP2Evidence: Codable, Equatable, Sendable {
    public static let requiredLegIDs = Set(Phase0Registry.legRules.keys.filter { $0.hasPrefix("sp2.") })
    public var schemaVersion: Int
    public var spikeID: String
    public var legs: [SP2Leg]
    public var verdict: Verdict
    public var o6Status: SP2O6Status
    public var g0Status: G0Status
    public var runnerSourceSha256: [String: String]

    public init(schemaVersion: Int = 1, legs: [SP2Leg], verdict: Verdict, o6Status: SP2O6Status,
                g0Status: G0Status, runnerSourceSha256: [String: String]) {
        self.schemaVersion = schemaVersion; self.spikeID = "SP-2"; self.legs = legs; self.verdict = verdict
        self.o6Status = o6Status; self.g0Status = g0Status; self.runnerSourceSha256 = runnerSourceSha256
    }

    public func validate() throws {
        let groups = Dictionary(grouping: legs, by: \SP2Leg.legID)
        if groups.values.contains(where: { $0.count != 1 }) { throw SP2ValidationError.duplicateLeg }
        guard Set(groups.keys) == Self.requiredLegIDs else { throw SP2ValidationError.missingLeg }
        guard schemaVersion == 1, spikeID == "SP-2" else { throw SP2ValidationError.invalidProvenance }
        guard Set(runnerSourceSha256.keys) == SP2RunnerBinding.sourcePaths,
              runnerSourceSha256.values.allSatisfy(\.isLowercaseSHA256) else { throw SP2ValidationError.invalidRunnerSourceSet }

        for leg in legs {
            guard let rule = Phase0Registry.legRules[leg.legID], rule.evidenceKind == leg.evidenceKind,
                  rule.detectorID == leg.detectorID else { throw SP2ValidationError.invalidRule }
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1,
                  leg.environmentSha256.isLowercaseSHA256, leg.environmentSha256 != String(repeating: "0", count: 64),
                  leg.dataDelta >= 0, leg.metaDelta >= 0 else {
                throw SP2ValidationError.invalidProvenance
            }
            if leg.verdict == .blocked {
                guard !leg.detectorAvailable, leg.blocker?.complete == true, leg.command.isEmpty,
                      leg.exitStatus == nil, leg.artifactPath == nil, leg.artifactSha256 == nil else { throw SP2ValidationError.invalidBlocker }
            } else {
                guard leg.detectorAvailable, leg.blocker == nil, !leg.command.isEmpty,
                      leg.exitStatus != nil, leg.artifactPath?.isEmpty == false,
                      leg.artifactSha256?.isLowercaseSHA256 == true,
                      leg.artifactSha256 != String(repeating: "0", count: 64) else {
                    throw SP2ValidationError.invalidVerdict
                }
                if leg.verdict == .inconclusive, !rule.allowsInconclusive { throw SP2ValidationError.invalidVerdict }
            }
            if Self.zeroDeltaLegIDs.contains(leg.legID) || leg.verdict == .blocked {
                guard leg.dataDelta == 0, leg.metaDelta == 0 else { throw SP2ValidationError.invalidDelta }
            }
        }
        let aggregate = legs.map(\.verdict).max { Self.precedence($0) < Self.precedence($1) } ?? .blocked
        guard aggregate == verdict else { throw SP2ValidationError.invalidAggregate }
        let allPass = legs.allSatisfy { $0.verdict == .pass }
        guard o6Status == (allPass ? .resolved : .open), g0Status == .open else { throw SP2ValidationError.invalidGate }
    }

    private static let zeroDeltaLegIDs: Set<String> = [
        "sp2.frontmostIndeterminate", "sp2.secureInput", "sp2.excludedApp", "sp2.tapReset",
        "sp2.sleepWake", "sp2.sidedModifiers", "sp2.sidedRecovery", "sp2.fnRecoveryModel", "sp2.fnRecoveryLive",
    ]
    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

public enum SP2RunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
        "Spikes/Sources/Phase0Probe/SP2Probe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/EvidenceDocuments.swift",
        "Spikes/Sources/Phase0Support/EvidenceModels.swift",
        "Spikes/Sources/Phase0Support/PrivacyTransition.swift",
        "Spikes/Sources/Phase0Support/ModifierReconstruction.swift",
        "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP2Evidence.swift",
        "Spikes/Sources/Phase0Support/SP2ModelScenarios.swift",
        "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP2DirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
    ]
}

public enum SP2DirectoryLayout {
    public static let artifactNames: Set<String> = [
        "SP-2-CONCLUSION.md", "evidence.json", "privacy-model.json", "modifier-model.json", "live-aggregate-counts.json",
    ]
    public static let allNames = artifactNames.union(["manifest.sha256"])
    public static let boundArtifactNames: Set<String> = ["privacy-model.json", "modifier-model.json", "live-aggregate-counts.json"]
}

public struct SP2AggregateArtifact: Codable, Equatable, Sendable {
    public let evidenceKind: EvidenceKind
    public let dataDelta: Int
    public let metaDelta: Int
    public init(evidenceKind: EvidenceKind, dataDelta: Int = 0, metaDelta: Int = 0) {
        self.evidenceKind = evidenceKind; self.dataDelta = dataDelta; self.metaDelta = metaDelta
    }
}

public enum SP2FrontmostAttribution: String, Codable, CaseIterable, Sendable { case knownAttributable, knownUnattributable, indeterminate, excluded }

public enum SP2LiveAggregateV2Error: Error, Equatable, Sendable {
    case invalidSchemaVersion(found: Int), invalidEvidenceKind(found: EvidenceKind), negativeCount(field: String)
}

public struct SP2LiveAggregateV2: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let evidenceKind: EvidenceKind
    public internal(set) var knownAttributable = 0
    public internal(set) var knownUnattributable = 0
    public internal(set) var tapResets = 0
    public internal(set) var fnUnknownAfterReset = 0
    public internal(set) var fnRecoveredKnownNone = 0
    public internal(set) var fnRecoveredKnownActive = 0
    public init() { schemaVersion = Self.currentSchemaVersion; evidenceKind = .live }

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case schemaVersion, evidenceKind, knownAttributable, knownUnattributable, tapResets
        case fnUnknownAfterReset, fnRecoveredKnownNone, fnRecoveredKnownActive
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP2LiveAggregateV2")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        evidenceKind = try values.decode(EvidenceKind.self, forKey: .evidenceKind)
        knownAttributable = try values.decode(Int.self, forKey: .knownAttributable)
        knownUnattributable = try values.decode(Int.self, forKey: .knownUnattributable)
        tapResets = try values.decode(Int.self, forKey: .tapResets)
        fnUnknownAfterReset = try values.decode(Int.self, forKey: .fnUnknownAfterReset)
        fnRecoveredKnownNone = try values.decode(Int.self, forKey: .fnRecoveredKnownNone)
        fnRecoveredKnownActive = try values.decode(Int.self, forKey: .fnRecoveredKnownActive)
        try validate()
    }

    private var counts: [(String, Int)] {
        [("knownAttributable", knownAttributable), ("knownUnattributable", knownUnattributable),
         ("tapResets", tapResets), ("fnUnknownAfterReset", fnUnknownAfterReset),
         ("fnRecoveredKnownNone", fnRecoveredKnownNone), ("fnRecoveredKnownActive", fnRecoveredKnownActive)]
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw SP2LiveAggregateV2Error.invalidSchemaVersion(found: schemaVersion) }
        guard evidenceKind == .live else { throw SP2LiveAggregateV2Error.invalidEvidenceKind(found: evidenceKind) }
        for (field, count) in counts where count < 0 { throw SP2LiveAggregateV2Error.negativeCount(field: field) }
    }

    public func canonicalData() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self); data.append(10); return data
    }
}

public struct SP2LiveAggregateV2Reducer: Sendable {
    public private(set) var aggregate = SP2LiveAggregateV2()
    public init() {}

    public mutating func recordTerminalKeyDown(gateOpen: Bool, secureInput: SecureInputState, frontmost: SP2FrontmostAttribution) {
        guard gateOpen, secureInput == .disabled else { return }
        switch frontmost {
        case .knownAttributable: aggregate.knownAttributable += 1
        case .knownUnattributable: aggregate.knownUnattributable += 1
        case .indeterminate, .excluded: return
        }
    }

    public mutating func recordTapReset() { aggregate.tapResets += 1 }

    public mutating func recordFnRecoverySnapshot(_ confidence: FnConfidence) {
        switch confidence {
        case .unknown: aggregate.fnUnknownAfterReset += 1
        case .knownNone: aggregate.fnRecoveredKnownNone += 1
        case .knownActive: aggregate.fnRecoveredKnownActive += 1
        }
    }
}

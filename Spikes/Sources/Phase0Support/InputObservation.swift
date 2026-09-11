import Foundation

public enum ProductSyntheticMarker {
    public static let value: UInt64 = 0x4b_52_53_50_31_54_45_53
}

public enum InputEventKind: String, Codable, CaseIterable, Sendable { case keyDown, keyUp, flagsChanged }
public enum InputSourceClass: String, Codable, Sendable { case ordinaryObserved, productTest, suspectedSynthetic }

public struct SyntheticInputEvent: Codable, Equatable, Sendable {
    public let kind: InputEventKind
    public let keyCode: UInt16
    public let isAutoRepeat: Bool
    public let marker: UInt64?
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case kind, keyCode, isAutoRepeat, marker }
    public init(kind: InputEventKind, keyCode: UInt16, isAutoRepeat: Bool, marker: UInt64?) {
        self.kind = kind; self.keyCode = keyCode; self.isAutoRepeat = isAutoRepeat; self.marker = marker
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SyntheticInputEvent")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(InputEventKind.self, forKey: .kind)
        keyCode = try values.decode(UInt16.self, forKey: .keyCode)
        isAutoRepeat = try values.decode(Bool.self, forKey: .isAutoRepeat)
        marker = try values.decodeIfPresent(UInt64.self, forKey: .marker)
    }
}

public struct ProductStampedRecord: Codable, Equatable, Sendable {
    public let kind: InputEventKind
    public let keyCode: UInt16
    public let isAutoRepeat: Bool
    public let marker: UInt64
    public let dropped: Bool
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case kind, keyCode, isAutoRepeat, marker, dropped }
    public init(kind: InputEventKind, keyCode: UInt16, isAutoRepeat: Bool, marker: UInt64, dropped: Bool) {
        self.kind = kind; self.keyCode = keyCode; self.isAutoRepeat = isAutoRepeat; self.marker = marker; self.dropped = dropped
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "ProductStampedRecord")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(InputEventKind.self, forKey: .kind)
        keyCode = try values.decode(UInt16.self, forKey: .keyCode)
        isAutoRepeat = try values.decode(Bool.self, forKey: .isAutoRepeat)
        marker = try values.decode(UInt64.self, forKey: .marker)
        dropped = try values.decode(Bool.self, forKey: .dropped)
    }
}

public struct SP1SyntheticArtifact: Codable, Equatable, Sendable {
    public let evidenceKind: EvidenceKind
    public let productStampedSynthetic: Bool
    public let records: [ProductStampedRecord]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case evidenceKind, productStampedSynthetic, records }
    public init(records: [ProductStampedRecord]) {
        evidenceKind = .synthetic; productStampedSynthetic = true; self.records = records
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP1SyntheticArtifact")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        evidenceKind = try values.decode(EvidenceKind.self, forKey: .evidenceKind)
        productStampedSynthetic = try values.decode(Bool.self, forKey: .productStampedSynthetic)
        records = try values.decode([ProductStampedRecord].self, forKey: .records)
    }
}

public struct SP1LiveAggregateArtifact: Codable, Equatable, Sendable {
    public let evidenceKind: EvidenceKind
    public let systemShortcutObservedCount: Int
    public let unmarkedObservedCount: Int
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case evidenceKind, systemShortcutObservedCount, unmarkedObservedCount }
    public init(systemShortcutObservedCount: Int, unmarkedObservedCount: Int) {
        evidenceKind = .live; self.systemShortcutObservedCount = systemShortcutObservedCount; self.unmarkedObservedCount = unmarkedObservedCount
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP1LiveAggregateArtifact")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        evidenceKind = try values.decode(EvidenceKind.self, forKey: .evidenceKind)
        systemShortcutObservedCount = try values.decode(Int.self, forKey: .systemShortcutObservedCount)
        unmarkedObservedCount = try values.decode(Int.self, forKey: .unmarkedObservedCount)
    }
}

public enum InputObservationError: Error, Equatable { case malformedProductMarker }

public struct InputObservationState: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var gateOpen = true
    public private(set) var aggregateCount = 0
    public private(set) var productStampedRecords: [ProductStampedRecord] = []
    private var heldCodes = Set<UInt16>()

    public init() {}

    public mutating func observe(_ event: SyntheticInputEvent) throws {
        if let marker = event.marker {
            guard marker == ProductSyntheticMarker.value else { throw InputObservationError.malformedProductMarker }
            productStampedRecords.append(.init(kind: event.kind, keyCode: event.keyCode, isAutoRepeat: event.isAutoRepeat, marker: marker, dropped: true))
            return
        }
        guard gateOpen else { return }
        switch event.kind {
        case .keyDown where !event.isAutoRepeat && heldCodes.insert(event.keyCode).inserted: aggregateCount += 1
        case .keyUp: heldCodes.remove(event.keyCode)
        default: break
        }
    }

    public mutating func tapDisabled() { generation += 1; gateOpen = false; heldCodes.removeAll() }
    public mutating func rebuildTap() { gateOpen = true }
}

public enum O7Boundary {
    public static let guarantee = "only product-stamped synthetic events are guaranteed excluded; unmarked injection indicators remain suspected, never proven, and no source-field exclusion is claimed."
    public static func classify(marker: UInt64?, hasInjectionIndicator: Bool) -> InputSourceClass {
        if marker == ProductSyntheticMarker.value { return .productTest }
        return hasInjectionIndicator ? .suspectedSynthetic : .ordinaryObserved
    }
}

public struct SP1SyntheticAssertion: Codable, Equatable, Sendable {
    public let legID: String, passed: Bool
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case legID, passed }
    public init(legID: String, passed: Bool) { self.legID = legID; self.passed = passed }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP1SyntheticAssertion")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        legID = try values.decode(String.self, forKey: .legID)
        passed = try values.decode(Bool.self, forKey: .passed)
    }
}

public struct SP1SyntheticAssertionsArtifact: Codable, Equatable, Sendable {
    public let schemaVersion: Int, evidenceKind: EvidenceKind, assertions: [SP1SyntheticAssertion]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case schemaVersion, evidenceKind, assertions }
    public init(assertions: [SP1SyntheticAssertion]) { schemaVersion = 2; evidenceKind = .synthetic; self.assertions = assertions }
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self); data.append(10); return data
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP1SyntheticAssertionsArtifact")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        evidenceKind = try values.decode(EvidenceKind.self, forKey: .evidenceKind)
        assertions = try values.decode([SP1SyntheticAssertion].self, forKey: .assertions)
    }
}

public enum SP1SyntheticScenarios {
    public static func run() throws -> SP1SyntheticAssertionsArtifact {
        try SP1SyntheticAssertionsArtifact(assertions: [
            .init(legID: "sp1.autoRepeat", passed: autoRepeatPasses()), .init(legID: "sp1.o7Boundary", passed: o7BoundaryPasses()),
            .init(legID: "sp1.productStampedDrop", passed: productStampedDropPasses()), .init(legID: "sp1.tapReset", passed: tapResetPasses()),
        ])
    }
    static func autoRepeatPasses() throws -> Bool {
        var state = InputObservationState()
        for (kind, isRepeat) in [(InputEventKind.keyDown, false), (.keyDown, true), (.keyDown, true), (.keyUp, false)] { try state.observe(.init(kind: kind, keyCode: 4, isAutoRepeat: isRepeat, marker: nil)) }; return state.aggregateCount == 1
    }
    static func o7BoundaryPasses() -> Bool {
        O7Boundary.classify(marker: ProductSyntheticMarker.value, hasInjectionIndicator: true) == .productTest
            && O7Boundary.classify(marker: 1, hasInjectionIndicator: true) == .suspectedSynthetic
            && O7Boundary.classify(marker: nil, hasInjectionIndicator: true) == .suspectedSynthetic && O7Boundary.classify(marker: nil, hasInjectionIndicator: false) == .ordinaryObserved
    }
    static func productStampedDropPasses() throws -> Bool {
        var state = InputObservationState()
        for kind in InputEventKind.allCases { try state.observe(.init(kind: kind, keyCode: 4, isAutoRepeat: false, marker: ProductSyntheticMarker.value)) }; return state.aggregateCount == 0 && state.productStampedRecords.count == InputEventKind.allCases.count && state.productStampedRecords.allSatisfy(\.dropped)
    }
    static func tapResetPasses() throws -> Bool {
        var state = InputObservationState(); try state.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        state.tapDisabled(); try state.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        let frozenCount = state.aggregateCount; state.rebuildTap()
        try state.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        return state.generation == 1 && frozenCount == 1 && state.aggregateCount == 2 && state.gateOpen
    }
}

public struct SelectedTapIdentity: Codable, Equatable, Sendable {
    public var tapType: String
    public var attemptID: String
    public var runnerCommitSha: String
    public var runnerTreeSha: String
    public var environmentSha256: String
    public var tapConfigSha256: String
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case tapType, attemptID = "attemptId", runnerCommitSha, runnerTreeSha, environmentSha256, tapConfigSha256
    }
    public init(tapType: String, attemptID: String, runnerCommitSha: String, runnerTreeSha: String, environmentSha256: String, tapConfigSha256: String) {
        self.tapType = tapType; self.attemptID = attemptID; self.runnerCommitSha = runnerCommitSha
        self.runnerTreeSha = runnerTreeSha; self.environmentSha256 = environmentSha256; self.tapConfigSha256 = tapConfigSha256
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SelectedTapIdentity")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tapType = try values.decode(String.self, forKey: .tapType)
        attemptID = try values.decode(String.self, forKey: .attemptID)
        runnerCommitSha = try values.decode(String.self, forKey: .runnerCommitSha)
        runnerTreeSha = try values.decode(String.self, forKey: .runnerTreeSha)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        tapConfigSha256 = try values.decode(String.self, forKey: .tapConfigSha256)
    }
}

public struct SP1Blocker: Codable, Equatable, Sendable {
    public let blockedBy: String
    public let detectCommand: [String]
    public let prerequisite: String
    public let unblockAction: String
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case blockedBy = "blocked_by", detectCommand = "detect_command", prerequisite, unblockAction = "unblock_action" }
    public init(blockedBy: String, detectCommand: [String], prerequisite: String, unblockAction: String) {
        self.blockedBy = blockedBy; self.detectCommand = detectCommand; self.prerequisite = prerequisite; self.unblockAction = unblockAction
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP1Blocker")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        blockedBy = try values.decode(String.self, forKey: .blockedBy)
        detectCommand = try values.decode([String].self, forKey: .detectCommand)
        prerequisite = try values.decode(String.self, forKey: .prerequisite)
        unblockAction = try values.decode(String.self, forKey: .unblockAction)
    }
    public var complete: Bool { !blockedBy.isEmpty && !detectCommand.isEmpty && detectCommand.allSatisfy { !$0.isEmpty } && !prerequisite.isEmpty && !unblockAction.isEmpty }
}

public enum SP1CanonicalBlockers {
    public static let d1 = SP1Blocker(
        blockedBy: "input_monitoring_denied",
        detectCommand: ["CGPreflightListenEventAccess", "environment.json guiSession.tapCreate"],
        prerequisite: "GUI session with Input Monitoring already granted for this executable",
        unblockAction: "Grant Input Monitoring outside this probe, then rerun; this probe never prompts"
    )

    private static let guiSessionDenied = SP1Blocker(
        blockedBy: "gui_session_denied",
        detectCommand: ["environment.json guiSession.status"],
        prerequisite: "An available GUI session for the listen-only event tap",
        unblockAction: "Establish an available GUI session outside this probe, then regenerate environment evidence and rerun"
    )

    private static let guiSessionUnavailable = SP1Blocker(
        blockedBy: "gui_session_unavailable",
        detectCommand: ["environment.json guiSession.status"],
        prerequisite: "An available GUI session for the listen-only event tap",
        unblockAction: "Establish an available GUI session outside this probe, then regenerate environment evidence and rerun"
    )

    private static let guiSessionUnknown = SP1Blocker(
        blockedBy: "gui_session_unknown",
        detectCommand: ["environment.json guiSession.status"],
        prerequisite: "A deterministically available GUI session for the listen-only event tap",
        unblockAction: "Resolve GUI session detection outside this probe, then regenerate environment evidence and rerun"
    )

    private static let listenEventUnavailable = SP1Blocker(
        blockedBy: "input_monitoring_unavailable",
        detectCommand: ["CGPreflightListenEventAccess", "environment.json listenEventAccess"],
        prerequisite: "Input Monitoring available for this executable",
        unblockAction: "Make Input Monitoring available outside this probe, then regenerate environment evidence and rerun; this probe never prompts"
    )

    private static let listenEventUnknown = SP1Blocker(
        blockedBy: "input_monitoring_unknown",
        detectCommand: ["CGPreflightListenEventAccess", "environment.json listenEventAccess"],
        prerequisite: "A deterministic Input Monitoring grant status for this executable",
        unblockAction: "Resolve Input Monitoring detection outside this probe, then regenerate environment evidence and rerun; this probe never prompts"
    )

    private static let tapCreateDenied = SP1Blocker(
        blockedBy: "tap_create_denied",
        detectCommand: ["environment.json guiSession.tapCreate"],
        prerequisite: "Successful creation of a listen-only event tap",
        unblockAction: "Resolve the denied listen-only tap creation prerequisite outside this probe, then regenerate environment evidence and rerun"
    )

    private static let tapCreateUnavailable = SP1Blocker(
        blockedBy: "tap_create_unavailable",
        detectCommand: ["environment.json guiSession.tapCreate"],
        prerequisite: "Successful creation of a listen-only event tap",
        unblockAction: "Make listen-only tap creation available outside this probe, then regenerate environment evidence and rerun"
    )

    private static let tapCreateUnknown = SP1Blocker(
        blockedBy: "tap_create_unknown",
        detectCommand: ["environment.json guiSession.tapCreate"],
        prerequisite: "A deterministic listen-only event tap creation status",
        unblockAction: "Resolve listen-only tap creation detection outside this probe, then regenerate environment evidence and rerun"
    )

    public static func d1Failure(for environment: EnvironmentEvidence) -> SP1Blocker? {
        switch environment.guiSession.status {
        case .denied: return guiSessionDenied
        case .unavailable: return guiSessionUnavailable
        case .unknown: return guiSessionUnknown
        case .available: break
        }
        switch environment.listenEventAccess {
        case .denied: return d1
        case .unavailable: return listenEventUnavailable
        case .unknown: return listenEventUnknown
        case .available: break
        }
        switch environment.guiSession.tapCreate {
        case .denied: return tapCreateDenied
        case .unavailable: return tapCreateUnavailable
        case .unknown: return tapCreateUnknown
        case .available: return nil
        }
    }

    public static func legacyV1Matrix(inputMonitoringUnavailable: Bool, karabinerAbsent: Bool) -> SP1Blocker {
        let reasons = [inputMonitoringUnavailable ? "input_monitoring_denied" : nil, karabinerAbsent ? "karabiner_absent" : nil].compactMap { $0 }
        return SP1Blocker(
            blockedBy: reasons.joined(separator: ";"),
            detectCommand: ["CGPreflightListenEventAccess", "environment.json applications[name=Karabiner-Elements]"],
            prerequisite: "Input Monitoring granted and a separately authorized supported Karabiner installation with controlled OFF/ON mapping",
            unblockAction: "Grant Input Monitoring and install/configure Karabiner only through separate user-authorized actions, then rerun both OFF/ON legs"
        )
    }

    public static func legacyV1Matrix(environment: EnvironmentEvidence, karabinerAbsent: Bool) -> SP1Blocker {
        guard let failure = d1Failure(for: environment) else {
            return legacyV1Matrix(inputMonitoringUnavailable: false, karabinerAbsent: karabinerAbsent)
        }
        guard failure != d1 else {
            return legacyV1Matrix(inputMonitoringUnavailable: true, karabinerAbsent: karabinerAbsent)
        }
        let reasons = [failure.blockedBy, karabinerAbsent ? "karabiner_absent" : nil].compactMap { $0 }
        return SP1Blocker(
            blockedBy: reasons.joined(separator: ";"),
            detectCommand: ["environment.json guiSession.status", "CGPreflightListenEventAccess", "environment.json guiSession.tapCreate", "environment.json applications[name=Karabiner-Elements]"],
            prerequisite: "All D1 prerequisites available and a separately authorized supported Karabiner installation with controlled OFF/ON mapping",
            unblockAction: "Satisfy the reported D1 prerequisite and install/configure Karabiner only through separate user-authorized actions, then rerun both OFF/ON legs"
        )
    }

    public static let systemShortcutExecutionNotImplemented = SP1Blocker(
        blockedBy: "system_shortcut_execution_not_implemented",
        detectCommand: ["SP1Probe system shortcut execution path"],
        prerequisite: "A live system shortcut execution and aggregate observation",
        unblockAction: "No live shortcut was executed; permissions alone cannot enable it. Implement the shortcut executor before any evidentiary run is possible"
    )

    public static let v2KarabinerAbsent = SP1Blocker(
        blockedBy: "karabiner_absent",
        detectCommand: ["CGPreflightListenEventAccess", "environment.json applications[name=Karabiner-Elements]"],
        prerequisite: "Input Monitoring granted and a supported Karabiner installation",
        unblockAction: "Satisfy the missing prerequisite in a fresh environment artifact; this probe does not alter permissions or installations"
    )

    public static let v2MatrixExecutionNotImplemented = SP1Blocker(
        blockedBy: "matrix_execution_not_implemented",
        detectCommand: ["SP1Probe OFF/ON matrix execution path"],
        prerequisite: "An implemented OFF/ON matrix executor",
        unblockAction: "Permissions and installation alone cannot enable execution; implement the matrix executor before any evidentiary run is possible"
    )

    public static let liveExecutionNotArmed = SP1Blocker(
        blockedBy: "live_execution_not_armed",
        detectCommand: ["KEYRECORD_SP1_LIVE_EXECUTION"],
        prerequisite: "Explicit live execution arming on an authorized dedicated test host",
        unblockAction: "Set KEYRECORD_SP1_LIVE_EXECUTION=1 only after Input Monitoring and isolated Karabiner prerequisites exist on the dedicated host; this probe never prompts"
    )
}

public enum SP1IsolatedKarabinerMapping {
    public static let profileName = "KeyRecord-Phase0-SP1"
    public static let expectedPhysicalCode: UInt16 = 79
    public static let expectedTransformedCode: UInt16 = 80
    public static let controlledShortcutCount = 2
}

public struct SP1TapConfiguration: Equatable, Sendable {
    public static func sha256(tapType: String) -> String {
        let object: [String: Any] = [
            "eventsOfInterest": ["flagsChanged", "keyDown", "keyUp"],
            "options": "listenOnly",
            "place": "headInsertEventTap",
            "tapType": tapType,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return AtomicityDigest.sha256(data)
    }
}

public enum SP1AttemptIdentity {
    public static func attemptID(
        runnerCommitSha: String,
        runnerTreeSha: String,
        environmentSha256: String,
        tapConfigSha256: String,
        nonce: String
    ) -> String {
        let object: [String: String] = [
            "environmentSha256": environmentSha256,
            "nonce": nonce,
            "runnerCommitSha": runnerCommitSha,
            "runnerTreeSha": runnerTreeSha,
            "tapConfigSha256": tapConfigSha256,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return AtomicityDigest.sha256(data)
    }
}

public enum SP1TapSelection {
    public static func select(sessionPasses: Bool, annotatedPasses: Bool) -> String? {
        if sessionPasses { return "session" }
        if annotatedPasses { return "annotated" }
        return nil
    }
}

public struct SP1ShortcutExecution: Equatable, Sendable {
    public var observedCount: Int
    public var absentCount: Int
    public var unmarkedCount: Int
    public var armed: Bool
    public var completed: Bool

    public init(observedCount: Int, absentCount: Int, unmarkedCount: Int, armed: Bool, completed: Bool) {
        self.observedCount = observedCount
        self.absentCount = absentCount
        self.unmarkedCount = unmarkedCount
        self.armed = armed
        self.completed = completed
    }

    public var isPass: Bool {
        armed && completed && observedCount >= 0 && absentCount >= 0
            && observedCount + absentCount == SP1IsolatedKarabinerMapping.controlledShortcutCount
    }
}

public struct SP1MatrixExecution: Equatable, Sendable {
    public var observation: TapMatrixObservation?
    public var armed: Bool
    public var completed: Bool

    public init(observation: TapMatrixObservation?, armed: Bool, completed: Bool) {
        self.observation = observation
        self.armed = armed
        self.completed = completed
    }

    public var passes: Bool { armed && completed && observation?.passes == true }
}

public enum SP1LiveArming {
    public static let environmentKey = "KEYRECORD_SP1_LIVE_EXECUTION"
    public static var isArmed: Bool { ProcessInfo.processInfo.environment[environmentKey] == "1" }
}

public struct TapMatrixObservation: Codable, Equatable, Sendable {
    public let offObservedCode: UInt16?
    public let offCount: Int
    public let onObservedCode: UInt16?
    public let onCount: Int
    public let expectedPhysicalCode: UInt16
    public let expectedTransformedCode: UInt16
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case offObservedCode, offCount, onObservedCode, onCount, expectedPhysicalCode, expectedTransformedCode }
    public init(offObservedCode: UInt16?, offCount: Int, onObservedCode: UInt16?, onCount: Int, expectedPhysicalCode: UInt16, expectedTransformedCode: UInt16) {
        self.offObservedCode = offObservedCode; self.offCount = offCount; self.onObservedCode = onObservedCode
        self.onCount = onCount; self.expectedPhysicalCode = expectedPhysicalCode; self.expectedTransformedCode = expectedTransformedCode
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "TapMatrixObservation")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        offObservedCode = try values.decodeIfPresent(UInt16.self, forKey: .offObservedCode)
        offCount = try values.decode(Int.self, forKey: .offCount)
        onObservedCode = try values.decodeIfPresent(UInt16.self, forKey: .onObservedCode)
        onCount = try values.decode(Int.self, forKey: .onCount)
        expectedPhysicalCode = try values.decode(UInt16.self, forKey: .expectedPhysicalCode)
        expectedTransformedCode = try values.decode(UInt16.self, forKey: .expectedTransformedCode)
    }
    public var passes: Bool { offObservedCode == expectedPhysicalCode && offCount == 1 && onObservedCode == expectedTransformedCode && onCount == 1 }
}

public struct SP1Leg: Codable, Equatable, Sendable {
    public var legID: String
    public var verdict: Verdict
    public var detectorAvailable: Bool
    public var blocker: SP1Blocker?
    public var identity: SelectedTapIdentity?
    public var runnerCommitSha: String
    public var runnerTreeSha: String
    public var environmentSha256: String
    public var artifactSha256: String?
    public var matrix: TapMatrixObservation?
    public var aggregateCount: Int?
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case legID, verdict, detectorAvailable, blocker, identity, runnerCommitSha, runnerTreeSha, environmentSha256, artifactSha256, matrix, aggregateCount }
    public init(legID: String, verdict: Verdict, detectorAvailable: Bool, blocker: SP1Blocker?, identity: SelectedTapIdentity?, runnerCommitSha: String, runnerTreeSha: String, environmentSha256: String, artifactSha256: String?, matrix: TapMatrixObservation?, aggregateCount: Int?) {
        self.legID = legID; self.verdict = verdict; self.detectorAvailable = detectorAvailable; self.blocker = blocker
        self.identity = identity; self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha
        self.environmentSha256 = environmentSha256; self.artifactSha256 = artifactSha256; self.matrix = matrix; self.aggregateCount = aggregateCount
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP1Leg")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        legID = try values.decode(String.self, forKey: .legID)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        detectorAvailable = try values.decode(Bool.self, forKey: .detectorAvailable)
        blocker = try values.decodeIfPresent(SP1Blocker.self, forKey: .blocker)
        identity = try values.decodeIfPresent(SelectedTapIdentity.self, forKey: .identity)
        runnerCommitSha = try values.decode(String.self, forKey: .runnerCommitSha)
        runnerTreeSha = try values.decode(String.self, forKey: .runnerTreeSha)
        environmentSha256 = try values.decode(String.self, forKey: .environmentSha256)
        artifactSha256 = try values.decodeIfPresent(String.self, forKey: .artifactSha256)
        matrix = try values.decodeIfPresent(TapMatrixObservation.self, forKey: .matrix)
        aggregateCount = try values.decodeIfPresent(Int.self, forKey: .aggregateCount)
    }
}

public enum SP1ValidationError: String, Error, Codable, Equatable {
    case duplicateLeg, missingLeg, invalidBlocker, invalidSelection, mixedIdentity, reusedEvidence, invalidMatrix, invalidAggregate, invalidO7, invalidProvenance
}

public struct SP1Evidence: Codable, Equatable, Sendable {
    public static let requiredLegIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix", "sp1.systemShortcut", "sp1.autoRepeat", "sp1.productStampedDrop", "sp1.tapReset", "sp1.o7Boundary"]
    public var schemaVersion = 1
    public var selectedTapIdentity: SelectedTapIdentity?
    public var legs: [SP1Leg]
    public var verdict: Verdict
    public var g0Status: G0Status
    public var o7Guarantee: String
    public var runnerSourceSha256: [String: String]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case schemaVersion, selectedTapIdentity, legs, verdict, g0Status, o7Guarantee, runnerSourceSha256 }
    public init(selectedTapIdentity: SelectedTapIdentity?, legs: [SP1Leg], verdict: Verdict, g0Status: G0Status, o7Guarantee: String, runnerSourceSha256: [String: String]) {
        self.selectedTapIdentity = selectedTapIdentity; self.legs = legs; self.verdict = verdict; self.g0Status = g0Status
        self.o7Guarantee = o7Guarantee; self.runnerSourceSha256 = runnerSourceSha256
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP1Evidence")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        selectedTapIdentity = try values.decodeIfPresent(SelectedTapIdentity.self, forKey: .selectedTapIdentity)
        legs = try values.decode([SP1Leg].self, forKey: .legs)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        g0Status = try values.decode(G0Status.self, forKey: .g0Status)
        o7Guarantee = try values.decode(String.self, forKey: .o7Guarantee)
        runnerSourceSha256 = try values.decode([String: String].self, forKey: .runnerSourceSha256)
    }

    public func validate(candidateEnvironmentSha256: String? = nil) throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        if grouped.values.contains(where: { $0.count != 1 }) { throw SP1ValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP1ValidationError.missingLeg }
        guard schemaVersion == 1 || schemaVersion == 2 || schemaVersion == 3, g0Status == .open, o7Guarantee == O7Boundary.guarantee else { throw SP1ValidationError.invalidO7 }
        guard !runnerSourceSha256.isEmpty, runnerSourceSha256.values.allSatisfy(\.isLowercaseSHA256) else { throw SP1ValidationError.invalidProvenance }
        guard Set(legs.map(\.runnerCommitSha)).count == 1,
              Set(legs.map(\.runnerTreeSha)).count == 1,
              Set(legs.map(\.environmentSha256)).count == 1 else { throw SP1ValidationError.mixedIdentity }
        if let candidateEnvironmentSha256 {
            guard legs.first?.environmentSha256 == candidateEnvironmentSha256 else { throw SP1ValidationError.mixedIdentity }
        }
        for leg in legs {
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1, leg.environmentSha256.isLowercaseSHA256 else { throw SP1ValidationError.invalidProvenance }
            if leg.verdict == .blocked {
                guard !leg.detectorAvailable, leg.blocker?.complete == true, leg.identity == nil, leg.artifactSha256 == nil, leg.matrix == nil, leg.aggregateCount == nil else { throw SP1ValidationError.invalidBlocker }
            } else {
                guard leg.detectorAvailable, leg.blocker == nil, leg.artifactSha256?.isLowercaseSHA256 == true else { throw SP1ValidationError.invalidProvenance }
            }
        }
        let artifactOwners = Dictionary(grouping: legs.compactMap { leg -> (hash: String, leg: SP1Leg)? in
            guard leg.verdict != .blocked, let hash = leg.artifactSha256 else { return nil }
            return (hash, leg)
        }, by: \.hash)
        for owners in artifactOwners.values where owners.count > 1 {
            let synthetic = owners.allSatisfy { Self.syntheticLegIDs.contains($0.leg.legID) }
            let live = owners.allSatisfy { !Self.syntheticLegIDs.contains($0.leg.legID) }
            if schemaVersion == 2, synthetic { continue }
            if schemaVersion == 3, synthetic || live { continue }
            throw SP1ValidationError.reusedEvidence
        }
        let passingMatrices = legs.filter { Self.matrixIDs.contains($0.legID) && $0.verdict == .pass }
        if selectedTapIdentity == nil {
            guard passingMatrices.isEmpty else { throw SP1ValidationError.invalidSelection }
            guard verdict == Self.aggregate(legs.map(\.verdict)) else { throw SP1ValidationError.invalidAggregate }
        } else {
            guard let selected = selectedTapIdentity else { throw SP1ValidationError.invalidSelection }
            let selectedLegID = "sp1.tap.\(selected.tapType).matrix"
            guard let selectedLeg = legs.first(where: { $0.legID == selectedLegID }),
                  selectedLeg.verdict == .pass, selectedLeg.matrix?.passes == true else {
                throw SP1ValidationError.invalidMatrix
            }
            guard !selected.tapType.isEmpty, !selected.attemptID.isEmpty, selected.runnerCommitSha.isLowercaseGitSHA1,
                  selected.runnerTreeSha.isLowercaseGitSHA1, selected.environmentSha256.isLowercaseSHA256,
                  selected.tapConfigSha256.isLowercaseSHA256 else { throw SP1ValidationError.invalidProvenance }
            let bound = legs.filter { $0.legID == selectedLegID || !Self.matrixIDs.contains($0.legID) }
            for leg in bound {
                guard leg.identity == selected,
                      leg.runnerCommitSha == selected.runnerCommitSha, leg.runnerTreeSha == selected.runnerTreeSha,
                      leg.environmentSha256 == selected.environmentSha256 else { throw SP1ValidationError.mixedIdentity }
            }
            guard verdict == Self.aggregate(bound.map(\.verdict)) else { throw SP1ValidationError.invalidAggregate }
        }
    }
    private static let matrixIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]
    private static let syntheticLegIDs: Set<String> = ["sp1.autoRepeat", "sp1.o7Boundary", "sp1.productStampedDrop", "sp1.tapReset"]
    private static func aggregate(_ verdicts: [Verdict]) -> Verdict {
        verdicts.max { precedence($0) < precedence($1) } ?? .blocked
    }
    private static func precedence(_ verdict: Verdict) -> Int {
        switch verdict { case .pass: 0; case .inconclusive: 1; case .blocked: 2; case .fail: 3 }
    }
}

public enum SP1CanonicalArtifacts {
    public static let v1Synthetic: Data = Data(("""
    {
      "evidenceKind" : "synthetic",
      "productStampedSynthetic" : true,
      "records" : [
        {
          "dropped" : true,
          "isAutoRepeat" : false,
          "keyCode" : 4,
          "kind" : "keyDown",
          "marker" : 5427492104824964435
        },
        {
          "dropped" : true,
          "isAutoRepeat" : false,
          "keyCode" : 4,
          "kind" : "keyUp",
          "marker" : 5427492104824964435
        },
        {
          "dropped" : true,
          "isAutoRepeat" : false,
          "keyCode" : 4,
          "kind" : "flagsChanged",
          "marker" : 5427492104824964435
        }
      ]
    }
    """ + "\n").utf8)
}

public enum SP1CanonicalNarratives {
    public static func o7() -> Data {
        Data(("# O7 addendum\n\n" + O7Boundary.guarantee + "\n\nNo source-field exclusion beyond aggregate observation is claimed.\n").utf8)
    }

    public static func conclusion(for evidence: SP1Evidence) -> Data {
        let legs = evidence.legs.sorted { $0.legID < $1.legID }.map { "- `\($0.legID)`: \($0.verdict.rawValue) (`\($0.blocker?.blockedBy ?? "executed")`)" }.joined(separator: "\n")
        return Data("# SP-1 conclusion\n\nVerdict: **\(evidence.verdict.rawValue)**\n\nSelected tap identity: **NONE**\n\nG0: **OPEN**\n\nHID tap is unavailable to a normal non-root menu-bar process and was not attempted. Session and annotated-session candidates are listen-only. No live assertion was inferred from an unexecuted check.\n\n\(legs)\n".utf8)
    }
}

public enum SP1RunnerBinding {
    public static let sourcePaths: Set<String> = [
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityProbe.swift",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
        "Spikes/Sources/Phase0Probe/SP1Probe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/AtomicReplacement.swift",
        "Spikes/Sources/Phase0Support/AtomicityEvidence.swift",
        "Spikes/Sources/Phase0Support/InputObservation.swift",
    ]
}

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
    public init(kind: InputEventKind, keyCode: UInt16, isAutoRepeat: Bool, marker: UInt64?) {
        self.kind = kind; self.keyCode = keyCode; self.isAutoRepeat = isAutoRepeat; self.marker = marker
    }
}

public struct ProductStampedRecord: Codable, Equatable, Sendable {
    public let kind: InputEventKind
    public let keyCode: UInt16
    public let isAutoRepeat: Bool
    public let marker: UInt64
    public let dropped: Bool
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

public struct SelectedTapIdentity: Codable, Equatable, Sendable {
    public var tapType: String
    public var attemptID: String
    public var runnerCommitSha: String
    public var runnerTreeSha: String
    public var environmentSha256: String
    public var tapConfigSha256: String
    enum CodingKeys: String, CodingKey {
        case tapType, attemptID = "attemptId", runnerCommitSha, runnerTreeSha, environmentSha256, tapConfigSha256
    }
    public init(tapType: String, attemptID: String, runnerCommitSha: String, runnerTreeSha: String, environmentSha256: String, tapConfigSha256: String) {
        self.tapType = tapType; self.attemptID = attemptID; self.runnerCommitSha = runnerCommitSha
        self.runnerTreeSha = runnerTreeSha; self.environmentSha256 = environmentSha256; self.tapConfigSha256 = tapConfigSha256
    }
}

public struct SP1Blocker: Codable, Equatable, Sendable {
    public let blockedBy: String
    public let detectCommand: [String]
    public let prerequisite: String
    public let unblockAction: String
    enum CodingKeys: String, CodingKey { case blockedBy = "blocked_by", detectCommand = "detect_command", prerequisite, unblockAction = "unblock_action" }
    public init(blockedBy: String, detectCommand: [String], prerequisite: String, unblockAction: String) {
        self.blockedBy = blockedBy; self.detectCommand = detectCommand; self.prerequisite = prerequisite; self.unblockAction = unblockAction
    }
    var complete: Bool { !blockedBy.isEmpty && !detectCommand.isEmpty && detectCommand.allSatisfy { !$0.isEmpty } && !prerequisite.isEmpty && !unblockAction.isEmpty }
}

public struct TapMatrixObservation: Codable, Equatable, Sendable {
    public let offObservedCode: UInt16?
    public let offCount: Int
    public let onObservedCode: UInt16?
    public let onCount: Int
    public let expectedPhysicalCode: UInt16
    public let expectedTransformedCode: UInt16
    public init(offObservedCode: UInt16?, offCount: Int, onObservedCode: UInt16?, onCount: Int, expectedPhysicalCode: UInt16, expectedTransformedCode: UInt16) {
        self.offObservedCode = offObservedCode; self.offCount = offCount; self.onObservedCode = onObservedCode
        self.onCount = onCount; self.expectedPhysicalCode = expectedPhysicalCode; self.expectedTransformedCode = expectedTransformedCode
    }
    var passes: Bool { offObservedCode == expectedPhysicalCode && offCount == 1 && onObservedCode == expectedTransformedCode && onCount == 1 }
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
    public init(legID: String, verdict: Verdict, detectorAvailable: Bool, blocker: SP1Blocker?, identity: SelectedTapIdentity?, runnerCommitSha: String, runnerTreeSha: String, environmentSha256: String, artifactSha256: String?, matrix: TapMatrixObservation?, aggregateCount: Int?) {
        self.legID = legID; self.verdict = verdict; self.detectorAvailable = detectorAvailable; self.blocker = blocker
        self.identity = identity; self.runnerCommitSha = runnerCommitSha; self.runnerTreeSha = runnerTreeSha
        self.environmentSha256 = environmentSha256; self.artifactSha256 = artifactSha256; self.matrix = matrix; self.aggregateCount = aggregateCount
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
    public init(selectedTapIdentity: SelectedTapIdentity?, legs: [SP1Leg], verdict: Verdict, g0Status: G0Status, o7Guarantee: String, runnerSourceSha256: [String: String]) {
        self.selectedTapIdentity = selectedTapIdentity; self.legs = legs; self.verdict = verdict; self.g0Status = g0Status
        self.o7Guarantee = o7Guarantee; self.runnerSourceSha256 = runnerSourceSha256
    }

    public func validate() throws {
        let grouped = Dictionary(grouping: legs, by: \.legID)
        if grouped.values.contains(where: { $0.count != 1 }) { throw SP1ValidationError.duplicateLeg }
        guard Set(grouped.keys) == Self.requiredLegIDs else { throw SP1ValidationError.missingLeg }
        guard schemaVersion == 1, g0Status == .open, o7Guarantee == O7Boundary.guarantee else { throw SP1ValidationError.invalidO7 }
        guard !runnerSourceSha256.isEmpty, runnerSourceSha256.values.allSatisfy(\.isLowercaseSHA256) else { throw SP1ValidationError.invalidProvenance }
        for leg in legs {
            guard leg.runnerCommitSha.isLowercaseGitSHA1, leg.runnerTreeSha.isLowercaseGitSHA1, leg.environmentSha256.isLowercaseSHA256 else { throw SP1ValidationError.invalidProvenance }
            if leg.verdict == .blocked {
                guard !leg.detectorAvailable, leg.blocker?.complete == true, leg.identity == nil, leg.artifactSha256 == nil, leg.matrix == nil else { throw SP1ValidationError.invalidBlocker }
            }
        }
        let passingMatrices = legs.filter { Self.matrixIDs.contains($0.legID) && $0.verdict == .pass }
        if selectedTapIdentity == nil {
            guard verdict != .pass, passingMatrices.isEmpty, legs.contains(where: { $0.verdict != .pass }) else { throw SP1ValidationError.invalidSelection }
            return
        }
        guard verdict == .pass, passingMatrices.count == 1, let selected = selectedTapIdentity, passingMatrices[0].matrix?.passes == true else { throw SP1ValidationError.invalidMatrix }
        guard !selected.tapType.isEmpty, !selected.attemptID.isEmpty, selected.runnerCommitSha.isLowercaseGitSHA1,
              selected.runnerTreeSha.isLowercaseGitSHA1, selected.environmentSha256.isLowercaseSHA256,
              selected.tapConfigSha256.isLowercaseSHA256 else { throw SP1ValidationError.invalidProvenance }
        let selectedLegID = "sp1.tap.\(selected.tapType).matrix"
        guard passingMatrices[0].legID == selectedLegID else { throw SP1ValidationError.invalidSelection }
        let bound = legs.filter { $0.legID == selectedLegID || !Self.matrixIDs.contains($0.legID) }
        var hashes = Set<String>()
        for leg in bound {
            guard leg.verdict == .pass, leg.identity == selected,
                  leg.runnerCommitSha == selected.runnerCommitSha, leg.runnerTreeSha == selected.runnerTreeSha,
                  leg.environmentSha256 == selected.environmentSha256 else { throw SP1ValidationError.mixedIdentity }
            guard let hash = leg.artifactSha256, hash.isLowercaseSHA256 else { throw SP1ValidationError.invalidProvenance }
            guard hashes.insert(hash).inserted else { throw SP1ValidationError.reusedEvidence }
        }
    }
    private static let matrixIDs: Set<String> = ["sp1.tap.session.matrix", "sp1.tap.annotated.matrix"]
}

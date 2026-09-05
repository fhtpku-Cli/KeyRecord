import Foundation

public struct SP4BRoundTripArtifact: Codable, Equatable, Sendable {
    public let fixtureKind: String
    public let fixturePath: String
    public let fixtureSha256: String
    public let fixtureByteCount: Int
    public let noTrailingNewline: Bool
    public let selectedSlot: [Int]
    public let beforeValue: String
    public let afterValue: String
    public let outputSha256: String
    public let bytesOutsideSelectedSlotIdentical: Bool
    public let nonSelectedContentPreserved: Bool
    public let opaqueSha256Before: [String: String]
    public let opaqueSha256After: [String: String]
}

public struct SP4BBoundResult: Codable, Equatable, Sendable {
    public let limit: String
    public let maximum: Int
    public let exactAccepted: Bool
    public let plusOneError: ViaLayoutError
}

public struct SP4BBoundsArtifact: Codable, Equatable, Sendable {
    public let countingRule: String
    public let results: [SP4BBoundResult]
}

public enum SP4BAxisID: String, Codable, CaseIterable, Sendable {
    case definitionSchema, deviceProtocol, layoutFormat, keycodeDialect, officialImporterCompatibility
}

public struct SP4BAxisEvidence: Codable, Equatable, Sendable {
    public let artifactPath: String
    public let artifactSha256: String
    public let claim: String
}

public struct SP4BAxisResult: Codable, Equatable, Sendable {
    public let axisID: SP4BAxisID
    public let verdict: Verdict
    public let evidence: SP4BAxisEvidence?
    public let blocker: SP1Blocker?
}

public struct SP4BAxesArtifact: Codable, Equatable, Sendable {
    public let axes: [SP4BAxisResult]
    public let firmwareDependentProtocolAndKeycodeDictionaries: Bool
    public let viaProtocol13VialGUICompatible: Bool
}

public struct SP4BSourceCitation: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
}

public struct SP4BSourceFactsArtifact: Codable, Equatable, Sendable {
    public let layoutContract: String
    public let protocolAndKeycodeContract: String
    public let vialCompatibility: String
    public let citations: [SP4BSourceCitation]
    public let excludedClaims: [String]
}

public enum SP4BScenarios {
    public static let fixturePath = "evidence/phase0/fixtures/synthetic/via-layout.json"
    public static let fixtureSha256 = "4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800"
    public static let compatibility = ViaLayoutCompatibility(
        vendorProductID: 1_980_457_056, layerSlotCounts: [2, 2], macroCount: 1, viaProtocol: 13,
        keycodeDialect: "qmk-via-protocol-13", supportedKeycodes: ["KC_A", "KC_B", "KC_C", "KC_D", "KC_ESC"]
    )

    public static func roundTrip(repository: URL) throws -> SP4BRoundTripArtifact {
        let bytes = try boundedFile(repository.appendingPathComponent(fixturePath))
        guard ViaDefinitionDigest.sha256(bytes) == fixtureSha256 else { throw SP4BScenarioError.fixtureHashMismatch }
        let document = try ViaLayoutParser.parse(bytes)
        let before = try required(document.slotValue(layer: 0, slot: 1))
        let preserved = [
            try required(document.slotValue(layer: 0, slot: 0)),
            try required(document.slotValue(layer: 1, slot: 0)),
            try required(document.slotValue(layer: 1, slot: 1)),
        ]
        let beforeHashes = try opaqueHashes(document)
        let patch = try document.patchSelectedSlot(
            layer: 0, slot: 1, replacement: "KC_ESC", compatibility: compatibility,
            observedProtocol: 13, observedKeycodeDialect: "qmk-via-protocol-13"
        )
        let reparsed = try ViaLayoutParser.parse(patch.bytes)
        let afterHashes = try opaqueHashes(reparsed)
        return SP4BRoundTripArtifact(
            fixtureKind: "synthetic", fixturePath: fixturePath, fixtureSha256: fixtureSha256,
            fixtureByteCount: bytes.count, noTrailingNewline: bytes.last != 10, selectedSlot: [0, 1],
            beforeValue: before, afterValue: try required(reparsed.slotValue(layer: 0, slot: 1)),
            outputSha256: ViaDefinitionDigest.sha256(patch.bytes),
            bytesOutsideSelectedSlotIdentical: patch.bytesOutsideSelectedSlotIdentical,
            nonSelectedContentPreserved: preserved == [
                try required(reparsed.slotValue(layer: 0, slot: 0)),
                try required(reparsed.slotValue(layer: 1, slot: 0)),
                try required(reparsed.slotValue(layer: 1, slot: 1)),
            ], opaqueSha256Before: beforeHashes, opaqueSha256After: afterHashes
        )
    }

    public static func bounds() throws -> SP4BBoundsArtifact {
        let cases: [(String, Int, Data, Data, ViaLayoutError)] = [
            ("inputBytes", ViaDefinitionLimits.maximumInputBytes, input(ViaDefinitionLimits.maximumInputBytes), input(ViaDefinitionLimits.maximumInputBytes + 1), .inputTooLarge),
            ("depth", ViaDefinitionLimits.maximumDepth, nested(ViaDefinitionLimits.maximumDepth), nested(ViaDefinitionLimits.maximumDepth + 1), .depthExceeded),
            ("collectionElements", ViaDefinitionLimits.maximumCollectionElements, collection(ViaDefinitionLimits.maximumCollectionElements), collection(ViaDefinitionLimits.maximumCollectionElements + 1), .collectionElementsExceeded),
            ("scalarBytes", ViaDefinitionLimits.maximumScalarBytes, scalar(ViaDefinitionLimits.maximumScalarBytes), scalar(ViaDefinitionLimits.maximumScalarBytes + 1), .scalarTooLarge),
        ]
        let results = try cases.map { item -> SP4BBoundResult in
            _ = try ViaLayoutParser.parse(item.2)
            do { _ = try ViaLayoutParser.parse(item.3); throw SP4BScenarioError.plusOneAccepted }
            catch let error as ViaLayoutError {
                guard error == item.4 else { throw SP4BScenarioError.wrongBoundError }
                return .init(limit: item.0, maximum: item.1, exactAccepted: true, plusOneError: error)
            }
        }
        return .init(
            countingRule: "root container depth is 1; every object member and array element counts toward one aggregate collection limit; scalar bytes exclude JSON string quotes",
            results: results
        )
    }

    public static func axes(repository: URL) throws -> SP4BAxesArtifact {
        let sp4a = repository.appendingPathComponent("evidence/phase0/sp4a/evidence.json")
        let layout = repository.appendingPathComponent(fixturePath)
        let blockedDevice = SP1Blocker(
            blockedBy: "approved_via_device_absent", detectCommand: ["environment-inventory", "approved-via-device"],
            prerequisite: "an explicitly approved VIA-capable keyboard and separately authorized non-mutating protocol procedure",
            unblockAction: "Inventory and approve a VIA keyboard, then capture protocol and firmware-selected keycode dictionary without writing the device"
        )
        let importer = SP1Blocker(
            blockedBy: "via_app_absent_and_approved_device_absent", detectCommand: ["environment-inventory", "VIA"],
            prerequisite: "official VIA app installed plus an explicitly approved matching keyboard under a separate import procedure",
            unblockAction: "Install official VIA and approve a matching device, then test import separately without exporting a deployment"
        )
        return SP4BAxesArtifact(axes: [
            .init(axisID: .definitionSchema, verdict: .pass, evidence: evidence(sp4a, repository, "SP-4A independently characterizes V2/V3 definition schema only"), blocker: nil),
            .init(axisID: .deviceProtocol, verdict: .blocked, evidence: nil, blocker: blockedDevice),
            .init(axisID: .layoutFormat, verdict: .pass, evidence: evidence(layout, repository, "exact deterministic synthetic layout exercises the unversioned layout shape only"), blocker: nil),
            .init(axisID: .keycodeDialect, verdict: .blocked, evidence: nil, blocker: blockedDevice),
            .init(axisID: .officialImporterCompatibility, verdict: .blocked, evidence: nil, blocker: importer),
        ], firmwareDependentProtocolAndKeycodeDictionaries: true, viaProtocol13VialGUICompatible: false)
    }

    public static func sourceFacts(repository: URL) throws -> SP4BSourceFactsArtifact {
        let citations = [
            SP4BSourceCitation(path: "evidence/phase0/sources/repos/via-app/files/src/components/panes/configure-panes/save-load.tsx", sha256: "b2b37026eff7dba3011305613858b00d64d0f3075909b5b80f06b7904550c7b2"),
            SP4BSourceCitation(path: "evidence/phase0/sources/repos/qmk/files/quantum/via.h", sha256: "fdf2231eb0ba8699019b973ba68b685a9782b2fff87be6827bd899e299b76b1a"),
            SP4BSourceCitation(path: "evidence/phase0/sources/repos/vial-gui/files/src/main/python/protocol/keyboard_comm.py", sha256: "d71b73a6217c5d12a05ff0cd3c85ea06b8f9df798cfb5f1a783207af4623ecdb"),
        ]
        for citation in citations where ViaDefinitionDigest.sha256(try boundedFile(repository.appendingPathComponent(citation.path))) != citation.sha256 {
            throw SP4BScenarioError.sourceDrift
        }
        return .init(
            layoutContract: "Pinned VIA app saves an unversioned .layout.json object with name, vendorProductId, layers, optional macros, and optional encoders; it checks keyboard ID and layer/macro shapes before device writes.",
            protocolAndKeycodeContract: "Protocol and keycode dictionaries are firmware-dependent; protocol 13 selects a per-device QMK keycode dictionary.",
            vialCompatibility: "QMK VIA_PROTOCOL_VERSION 0x000D is protocol 13; pinned Vial GUI accepts only VIA protocols -1 and 9, so VIA protocol 13 is not Vial-GUI compatible.",
            citations: citations,
            excludedClaims: ["stable interchange standard", "official importer compatibility", "device compatibility", "device behavior", "deployment export"]
        )
    }

    public static func validates(_ value: SP4BRoundTripArtifact) -> Bool {
        value.fixtureKind == "synthetic" && value.fixtureSha256 == fixtureSha256 && value.fixtureByteCount == 124
            && value.noTrailingNewline && value.selectedSlot == [0, 1] && value.beforeValue == "KC_B" && value.afterValue == "KC_ESC"
            && value.bytesOutsideSelectedSlotIdentical && value.nonSelectedContentPreserved
            && value.opaqueSha256Before == value.opaqueSha256After
    }

    private static func evidence(_ url: URL, _ repository: URL, _ claim: String) -> SP4BAxisEvidence {
        let relative = url.path.replacingOccurrences(of: repository.path + "/", with: "")
        let data = (try? Data(contentsOf: url)) ?? Data()
        return .init(artifactPath: relative, artifactSha256: ViaDefinitionDigest.sha256(data), claim: claim)
    }
    private static func required(_ value: String?) throws -> String { guard let value else { throw SP4BScenarioError.valueMissing }; return value }
    private static func opaqueHashes(_ value: ViaLayoutDocument) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: ["macros", "encoders"].map { key in
            guard let bytes = value.rawSlice(named: key) else { throw SP4BScenarioError.valueMissing }
            return (key, ViaDefinitionDigest.sha256(bytes))
        })
    }
    private static func boundedFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= ViaDefinitionLimits.maximumInputBytes else { throw SP4BScenarioError.invalidFile }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private static func input(_ count: Int) -> Data { let base = Data(#"{"name":"x","vendorProductId":1,"layers":[["KC_A"]]}"#.utf8); return base + Data(repeating: 0x20, count: max(count - base.count, 0)) }
    private static func nested(_ depth: Int) -> Data { Data((#"{"name":"x","vendorProductId":1,"layers":[["KC_A"]],"future":"# + String(repeating: "[", count: max(depth - 1, 0)) + "0" + String(repeating: "]", count: max(depth - 1, 0)) + "}").utf8) }
    private static func collection(_ count: Int) -> Data { Data((#"{"name":"x","vendorProductId":1,"layers":[["# + Array(repeating: #""KC_A""#, count: max(count - 4, 0)).joined(separator: ",") + "]]}").utf8) }
    private static func scalar(_ count: Int) -> Data { Data((#"{"name":""# + String(repeating: "a", count: count) + #"","vendorProductId":1,"layers":[["KC_A"]]}"#).utf8) }
}

public enum SP4BScenarioError: Error, Equatable {
    case fixtureHashMismatch, invalidFile, plusOneAccepted, sourceDrift, valueMissing, wrongBoundError
}

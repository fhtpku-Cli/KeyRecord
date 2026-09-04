import Foundation

public struct SP5ARoundTripArtifact: Codable, Equatable, Sendable {
    public let fixtureKind: String
    public let fixturePath: String
    public let fixtureSha256: String
    public let fixtureByteCount: Int
    public let noTrailingNewline: Bool
    public let version: Int
    public let uid: String
    public let selectedSlot: [Int]
    public let beforeValue: String
    public let afterValue: String
    public let outputSha256: String
    public let bytesOutsideSelectedSlotIdentical: Bool
    public let nonSelectedSlotPreserved: Bool
    public let unsupportedFieldSha256Before: [String: String]
    public let unsupportedFieldSha256After: [String: String]
    public let allUnsupportedFieldsPreserved: Bool
}

public struct SP5AUIDArtifact: Codable, Equatable, Sendable {
    public let fixtureUID: String
    public let matchingUIDAccepted: Bool
    public let mismatchedUID: String
    public let mismatchDisposition: String
    public let mismatchError: VialDocumentError
    public let mismatchVerified: Bool
}

public struct SP5ABoundResult: Codable, Equatable, Sendable {
    public let limit: String
    public let maximum: Int
    public let exactAccepted: Bool
    public let plusOneError: VialDocumentError
}

public struct SP5ABoundsArtifact: Codable, Equatable, Sendable {
    public let countingRule: String
    public let results: [SP5ABoundResult]
}

public struct SP5ASourceCitation: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
}

public struct SP5AFormatFactsArtifact: Codable, Equatable, Sendable {
    public let exportContract: String
    public let uidContract: String
    public let vialJSONClassification: String
    public let interchangeability: String
    public let citations: [SP5ASourceCitation]
    public let excludedClaims: [String]
}

public enum SP5AFixtureScenarios {
    public static let fixturePath = "evidence/phase0/fixtures/synthetic/phase0.vil"
    public static let fixtureSha256 = "61a93eac2421c9cbe1b0f81625f3d01f3ca9443645b4d9ba86c1f5237af633b3"
    public static let uid = "0000000000000000"
    public static let unsupportedFields = ["alt_repeat_key", "combo", "encoder_layout", "key_override", "layout_options", "macro", "settings", "tap_dance", "via_protocol", "vial_protocol"]

    public static func roundTrip(repository: URL) throws -> SP5ARoundTripArtifact {
        let bytes = try boundedFile(repository.appendingPathComponent(fixturePath), maximum: VialDocumentLimits.maximumInputBytes)
        guard ViaDefinitionDigest.sha256(bytes) == fixtureSha256 else { throw SP5AScenarioError.fixtureHashMismatch }
        let document = try VialDocumentParser.parse(bytes)
        let before = try requiredValue(document.layoutValue(layer: 0, row: 0, column: 1))
        let nonSelected = try requiredValue(document.layoutValue(layer: 0, row: 0, column: 0))
        let beforeHashes = try rawHashes(document)
        let plan = try document.patchLayoutSlot(layer: 0, row: 0, column: 1, replacement: "KC_ESC", expectedUID: uid)
        let reparsed = try VialDocumentParser.parse(plan.bytes)
        let afterHashes = try rawHashes(reparsed)
        return SP5ARoundTripArtifact(
            fixtureKind: "synthetic", fixturePath: fixturePath, fixtureSha256: fixtureSha256,
            fixtureByteCount: bytes.count, noTrailingNewline: bytes.last != 10, version: document.version, uid: document.uid,
            selectedSlot: [0, 0, 1], beforeValue: before, afterValue: try requiredValue(reparsed.layoutValue(layer: 0, row: 0, column: 1)),
            outputSha256: ViaDefinitionDigest.sha256(plan.bytes), bytesOutsideSelectedSlotIdentical: plan.bytesOutsideSelectedSlotIdentical,
            nonSelectedSlotPreserved: reparsed.layoutValue(layer: 0, row: 0, column: 0) == nonSelected,
            unsupportedFieldSha256Before: beforeHashes, unsupportedFieldSha256After: afterHashes,
            allUnsupportedFieldsPreserved: beforeHashes == afterHashes
        )
    }

    public static func uidBinding(repository: URL) throws -> SP5AUIDArtifact {
        let document = try VialDocumentParser.parse(try boundedFile(repository.appendingPathComponent(fixturePath), maximum: VialDocumentLimits.maximumInputBytes))
        _ = try document.patchLayoutSlot(layer: 0, row: 0, column: 1, replacement: "KC_ESC", expectedUID: uid)
        let mismatched = "FFFFFFFFFFFFFFFF"
        do {
            _ = try document.patchLayoutSlot(layer: 0, row: 0, column: 1, replacement: "KC_ESC", expectedUID: mismatched)
            throw SP5AScenarioError.uidMismatchAccepted
        } catch let error as VialDocumentError {
            guard error == .uidMismatch else { throw SP5AScenarioError.wrongUIDError }
        }
        return SP5AUIDArtifact(
            fixtureUID: document.uid, matchingUIDAccepted: true, mismatchedUID: mismatched,
            mismatchDisposition: "rejected-with-warning-required", mismatchError: .uidMismatch, mismatchVerified: false
        )
    }

    public static func bounds() throws -> SP5ABoundsArtifact {
        let cases: [(String, Int, Data, Data, VialDocumentError)] = [
            ("inputBytes", VialDocumentLimits.maximumInputBytes, input(bytes: VialDocumentLimits.maximumInputBytes), input(bytes: VialDocumentLimits.maximumInputBytes + 1), .inputTooLarge),
            ("depth", VialDocumentLimits.maximumDepth, nested(depth: VialDocumentLimits.maximumDepth), nested(depth: VialDocumentLimits.maximumDepth + 1), .depthExceeded),
            ("collectionElements", VialDocumentLimits.maximumCollectionElements, collection(elements: VialDocumentLimits.maximumCollectionElements), collection(elements: VialDocumentLimits.maximumCollectionElements + 1), .collectionElementsExceeded),
            ("scalarBytes", VialDocumentLimits.maximumScalarBytes, scalar(bytes: VialDocumentLimits.maximumScalarBytes), scalar(bytes: VialDocumentLimits.maximumScalarBytes + 1), .scalarTooLarge),
        ]
        let results = try cases.map { item -> SP5ABoundResult in
            _ = try VialDocumentParser.parse(item.2)
            do { _ = try VialDocumentParser.parse(item.3); throw SP5AScenarioError.plusOneAccepted }
            catch let error as VialDocumentError {
                guard error == item.4 else { throw SP5AScenarioError.wrongBoundError }
                return SP5ABoundResult(limit: item.0, maximum: item.1, exactAccepted: true, plusOneError: error)
            }
        }
        return SP5ABoundsArtifact(
            countingRule: "root container depth is 1; every object member and array element counts toward one aggregate collection limit; scalar bytes exclude JSON string quotes",
            results: results
        )
    }

    public static func sourceFacts(repository: URL) throws -> SP5AFormatFactsArtifact {
        let citations = [
            SP5ASourceCitation(path: "evidence/phase0/sources/repos/vial-gui/files/src/main/python/protocol/keyboard_comm.py", sha256: "d71b73a6217c5d12a05ff0cd3c85ea06b8f9df798cfb5f1a783207af4623ecdb"),
            SP5ASourceCitation(path: "evidence/phase0/sources/repos/vial-gui/files/src/main/python/editor/keymap_editor.py", sha256: "5266420876959c83bf4f2d7c5db177170a67a368e028f6b0813b3d1e9e6e03e1"),
            SP5ASourceCitation(path: "evidence/phase0/sources/repos/vial-qmk/files/util/vial_generate_definition.py", sha256: "ecd4b1ffeae61a1918ef704eff47f67e2f55ec48944a34a357af6a48abd4caae"),
            SP5ASourceCitation(path: "evidence/phase0/sources/repos/vial-qmk/files/keyboards/vial_example/vial_rp2040/keymaps/vial/vial.json", sha256: "09bdbe2ced2496af1ac7f0e7bf20956acc76b861670afe890b62f53bf512f711"),
        ]
        for citation in citations {
            guard ViaDefinitionDigest.sha256(try boundedFile(repository.appendingPathComponent(citation.path), maximum: VialDocumentLimits.maximumInputBytes)) == citation.sha256 else {
                throw SP5AScenarioError.sourceDrift
            }
        }
        return SP5AFormatFactsArtifact(
            exportContract: "Pinned Vial GUI save_layout emits a JSON version-1 keymap export containing UID, layout, encoder layout, options, macros, protocol values, advanced fields, and settings.",
            uidContract: "Pinned Vial GUI compares the export UID with the connected keyboard UID and warns before any restore on mismatch.",
            vialJSONClassification: "vial.json is a firmware-embedded keyboard definition consumed by the Vial QMK definition generator.",
            interchangeability: "vial.json is not interchangeable with a .vil keymap export or a VIA definition.",
            citations: citations,
            excludedClaims: ["official importer compatibility", "device compatibility", "device behavior", "HID interaction", "firmware write", "real-device verification"]
        )
    }

    public static func validates(_ artifact: SP5ARoundTripArtifact) -> Bool {
        artifact.fixtureKind == "synthetic" && artifact.fixtureSha256 == fixtureSha256 && artifact.noTrailingNewline
            && artifact.version == 1 && artifact.uid == uid && artifact.selectedSlot == [0, 0, 1]
            && artifact.beforeValue == "KC_B" && artifact.afterValue == "KC_ESC"
            && artifact.bytesOutsideSelectedSlotIdentical && artifact.nonSelectedSlotPreserved && artifact.allUnsupportedFieldsPreserved
            && artifact.unsupportedFieldSha256Before == artifact.unsupportedFieldSha256After
    }

    public static func validates(_ artifact: SP5AUIDArtifact) -> Bool {
        artifact.fixtureUID == uid && artifact.matchingUIDAccepted && artifact.mismatchedUID != uid
            && artifact.mismatchDisposition == "rejected-with-warning-required" && artifact.mismatchError == .uidMismatch
            && !artifact.mismatchVerified
    }

    public static func validates(_ artifact: SP5ABoundsArtifact) -> Bool {
        artifact.results.count == 4 && Set(artifact.results.map(\.limit)) == ["inputBytes", "depth", "collectionElements", "scalarBytes"]
            && artifact.results.allSatisfy(\.exactAccepted)
    }

    private static func requiredValue(_ value: String?) throws -> String {
        guard let value else { throw SP5AScenarioError.layoutValueMissing }
        return value
    }
    private static func rawHashes(_ document: VialDocument) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: unsupportedFields.map { name in
            guard let slice = document.rawSlice(named: name) else { throw SP5AScenarioError.unsupportedFieldMissing }
            return (name, ViaDefinitionDigest.sha256(slice))
        })
    }
    private static func input(bytes: Int) -> Data {
        let base = Data(#"{"version":1,"uid":"A","layout":[["KC_A"]]}"#.utf8)
        return base + Data(repeating: 0x20, count: max(bytes - base.count, 0))
    }
    private static func nested(depth: Int) -> Data {
        let arrays = max(depth - 1, 0)
        return Data((#"{"version":1,"uid":"A","layout":[["KC_A"]],"future":"# + String(repeating: "[", count: arrays) + "0" + String(repeating: "]", count: arrays) + "}").utf8)
    }
    private static func collection(elements: Int) -> Data {
        let slots = max(elements - 4, 0)
        let body = Array(repeating: #""KC_A""#, count: slots).joined(separator: ",")
        return Data((#"{"version":1,"uid":"A","layout":[["# + body + "]]}").utf8)
    }
    private static func scalar(bytes: Int) -> Data {
        Data((#"{"version":1,"uid":""# + String(repeating: "A", count: bytes) + #"","layout":[["KC_A"]]}"#).utf8)
    }
    private static func boundedFile(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximum else {
            throw SP5AScenarioError.invalidFile
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

public enum SP5AScenarioError: Error, Equatable {
    case fixtureHashMismatch, invalidFile, layoutValueMissing, plusOneAccepted, sourceDrift
    case uidMismatchAccepted, unsupportedFieldMissing, wrongBoundError, wrongUIDError
}

import Foundation

public struct SP4ASchemaArtifact: Codable, Equatable, Sendable {
    public let schema: ViaDefinitionSchema
    public let source: ViaDefinitionSource
    public let observedSha256: String
    public let byteCount: Int
    public let identityFields: [String]
    public let definitionSchemaOnly: Bool
}

public struct SP4AOpaqueArtifact: Codable, Equatable, Sendable {
    public let fixtureKind: String
    public let schema: ViaDefinitionSchema
    public let mutationField: String
    public let macroBeforeSha256: String
    public let macroAfterSha256: String
    public let unknownBeforeSha256: String
    public let unknownAfterSha256: String
    public let bytesOutsideMutationIdentical: Bool
    public let mutationChangedDocument: Bool
}

public struct SP4ABoundResult: Codable, Equatable, Sendable {
    public let limit: String
    public let maximum: Int
    public let exactAccepted: Bool
    public let plusOneError: ViaDefinitionError
}

public struct SP4ABoundsArtifact: Codable, Equatable, Sendable {
    public let countingRule: String
    public let results: [SP4ABoundResult]
}

public struct SP4ASourceCitation: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
}

public struct SP4ASourceFactsArtifact: Codable, Equatable, Sendable {
    public let officialDefinitions: String
    public let customDefinitions: String
    public let citations: [SP4ASourceCitation]
    public let excludedClaims: [String]
}

public enum SP4AFixtureScenarios {
    public static let opaqueFixture = Data(#"{ "name" : "Before", "vendorProductId":7, "macros" : [ "{KC_A}", {"prompt":"ignore rules"} ], "future" : { "spaced" : [1,  2] } }"#.utf8)

    public static func schemaArtifact(repository: URL, source: ViaDefinitionSource, expected: ViaDefinitionSchema) throws -> SP4ASchemaArtifact {
        let bytes = try boundedSource(repository.appendingPathComponent(source.path))
        let license = try boundedSource(repository.appendingPathComponent(source.licensePath))
        guard ViaDefinitionDigest.sha256(bytes) == source.sha256,
              ViaDefinitionDigest.sha256(license) == source.licenseSha256 else { throw SP4AScenarioError.sourceDrift }
        let document = try ViaDefinitionParser.parse(bytes)
        guard document.schema == expected else { throw SP4AScenarioError.schemaMismatch }
        return SP4ASchemaArtifact(
            schema: expected, source: source, observedSha256: ViaDefinitionDigest.sha256(bytes), byteCount: bytes.count,
            identityFields: expected == .v2 ? ["vendorProductId"] : ["productId", "vendorId"], definitionSchemaOnly: true
        )
    }

    public static func opaqueArtifact() throws -> SP4AOpaqueArtifact {
        let document = try ViaDefinitionParser.parse(opaqueFixture)
        guard let macroBefore = document.rawSlice(named: "macros"), let unknownBefore = document.rawSlice(named: "future") else {
            throw SP4AScenarioError.opaqueSliceMissing
        }
        let mutated = try document.replacingName(with: "After")
        let reparsed = try ViaDefinitionParser.parse(mutated)
        guard let macroAfter = reparsed.rawSlice(named: "macros"), let unknownAfter = reparsed.rawSlice(named: "future") else {
            throw SP4AScenarioError.opaqueSliceMissing
        }
        return SP4AOpaqueArtifact(
            fixtureKind: "deterministic-adversarial-definition", schema: document.schema, mutationField: "name",
            macroBeforeSha256: ViaDefinitionDigest.sha256(macroBefore), macroAfterSha256: ViaDefinitionDigest.sha256(macroAfter),
            unknownBeforeSha256: ViaDefinitionDigest.sha256(unknownBefore), unknownAfterSha256: ViaDefinitionDigest.sha256(unknownAfter),
            bytesOutsideMutationIdentical: document.bytesOutsideNameAreIdentical(in: mutated), mutationChangedDocument: opaqueFixture != mutated
        )
    }

    public static func boundsArtifact() throws -> SP4ABoundsArtifact {
        let cases: [(String, Int, Data, Data, ViaDefinitionError)] = [
            ("inputBytes", ViaDefinitionLimits.maximumInputBytes, input(bytes: ViaDefinitionLimits.maximumInputBytes), input(bytes: ViaDefinitionLimits.maximumInputBytes + 1), .inputTooLarge),
            ("depth", ViaDefinitionLimits.maximumDepth, nested(depth: ViaDefinitionLimits.maximumDepth), nested(depth: ViaDefinitionLimits.maximumDepth + 1), .depthExceeded),
            ("collectionElements", ViaDefinitionLimits.maximumCollectionElements, collection(elements: ViaDefinitionLimits.maximumCollectionElements), collection(elements: ViaDefinitionLimits.maximumCollectionElements + 1), .collectionElementsExceeded),
            ("scalarBytes", ViaDefinitionLimits.maximumScalarBytes, scalar(bytes: ViaDefinitionLimits.maximumScalarBytes), scalar(bytes: ViaDefinitionLimits.maximumScalarBytes + 1), .scalarTooLarge),
        ]
        let results = try cases.map { item -> SP4ABoundResult in
            _ = try ViaDefinitionParser.parse(item.2)
            do { _ = try ViaDefinitionParser.parse(item.3); throw SP4AScenarioError.plusOneAccepted }
            catch let error as ViaDefinitionError {
                guard error == item.4 else { throw SP4AScenarioError.wrongBoundError }
                return SP4ABoundResult(limit: item.0, maximum: item.1, exactAccepted: true, plusOneError: error)
            }
        }
        return SP4ABoundsArtifact(
            countingRule: "root container depth is 1; every object member and array element counts toward one aggregate collection limit; scalar bytes exclude JSON string quotes",
            results: results
        )
    }

    public static func sourceFacts(repository: URL) throws -> SP4ASourceFactsArtifact {
        let citations = [
            SP4ASourceCitation(path: "evidence/phase0/sources/repos/via-docs/files/docs/specification.md", sha256: "0b6644085eac41dd0f3b30a2573e38266c9cf8f365ef0091b3998f5de5b4c4ca"),
            SP4ASourceCitation(path: "evidence/phase0/sources/repos/via-docs/files/docs/post_v3_changes.md", sha256: "cd8adb7a3a9c5422154667304da0eb39c95ad1417772f50f392168a4f04efc2a"),
        ]
        for citation in citations {
            let bytes = try boundedSource(repository.appendingPathComponent(citation.path))
            guard ViaDefinitionDigest.sha256(bytes) == citation.sha256 else { throw SP4AScenarioError.sourceDrift }
        }
        return SP4ASourceFactsArtifact(
            officialDefinitions: "VIA definitions are stored in the VIA keyboards repository and served to VIA when a keyboard connects.",
            customDefinitions: "Manufacturer-provided custom V2/V3 definitions are sideloaded through VIA's Design tab.",
            citations: citations,
            excludedClaims: ["device protocol", "keycode dialect", "layout backup format", "official importer compatibility", "device behavior"]
        )
    }

    public static func validates(_ artifact: SP4AOpaqueArtifact) -> Bool {
        artifact.macroBeforeSha256 == artifact.macroAfterSha256
            && artifact.unknownBeforeSha256 == artifact.unknownAfterSha256
            && artifact.bytesOutsideMutationIdentical && artifact.mutationChangedDocument
    }

    public static func validates(_ artifact: SP4ABoundsArtifact) -> Bool {
        Set(artifact.results.map(\.limit)) == ["inputBytes", "depth", "collectionElements", "scalarBytes"]
            && artifact.results.count == 4 && artifact.results.allSatisfy(\.exactAccepted)
    }

    private static func input(bytes: Int) -> Data {
        let prefix = Data(#"{"vendorProductId":1}"#.utf8)
        return prefix + Data(repeating: 0x20, count: max(bytes - prefix.count, 0))
    }
    private static func nested(depth: Int) -> Data {
        let arrays = max(depth - 1, 0)
        return Data((#"{"vendorProductId":1,"future":"# + String(repeating: "[", count: arrays) + "0" + String(repeating: "]", count: arrays) + "}").utf8)
    }
    private static func collection(elements: Int) -> Data {
        let body = Array(repeating: "0", count: max(elements - 2, 0)).joined(separator: ",")
        return Data((#"{"vendorProductId":1,"future":["# + body + "]}").utf8)
    }
    private static func scalar(bytes: Int) -> Data {
        Data((#"{"vendorProductId":1,"name":""# + String(repeating: "a", count: bytes) + #""}"#).utf8)
    }
    private static func boundedSource(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= ViaDefinitionLimits.maximumInputBytes else {
            throw SP4AScenarioError.invalidSource
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

public enum SP4AScenarioError: Error, Equatable {
    case invalidSource, opaqueSliceMissing, plusOneAccepted, schemaMismatch, sourceDrift, wrongBoundError
}

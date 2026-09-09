import XCTest
@testable import Phase0Support

final class SP2LiveAggregateV2SchemaTests: XCTestCase {
    private static let counterFields = [
        "knownAttributable", "knownUnattributable", "tapResets", "fnUnknownAfterReset",
        "fnRecoveredKnownNone", "fnRecoveredKnownActive",
    ]
    private static let sortedKeys = ["evidenceKind"] + [
        "fnRecoveredKnownActive", "fnRecoveredKnownNone", "fnUnknownAfterReset",
        "knownAttributable", "knownUnattributable", "schemaVersion", "tapResets",
    ]

    func testCounterFieldTableCoversEveryStoredProperty() {
        let storedProperties = Set(Mirror(reflecting: SP2LiveAggregateV2()).children.compactMap(\.label))
        XCTAssertEqual(storedProperties, Set(Self.counterFields).union(["schemaVersion", "evidenceKind"]))
    }

    func testDecodeRejectsWrongSchemaVersion() throws {
        for version in [0, 1, 3] {
            var object = baseObject()
            object["schemaVersion"] = version
            XCTAssertThrowsError(try decoded(object), "version \(version)") {
                XCTAssertEqual($0 as? SP2LiveAggregateV2Error, .invalidSchemaVersion(found: version))
            }
        }
    }

    func testDecodeRejectsNonLiveEvidenceKind() throws {
        for kind in ["fixture", "synthetic", "source"] {
            var object = baseObject()
            object["evidenceKind"] = kind
            XCTAssertThrowsError(try decoded(object), kind) {
                XCTAssertEqual($0 as? SP2LiveAggregateV2Error, .invalidEvidenceKind(found: EvidenceKind(rawValue: kind)!))
            }
        }
    }

    func testDecodeRejectsUnknownRootKeys() throws {
        for key in ["rawDetails", "verdict", "spikeID", "bundleID", "timestamps"] {
            var object = baseObject()
            object[key] = "hostile"
            XCTAssertThrowsError(try decoded(object), key) {
                XCTAssertEqual($0 as? EvidenceModelError, .unknownFields(type: "SP2LiveAggregateV2", fields: [key]), key)
            }
        }
        var object = baseObject()
        object["extraZ"] = 0
        object["extraA"] = 0
        XCTAssertThrowsError(try decoded(object)) {
            XCTAssertEqual($0 as? EvidenceModelError, .unknownFields(type: "SP2LiveAggregateV2", fields: ["extraA", "extraZ"]))
        }
    }

    func testDecodeRejectsBooleanCountForEveryCounterField() throws {
        for field in Self.counterFields {
            var object = baseObject()
            object[field] = true
            XCTAssertThrowsError(try decoded(object), field) {
                XCTAssertTrue($0 is DecodingError, "\(field) must reject Boolean counts, threw \($0)")
            }
        }
    }

    func testDecodeRejectsFractionalCountForEveryCounterField() throws {
        for field in Self.counterFields {
            var object = baseObject()
            object[field] = 1.5
            XCTAssertThrowsError(try decoded(object), field) {
                XCTAssertTrue($0 is DecodingError, "\(field) must reject fractional counts, threw \($0)")
            }
        }
    }

    func testDecodeRejectsNegativeCountForEveryCounterField() throws {
        for field in Self.counterFields {
            var object = baseObject()
            object[field] = -1
            XCTAssertThrowsError(try decoded(object), field) {
                XCTAssertEqual($0 as? SP2LiveAggregateV2Error, .negativeCount(field: field), field)
            }
        }
    }

    func testDecodeRejectsOverflowingCountForEveryCounterField() throws {
        for field in Self.counterFields {
            let json = rawBaseJSON(overriding: field, rawValue: "9223372036854775808")
            XCTAssertThrowsError(try decodeRawJSON(json), field) {
                XCTAssertTrue($0 is DecodingError, "\(field) must reject counts overflowing Int, threw \($0)")
            }
        }
    }

    func testFrontmostAttributionRejectsUnknownRawValue() {
        XCTAssertThrowsError(try JSONDecoder().decode(SP2FrontmostAttribution.self, from: Data("\"hostile\"".utf8)))
    }

    func testValidateAcceptsPopulatedLiveAggregateAcrossCanonicalRoundTrip() throws {
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: false, secureInput: .disabled, frontmost: .excluded)
        reducer.recordTapReset(gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.knownActive, gateOpen: true, secureInput: .disabled)
        XCTAssertNoThrow(try reducer.aggregate.validate())
        let revived = try JSONDecoder().decode(SP2LiveAggregateV2.self, from: reducer.aggregate.canonicalData())
        XCTAssertEqual(revived, reducer.aggregate)
        XCTAssertNoThrow(try revived.validate())
    }

    func testCanonicalEncodingRejectsInvalidAggregate() {
        var aggregate = SP2LiveAggregateV2()
        aggregate.knownAttributable = -1
        XCTAssertThrowsError(try aggregate.canonicalData()) {
            XCTAssertEqual($0 as? SP2LiveAggregateV2Error, .negativeCount(field: "knownAttributable"))
        }
    }

    func testCanonicalEncodingIsDeterministicAcrossEncodesAndRecordingOrder() throws {
        var first = SP2LiveAggregateV2Reducer()
        var second = SP2LiveAggregateV2Reducer()
        first.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownAttributable)
        first.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownUnattributable)
        first.recordTapReset(gateOpen: true, secureInput: .disabled)
        first.recordFnRecoverySnapshot(.knownNone, gateOpen: true, secureInput: .disabled)
        second.recordFnRecoverySnapshot(.knownNone, gateOpen: true, secureInput: .disabled)
        second.recordTapReset(gateOpen: true, secureInput: .disabled)
        second.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownUnattributable)
        second.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownAttributable)
        let data = try first.aggregate.canonicalData()
        XCTAssertEqual(data, try first.aggregate.canonicalData())
        XCTAssertEqual(data, try second.aggregate.canonicalData())
    }

    func testCanonicalEncodingHasExactSortedKeySetTrailingNewlineAndDimensionlessValues() throws {
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownUnattributable)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .indeterminate)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .excluded)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .enabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: false, secureInput: .disabled, frontmost: .knownAttributable)
        reducer.recordTapReset(gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.unknown, gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.knownNone, gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.knownActive, gateOpen: true, secureInput: .disabled)
        let data = try reducer.aggregate.canonicalData()
        XCTAssertEqual(data.last, UInt8(10))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\\/"))
        var position = text.startIndex
        for key in Self.sortedKeys {
            let occurrence = text.range(of: "\"\(key)\"", range: position..<text.endIndex)
            XCTAssertNotNil(occurrence, key)
            position = occurrence?.upperBound ?? position
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.count, 8)
        XCTAssertEqual(Set(object.keys), Set(Self.sortedKeys))
        XCTAssertEqual(object["evidenceKind"] as? String, "live")
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        for (key, value) in object where key != "evidenceKind" {
            XCTAssertTrue(value is NSNumber, "counter \(key) must stay dimensionless")
        }
        XCTAssertFalse(object.keys.contains {
            let lowered = $0.lowercased()
            return lowered.contains("verdict") || lowered.contains("pass") || lowered.contains("bundle")
                || lowered.contains("keycode") || lowered.contains("sequence") || lowered.contains("timestamp")
        })
    }

    func testAttributionEnumIsCompactAndCarriesNoEventDetails() {
        XCTAssertEqual(SP2FrontmostAttribution.allCases.count, 4)
        XCTAssertEqual(
            Set(SP2FrontmostAttribution.allCases.map(\.rawValue)),
            ["knownAttributable", "knownUnattributable", "indeterminate", "excluded"]
        )
        for frontmost in SP2FrontmostAttribution.allCases {
            XCTAssertEqual(SP2FrontmostAttribution(rawValue: frontmost.rawValue), frontmost)
        }
    }

    func testCanonicalArtifactPassesPhase0PrivacyAuditWithZeroFindings() throws {
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .knownUnattributable)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .indeterminate)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: .excluded)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .enabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: false, secureInput: .disabled, frontmost: .knownAttributable)
        reducer.recordTapReset(gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.unknown, gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.knownNone, gateOpen: true, secureInput: .disabled)
        reducer.recordFnRecoverySnapshot(.knownActive, gateOpen: true, secureInput: .disabled)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp2-live-aggregate-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try reducer.aggregate.canonicalData().write(to: directory.appendingPathComponent("live-aggregate-v2.json"))
        let report = try Phase0PrivacyAudit.scan(root: directory)
        XCTAssertEqual(report.filesScanned, 1)
        XCTAssertEqual(report.jsonFilesScanned, 1)
        XCTAssertEqual(report.forbiddenHitCount, 0)
        XCTAssertEqual(report.unmarkedEventRecordCount, 0)
        XCTAssertEqual(report.symlinkCount, 0)
    }

    func testDirectoryLayoutRunnerBindingAndRegistryRemainUnchanged() {
        XCTAssertEqual(SP2DirectoryLayout.artifactNames, [
            "SP-2-CONCLUSION.md", "evidence.json", "privacy-model.json", "modifier-model.json", "live-aggregate-counts.json",
        ])
        XCTAssertEqual(SP2DirectoryLayout.allNames, SP2DirectoryLayout.artifactNames.union(["manifest.sha256"]))
        XCTAssertEqual(SP2DirectoryLayout.boundArtifactNames, ["privacy-model.json", "modifier-model.json", "live-aggregate-counts.json"])
        XCTAssertEqual(SP2RunnerBinding.sourcePaths, [
            "Spikes/Scripts/run-task-qa.sh",
            "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
            "Spikes/Sources/Phase0Probe/SP2LiveExecutor.swift",
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
        ])
        XCTAssertEqual(Phase0Registry.legRules.count, 57)
        XCTAssertEqual(SP2Evidence.requiredLegIDs.count, 11)
        XCTAssertFalse(SP2RunnerBinding.sourcePaths.contains { $0.contains("LiveAggregateV2") })
        XCTAssertFalse(SP2DirectoryLayout.allNames.contains { $0.lowercased().contains("v2") })
    }

    func testDefaultSP2AggregateArtifactEncodingRemainsUnchanged() throws {
        let artifact = SP2AggregateArtifact(evidenceKind: .live)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(artifact)
        XCTAssertEqual(data, try encoder.encode(artifact))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["evidenceKind", "dataDelta", "metaDelta"])
        XCTAssertEqual(object["evidenceKind"] as? String, "live")
        XCTAssertEqual(object["dataDelta"] as? Int, 0)
        XCTAssertEqual(object["metaDelta"] as? Int, 0)
    }

    private func baseObject() -> [String: Any] {
        [
            "schemaVersion": 2, "evidenceKind": "live",
            "knownAttributable": 0, "knownUnattributable": 0,
            "tapResets": 0, "fnUnknownAfterReset": 0,
            "fnRecoveredKnownNone": 0, "fnRecoveredKnownActive": 0,
        ]
    }

    private func decoded(_ object: [String: Any]) throws -> SP2LiveAggregateV2 {
        try JSONDecoder().decode(SP2LiveAggregateV2.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func rawBaseJSON(overriding field: String, rawValue: String) -> String {
        var pairs = ["\"evidenceKind\":\"live\"", "\"schemaVersion\":2"]
        for key in Self.counterFields {
            pairs.append("\"\(key)\":\(key == field ? rawValue : "0")")
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }

    private func decodeRawJSON(_ json: String) throws -> SP2LiveAggregateV2 {
        try JSONDecoder().decode(SP2LiveAggregateV2.self, from: Data(json.utf8))
    }
}

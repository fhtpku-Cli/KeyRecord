import XCTest
import Foundation
import Darwin
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore
@testable import KeyRecordMappings

private let firmwareBytes = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["MO(1)","KC_NO","CUSTOM"],["KC_NO","KC_TRNS","QK_BOOT"]], "macros":["sensitive macro"],"unknown": { "spaces" : [1,2] }}"#.utf8)
private let firmwareAxes = FirmwareVersionAxes(definitionSchema: "fixture-schema", deviceProtocol: "fixture-protocol",
    layoutFormat: "fixture-layout", keycodeDialect: "fixture-dialect", importer: "fixture-importer")
private let firmwareChanges = [FirmwareSlotChange(slot: FirmwareSlot(layer: 0, column: 1), output: "KC_C", automatic: true)]
private func firmwareSupport(_ backend: FirmwareBackend = .via, device: String = "42") -> FirmwareSupportDirectory {
    FirmwareSupportDirectory(entries: [FirmwareCompatibility(backend: backend, device: device, axes: firmwareAxes,
        supportedOutputs: ["KC_C", "KC_A", "LCTL(KC_C)", "MACRO(1)", "MO(2)"])])
}
private final class FirmwareFault: @unchecked Sendable {
    private let lock = NSLock()
    private var phase: FirmwareJournalPhase?
    func set(_ phase: FirmwareJournalPhase?) { lock.withLock { self.phase = phase } }
    func hit(_ phase: FirmwareJournalPhase) throws { try lock.withLock { if self.phase == phase { throw FirmwareError.unavailable } } }
}
@MainActor
final class FirmwareOperationTests: XCTestCase {
    func testRenamePersistsWithoutChangingOriginalOrDeploymentState() async throws {
        let (_, store, _, gate) = try await fixture()
        let operations = try coordinator(store, gate)
        let record = try await retain(operations)
        let oldWire = try JSONEncoder().encode(record)
        XCTAssertNil(try JSONDecoder().decode(FirmwareBatchRecord.self, from: oldWire).name)
        let renamed = try await operations.rename(record.id, name: "  C / Global  ")
        XCTAssertEqual(renamed.records.first?.name, "C / Global")
        XCTAssertEqual(renamed.records.first?.state, record.state)
        XCTAssertEqual(renamed.records.first?.changes, record.changes)
        let original = try await operations.original(record.id)
        XCTAssertEqual(original, firmwareBytes)
        for invalid in ["   ", String(repeating: "a", count: 257)] {
            do { _ = try await operations.rename(record.id, name: invalid); XCTFail("Accepted invalid name") }
            catch FirmwareError.invalidDocument {}
        }
        let reopened = try await coordinator(store, gate).ledger()
        XCTAssertEqual(reopened.records.first?.name, "C / Global")
    }

    func testConfigurationExportIncludesOnlyPreferencesAndMappingSelections() async throws {
        let (_, store, _, gate) = try await fixture()
        let preferences = Preferences(currentCycleID: CycleID(rawValue: UUID().uuidString), excludedBundleIDs: ["com.example.private"], showDockIcon: true)
        _ = try await store.put(identity: CycleResetObjects.preferences, payload: JSONEncoder().encode(preferences))
        _ = try await store.put(identity: CycleResetObjects.currentCycle, payload: Data("SECRET_STATISTICS".utf8))
        let operations = try coordinator(store, gate)
        let record = try await retain(operations)
        _ = try await operations.rename(record.id, name: "C / Global")
        let before = try await store.entries()
        let exported = try await ConfigurationExport.load(store: store, gate: gate, firmwareDrafts: [record.id: firmwareChanges])
        XCTAssertTrue(exported.preferences.showDockIcon)
        XCTAssertEqual(exported.firmware.first?.name, "C / Global")
        XCTAssertEqual(exported.firmwareDrafts.first?.changes, firmwareChanges)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported.encoded()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "preferences", "karabiner", "firmware", "karabinerDrafts", "firmwareDrafts"])
        let text = String(decoding: try exported.encoded(), as: UTF8.self)
        for forbidden in ["SECRET_STATISTICS", "sensitive macro", "currentCycleID", "baselineSHA256", "locator", "bookmark"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        let after = try await store.entries()
        XCTAssertEqual(before, after)
        gate.update(.locked)
        do { _ = try await ConfigurationExport.load(store: store, gate: gate); XCTFail("Exported while locked") } catch {}
    }

    func testConfigurationExportExcludesTemporaryRulesAndRefusesPendingTransaction() async throws {
        let (_, store, _, gate) = try await fixture()
        _ = try await store.put(identity: CycleResetObjects.preferences,
            payload: JSONEncoder().encode(Preferences(currentCycleID: CycleID(rawValue: UUID().uuidString))))
        let journal = try EncryptedKarabinerTransactionStore(store: store, namespace: UUID())
        var ledger = KarabinerLedger()
        let chord = Chord(keyCode: try KeyCode(8), modifiers: ModifierSet())
        let saved = KarabinerMappingDraft(name: "Saved", profile: "Example", trigger: chord, output: chord)
        var temporary = saved; temporary.temporary = true; temporary.name = "TEMPORARY_SECRET"
        ledger.desired = [saved, temporary]
        try await journal.save(ledger)
        let value = try await ConfigurationExport.load(store: store, gate: gate, karabinerDrafts: [temporary, saved])
        XCTAssertEqual(value.karabiner.first?.mappings, [saved])
        XCTAssertEqual(value.karabinerDrafts, [saved])
        XCTAssertFalse(String(decoding: try value.encoded(), as: UTF8.self).contains("TEMPORARY_SECRET"))
        ledger.pending = UUID(); try await journal.save(ledger)
        do { _ = try await ConfigurationExport.load(store: store, gate: gate); XCTFail("Exported pending transaction") }
        catch FirmwareError.busy {}
    }

    func testRecommendationRequiresExplicitMatchingPositionAndPreservesExistingChanges() async throws {
        let (_, store, _, gate) = try await fixture()
        let operations = try coordinator(store, gate, support: FirmwareSupportDirectory())
        let bytes = Data(#"{"name":"Recommendation","vendorProductId":42,"layers":[["KC_A","KC_A","MO(1)","KC_NO"],["KC_A","KC_NO","KC_TRNS","KC_NO"],["KC_A","KC_NO","KC_NO","KC_NO"]],"macros":["opaque"]}"#.utf8)
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .via)
        let record = try await operations.retainOriginal(bytes, backend: .via, axes: axes, confirmedAt: Date(), compatibilityBasis: .viaFile)
        let bare = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        let request = RecommendationDraft(backend: .via, output: Chord(keyCode: try KeyCode(8), modifiers: bare),
            trigger: Chord(keyCode: try KeyCode(0), modifiers: bare), scope: .global)
        let slots = try await operations.recommendationSlots(record.id, request: request)
        XCTAssertEqual(slots.map(\.change.slot), [.init(layer: 0, column: 0), .init(layer: 0, column: 1), .init(layer: 1, column: 0), .init(layer: 2, column: 0)])
        XCTAssertTrue(slots.allSatisfy { $0.before == "KC_A" && $0.change.output == "KC_C" && !$0.change.automatic })
        let existing = FirmwareSlotChange(slot: .init(layer: 0, column: 3), output: "KC_B", automatic: true)
        let preview = try await operations.previewRecommendation(record.id, request: request, slot: slots[1].change.slot, existing: [existing])
        XCTAssertEqual(preview.differences.map(\.change), [existing, slots[1].change])
        for (slot, changes, error) in [
            (slots[1].change.slot, [slots[1].change], FirmwareError.invalidSlot),
            (FirmwareSlot(layer: 0, column: 3), [], .invalidSlot),
            (FirmwareSlot(layer: 2, column: 0), [], .unreachableLayer),
            (slots[0].change.slot, [FirmwareSlotChange(slot: .init(layer: 0, column: 2), output: "KC_B", automatic: false)], .protectedEntry)
        ] {
            do { _ = try await operations.previewRecommendation(record.id, request: request, slot: slot, existing: changes); XCTFail("Expected \(error)") }
            catch let actual as FirmwareError { XCTAssertEqual(actual, error) }
        }
        let wrong = RecommendationDraft(backend: .vial, output: request.output, trigger: request.trigger, scope: .global)
        do { _ = try await operations.recommendationSlots(record.id, request: wrong); XCTFail("Backend mismatch") }
        catch FirmwareError.unsupportedOutput {}
        let original = try await operations.original(record.id)
        XCTAssertEqual(original, bytes)
        _ = try await operations.retainOriginal(bytes, backend: .via, axes: axes, confirmedAt: Date(), compatibilityBasis: .viaFile)
        do { _ = try await operations.previewRecommendation(record.id, request: request, slot: slots[0].change.slot, existing: []); XCTFail("Stale original") }
        catch FirmwareError.staleBaseline {}
    }

    func testVialRecommendationRetainsSupportQualificationAndAliasMatching() async throws {
        let (_, store, _, gate) = try await fixture()
        let bytes = Data(#"{"version":1,"uid":"42","layout":[[["KC_ENTER","KC_ENT"]]],"macros":[]}"#.utf8)
        let operations = try coordinator(store, gate, support: FirmwareSupportDirectory())
        let record = try await operations.retainOriginal(bytes, backend: .vial, axes: firmwareAxes, confirmedAt: Date())
        let bare = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        let request = RecommendationDraft(backend: .vial, output: Chord(keyCode: try KeyCode(8), modifiers: bare),
            trigger: Chord(keyCode: try KeyCode(36), modifiers: bare), scope: .global)
        do { _ = try await operations.recommendationSlots(record.id, request: request); XCTFail("Unknown device") }
        catch FirmwareError.unknownCompatibility {}
        let supported = try coordinator(store, gate, support: firmwareSupport(.vial))
        let slots = try await supported.recommendationSlots(record.id, request: request)
        XCTAssertEqual(slots.map(\.before), ["KC_ENTER", "KC_ENT"])
        let preview = try await supported.previewRecommendation(record.id, request: request, slot: slots[1].change.slot, existing: [])
        XCTAssertEqual(preview.differences.map(\.change.output), ["KC_C"])
        let unsupported = RecommendationDraft(backend: .vial, output: Chord(keyCode: try KeyCode(11), modifiers: bare), trigger: request.trigger, scope: .global)
        do { _ = try await supported.recommendationSlots(record.id, request: unsupported); XCTFail("Unsupported output") }
        catch FirmwareError.unsupportedOutput {}
    }

    func testVIAFilePositionCatalogMatchesRealPatchRestrictions() throws {
        let bytes = Data(#"{"name":"Positions","vendorProductId":42,"layers":[["KC_A","MO(1)","CUSTOM","FN_MO13","LM(1,MOD_LCTL)","QK_BOOT"],["KC_NO","KC_TRNS","KC_B","KC_C","KC_D","KC_E"],["KC_A","KC_A","KC_A","KC_A","KC_A","KC_A"]],"macros":["preserved"]}"#.utf8)
        let document = try FirmwareDocument(bytes: bytes, backend: .via)
        let slots = try document.viaFileSlots()
        XCTAssertEqual(slots.count, 18)
        XCTAssertEqual(slots.map(\.slot), (0..<3).flatMap { layer in (0..<6).map { FirmwareSlot(layer: layer, column: $0) } })
        XCTAssertEqual(slots[1].restriction, .protectedEntry)
        XCTAssertEqual(slots[2].restriction, .unsupportedOutput)
        XCTAssertEqual(slots[12].restriction, .unreachableLayer)
        for entry in slots {
            let change = FirmwareSlotChange(slot: entry.slot, output: "KC_Z", automatic: false)
            if let restriction = entry.restriction {
                XCTAssertThrowsError(try document.patchVIAFile([change], expectedDevice: "42")) {
                    XCTAssertEqual($0 as? FirmwareError, restriction)
                }
            } else {
                let edited = try document.patchVIAFile([change], expectedDevice: "42")
                XCTAssertEqual(try FirmwareDocument(bytes: edited, backend: .via).value(at: entry.slot), "KC_Z")
            }
        }
        XCTAssertEqual(document.bytes, bytes)
        let large = try JSONSerialization.data(withJSONObject: ["name": "Wide file", "vendorProductId": 42,
            "layers": [Array(repeating: "KC_A", count: 300)], "macros": [String]()])
        let largeSlots = try FirmwareDocument(bytes: large, backend: .via).viaFileSlots()
        XCTAssertEqual(largeSlots.last?.slot.column, 299)
        XCTAssertNil(largeSlots.last?.restriction)
    }
    func testVIAFilePositionCatalogRequiresLatestExplicitFileBasis() async throws {
        let (_, store, _, gate) = try await fixture()
        let operations = try coordinator(store, gate, support: FirmwareSupportDirectory())
        let axes = try FirmwareVersionProvider.axes(bytes: firmwareBytes, backend: .via)
        let legacy = try await operations.retainOriginal(firmwareBytes, backend: .via, axes: axes, confirmedAt: Date())
        do { _ = try await operations.viaFileSlots(legacy.id); XCTFail("Old records must not gain file editing") }
        catch FirmwareError.unknownCompatibility {}
        let first = try await operations.retainOriginal(firmwareBytes, backend: .via, axes: axes, confirmedAt: Date(), compatibilityBasis: .viaFile)
        let slots = try await operations.viaFileSlots(first.id)
        XCTAssertEqual(slots.count, 6)
        _ = try await operations.retainOriginal(firmwareBytes, backend: .via, axes: axes, confirmedAt: Date(), compatibilityBasis: .viaFile)
        do { _ = try await operations.viaFileSlots(first.id); XCTFail("Old originals must not be selectable") }
        catch FirmwareError.staleBaseline {}
    }
    private let vialBytes = Data(#"{"version":1,"uid":"fixture-vial","layout":[[["KC_NO","CUSTOM"]]],"macros":["opaque macro"]}"#.utf8)
    func testLargeVIAFileWithMissingLayerReferencesPreservesReachabilityAndOriginal() throws {
        for count in [1_000, 4_000, 16_000] {
            let layers = [Array(repeating: "MO(31)", count: count) + ["KC_NO"],
                          Array(repeating: "KC_NO", count: count + 1)]
            let bytes = try JSONSerialization.data(withJSONObject: ["name": "Missing layer fixture", "vendorProductId": 42,
                "layers": layers, "macros": [String]()])
            let document = try FirmwareDocument(bytes: bytes, backend: .via)
            let start = ContinuousClock.now
            for automatic in [false, true] {
                let patched = try document.patchVIAFile([.init(slot: .init(layer: 0, column: count), output: "KC_C", automatic: automatic)], expectedDevice: "42")
                let result = try FirmwareDocument(bytes: patched, backend: .via)
                XCTAssertEqual(try result.value(at: .init(layer: 0, column: count)), "KC_C")
                XCTAssertEqual(try result.value(at: .init(layer: 0, column: 0)), "MO(31)")
                XCTAssertEqual(try result.value(at: .init(layer: 1, column: count)), "KC_NO")
                XCTAssertThrowsError(try document.patchVIAFile([.init(slot: .init(layer: 1, column: count), output: "KC_C", automatic: automatic)], expectedDevice: "42")) {
                    XCTAssertEqual($0 as? FirmwareError, .unreachableLayer)
                }
            }
            XCTAssertEqual(document.bytes, bytes)
            print("Offline VIA missing-layer fixture: \(count) references, \(start.duration(to: .now))")
        }
    }
    func testVIAFileLayerTapCannotAuthorizeTruncatedLayerDestinations() async throws {
        func configuration(_ entry: String) throws -> Data {
            var layers = Array(repeating: ["KC_NO", "KC_NO"], count: 32)
            layers[0][0] = entry
            return try JSONSerialization.data(withJSONObject: ["name": "Layer bounds", "vendorProductId": 42,
                "layers": layers, "macros": [String]()])
        }
        for layer in 0...31 {
            let bytes = try configuration("LT(\(layer),KC_A)")
            let document = try FirmwareDocument(bytes: bytes, backend: .via)
            for automatic in [false, true] {
                let changes = [FirmwareSlotChange(slot: .init(layer: layer, column: 1), output: "KC_C", automatic: automatic)]
                if layer < 16 {
                    let patched = try document.patchVIAFile(changes, expectedDevice: "42")
                    let result = try FirmwareDocument(bytes: patched, backend: .via)
                    XCTAssertEqual(try result.value(at: changes[0].slot), "KC_C")
                    XCTAssertEqual(try result.value(at: .init(layer: 0, column: 0)), "LT(\(layer),KC_A)")
                } else {
                    XCTAssertThrowsError(try document.patchVIAFile(changes, expectedDevice: "42"), "layer \(layer), automatic \(automatic)") {
                        XCTAssertEqual($0 as? FirmwareError, .unreachableLayer)
                    }
                }
            }
        }
        let momentary = try FirmwareDocument(bytes: configuration("MO(31)"), backend: .via)
        XCTAssertNoThrow(try momentary.patchVIAFile([.init(slot: .init(layer: 31, column: 1), output: "KC_C", automatic: true)], expectedDevice: "42"))
        let (root, store, _, gate) = try await fixture()
        let operations = try coordinator(store, gate, support: FirmwareSupportDirectory())
        let bytes = try configuration("LT(16,KC_A)")
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .via)
        let record = try await operations.retainOriginal(bytes, backend: .via, axes: axes, confirmedAt: Date(), compatibilityBasis: .viaFile)
        let changes = [FirmwareSlotChange(slot: .init(layer: 16, column: 1), output: "KC_C", automatic: false)]
        do { _ = try await operations.preview(record.id, changes: changes); XCTFail("Truncated layer must not be previewed as reachable") }
        catch FirmwareError.unreachableLayer {}
        let target = root.appendingPathComponent("unreachable.json")
        do {
            _ = try await operations.export(record.id, changes: changes, destination: FirmwareFileDestination(target: target, gate: gate))
            XCTFail("Truncated layer must not authorize export")
        } catch FirmwareError.unreachableLayer {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        let ledger = try await operations.ledger()
        XCTAssertEqual(ledger.records.last?.state, .draft)
        XCTAssertNil(ledger.pending)
        let original = try await operations.original(record.id)
        XCTAssertEqual(original, bytes)
    }
    func testVIAFileTransactionPreservesBytesAndScopeAcrossEncryptedReopen() async throws {
        let (root, store, _, gate) = try await fixture()
        let fault = FirmwareFault()
        let operations = try coordinator(store, gate, fault: fault, support: FirmwareSupportDirectory())
        let axes = try FirmwareVersionProvider.axes(bytes: firmwareBytes, backend: .via)
        let record = try await operations.retainOriginal(firmwareBytes, backend: .via, axes: axes, confirmedAt: Date(), compatibilityBasis: .viaFile)
        XCTAssertFalse(axes.complete)
        XCTAssertFalse(FirmwareSupportDirectory().supports(backend: .via, device: "42", axes: axes))
        let preview = try await operations.preview(record.id, changes: firmwareChanges)
        XCTAssertEqual(preview.differences.map(\.before), ["KC_NO"])
        let target = root.appendingPathComponent("via-file.json")
        fault.set(.externalExported)
        do {
            _ = try await operations.export(record.id, changes: firmwareChanges, destination: FirmwareFileDestination(target: target, gate: gate))
            XCTFail("Expected interruption after external export")
        } catch FirmwareError.unavailable {}
        let reopened = try coordinator(store, gate, support: FirmwareSupportDirectory())
        let exported = try await reopened.reconcile()
        XCTAssertEqual(exported.records.last?.state, .awaitingUserImport)
        XCTAssertNil(exported.records.last?.verifiedAt)
        let expected = String(decoding: firmwareBytes, as: UTF8.self).replacingOccurrences(of: #"["MO(1)","KC_NO","CUSTOM"]"#, with: #"["MO(1)","KC_C","CUSTOM"]"#)
        XCTAssertEqual(try Data(contentsOf: target), Data(expected.utf8))
        let ledger = try await reopened.reconcile()
        XCTAssertEqual(ledger.records.last?.compatibilityBasis, .viaFile)
        let original = try await reopened.original(record.id)
        XCTAssertEqual(original, firmwareBytes)
        let claimed = try await reopened.claimImport(record.id, at: Date())
        XCTAssertEqual(claimed.records.last?.state, .importClaimed)
        XCTAssertNil(claimed.records.last?.verifiedAt)
    }
    func testVIAFileEditingCannotRelaxDeviceQualificationOrProtectiveChecks() async throws {
        let (_, store, _, gate) = try await fixture()
        let operations = try coordinator(store, gate, support: FirmwareSupportDirectory())
        let axes = try FirmwareVersionProvider.axes(bytes: firmwareBytes, backend: .via)
        let legacy = try await operations.retainOriginal(firmwareBytes, backend: .via, axes: axes, confirmedAt: Date())
        do { _ = try await operations.prepare(legacy.id, changes: firmwareChanges); XCTFail() }
        catch FirmwareError.unknownCompatibility {}
        let record = try await operations.retainOriginal(firmwareBytes, backend: .via, axes: axes, confirmedAt: Date(), compatibilityBasis: .viaFile)
        let failures: [(FirmwareSlotChange, FirmwareError)] = [
            (.init(slot: .init(layer: 0, column: 0), output: "KC_A", automatic: false), .protectedEntry),
            (.init(slot: .init(layer: 0, column: 2), output: "KC_A", automatic: false), .unsupportedOutput),
            (.init(slot: .init(layer: 0, column: 1), output: "LCTL(KC_C)", automatic: false), .unsupportedOutput),
            (.init(slot: .init(layer: 1, column: 1), output: "KC_A", automatic: true), .occupiedAutomaticSlot),
            (.init(slot: .init(layer: 0, column: 9), output: "KC_A", automatic: false), .invalidSlot)
        ]
        for (change, expected) in failures {
            do { _ = try await operations.prepare(record.id, changes: [change]); XCTFail() }
            catch { XCTAssertEqual(error as? FirmwareError, expected) }
        }
        do { _ = try await operations.prepare(legacy.id, changes: firmwareChanges); XCTFail() }
        catch FirmwareError.staleBaseline {}
        let bytes = Data(#"{"name":"Malformed entry","vendorProductId":42,"layers":[["MO(1,extra)","KC_NO"],["KC_NO","KC_NO"]]}"#.utf8)
        let document = try FirmwareDocument(bytes: bytes, backend: .via)
        XCTAssertThrowsError(try document.patchVIAFile([.init(slot: .init(layer: 1, column: 0), output: "KC_A", automatic: false)], expectedDevice: "42")) {
            XCTAssertEqual($0 as? FirmwareError, .unreachableLayer)
        }
        for token in ["FN_MO13", "FN_MO23", "LM(1,MOD_LCTL)", "RESET", "QK_BOOT", "0x7c00", " mo(1)"] {
            let bytes = Data("{\"name\":\"Protected\",\"vendorProductId\":42,\"layers\":[[\"\(token)\"]]}".utf8)
            XCTAssertThrowsError(try FirmwareDocument(bytes: bytes, backend: .via).patchVIAFile([.init(slot: .init(layer: 0, column: 0), output: "KC_A", automatic: false)], expectedDevice: "42"))
        }
    }
    func testVIAFileStructureAndStoredBasisCannotBeForgedByInputMetadata() async throws {
        let (_, store, _, gate) = try await fixture()
        let operations = try coordinator(store, gate, support: FirmwareSupportDirectory())
        for text in [
            #"{"vendorProductId":42,"layers":[["KC_NO"]]}"#,
            #"{"name":"Bad","vendorProductId":0,"layers":[["KC_NO"]]}"#,
            #"{"name":"Bad","vendorProductId":42,"layers":[["KC_NO"]],"macros":[1]}"#,
            #"{"name":"Bad","vendorProductId":42,"layers":[["KC_NO"]],"encoders":[[["KC_A"]]]}"#,
            #"{"name":"Bad","vendorProductId":42,"layers":[["KC_NO"]],"encoders":[[["KC_A","KC_B"],["KC_C","KC_D"]]]}"#
        ] { XCTAssertThrowsError(try VIAFileCompatibility.validate(Data(text.utf8))) }
        let bytes = Data(#"{"name":"Forged","vendorProductId":42,"layers":[["KC_NO"]],"compatibilityBasis":"viaFile","importer":"trusted"}"#.utf8)
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .via)
        let record = try await operations.retainOriginal(bytes, backend: .via, axes: axes, confirmedAt: Date())
        XCTAssertNil(record.compatibilityBasis); XCTAssertNil(record.axes.importer)
        do { _ = try await operations.retainOriginal(bytes, backend: .via, axes: firmwareAxes, confirmedAt: Date(), compatibilityBasis: .viaFile); XCTFail() }
        catch FirmwareError.unknownCompatibility {}
        do { _ = try await operations.retainOriginal(vialBytes, backend: .vial, axes: firmwareAxes, confirmedAt: Date(), compatibilityBasis: .viaFile); XCTFail() }
        catch FirmwareError.unknownCompatibility {}
    }
    func testKeymapMatchCannotClaimCompleteVerificationOfOpaqueConfiguration() async throws {
        let (root, store, _, gate) = try await fixture()
        let (operations, batch) = try await exportedVial(store, gate, root: root)
        let result = try await operations.confirmVialReadback(batch.id, observation: observation("KC_C"))
        XCTAssertEqual(result.records.last?.state.rawValue, "partiallyVerified")
        XCTAssertEqual(result.records.last?.unverifiedSections, ["macros"])
        let original = try await operations.original(batch.id)
        XCTAssertEqual(original, vialBytes)
        do { try await operations.deleteOriginal(batch.id); XCTFail("Readback must not authorize deletion") }
        catch FirmwareError.invalidState {}
    }
    func testLegacySuccessfulReadbackAndPendingReplayRecoverHonestScope() async throws {
        let (root, store, _, gate) = try await fixture()
        let (operations, batch) = try await exportedVial(store, gate, root: root)
        var legacy = try await operations.confirmVialReadback(batch.id, observation: observation("KC_C"))
        legacy.records[0].state = .verified
        legacy.records[0].unverifiedSections = nil
        let identity = try CanonicalLogicalIdentity(objectType: "com.keyrecord.firmware-journal", schemaVersion: 1, logicalIDText: "firmware")
        _ = try await store.put(identity: identity, payload: JSONEncoder().encode(legacy))
        let loaded = try await operations.ledger()
        XCTAssertEqual(loaded.records[0].state, .partiallyVerified)
        XCTAssertEqual(loaded.records[0].unverifiedSections, ["macros"])
        legacy.records[0].state = .importClaimed
        legacy.pending = FirmwarePendingOperation(batch: batch.id, phase: .evidenceRecorded,
            recordedAt: Date(timeIntervalSince1970: 4), verificationState: .verified, verificationSource: "vialKeymapReadback")
        _ = try await store.put(identity: identity, payload: JSONEncoder().encode(legacy))
        let replayed = try await operations.reconcile()
        XCTAssertNil(replayed.pending)
        XCTAssertEqual(replayed.records[0].state, .partiallyVerified)
        XCTAssertEqual(replayed.records[0].unverifiedSections, ["macros"])
    }
    private func exportedVial(_ store: ObjectStore, _ gate: KeyAvailabilityGate, root: URL,
                              fault: FirmwareFault? = nil) async throws -> (FirmwareOperationCoordinator, FirmwareBatchRecord) {
        let operations = try FirmwareOperationCoordinator(store: store, support: firmwareSupport(.vial, device: "fixture-vial"),
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }, injection: { try fault?.hit($0) })
        let batch = try await operations.retainOriginal(vialBytes, backend: .vial, axes: firmwareAxes, confirmedAt: Date(timeIntervalSince1970: 1))
        _ = try await operations.export(batch.id,
            changes: [FirmwareSlotChange(slot: FirmwareSlot(layer: 0, column: 0), output: "KC_C", automatic: false)],
            destination: FirmwareFileDestination(target: root.appendingPathComponent("patch.vil"), gate: gate))
        let ledger = try await operations.claimImport(batch.id, at: Date(timeIntervalSince1970: 2))
        return (operations, try XCTUnwrap(ledger.records.last))
    }
    private func observation(_ first: String, second: String = "CUSTOM", device: String = "fixture-vial",
                             axes: FirmwareVersionAxes = firmwareAxes, at: Date = Date(timeIntervalSince1970: 3)) -> VialKeymapObservation {
        VialKeymapObservation(device: device, axes: axes,
            values: [FirmwareSlot(layer: 0, column: 0): first, FirmwareSlot(layer: 0, column: 1): second], observedAt: at)
    }
    func testMultiSlotPreviewIsReadOnlyAndMatchesPreparedArtifact() async throws {
        let (_, store, _, gate) = try await fixture()
        let operations = try coordinator(store, gate)
        let batch = try await retain(operations)
        let before = try await operations.ledger()
        let changes = [firmwareChanges[0], FirmwareSlotChange(slot: .init(layer: 1, column: 0), output: "KC_A", automatic: true)]
        let preview = try await operations.preview(batch.id, changes: changes)
        XCTAssertEqual(preview.batch, batch.id)
        XCTAssertEqual(preview.differences.map(\.change), changes)
        XCTAssertEqual(preview.differences.map(\.before), ["KC_NO", "KC_NO"])
        let prepared = try await operations.prepare(batch.id, changes: changes)
        let expected = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["MO(1)","KC_C","CUSTOM"],["KC_A","KC_TRNS","QK_BOOT"]], "macros":["sensitive macro"],"unknown": { "spaces" : [1,2] }}"#.utf8)
        XCTAssertEqual(prepared, expected)
        let after = try await operations.ledger()
        let original = try await operations.original(batch.id)
        XCTAssertEqual(after, before); XCTAssertEqual(original, firmwareBytes)
    }
    func testVialPreviewRetainsRowCoordinatesAndRejectsInvalidOrStaleChanges() async throws {
        let (_, store, _, gate) = try await fixture()
        let operations = try FirmwareOperationCoordinator(store: store, support: firmwareSupport(.vial, device: "fixture-vial"),
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let bytes = Data(#"{"version":1,"uid":"fixture-vial","layout":[[["MO(1)","KC_NO"],["KC_NO","CUSTOM"]],[["KC_NO","KC_TRNS"],["KC_NO","QK_BOOT"]]],"macros":["opaque"]}"#.utf8)
        let batch = try await operations.retainOriginal(bytes, backend: .vial, axes: firmwareAxes, confirmedAt: Date())
        let valid = FirmwareSlotChange(slot: .init(layer: 0, row: 1, column: 0), output: "KC_A", automatic: false)
        let preview = try await operations.preview(batch.id, changes: [valid])
        XCTAssertEqual(preview.differences.first?.change, valid); XCTAssertEqual(preview.differences.first?.before, "KC_NO")
        let invalid: [([FirmwareSlotChange], FirmwareError)] = [
            ([valid, valid], .invalidSlot),
            ([.init(slot: .init(layer: 0, row: 0, column: 0), output: "KC_C", automatic: false)], .protectedEntry),
            ([.init(slot: .init(layer: 0, row: 9, column: 0), output: "KC_C", automatic: false)], .invalidSlot),
            ([.init(slot: valid.slot, output: "MACRO(1)", automatic: false)], .unsupportedOutput),
            ([.init(slot: .init(layer: 1, row: 0, column: 1), output: "KC_C", automatic: true)], .occupiedAutomaticSlot)
        ]
        for (changes, expectedError) in invalid {
            do { _ = try await operations.preview(batch.id, changes: changes); XCTFail("Expected invalid preview") }
            catch { XCTAssertEqual(error as? FirmwareError, expectedError) }
        }
        let unknown = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        do { _ = try await unknown.preview(batch.id, changes: [valid]); XCTFail("Expected unknown compatibility refusal") }
        catch FirmwareError.unknownCompatibility {}
        _ = try await operations.retainOriginal(bytes, backend: .vial, axes: firmwareAxes, confirmedAt: Date())
        do { _ = try await operations.preview(batch.id, changes: [valid]); XCTFail("Expected stale copy refusal") }
        catch FirmwareError.staleBaseline {}
    }
    func testVialReadbackComparesAllSlotsAndClassifiesExpectedBaselineAndExternal() async throws {
        let (root, store, _, gate) = try await fixture()
        let (operations, batch) = try await exportedVial(store, gate, root: root)
        for (snapshot, state) in [(observation("KC_C"), FirmwareMappingState.partiallyVerified),
                                  (observation("KC_NO"), .failed), (observation("KC_C", second: "KC_A"), .externallyChanged)] {
            let result = try await operations.confirmVialReadback(batch.id, observation: snapshot)
            XCTAssertEqual(result.records.last?.state, state)
            XCTAssertEqual(result.records.last?.verificationSource, "vialKeymapReadback")
        }
        let restored = try await operations.original(batch.id)
        XCTAssertEqual(restored, vialBytes)
    }
    func testVialReadbackRejectsWrongDeviceAxesPartialShapeStaleEvidenceAndUnknownDirectory() async throws {
        let (root, store, _, gate) = try await fixture()
        let (operations, batch) = try await exportedVial(store, gate, root: root)
        let partial = VialKeymapObservation(device: batch.device, axes: firmwareAxes,
            values: [FirmwareSlot(layer: 0, column: 0): "KC_C"], observedAt: Date(timeIntervalSince1970: 3))
        let unknown = FirmwareVersionAxes(definitionSchema: nil, deviceProtocol: nil, layoutFormat: nil, keycodeDialect: nil, importer: nil)
        for value in [observation("KC_C", device: "other"), observation("KC_C", axes: unknown), partial,
                      observation("KC_C", at: Date(timeIntervalSince1970: 1))] {
            do { _ = try await operations.confirmVialReadback(batch.id, observation: value); XCTFail("Expected invalid observation") }
            catch { }
            let current = try await operations.ledger()
            XCTAssertEqual(current.records.last?.state, .importClaimed); XCTAssertNil(current.pending)
        }
        let denied = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        do { _ = try await denied.confirmVialReadback(batch.id, observation: observation("KC_C")); XCTFail("Expected unknown directory refusal") }
        catch FirmwareError.unknownCompatibility {}
        _ = try await operations.confirmVialReadback(batch.id, observation: observation("KC_C", at: Date(timeIntervalSince1970: 4)))
        do { _ = try await operations.confirmVialReadback(batch.id, observation: observation("KC_NO")); XCTFail("Expected older evidence refusal") }
        catch FirmwareError.unavailable {}
        let latest = try await operations.ledger()
        XCTAssertEqual(latest.records.last?.state, .partiallyVerified)
        XCTAssertEqual(latest.records.last?.unverifiedSections, ["macros"])
        XCTAssertEqual(latest.records.last?.verifiedAt, Date(timeIntervalSince1970: 4))
    }
    func testVialReadbackEvidenceReopensAfterEveryRecordedResult() async throws {
        for (snapshot, state) in [(observation("KC_C"), FirmwareMappingState.partiallyVerified),
                                  (observation("KC_NO"), .failed), (observation("KC_C", second: "KC_A"), .externallyChanged)] {
            let (root, store, _, gate) = try await fixture()
            let fault = FirmwareFault()
            let (operations, batch) = try await exportedVial(store, gate, root: root, fault: fault)
            fault.set(.evidenceRecorded)
            do { _ = try await operations.confirmVialReadback(batch.id, observation: snapshot); XCTFail("Expected interruption") }
            catch FirmwareError.unavailable {}
            let reopened = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
            let result = try await reopened.reconcile()
            XCTAssertEqual(result.records.last?.state, state); XCTAssertNil(result.pending)
            XCTAssertEqual(result.records.last?.verifiedAt, snapshot.observedAt)
            XCTAssertEqual(result.records.last?.verificationSource, "vialKeymapReadback")
        }
    }
    private func fixture() async throws -> (URL, ObjectStore, MappingFixtureKeys, KeyAvailabilityGate) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("firmware-operation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let keys = MappingFixtureKeys()
        let store = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keys)
        _ = try await store.bootstrap(); await keys.seed()
        try await store.initializeFreshInstallation(version: KeyVersion(rawValue: 1))
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        return (root, store, keys, gate)
    }
    private func coordinator(_ store: ObjectStore, _ gate: KeyAvailabilityGate, fault: FirmwareFault = FirmwareFault(),
                             support: FirmwareSupportDirectory = firmwareSupport()) throws -> FirmwareOperationCoordinator {
        try FirmwareOperationCoordinator(store: store, support: support,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }, injection: { try fault.hit($0) })
    }
    private func retain(_ coordinator: FirmwareOperationCoordinator, axes: FirmwareVersionAxes = firmwareAxes) async throws -> FirmwareBatchRecord {
        try await coordinator.retainOriginal(firmwareBytes, backend: .via, axes: axes, confirmedAt: Date(timeIntervalSince1970: 123))
    }
    func testMultiSlotPatchPreservesOpaqueBytesAndProtectsEntrances() throws {
        let document = try FirmwareDocument(bytes: firmwareBytes, backend: .via)
        let changes = firmwareChanges + [FirmwareSlotChange(slot: FirmwareSlot(layer: 1, column: 0), output: "LCTL(KC_C)", automatic: true)]
        let actual = try document.patch(changes, expectedDevice: "42", axes: firmwareAxes, support: firmwareSupport())
        let expected = String(decoding: firmwareBytes, as: UTF8.self)
            .replacingOccurrences(of: #"["MO(1)","KC_NO","CUSTOM"]"#, with: #"["MO(1)","KC_C","CUSTOM"]"#)
            .replacingOccurrences(of: #"["KC_NO","KC_TRNS","QK_BOOT"]"#, with: #"["LCTL(KC_C)","KC_TRNS","QK_BOOT"]"#)
        XCTAssertEqual(actual, Data(expected.utf8))
        XCTAssertNotNil(actual.range(of: Data(#""macros":["sensitive macro"],"unknown": { "spaces" : [1,2] }"#.utf8)))
        XCTAssertEqual(try FirmwareDocument(bytes: actual, backend: .via).value(at: FirmwareSlot(layer: 1, column: 0)), "LCTL(KC_C)")
        for column in [0, 2] {
            let slot = FirmwareSlot(layer: column == 0 ? 0 : 1, column: column)
            XCTAssertThrowsError(try document.patch([FirmwareSlotChange(slot: slot, output: "KC_C", automatic: false)], expectedDevice: "42", axes: firmwareAxes, support: firmwareSupport()))
        }
        XCTAssertThrowsError(try document.patch([FirmwareSlotChange(slot: FirmwareSlot(layer: 1, column: 1), output: "KC_C", automatic: true)], expectedDevice: "42", axes: firmwareAxes, support: firmwareSupport()))
        XCTAssertThrowsError(try document.patch([FirmwareSlotChange(slot: FirmwareSlot(layer: 0, column: 1), output: "MACRO(1)", automatic: true)], expectedDevice: "42", axes: firmwareAxes, support: firmwareSupport()))
    }
    func testVIALayerEntriesCannotBeReplacedByManualOrAutomaticChanges() throws {
        for token in ["FN_MO13", "FN_MO23", "LM(1,MOD_LCTL)", "LM(2,MOD_LSFT | MOD_LALT)"] {
            let bytes = Data("{\"vendorProductId\":42,\"layers\":[[\"\(token)\",\"KC_NO\"]]}".utf8)
            let document = try FirmwareDocument(bytes: bytes, backend: .via)
            for automatic in [false, true] {
                XCTAssertThrowsError(try document.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_A", automatic: automatic)],
                    expectedDevice: "42", axes: firmwareAxes, support: firmwareSupport())) {
                    XCTAssertEqual($0 as? FirmwareError, .protectedEntry)
                }
            }
            let patched = try document.patch([.init(slot: .init(layer: 0, column: 1), output: "KC_A", automatic: true)],
                expectedDevice: "42", axes: firmwareAxes, support: firmwareSupport())
            XCTAssertEqual(try FirmwareDocument(bytes: patched, backend: .via).value(at: .init(layer: 0, column: 0)), token)
        }
    }
    func testVIALayerEntryRefusalDoesNotCreatePreviewArtifactOrChangeEncryptedOriginal() async throws {
        for token in ["FN_MO13", "FN_MO23", "LM(1,MOD_LCTL)", "LM(2,MOD_LSFT | MOD_LALT)"] {
            let (root, store, _, gate) = try await fixture()
            let operations = try coordinator(store, gate)
            let bytes = Data("{\"vendorProductId\":42,\"layers\":[[\"\(token)\",\"KC_NO\"]]}".utf8)
            let batch = try await operations.retainOriginal(bytes, backend: .via, axes: firmwareAxes, confirmedAt: Date())
            let changes = [FirmwareSlotChange(slot: .init(layer: 0, column: 0), output: "KC_A", automatic: false)]
            do { _ = try await operations.preview(batch.id, changes: changes); XCTFail("Layer entry must not produce a preview") }
            catch FirmwareError.protectedEntry {}
            let output = root.appendingPathComponent("patch.json")
            do {
                _ = try await operations.export(batch.id, changes: changes, destination: FirmwareFileDestination(target: output, gate: gate))
                XCTFail("Layer entry must not be overwritten")
            } catch FirmwareError.protectedEntry {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            let ledger = try await operations.ledger()
            XCTAssertEqual(ledger.records, [batch]); XCTAssertNil(ledger.pending)
            let retained = try await operations.original(batch.id)
            XCTAssertEqual(retained, bytes)
        }
    }
    func testUnknownAxesAndEmptyProductionDirectoryRefuseGeneration() throws {
        let document = try FirmwareDocument(bytes: firmwareBytes, backend: .via)
        for missing in 0..<5 {
            let values: [String?] = (0..<5).map { $0 == missing ? nil : ["fixture-schema", "fixture-protocol", "fixture-layout", "fixture-dialect", "fixture-importer"][$0] }
            let axes = FirmwareVersionAxes(definitionSchema: values[0], deviceProtocol: values[1], layoutFormat: values[2], keycodeDialect: values[3], importer: values[4])
            XCTAssertThrowsError(try document.patch(firmwareChanges, expectedDevice: "42", axes: axes, support: firmwareSupport()))
        }
        XCTAssertThrowsError(try document.patch(firmwareChanges, expectedDevice: "42", axes: firmwareAxes, support: FirmwareSupportDirectory()))
        XCTAssertThrowsError(try document.patch(firmwareChanges, expectedDevice: "43", axes: firmwareAxes, support: firmwareSupport()))
    }
    func testVialPatchPreservesUnknownSubtreesWithoutDeviceAccess() throws {
        let bytes = Data(#"{"version":1,"uid":"9007199254740993","layout":[[["KC_NO","KC_A"]]],"macro":[{"opaque":"keep"}],"combo": { "unchanged" : 1 }}"#.utf8)
        let document = try FirmwareDocument(bytes: bytes, backend: .vial)
        let result = try document.patch([FirmwareSlotChange(slot: FirmwareSlot(layer: 0, column: 0), output: "KC_C", automatic: true)],
            expectedDevice: document.device, axes: firmwareAxes, support: firmwareSupport(.vial, device: document.device))
        XCTAssertEqual(String(decoding: result, as: UTF8.self), String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "KC_NO", with: "KC_C"))
        XCTAssertThrowsError(try FirmwareDocument(bytes: Data(#"{"version":1,"uid":"1","layout":[[["KC_A"]]],"uid":"2"}"#.utf8), backend: .vial))
    }
    func testEncryptedBatchExportClaimEvidenceAndAbandonRetainOriginal() async throws {
        let (root, store, _, gate) = try await fixture()
        let coordinator = try coordinator(store, gate)
        let record = try await retain(coordinator)
        let destination = try FirmwareFileDestination(target: root.appendingPathComponent("export.json"), gate: gate)
        let exported = try await coordinator.export(record.id, changes: firmwareChanges, destination: destination)
        XCTAssertEqual(exported.records.first?.state, .awaitingUserImport)
        XCTAssertNil(exported.records.first?.verifiedAt)
        let repeated = try await coordinator.export(record.id, changes: firmwareChanges, destination: destination)
        XCTAssertEqual(repeated.records.count, 1)
        let claimed = try await coordinator.claimImport(record.id, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(claimed.records.first?.state, .importClaimed); XCTAssertNil(claimed.records.first?.verifiedAt)
        let verified = try await coordinator.confirmVIABehavior(record.id, passed: true, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(verified.records.first?.state, .verified)
        let original = try await coordinator.original(record.id)
        XCTAssertEqual(original, firmwareBytes)
        for entry in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("objects"), includingPropertiesForKeys: nil) {
            XCTAssertNil(try Data(contentsOf: entry).range(of: Data("sensitive macro".utf8)))
            XCTAssertNil(try Data(contentsOf: entry).range(of: Data(root.path.utf8)))
        }
        let later = try await retain(coordinator)
        _ = try await coordinator.export(later.id, changes: firmwareChanges, destination: destination)
        let abandoned = try await coordinator.abandon(later.id)
        XCTAssertEqual(abandoned.records.last?.state, .draft)
        let retained = try await coordinator.original(later.id)
        XCTAssertEqual(retained, firmwareBytes)
    }
    func testEveryExportJournalBoundaryReopensFromEncryptedDisk() async throws {
        for phase in [FirmwareJournalPhase.artifactReady, .exportRequested, .externalExported] {
            let (root, store, keys, gate) = try await fixture()
            let fault = FirmwareFault(); fault.set(phase)
            let coordinator = try coordinator(store, gate, fault: fault)
            let record = try await retain(coordinator)
            let target = root.appendingPathComponent("export.json")
            do { _ = try await coordinator.export(record.id, changes: firmwareChanges, destination: FirmwareFileDestination(target: target, gate: gate)); XCTFail("Expected interruption") }
            catch FirmwareError.unavailable {}
            let reopened = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keys)
            _ = try await reopened.bootstrap()
            let restored = try await self.coordinator(reopened, gate).reconcile()
            XCTAssertNil(restored.pending)
            XCTAssertEqual(restored.records.first?.state, phase == .externalExported ? .awaitingUserImport : .draft)
            XCTAssertEqual(FileManager.default.fileExists(atPath: target.path), phase == .externalExported)
        }
    }
    func testClaimEvidenceAndAbandonInterruptionsDoNotInventFacts() async throws {
        let (root, store, _, gate) = try await fixture()
        let fault = FirmwareFault()
        let coordinator = try coordinator(store, gate, fault: fault)
        let record = try await retain(coordinator)
        _ = try await coordinator.export(record.id, changes: firmwareChanges, destination: FirmwareFileDestination(target: root.appendingPathComponent("export.json"), gate: gate))
        fault.set(.claimRecorded)
        do { _ = try await coordinator.claimImport(record.id, at: Date(timeIntervalSince1970: 200)); XCTFail("Expected interruption") } catch FirmwareError.unavailable {}
        let claim = try await self.coordinator(store, gate).reconcile()
        XCTAssertEqual(claim.records.first?.importClaimedAt, Date(timeIntervalSince1970: 200)); XCTAssertNil(claim.records.first?.verifiedAt)
        fault.set(.evidenceRecorded)
        do { _ = try await coordinator.confirmVIABehavior(record.id, passed: false, at: Date(timeIntervalSince1970: 300)); XCTFail("Expected interruption") } catch FirmwareError.unavailable {}
        let failed = try await self.coordinator(store, gate).reconcile()
        XCTAssertEqual(failed.records.first?.state, .failed)
        let other = try await retain(coordinator)
        fault.set(nil)
        _ = try await coordinator.export(other.id, changes: firmwareChanges, destination: FirmwareFileDestination(target: root.appendingPathComponent("other.json"), gate: gate))
        fault.set(.abandonRequested)
        do { _ = try await coordinator.abandon(other.id); XCTFail("Expected interruption") } catch FirmwareError.unavailable {}
        let abandoned = try await self.coordinator(store, gate).reconcile()
        XCTAssertEqual(abandoned.records.last?.state, .draft)
        let original = try await coordinator.original(other.id)
        XCTAssertEqual(original, firmwareBytes)
    }
    func testFileProtectionPrivacyAndMissingExternalExportNeverOverwrite() async throws {
        let (root, store, _, gate) = try await fixture()
        let file = root.appendingPathComponent("original.json"); try firmwareBytes.write(to: file)
        let link = root.appendingPathComponent("link.json"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let fifo = root.appendingPathComponent("fifo.json"); XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        for target in [link, fifo, root] {
            let destination = try FirmwareFileDestination(target: target, gate: gate)
            XCTAssertThrowsError(try destination.write(firmwareBytes))
        }
        let destination = try FirmwareFileDestination(target: file, gate: gate)
        gate.update(.locked); gate.update(.unlocked)
        XCTAssertThrowsError(try destination.write(firmwareBytes))
        let fault = FirmwareFault(); fault.set(.externalExported)
        let coordinator = try coordinator(store, gate, fault: fault)
        let record = try await retain(coordinator)
        let exported = root.appendingPathComponent("exported.json")
        do { _ = try await coordinator.export(record.id, changes: firmwareChanges, destination: FirmwareFileDestination(target: exported, gate: gate)); XCTFail("Expected interruption") } catch FirmwareError.unavailable {}
        let external = firmwareBytes + Data(" ".utf8); try external.write(to: exported, options: .atomic)
        let recovered = try await self.coordinator(store, gate).reconcile()
        XCTAssertEqual(recovered.records.first?.state, .draft)
        XCTAssertNil(recovered.records.first?.importClaimedAt)
        XCTAssertEqual(try Data(contentsOf: exported), external)
    }
    func testFirmwareExportDirectoryReplacementCannotRedirectExistingDestination() async throws {
        for existing in [false, true] {
            let (root, _, _, gate) = try await fixture()
            let selected = root.appendingPathComponent("selected")
            let moved = root.appendingPathComponent("moved")
            try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
            let target = selected.appendingPathComponent("export.json")
            if existing { try firmwareBytes.write(to: target) }
            let destination = try FirmwareFileDestination(target: target, gate: gate)
            try FileManager.default.moveItem(at: selected, to: moved)
            try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
            if existing { try firmwareBytes.write(to: target) }
            XCTAssertThrowsError(try destination.read()) {
                XCTAssertEqual($0 as? FirmwareError, .externalChange)
            }
            XCTAssertThrowsError(try destination.write(firmwareBytes + Data(" ".utf8))) {
                XCTAssertEqual($0 as? FirmwareError, .externalChange)
            }
            if existing {
                XCTAssertEqual(try Data(contentsOf: target), firmwareBytes)
                XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("export.json")), firmwareBytes)
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: moved.appendingPathComponent("export.json").path))
            }
        }
    }
    func testFirmwareExportRejectsParentReplacedBySymlink() async throws {
        let (root, _, _, gate) = try await fixture()
        let selected = root.appendingPathComponent("selected"), moved = root.appendingPathComponent("moved")
        let replacement = root.appendingPathComponent("replacement")
        for directory in [selected, replacement] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try firmwareBytes.write(to: directory.appendingPathComponent("export.json"))
        }
        let destination = try FirmwareFileDestination(target: selected.appendingPathComponent("export.json"), gate: gate)
        try FileManager.default.moveItem(at: selected, to: moved)
        try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: replacement)
        XCTAssertThrowsError(try destination.read())
        XCTAssertThrowsError(try destination.write(firmwareBytes + Data(" ".utf8)))
        for directory in [moved, replacement] {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("export.json")), firmwareBytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["export.json"])
        }
    }
    func testFirmwareExportKeepsSelectedDirectoryThroughAliasRetargetingAndAtomicFileEdits() async throws {
        let (root, _, _, gate) = try await fixture()
        let selected = root.appendingPathComponent("selected"), other = root.appendingPathComponent("other")
        let alias = root.appendingPathComponent("alias")
        for directory in [selected, other] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try firmwareBytes.write(to: directory.appendingPathComponent("export.json"))
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: selected)
        let destination = try FirmwareFileDestination(target: alias.appendingPathComponent("export.json"), gate: gate)
        let target = selected.appendingPathComponent("export.json")
        XCTAssertEqual(destination.reference.location, target.resolvingSymlinksInPath().path)
        let edited = firmwareBytes + Data(" ".utf8)
        try edited.write(to: target, options: .atomic)
        XCTAssertEqual(try destination.read(), edited)
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: other)
        try destination.write(firmwareBytes)
        XCTAssertEqual(try Data(contentsOf: target), firmwareBytes)
        XCTAssertEqual(try Data(contentsOf: other.appendingPathComponent("export.json")), firmwareBytes)
        let reopened = try FirmwareFileDestination(reference: destination.reference, gate: gate)
        try reopened.write(edited)
        XCTAssertEqual(try Data(contentsOf: target), edited)
        XCTAssertEqual(try Data(contentsOf: other.appendingPathComponent("export.json")), firmwareBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: selected.path), ["export.json"])
    }
    func testDirectoryReplacementDuringJournaledExportPreservesBothFilesAndRecoveryCopy() async throws {
        let (root, store, _, gate) = try await fixture()
        let selected = root.appendingPathComponent("selected"), moved = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
        let target = selected.appendingPathComponent("export.json")
        try firmwareBytes.write(to: target)
        let operations = try FirmwareOperationCoordinator(store: store, support: firmwareSupport(),
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }, injection: { phase in
                if phase == .exportRequested {
                    try FileManager.default.moveItem(at: selected, to: moved)
                    try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
                    try firmwareBytes.write(to: target)
                }
            })
        let record = try await retain(operations)
        let destination = try FirmwareFileDestination(target: target, gate: gate)
        do {
            _ = try await operations.export(record.id, changes: firmwareChanges, destination: destination)
            XCTFail("Replaced export directory must be rejected")
        } catch FirmwareError.externalChange {}
        let recovered = try await coordinator(store, gate).reconcile()
        XCTAssertNil(recovered.pending)
        XCTAssertEqual(recovered.records.first?.state, .draft)
        XCTAssertNil(recovered.records.first?.exportedAt)
        XCTAssertNil(recovered.records.first?.importClaimedAt)
        let original = try await operations.original(record.id)
        XCTAssertEqual(original, firmwareBytes)
        for directory in [selected, moved] {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("export.json")), firmwareBytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["export.json"])
        }
    }
    func testOldOriginalIsNotLatestAndTwelveOriginalsAreNotPruned() async throws {
        let (_, store, _, gate) = try await fixture()
        let coordinator = try coordinator(store, gate)
        let first = try await retain(coordinator)
        for _ in 0..<11 { _ = try await retain(coordinator) }
        do { _ = try await coordinator.prepare(first.id, changes: firmwareChanges); XCTFail("Expected stale original") } catch FirmwareError.staleBaseline {}
        let ledger = try await coordinator.ledger()
        XCTAssertEqual(ledger.records.count, 12)
        let original = try await coordinator.original(first.id)
        XCTAssertEqual(original, firmwareBytes)
    }
    func testUninstallSecuresRecoveryBeforeRulesLoginAndSelectedData() async throws {
        let (root, store, _, gate) = try await fixture()
        let firmware = try coordinator(store, gate)
        let record = try await retain(firmware)
        let output = root.appendingPathComponent("restore.json")
        var events: [String] = []
        var phases: [UninstallPreparationStage] = []
        let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: { events.append("capture") },
            removeRules: { XCTAssertEqual(try Data(contentsOf: output), firmwareBytes); events.append("rules") },
            removeLogin: { events.append("login") }, eraseData: { events.append("data") }, onProgress: { phases.append($0) })
        let receipt = try await preparation.prepare(choices: [record.id: .export(FirmwareFileDestination(target: output, gate: gate))], deleteLocalData: true)
        XCTAssertEqual(events, ["capture", "rules", "login", "data"])
        XCTAssertEqual(phases, [.captureStopped, .recoverySecured, .rulesRemoved, .loginRemoved, .ready, .erasing, .completed])
        XCTAssertEqual(receipt.choices[record.id.uuidString], .exported)
    }
    func testUninstallSharedRecoveryDestinationStopsBeforeRulesAndCanRetryWithSeparateFiles() async throws {
        for deleteLocalData in [false, true] {
            for aliased in [false, true] {
                let (root, store, _, gate) = try await fixture()
                let firmware = try coordinator(store, gate), first = try await retain(firmware)
                let secondBytes = Data(#"{"vendorProductId":43,"layers":[["KC_B"]]}"#.utf8)
                let second = try await firmware.retainOriginal(secondBytes, backend: .via, axes: firmwareAxes, confirmedAt: Date())
                let directory = root.appendingPathComponent("exports")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let alias = root.appendingPathComponent("alias")
                try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true)
                let firstURL = directory.appendingPathComponent("restore.json")
                let secondURL = aliased ? alias.appendingPathComponent("../exports/restore.json") : firstURL
                var events: [String] = [], phases: [UninstallPreparationStage] = []
                let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
                    stopCapture: { events.append("capture") }, removeRules: { events.append("rules") },
                    removeLogin: { events.append("login") }, eraseData: { events.append("data") },
                    onProgress: { phases.append($0) })
                do {
                    _ = try await preparation.prepare(choices: [
                        first.id: .export(FirmwareFileDestination(target: firstURL, gate: gate)),
                        second.id: .export(FirmwareFileDestination(target: secondURL, gate: gate))], deleteLocalData: deleteLocalData)
                    XCTFail("Expected overwritten recovery copy refusal")
                } catch FirmwareError.externalChange {}
                XCTAssertEqual(events, ["capture"]); XCTAssertEqual(phases, [.captureStopped])
                let previous = try await UninstallPreparationCoordinator.previousPreparation(store: store)
                XCTAssertNil(previous)
                let originalFirst = try await firmware.original(first.id), originalSecond = try await firmware.original(second.id)
                XCTAssertEqual(originalFirst, firmwareBytes); XCTAssertEqual(originalSecond, secondBytes)
                XCTAssertEqual(try Data(contentsOf: firstURL), secondBytes)
                events = []; phases = []
                let retryURL = directory.appendingPathComponent("second.json")
                let result = try await preparation.prepare(choices: [
                    first.id: .export(FirmwareFileDestination(target: firstURL, gate: gate)),
                    second.id: .export(FirmwareFileDestination(target: retryURL, gate: gate))], deleteLocalData: deleteLocalData)
                XCTAssertEqual(events, deleteLocalData ? ["capture", "rules", "login", "data"] : ["capture", "rules", "login"])
                XCTAssertEqual(result.stage, deleteLocalData ? .completed : .ready)
                XCTAssertEqual(result.choices, [first.id.uuidString: .exported, second.id.uuidString: .exported])
                XCTAssertEqual(try Data(contentsOf: firstURL), firmwareBytes)
                XCTAssertEqual(try Data(contentsOf: retryURL), secondBytes)
            }
        }
    }
    func testUninstallSharedDestinationCanRetainIdenticalOriginals() async throws {
        let (root, store, _, gate) = try await fixture()
        let firmware = try coordinator(store, gate)
        let first = try await retain(firmware), second = try await retain(firmware)
        let destination = try FirmwareFileDestination(target: root.appendingPathComponent("identical.json"), gate: gate)
        var events: [String] = []
        let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: { events.append("capture") }, removeRules: { events.append("rules") },
            removeLogin: { events.append("login") }, eraseData: { events.append("data") })
        let result = try await preparation.prepare(choices: [first.id: .export(destination), second.id: .export(destination)], deleteLocalData: true)
        XCTAssertEqual(result.stage, .completed)
        XCTAssertEqual(events, ["capture", "rules", "login", "data"])
        XCTAssertEqual(try destination.read(), firmwareBytes)
    }
    func testUninstallFailureAndPrivacyClosureStopSubsequentSideEffects() async throws {
        let (_, store, _, gate) = try await fixture()
        let firmware = try coordinator(store, gate)
        let record = try await retain(firmware)
        var events: [String] = []
        let failed = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: {},
            removeRules: { events.append("rules"); throw FirmwareError.externalChange },
            removeLogin: { events.append("login") }, eraseData: { events.append("data") })
        do { _ = try await failed.prepare(choices: [record.id: .heldElsewhere], deleteLocalData: true); XCTFail("Expected stop") } catch FirmwareError.externalChange {}
        XCTAssertEqual(events, ["rules"])
        events = []
        let generation = try gate.begin()
        let closed = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: {},
            removeRules: { events.append("rules"); gate.update(.locked) },
            removeLogin: { events.append("login") }, eraseData: { events.append("data") },
            authorize: { try gate.use(generation) {} })
        do { _ = try await closed.prepare(choices: [record.id: .discardConfirmed], deleteLocalData: true); XCTFail("Expected closure") } catch {}
        XCTAssertEqual(events, ["rules"])
    }
    func testUninstallRefusesDataErasureWhenRecoveryCopyChangesDuringPreparation() async throws {
        let (root, store, _, gate) = try await fixture()
        let firmware = try coordinator(store, gate)
        let original = try await retain(firmware)
        let output = root.appendingPathComponent("restore.json")
        var erased = false
        let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: {},
            removeRules: { try (firmwareBytes + Data(" ".utf8)).write(to: output, options: .atomic) },
            removeLogin: {}, eraseData: { erased = true })
        do {
            _ = try await preparation.prepare(choices: [original.id: .export(FirmwareFileDestination(target: output, gate: gate))], deleteLocalData: true)
            XCTFail("Expected changed recovery copy refusal")
        } catch FirmwareError.externalChange {}
        XCTAssertFalse(erased)
    }
    func testUninstallRechecksRecoveryAfterPersistingErasureIntentAndAllowsRetry() async throws {
        for replacement in ["modified", "missing", "directory"] {
            let (root, store, _, gate) = try await fixture()
            let firmware = try coordinator(store, gate)
            let original = try await retain(firmware)
            let directory = root.appendingPathComponent("recovery")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let output = directory.appendingPathComponent("restore.json")
            var erased = false, changed = false
            var mutationError: Error?
            var phases: [UninstallPreparationStage] = []
            let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
                stopCapture: {}, removeRules: {}, removeLogin: {}, eraseData: { erased = true },
                onProgress: { phase in
                    phases.append(phase)
                    guard phase == .erasing, !changed else { return }
                    changed = true
                    do {
                        switch replacement {
                        case "modified": try (firmwareBytes + Data(" ".utf8)).write(to: output, options: .atomic)
                        case "missing": try FileManager.default.removeItem(at: output)
                        default:
                            try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("moved"))
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                            try firmwareBytes.write(to: output)
                        }
                    } catch { mutationError = error }
                })
            do {
                _ = try await preparation.prepare(choices: [original.id: .export(FirmwareFileDestination(target: output, gate: gate))], deleteLocalData: true)
                XCTFail("A recovery change after recording erasure intent must stop deletion: \(replacement)")
            } catch FirmwareError.externalChange {}
            XCTAssertNil(mutationError)
            XCTAssertTrue(changed)
            XCTAssertFalse(erased)
            XCTAssertEqual(phases.last, .erasing)
            let retained = try await firmware.original(original.id)
            XCTAssertEqual(retained, firmwareBytes)
            let previous = try await UninstallPreparationCoordinator.previousPreparation(store: store)
            XCTAssertEqual(previous?.stage, .erasing)
            let result = try await preparation.prepare(choices: [original.id: .export(FirmwareFileDestination(target: output, gate: gate))], deleteLocalData: true)
            XCTAssertTrue(erased)
            XCTAssertEqual(result.stage, .completed)
            XCTAssertEqual(try Data(contentsOf: output), firmwareBytes)
        }
    }
    func testUninstallSerializesNewOriginalsUntilThePreparationEnds() async throws {
        let (_, store, _, gate) = try await fixture()
        let firmware = try coordinator(store, gate)
        let original = try await retain(firmware)
        var erased = false
        let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: {},
            removeRules: { _ = try await self.retain(firmware) }, removeLogin: {}, eraseData: { erased = true })
        do { _ = try await preparation.prepare(choices: [original.id: .heldElsewhere], deleteLocalData: true); XCTFail("Expected serialization") }
        catch FirmwareError.busy {}
        XCTAssertFalse(erased)
        let next = try await retain(firmware)
        XCTAssertNotEqual(next.id, original.id)
    }
    func testPreviousPreparationLoadsLastCompletedStageAndRetryRequiresCurrentCopies() async throws {
        let (_, store, _, gate) = try await fixture()
        let firmware = try coordinator(store, gate)
        let missing = try await UninstallPreparationCoordinator.previousPreparation(store: store)
        XCTAssertNil(missing)
        let first = try await retain(firmware)
        var calls: [String] = []
        let failed = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: { calls.append("capture") }, removeRules: { calls.append("rules") },
            removeLogin: { calls.append("login"); throw FirmwareError.unavailable }, eraseData: { calls.append("data") })
        do { _ = try await failed.prepare(choices: [first.id: .heldElsewhere], deleteLocalData: true); XCTFail("Expected login failure") }
        catch FirmwareError.unavailable {}
        let loaded = try await UninstallPreparationCoordinator.previousPreparation(store: store)
        let previous = try XCTUnwrap(loaded)
        XCTAssertEqual(previous.stage, .rulesRemoved); XCTAssertTrue(previous.deleteLocalData)
        XCTAssertEqual(previous.choices, [first.id.uuidString: .heldElsewhere])
        let second = try await retain(firmware)
        calls = []
        let retry = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: { calls.append("capture") }, removeRules: { calls.append("rules") },
            removeLogin: { calls.append("login") }, eraseData: { calls.append("data") })
        do { _ = try await retry.prepare(choices: [first.id: .heldElsewhere], deleteLocalData: false); XCTFail("Expected new copy refusal") }
        catch FirmwareError.unavailable {}
        XCTAssertEqual(calls, ["capture"])
        let unchanged = try await UninstallPreparationCoordinator.previousPreparation(store: store)
        XCTAssertEqual(unchanged, previous)
        calls = []
        let result = try await retry.prepare(choices: [first.id: .heldElsewhere, second.id: .discardConfirmed], deleteLocalData: false)
        XCTAssertEqual(calls, ["capture", "rules", "login"])
        XCTAssertEqual(result.stage, .ready); XCTAssertFalse(result.deleteLocalData)
        XCTAssertNotEqual(result.id, previous.id)
        let reopened = try await UninstallPreparationCoordinator.previousPreparation(store: store)
        XCTAssertEqual(reopened, result)
    }
    func testCaptureStopFailureLeavesRecoveryCopiesAndLaterPortsUntouched() async throws {
        let (_, store, _, gate) = try await fixture()
        let firmware = try coordinator(store, gate)
        let original = try await retain(firmware)
        var events: [String] = []
        var phases: [UninstallPreparationStage] = []
        let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
            stopCapture: { events.append("capture"); throw FirmwareError.unavailable },
            removeRules: { events.append("rules") }, removeLogin: { events.append("login") },
            eraseData: { events.append("data") }, onProgress: { phases.append($0) })
        do { _ = try await preparation.prepare(choices: [original.id: .heldElsewhere], deleteLocalData: true); XCTFail("Expected stop failure") }
        catch FirmwareError.unavailable {}
        XCTAssertEqual(events, ["capture"]); XCTAssertTrue(phases.isEmpty)
        let retained = try await firmware.original(original.id)
        XCTAssertEqual(retained, firmwareBytes)
    }
}

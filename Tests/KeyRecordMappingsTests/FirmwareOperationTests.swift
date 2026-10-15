import XCTest
import Foundation
import Darwin
import KeyRecordCore
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
    private let vialBytes = Data(#"{"version":1,"uid":"fixture-vial","layout":[[["KC_NO","CUSTOM"]]],"macros":["opaque macro"]}"#.utf8)
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

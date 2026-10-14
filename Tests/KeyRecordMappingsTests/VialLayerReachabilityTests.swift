import XCTest
import Foundation
import KeyRecordCore
import KeyRecordStore
@testable import KeyRecordMappings

@MainActor
final class VialLayerReachabilityTests: XCTestCase {
    private func document(_ entry: String, alternate: String = "KC_NO", layers: Int = 17) throws -> FirmwareDocument {
        var layout = Array(repeating: [["KC_NO", "KC_NO", "KC_NO"]], count: layers)
        layout[0][0][0] = entry
        layout[0][0][2] = alternate
        layout[1][0][0] = "MO(2)"
        let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "uid": 42, "via_protocol": 9,
            "vial_protocol": 6, "layout": layout])
        return try FirmwareDocument(bytes: bytes, backend: .vial)
    }
    private func context(_ document: FirmwareDocument) throws -> (FirmwareVersionAxes, FirmwareSupportDirectory) {
        let axes = try FirmwareVersionProvider.axes(bytes: document.bytes, backend: .vial,
            definitionSchema: "offline-reachability", importer: "offline-reachability")
        return (axes, FirmwareSupportDirectory(entries: [.init(backend: .vial, device: "42", axes: axes, supportedOutputs: ["KC_C"])]))
    }
    private func patch(_ document: FirmwareDocument, layer: Int, automatic: Bool) throws -> Data {
        let (axes, support) = try context(document)
        return try document.patch([.init(slot: .init(layer: layer, column: 1), output: "KC_C", automatic: automatic)],
            expectedDevice: "42", axes: axes, support: support)
    }
    func testRejectedLayerExpressionsCannotAuthorizeDirectOrTransitiveTargets() throws {
        let tokens = ["MO(1,2)", "MO(1,)", "TG(1,2)", "DF(1,2)", "OSL(1,2)", "TT(1,2)", "TO(1,2)",
            "LT(1,USER00)", "LT(1,MO(0))", "LT(1,KC_A,KC_B)", "LT(1,)", "LT(1)", "LT(16,KC_A)", "LT1(USER00)"]
        for token in tokens {
            XCTAssertThrowsError(try VialKeycodeDialect.rawValue(token), token)
            let doc = try document(token), (axes, support) = try context(doc)
            for automatic in [true, false] {
                for layer in [1, 2, 16] {
                    XCTAssertThrowsError(try patch(doc, layer: layer, automatic: automatic)) {
                        XCTAssertEqual($0 as? FirmwareError, .unreachableLayer, "\(token) -> \(layer), automatic=\(automatic)")
                    }
                }
                XCTAssertThrowsError(try doc.patch([.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: automatic)],
                    expectedDevice: "42", axes: axes, support: support)) {
                    XCTAssertEqual($0 as? FirmwareError, .protectedEntry, token)
                }
                let result = try FirmwareDocument(bytes: patch(doc, layer: 0, automatic: automatic), backend: .vial)
                XCTAssertEqual(try result.value(at: .init(layer: 0, column: 0)), token)
                XCTAssertEqual(try result.value(at: .init(layer: 0, column: 1)), "KC_C")
            }
        }
    }
    func testValidEntriesRetainAutomaticOneHopAndManualTransitiveReachability() throws {
        for token in ["MO(1)", "0x5221", "LT(1,KC_A)", "LT1(KC_A)", "0x4104"] {
            let doc = try document(token)
            for automatic in [true, false] {
                let result = try FirmwareDocument(bytes: patch(doc, layer: 1, automatic: automatic), backend: .vial)
                XCTAssertEqual(try result.value(at: .init(layer: 1, column: 1)), "KC_C", token)
            }
            _ = try patch(doc, layer: 2, automatic: false)
            XCTAssertThrowsError(try patch(doc, layer: 2, automatic: true)) {
                XCTAssertEqual($0 as? FirmwareError, .unreachableLayer, token)
            }
        }
        for token in ["TG(1)", "DF(1)", "OSL(1)", "TT(1)", "TO(1)", "0x5261", "0x5241", "0x5281", "0x52c1", "0x5201"] {
            let doc = try document(token)
            for layer in [1, 2] {
                _ = try patch(doc, layer: layer, automatic: false)
                XCTAssertThrowsError(try patch(doc, layer: layer, automatic: true)) {
                    XCTAssertEqual($0 as? FirmwareError, .unreachableLayer, token)
                }
            }
        }
        for token in ["MO(31)", "LT15(KC_A)"] {
            let doc = try document(token, layers: 3)
            XCTAssertThrowsError(try patch(doc, layer: 1, automatic: false)) {
                XCTAssertEqual($0 as? FirmwareError, .unreachableLayer, token)
            }
        }
    }
    func testUnknownEntryDoesNotInvalidateAnIndependentValidPath() throws {
        for token in ["MO(1,2)", "LT(1,USER00)", "USER00"] {
            let doc = try document(token, alternate: "MO(1)")
            for automatic in [true, false] {
                let result = try FirmwareDocument(bytes: patch(doc, layer: 1, automatic: automatic), backend: .vial)
                XCTAssertEqual(try result.value(at: .init(layer: 0, column: 0)), token)
                XCTAssertEqual(try result.value(at: .init(layer: 0, column: 2)), "MO(1)")
                XCTAssertEqual(try result.value(at: .init(layer: 1, column: 1)), "KC_C")
            }
        }
    }
    func testRefusedPreviewPrepareAndExportPreserveDestinationAndEncryptedDraft() async throws {
        for existing in [false, true] {
            for automatic in [true, false] {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("vial-reachability-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                addTeardownBlock { try? FileManager.default.removeItem(at: root) }
                let keys = MappingFixtureKeys(), gate = KeyAvailabilityGate(); gate.update(.unlocked)
                let store = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keys)
                _ = try await store.bootstrap(); await keys.seed(); try await store.initializeFreshInstallation(version: .init(rawValue: 1))
                let doc = try document("MO(1,2)"), (axes, support) = try context(doc)
                let operations = try FirmwareOperationCoordinator(store: store, support: support,
                    resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
                let batch = try await operations.retainOriginal(doc.bytes, backend: .vial, axes: axes, confirmedAt: Date(timeIntervalSince1970: 1))
                let before = try await operations.ledger(), entryCount = try await store.entries().count
                let url = root.appendingPathComponent("destination.vil"), sentinel = Data("existing user export".utf8)
                if existing { try sentinel.write(to: url) }
                let destination = try FirmwareFileDestination(target: url, gate: gate)
                let changes = [FirmwareSlotChange(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: automatic)]
                do { _ = try await operations.preview(batch.id, changes: changes); XCTFail("Unexpected preview") }
                catch { XCTAssertEqual(error as? FirmwareError, .unreachableLayer) }
                do { _ = try await operations.prepare(batch.id, changes: changes); XCTFail("Unexpected artifact") }
                catch { XCTAssertEqual(error as? FirmwareError, .unreachableLayer) }
                do { _ = try await operations.export(batch.id, changes: changes, destination: destination); XCTFail("Unexpected export") }
                catch { XCTAssertEqual(error as? FirmwareError, .unreachableLayer) }
                if existing { XCTAssertEqual(try Data(contentsOf: url), sentinel) }
                else { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
                let reopened = try FirmwareOperationCoordinator(store: store, support: support,
                    resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
                let restored = try await reopened.reconcile(), original = try await reopened.original(batch.id)
                let afterCount = try await store.entries().count
                XCTAssertEqual(restored, before); XCTAssertEqual(original, doc.bytes); XCTAssertEqual(afterCount, entryCount)
                let valid = [FirmwareSlotChange(slot: .init(layer: 0, column: 1), output: "KC_C", automatic: true)]
                let recovered = try await operations.export(batch.id, changes: valid,
                    destination: FirmwareFileDestination(target: root.appendingPathComponent("valid.vil"), gate: gate))
                XCTAssertEqual(recovered.records.last?.state, .awaitingUserImport)
            }
        }
    }
}

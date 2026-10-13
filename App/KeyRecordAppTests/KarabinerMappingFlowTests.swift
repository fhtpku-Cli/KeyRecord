import XCTest
import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordMappings
import KeyRecordStore

extension FirmwareCopiesModel {
    func fixtureUninstallRequest(choice: Int, deleteData: Bool, discard: Bool) throws -> UninstallRequest {
        let option = try XCTUnwrap(RecoveryOption(rawValue: choice))
        return UninstallRequest(records: records, selections: Dictionary(uniqueKeysWithValues: records.map {
            ($0.id, RecoverySelection(option: option, discardConfirmed: discard))
        }), deleteLocalData: deleteData)
    }
}

private actor NativeMappingFixtureKeys: ObjectStoreKeySource {
    var present = false
    func seed() { present = true }
    func namespaceKeyVersions() -> Set<KeyVersion> { present ? [KeyVersion(rawValue: 1)] : [] }
    func material(for version: KeyVersion) throws -> Data { Data(repeating: 0xb3, count: 32) }
}
private final class DeploymentVersionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String? = "fixture-v1"
    func value() -> String? { lock.withLock { current } }
    func set(_ value: String?) { lock.withLock { current = value } }
}

@MainActor
final class KarabinerMappingFlowTests: XCTestCase {
    func testLoginBackendRepeatedRemovalAcceptsOnlyNativeJobNotFound() async throws {
        let removed = ProductLogin.make(registrationIsAbsent: { true }, unregisterService: {
            XCTFail("Absent login item must not be removed twice")
        })
        try await removed.unregister(); try await removed.unregister()
        if let fixtures = ProductLogin.nativeRejectionFixtures {
            let absent = ProductLogin.make(registrationIsAbsent: { false }, unregisterService: {
                throw fixtures.absent
            })
            try await absent.unregister(); try await absent.unregister()
            for failure in fixtures.denied {
                let rejected = ProductLogin.make(registrationIsAbsent: { false }, unregisterService: { throw failure })
                do { try await rejected.unregister(); XCTFail("Expected refusal") }
                catch { XCTAssertEqual(error as? LoginItemSystemRejection, .unregistrationDenied) }
            }
        }
    }
    private let fixtureAxes = FirmwareVersionAxes(definitionSchema: "synthetic-schema", deviceProtocol: "synthetic-protocol",
        layoutFormat: "synthetic-layout", keycodeDialect: "synthetic-dialect", importer: "synthetic-importer")
    private func qualifiedFirmware(_ model: FirmwareCopiesModel, store: ObjectStore, gate: KeyAvailabilityGate) {
        let axes = fixtureAxes
        model.configure(store: store, gate: gate,
            support: FirmwareSupportDirectory(entries: [FirmwareCompatibility(backend: .via, device: "42", axes: axes, supportedOutputs: ["KC_C"])]),
            versionAxes: { _ in axes })
    }
    func testNativeQualifiedFirmwareExportAndEvidenceButtons() throws {
        ScreenEvidence.prepare()
        var fixture: FlowFixture?
        var target: URL?
        var retained: FirmwareBatchRecord?
        ScreenEvidence.awaitMain {
            do {
                let result = try await self.deployment(); fixture = result.0; target = result.1
                self.qualifiedFirmware(result.0.flow.firmwareCopies, store: result.2, gate: result.3)
                retained = try await self.retainOriginal(result.0.flow.firmwareCopies)
            } catch { XCTFail("\(error)") }
        }
        let model = try XCTUnwrap(fixture?.flow.firmwareCopies)
        let record = try XCTUnwrap(retained)
        let artifact = try XCTUnwrap(target).deletingLastPathComponent().appendingPathComponent("native-patch.json")
        model.selectExport = { _ in artifact }
        let view = NSHostingView(rootView: Form {
            FirmwareCopiesSection(model: model, viaBytes: nil, text: NativeText(locale: "en"))
        }.formStyle(.grouped).frame(width: 900, height: 1200))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
        func press(_ id: String, state: FirmwareMappingState) throws {
            let done = XCTestExpectation(description: "Native firmware operation \(state)")
            var delivered = false
            model.onChange = {
                if !delivered, model.records.last?.state == state { delivered = true; done.fulfill() }
            }
            XCTAssertTrue(KRAXPress(try NativeEvidence.node(id, in: view)))
            ScreenEvidence.awaitMain {
                let result = await XCTWaiter.fulfillment(of: [done], timeout: 5)
                XCTAssertEqual(result, .completed)
            }
            NativeEvidence.update(view); NativeEvidence.update(view)
        }
        try press("patch-" + record.id.uuidString, state: .awaitingUserImport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.path))
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("claim-" + record.id.uuidString, in: view)))
        NativeEvidence.update(view)
        XCTAssertEqual(model.records.last?.state, .awaitingUserImport)
        try press("firmware-confirm-" + record.id.uuidString, state: .importClaimed)
        XCTAssertNil(model.records.last?.verifiedAt)
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("passed-" + record.id.uuidString, in: view)))
        NativeEvidence.update(view)
        try press("firmware-confirm-" + record.id.uuidString, state: .verified)
        XCTAssertNotNil(model.records.last?.verifiedAt)
        if let directory = NativeEvidence.outputRoot() {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ScreenEvidence.capturePNG(view).write(to: directory.appendingPathComponent("synthetic-firmware-verified-en.png"))
        }
    }
    func testFirmwareExportImportEvidenceAbandonAndRollbackAreDistinct() async throws {
        let (fixture, file, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        var record = try await retainOriginal(model)
        XCTAssertFalse(model.canGenerate(record))
        qualifiedFirmware(model, store: store, gate: gate)
        record = try await retainOriginal(model)
        XCTAssertTrue(model.canGenerate(record))
        let output = file.deletingLastPathComponent().appendingPathComponent("patch.json")
        let changes = [FirmwareSlotChange(slot: FirmwareSlot(layer: 0, column: 0), output: "KC_C", automatic: false)]
        model.selectExport = { _ in nil }
        await model.exportChanges(record, changes: changes, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.last?.state, .draft)
        model.selectExport = { _ in output }
        await model.exportChanges(record, changes: changes, ticket: try XCTUnwrap(model.selectionTicket()))
        record = try XCTUnwrap(model.records.last)
        XCTAssertEqual(record.state, .awaitingUserImport)
        XCTAssertNil(record.importClaimedAt); XCTAssertNil(record.verifiedAt)
        let document = try FirmwareDocument(bytes: Data(contentsOf: output), backend: .via)
        XCTAssertEqual(try document.value(at: FirmwareSlot(layer: 0, column: 0)), "KC_C")
        await model.perform(.claimImport, record: record, ticket: try XCTUnwrap(model.selectionTicket()))
        record = try XCTUnwrap(model.records.last)
        XCTAssertEqual(record.state, .importClaimed); XCTAssertNil(record.verifiedAt)
        await model.perform(.viaFailed, record: record, ticket: try XCTUnwrap(model.selectionTicket()))
        record = try XCTUnwrap(model.records.last)
        XCTAssertEqual(record.state, .failed)
        await model.perform(.viaPassed, record: record, ticket: try XCTUnwrap(model.selectionTicket()))
        record = try XCTUnwrap(model.records.last)
        XCTAssertEqual(record.state, .verified); XCTAssertNotNil(record.verifiedAt)
        await model.perform(.rollback, record: record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.last?.state, .rolledBack); XCTAssertNil(model.records.last?.verifiedAt)
        record = try await retainOriginal(model)
        await model.exportChanges(record, changes: changes, ticket: try XCTUnwrap(model.selectionTicket()))
        record = try XCTUnwrap(model.records.last)
        let external = try Data(contentsOf: output)
        await model.perform(.abandon, record: record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.last?.state, .draft)
        XCTAssertEqual(try Data(contentsOf: output), external)
        let original = try await FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).original(record.id)
        XCTAssertNotEqual(original, external)
    }
    private let vialOriginal = Data(#"{"version":1,"uid":18446744073709551615,"layout":[[["KC_NO","CUSTOM"]]],"macros":["opaque recovery marker"],"unknown": { "spaces" : [1,2] }}"#.utf8)
    private func claimedVial(_ fixture: FlowFixture, file: URL, store: ObjectStore, gate: KeyAvailabilityGate,
                             readback: (@Sendable (FirmwareBatchRecord) async throws -> VialKeymapObservation)?) async throws -> FirmwareBatchRecord {
        let model = fixture.flow.firmwareCopies
        let axes = fixtureAxes
        model.configure(store: store, gate: gate,
            support: FirmwareSupportDirectory(entries: [FirmwareCompatibility(backend: .vial, device: "18446744073709551615", axes: axes, supportedOutputs: ["KC_C"])]),
            versionAxes: { _ in axes }, vialReadback: readback)
        let original = file.deletingLastPathComponent().appendingPathComponent("readback-original.vil")
        try vialOriginal.write(to: original); model.selectVial = { original }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        let patch = file.deletingLastPathComponent().appendingPathComponent("readback-patch.vil")
        model.selectExport = { _ in patch }
        var record = try XCTUnwrap(model.records.last)
        await model.exportChanges(record, changes: [FirmwareSlotChange(slot: FirmwareSlot(layer: 0, column: 0), output: "KC_C", automatic: false)],
            ticket: try XCTUnwrap(model.selectionTicket()))
        record = try XCTUnwrap(model.records.last)
        await model.perform(.claimImport, record: record, ticket: try XCTUnwrap(model.selectionTicket()))
        return try XCTUnwrap(model.records.last)
    }
    func testNativeVialReadbackButtonUsesOnlyInjectedQualifiedSnapshot() throws {
        ScreenEvidence.prepare()
        var fixture: FlowFixture?
        var record: FirmwareBatchRecord?
        ScreenEvidence.awaitMain {
            do {
                let value = try await self.deployment(); fixture = value.0
                let axes = self.fixtureAxes
                record = try await self.claimedVial(value.0, file: value.1, store: value.2, gate: value.3, readback: { _ in
                    VialKeymapObservation(device: "18446744073709551615", axes: axes,
                        values: [FirmwareSlot(layer: 0, column: 0): "KC_C", FirmwareSlot(layer: 0, column: 1): "CUSTOM"], observedAt: Date())
                })
            } catch { XCTFail("\(error)") }
        }
        let model = try XCTUnwrap(fixture?.flow.firmwareCopies); let batch = try XCTUnwrap(record)
        XCTAssertEqual(batch.state, .importClaimed); XCTAssertNil(batch.verifiedAt)
        let view = NSHostingView(rootView: Form {
            FirmwareCopiesSection(model: model, viaBytes: nil, text: NativeText(locale: "en"))
        }.formStyle(.grouped).frame(width: 900, height: 1200))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
        let verified = XCTestExpectation(description: "Synthetic Vial comparison recorded")
        var delivered = false
        model.onChange = {
            if !delivered, model.records.last?.state == .verified { delivered = true; verified.fulfill() }
        }
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("readback-" + batch.id.uuidString, in: view)))
        ScreenEvidence.awaitMain {
            let result = await XCTWaiter.fulfillment(of: [verified], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
        XCTAssertEqual(model.records.last?.verificationSource, "vialKeymapReadback")
        NativeEvidence.update(view)
        if let directory = NativeEvidence.outputRoot() {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ScreenEvidence.capturePNG(view).write(to: directory.appendingPathComponent("synthetic-vial-readback-en.png"))
        }
    }
    func testVialReadbackNoDefaultPortAndLateResponseCannotCrossPrivacyGeneration() async throws {
        let (fixture, file, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        let withoutPort = try await claimedVial(fixture, file: file, store: store, gate: gate, readback: nil)
        XCTAssertFalse(model.canVerifyVial(withoutPort))
        let axes = fixtureAxes
        let record = try await claimedVial(fixture, file: file, store: store, gate: gate, readback: { _ in
            await MainActor.run {
                gate.update(.locked); fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
                gate.update(.unlocked); fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
            }
            return VialKeymapObservation(device: "18446744073709551615", axes: axes,
                values: [FirmwareSlot(layer: 0, column: 0): "KC_C", FirmwareSlot(layer: 0, column: 1): "CUSTOM"], observedAt: Date())
        })
        await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
        await model.refresh()
        XCTAssertEqual(model.records.last?.state, .importClaimed); XCTAssertNil(model.records.last?.verifiedAt)
    }
    func testVialOriginalRetentionExportAndInvalidSelectionRemainOffline() async throws {
        let (fixture, file, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        let selected = file.deletingLastPathComponent().appendingPathComponent("original.vil")
        try vialOriginal.write(to: selected)
        model.selectVial = { selected }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        let record = try XCTUnwrap(model.records.last)
        XCTAssertEqual(record.backend, .vial); XCTAssertEqual(record.device, "18446744073709551615")
        XCTAssertFalse(record.axes.complete)
        let output = file.deletingLastPathComponent().appendingPathComponent("restoration.vil")
        model.selectExport = { _ in output }
        await model.exportOriginal(record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(try Data(contentsOf: output), vialOriginal)
        let fresh = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let original = try await fresh.original(record.id)
        XCTAssertEqual(original, vialOriginal)
        model.selectVial = { nil }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.count, 1)
        try Data("{}".utf8).write(to: selected)
        model.selectVial = { selected }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.count, 1); XCTAssertNotNil(model.issueKey)
        let link = file.deletingLastPathComponent().appendingPathComponent("link.vil")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: selected)
        model.selectVial = { link }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.count, 1)
        model.selectVial = {
            fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
            return selected
        }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertTrue(model.records.isEmpty)
        let retained = try await fresh.ledger()
        XCTAssertEqual(retained.records.count, 1)
    }
    private func retainOriginal(_ model: FirmwareCopiesModel) async throws -> FirmwareBatchRecord {
        let original = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["KC_NO"]]}"#.utf8)
        model.selectedOriginal = { original }
        await model.retainVIA(original, ticket: try XCTUnwrap(model.selectionTicket()))
        return try XCTUnwrap(model.records.last)
    }
    func testNativeUninstallAndCopyDeletionRequireSeparateConfirmation() throws {
        ScreenEvidence.prepare()
        var fixture: FlowFixture!
        var original: FirmwareBatchRecord!
        ScreenEvidence.awaitMain {
            do {
                let result = try await self.deployment()
                fixture = result.0
                original = try await self.retainOriginal(fixture.flow.firmwareCopies)
            } catch { XCTFail("Fixture setup failed: \(error)") }
        }
        XCTAssertNotNil(fixture); XCTAssertNotNil(original)
        let model = fixture.flow.firmwareCopies
        var calls: [String] = []
        model.configureUninstall(.init(stopCapture: {}, removeRules: { calls.append("rules") }, removeLogin: { calls.append("login") },
            eraseData: { calls.append("data") }, editing: { _ in }))
        model.recoverySelections[original.id] = .init(option: .heldElsewhere)
        let view = NSHostingView(rootView: Form {
            FirmwareCopiesSection(model: model, viaBytes: nil, text: NativeText(locale: "en"))
        }.formStyle(.grouped).frame(width: 900, height: 1200))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(view); NativeEvidence.update(view)
        let vial = fixture.journalURL.deletingLastPathComponent().appendingPathComponent("native-original.vil")
        try vialOriginal.write(to: vial); model.selectVial = { vial }
        let retained = XCTestExpectation(description: "Native Vial recovery copy retained")
        var retainedDelivered = false
        model.onChange = {
            if !retainedDelivered, model.records.count == 2 { retainedDelivered = true; retained.fulfill() }
        }
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase4.retainVial", in: view)))
        ScreenEvidence.awaitMain {
            let result = await XCTWaiter.fulfillment(of: [retained], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
        NativeEvidence.update(view)
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("delete-" + original.id.uuidString, in: view)))
        NativeEvidence.update(view)
        XCTAssertEqual(model.records.count, 2)
        let deleted = XCTestExpectation(description: "Confirmed synthetic copy deletion")
        var deletionDelivered = false
        model.onChange = {
            if !deletionDelivered, model.records.count == 1, model.records.first?.backend == .vial {
                deletionDelivered = true; deleted.fulfill()
            }
        }
        let confirmation = try NativeEvidence.node("phase4.confirmDeleteOriginal", in: view)
        XCTAssertTrue(KRAXPress(confirmation))
        ScreenEvidence.awaitMain {
            let result = await XCTWaiter.fulfillment(of: [deleted], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
        NativeEvidence.update(view)
        let retainedVial = try XCTUnwrap(model.records.first)
        model.recoverySelections[retainedVial.id] = .init(option: .heldElsewhere)
        NativeEvidence.update(view)
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase4.prepareUninstall", in: view)))
        NativeEvidence.update(view); XCTAssertTrue(calls.isEmpty)
        let prepared = XCTestExpectation(description: "Confirmed synthetic uninstall ports")
        var preparationDelivered = false
        model.onChange = {
            if !preparationDelivered, model.uninstallReady { preparationDelivered = true; prepared.fulfill() }
        }
        let uninstall = try NativeEvidence.node("phase4.confirmUninstall", in: view)
        XCTAssertTrue(KRAXPress(uninstall))
        ScreenEvidence.awaitMain {
            let result = await XCTWaiter.fulfillment(of: [prepared], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
        XCTAssertEqual(calls, ["rules", "login"])
        XCTAssertEqual(model.uninstallStage, .ready)
        XCTAssertEqual(model.records.count, 1)
        if let output = NativeEvidence.outputRoot() {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try ScreenEvidence.capturePNG(view).write(to: output.appendingPathComponent("uninstall-en.png"))
        }
    }
    func testUninstallNativeModelExportsBeforeRulesAndLoginKeepsDataByDefault() async throws {
        let (fixture, file, _, _) = try await deployment()
        let flow = fixture.flow; let model = flow.firmwareCopies
        let original = try await retainOriginal(model)
        let copy = file.deletingLastPathComponent().appendingPathComponent("recovery.json")
        model.selectExport = { _ in copy }
        await flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        try stage(flow.karabinerMappings); await flow.karabinerMappings.check(); await flow.karabinerMappings.apply()
        XCTAssertNotEqual(try Data(contentsOf: file), bytes)
        var order: [String] = []
        flow.actions.setLoginItem = { _ in XCTFail("Login toggle cannot race uninstall") }
        model.configureUninstall(.init(stopCapture: {}, removeRules: {
            XCTAssertNotNil(try? Data(contentsOf: copy)); order.append("rules")
            flow.requestReset(); flow.requestDeleteLocalData(); await flow.setLoginItem(enabled: true)
            XCTAssertEqual(flow.dialog, .none)
            try await flow.karabinerDeployment.removeForUninstall()
        }, removeLogin: { order.append("login") }, eraseData: { order.append("data") },
        editing: { flow.karabinerMappings.maintenance = $0 }))
        XCTAssertFalse(model.deleteLocalData)
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: try model.fixtureUninstallRequest(choice: 0, deleteData: false, discard: false))
        XCTAssertEqual(order, ["rules", "login"])
        XCTAssertTrue(model.uninstallReady); XCTAssertNil(model.issueKey)
        XCTAssertEqual(model.uninstallStage, .ready)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(model.records.map(\.id), [original.id])
        XCTAssertFalse(flow.karabinerMappings.maintenance)
    }
    func testUninstallCancellationRejectionAndPrivacyStopDestructivePorts() async throws {
        let (fixture, _, _, _) = try await deployment()
        let model = fixture.flow.firmwareCopies
        _ = try await retainOriginal(model)
        var calls: [String] = []
        model.configureUninstall(.init(stopCapture: {}, removeRules: { calls.append("rules") },
            removeLogin: { calls.append("login"); throw FirmwareError.unavailable },
            eraseData: { calls.append("data") }, editing: { _ in }))
        model.selectExport = { _ in nil }
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: try model.fixtureUninstallRequest(choice: 0, deleteData: true, discard: false))
        XCTAssertTrue(calls.isEmpty); XCTAssertFalse(model.working)
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: try model.fixtureUninstallRequest(choice: 2, deleteData: true, discard: false))
        XCTAssertTrue(calls.isEmpty); XCTAssertFalse(model.uninstallReady)
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: try model.fixtureUninstallRequest(choice: 1, deleteData: true, discard: false))
        XCTAssertEqual(calls, ["rules", "login"]); XCTAssertFalse(model.uninstallReady)
        XCTAssertEqual(model.uninstallStage, .rulesRemoved)
        let ticket = try XCTUnwrap(model.selectionTicket())
        fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
        await model.prepareUninstall(ticket: ticket, request: try model.fixtureUninstallRequest(choice: 1, deleteData: true, discard: false))
        XCTAssertEqual(calls, ["rules", "login"])
    }
    func testDeploymentRefreshWaitsForUninstallMaintenanceThenReportsExternalChange() async throws {
        let (fixture, file, _, _) = try await deployment()
        let flow = fixture.flow
        await flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        try stage(flow.karabinerMappings); await flow.karabinerMappings.check(); await flow.karabinerMappings.apply()
        let model = flow.karabinerMappings
        let prior = model.lastLedger
        model.maintenance = true
        try (Data(contentsOf: file) + Data(" ".utf8)).write(to: file, options: .atomic)
        await model.refresh()
        XCTAssertFalse(model.working); XCTAssertEqual(model.lastLedger, prior)
        let refreshed = XCTestExpectation(description: "External changes reconcile after maintenance")
        var delivered = false
        model.onChange = {
            if !delivered, model.lastLedger?.batches.last?.state == .externallyChanged { delivered = true; refreshed.fulfill() }
        }
        model.maintenance = false
        await fulfillment(of: [refreshed], timeout: 5)
        XCTAssertEqual(model.lastLedger?.batches.last?.state, .externallyChanged)
    }
    func testUninstallMixedPerCopyChoicesRequireIndividualDiscardConfirmation() async throws {
        let (fixture, file, store, _) = try await deployment()
        let model = fixture.flow.firmwareCopies
        let first = try await retainOriginal(model)
        let second = try await retainOriginal(model)
        let third = try await retainOriginal(model)
        let output = file.deletingLastPathComponent().appendingPathComponent("mixed-recovery.json")
        var exported: [UUID] = []; var calls: [String] = []
        model.selectExport = { exported.append($0.id); return output }
        model.configureUninstall(.init(stopCapture: { calls.append("capture") }, removeRules: { calls.append("rules") },
            removeLogin: { calls.append("login") }, eraseData: { calls.append("data") }, editing: { _ in }))
        model.recoverySelections[second.id] = .init(option: .heldElsewhere)
        model.recoverySelections[third.id] = .init(option: .discard)
        XCTAssertEqual(model.recoverySelection(for: first).option, .export)
        XCTAssertFalse(model.canPrepareUninstall)
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: model.uninstallRequest())
        XCTAssertTrue(calls.isEmpty); XCTAssertTrue(exported.isEmpty)
        model.recoverySelections[third.id] = .init(option: .discard, discardConfirmed: true)
        XCTAssertTrue(model.canPrepareUninstall)
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: model.uninstallRequest())
        XCTAssertEqual(exported, [first.id]); XCTAssertEqual(calls, ["capture", "rules", "login"])
        let loaded = try await UninstallPreparationCoordinator.previousPreparation(store: store)
        let receipt = try XCTUnwrap(loaded)
        XCTAssertEqual(receipt.choices, [first.id.uuidString: .exported, second.id.uuidString: .heldElsewhere, third.id.uuidString: .discarded])
        XCTAssertFalse(receipt.deleteLocalData); XCTAssertEqual(model.records.count, 3)
        XCTAssertNotNil(try? Data(contentsOf: output))
    }
    func testUninstallConfirmationRefusesChangedOrIncompleteCopyLists() async throws {
        let (fixture, _, _, _) = try await deployment()
        let model = fixture.flow.firmwareCopies
        _ = try await retainOriginal(model)
        var calls: [String] = []
        model.configureUninstall(.init(stopCapture: { calls.append("capture") }, removeRules: { calls.append("rules") },
            removeLogin: { calls.append("login") }, eraseData: { calls.append("data") }, editing: { _ in }))
        let old = try model.fixtureUninstallRequest(choice: 1, deleteData: true, discard: false)
        _ = try await retainOriginal(model)
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: old)
        XCTAssertTrue(calls.isEmpty); XCTAssertEqual(model.issueKey, "phase4.recoveryChanged")
        let incomplete = FirmwareCopiesModel.UninstallRequest(records: model.records, selections: old.selections, deleteLocalData: true)
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: incomplete)
        XCTAssertTrue(calls.isEmpty)
        model.selectExport = { _ in nil }
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: model.uninstallRequest())
        XCTAssertTrue(calls.isEmpty); XCTAssertFalse(model.working)
    }
    func testNativePerCopyDiscardToggleAndConfirmationInBothLanguages() throws {
        ScreenEvidence.prepare()
        for locale in ["en", "zh-Hans"] {
            var fixture: FlowFixture!
            var originals: [FirmwareBatchRecord] = []
            ScreenEvidence.awaitMain {
                do {
                    fixture = try await self.deployment().0
                    originals.append(try await self.retainOriginal(fixture.flow.firmwareCopies))
                    originals.append(try await self.retainOriginal(fixture.flow.firmwareCopies))
                } catch { XCTFail("Fixture setup failed: \(error)") }
            }
            XCTAssertEqual(originals.count, 2)
            let model = fixture.flow.firmwareCopies
            var calls: [String] = []
            model.configureUninstall(.init(stopCapture: { calls.append("capture") }, removeRules: { calls.append("rules") },
                removeLogin: { calls.append("login") }, eraseData: { calls.append("data") }, editing: { _ in }))
            model.recoverySelections[originals[0].id] = .init(option: .heldElsewhere)
            model.recoverySelections[originals[1].id] = .init(option: .discard)
            let text = NativeText(locale: locale)
            let view = NSHostingView(rootView: Form { FirmwareUninstallSection(model: model, text: text) }
                .formStyle(.grouped).frame(width: 900, height: 1100))
            view.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1100),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
            defer { window.contentView = nil; window.close() }
            NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
            for original in originals {
                XCTAssertTrue(KRAXEnabled(try NativeEvidence.node("recovery-choice-" + original.id.uuidString, in: view)))
            }
            XCTAssertFalse(KRAXEnabled(try NativeEvidence.node("phase4.prepareUninstall", in: view)))
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("recovery-discard-" + originals[1].id.uuidString, in: view)))
            NativeEvidence.update(view)
            XCTAssertTrue(model.recoverySelection(for: originals[1]).discardConfirmed)
            XCTAssertEqual(model.recoverySelection(for: originals[0]).option, .heldElsewhere)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase4.prepareUninstall", in: view)))
            NativeEvidence.update(view); XCTAssertTrue(calls.isEmpty)
            let labels = NativeEvidence.elements(in: view).compactMap { KRAXLabel($0) }
            XCTAssertTrue(labels.contains(String(format: text("phase4.numberedCopy"), 1) + ": " + originals[0].device + ": " + text("phase4.recoveryHeld")))
            XCTAssertTrue(labels.contains(String(format: text("phase4.numberedCopy"), 2) + ": " + originals[1].device + ": " + text("phase4.recoveryDiscard")))
            XCTAssertTrue(labels.contains(text("phase4.confirmDataRetained")))
            if let output = NativeEvidence.outputRoot() {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try ScreenEvidence.capturePNG(view).write(to: output.appendingPathComponent("per-copy-confirmation-" + locale + ".png"))
            }
            let done = XCTestExpectation(description: "Mixed synthetic preparation confirmed")
            var delivered = false
            model.onChange = { if !delivered, model.uninstallReady { delivered = true; done.fulfill() } }
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase4.confirmUninstall", in: view)))
            ScreenEvidence.awaitMain {
                let result = await XCTWaiter.fulfillment(of: [done], timeout: 5)
                XCTAssertEqual(result, .completed)
            }
            XCTAssertEqual(calls, ["capture", "rules", "login"])
        }
    }
    func testNativePreviousUninstallStageReopensWithoutRestoringDeletionOrExecutingPorts() throws {
        ScreenEvidence.prepare()
        var fixture: FlowFixture!
        var calls: [String] = []
        ScreenEvidence.awaitMain {
            do {
                fixture = try await self.deployment().0
                let model = fixture.flow.firmwareCopies
                _ = try await self.retainOriginal(model)
                model.configureUninstall(.init(stopCapture: { calls.append("capture") }, removeRules: { calls.append("rules") },
                    removeLogin: { calls.append("login"); throw FirmwareError.unavailable }, eraseData: { calls.append("data") }, editing: { _ in }))
                await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()),
                    request: try model.fixtureUninstallRequest(choice: 1, deleteData: true, discard: false))
                model.clear(); await model.refresh()
            } catch { XCTFail("Fixture setup failed: \(error)") }
        }
        let model = fixture.flow.firmwareCopies
        XCTAssertEqual(calls, ["capture", "rules", "login"])
        XCTAssertEqual(model.previousPreparation?.stage, .rulesRemoved)
        XCTAssertEqual(model.previousPreparation?.deleteLocalData, true)
        XCTAssertNil(model.uninstallStage); XCTAssertFalse(model.uninstallReady); XCTAssertFalse(model.deleteLocalData)
        XCTAssertEqual(model.recoverySelection(for: try XCTUnwrap(model.records.first)).option, .export)
        let text = NativeText(locale: "en")
        let view = NSHostingView(rootView: Form { FirmwareUninstallSection(model: model, text: text) }
            .formStyle(.grouped).frame(width: 900, height: 800))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
        XCTAssertEqual(KRAXLabel(try NativeEvidence.node("phase4.previousUninstallProgress", in: view)), text("phase4.uninstallStage.rulesRemoved"))
        XCTAssertTrue(NativeEvidence.elements(in: view).contains { KRAXLabel($0) == text("phase4.previousUninstallReview") })
        XCTAssertEqual(calls, ["capture", "rules", "login"])
        if let output = NativeEvidence.outputRoot() {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try ScreenEvidence.capturePNG(view).write(to: output.appendingPathComponent("previous-uninstall-en.png"))
        }
        fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertNil(model.previousPreparation); XCTAssertTrue(model.records.isEmpty)
    }
    func testUninstallSelectedEraseFinishesWithoutRestoringSensitiveState() async throws {
        let (fixture, _, _, _) = try await deployment()
        let model = fixture.flow.firmwareCopies
        _ = try await retainOriginal(model)
        var order: [String] = []
        model.configureUninstall(.init(stopCapture: {}, removeRules: { order.append("rules") }, removeLogin: { order.append("login") },
            eraseData: { order.append("data"); model.clear() }, editing: { _ in }))
        await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()), request: try model.fixtureUninstallRequest(choice: 2, deleteData: true, discard: true))
        XCTAssertEqual(order, ["rules", "login", "data"])
        XCTAssertTrue(model.uninstallReady); XCTAssertTrue(model.records.isEmpty); XCTAssertFalse(model.working)
        XCTAssertNil(model.uninstallStage)
    }
    func testOriginalDeletionRequiresCurrentSessionAndDeletesOnlySelectedCopy() async throws {
        let (fixture, _, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        let first = try await retainOriginal(model); let second = try await retainOriginal(model)
        let old = try XCTUnwrap(model.selectionTicket())
        fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
        await model.refresh()
        await model.deleteOriginal(first, ticket: old)
        XCTAssertEqual(model.records.count, 2)
        await model.deleteOriginal(first, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.map(\.id), [second.id])
        let fresh = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let persisted = try await fresh.ledger()
        XCTAssertEqual(persisted.records.map(\.id), [second.id])
    }
    private func deployment(qualified: Bool = true) async throws -> (FlowFixture, URL, ObjectStore, KeyAvailabilityGate) {
        let (fixture, file) = try await ready()
        let keys = NativeMappingFixtureKeys()
        let store = ObjectStore(root: file.deletingLastPathComponent().appendingPathComponent("session-objects"), keySource: keys)
        _ = try await store.bootstrap(); await keys.seed()
        try await store.initializeFreshInstallation(version: KeyVersion(rawValue: 1))
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let dependencies = qualified ? KarabinerDeploymentDependencies(version: { "test" }, authority: { _, _ in .temporaryConfiguration })
            : KarabinerDeploymentDependencies(version: { "15.0.0" })
        fixture.flow.karabinerDeployment.configure(store: store, gate: gate, dependencies: dependencies)
        fixture.flow.firmwareCopies.configure(store: store, gate: gate)
        return (fixture, file, store, gate)
    }
    func testDeploymentBindingPersistsEncryptedTargetAndReopensAfterPrivacy() async throws {
        let (fixture, file, store, gate) = try await deployment()
        let deployment = fixture.flow.karabinerDeployment
        deployment.selectTarget = { file }
        await deployment.requestApplication(profile: "Synthetic")
        XCTAssertTrue(deployment.connected)
        let loaded = try await EncryptedKarabinerTargetStore(store: store).load()
        let reference = try XCTUnwrap(loaded)
        try stage(fixture.flow.karabinerMappings)
        await fixture.flow.karabinerMappings.check()
        XCTAssertTrue(fixture.flow.karabinerMappings.canApply)
        await fixture.flow.karabinerMappings.apply()
        XCTAssertEqual(fixture.flow.karabinerMappings.lastLedger?.desired.count, 1)
        gate.update(.locked); fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertFalse(deployment.connected); XCTAssertNil(deployment.selectedConfiguration)
        XCTAssertFalse(fixture.flow.karabinerMappings.canManage)
        let resumed = XCTestExpectation(description: "Protected session reopened")
        deployment.onChange = { if deployment.connected { resumed.fulfill() } }
        gate.update(.unlocked); fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertEqual(fixture.flow.karabinerMappings.lastLedger?.desired.count, 1)
        let reopened = try await EncryptedKarabinerTargetStore(store: store).load()
        XCTAssertEqual(reopened?.namespace, reference.namespace)
        for entry in try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent().appendingPathComponent("session-objects"), includingPropertiesForKeys: nil) {
            XCTAssertNil(try Data(contentsOf: entry).range(of: Data(file.path.utf8)))
        }
    }
    func testEmptyProductionSupportDirectoryConnectsReadOnlyAndCannotApply() async throws {
        let (fixture, file, _, _) = try await deployment(qualified: false)
        await fixture.flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        XCTAssertTrue(fixture.flow.karabinerDeployment.connected)
        XCTAssertEqual(fixture.flow.karabinerDeployment.version, "15.0.0")
        XCTAssertEqual(fixture.flow.karabinerDeployment.issueKey, "phase3.readOnlyVersion")
        try stage(fixture.flow.karabinerMappings); await fixture.flow.karabinerMappings.check()
        XCTAssertFalse(fixture.flow.karabinerMappings.canApply)
        await fixture.flow.karabinerMappings.apply()
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testDeploymentRefusesRebindWhileOldProfileIsManaged() async throws {
        let (fixture, file, store, _) = try await deployment()
        await fixture.flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        try stage(fixture.flow.karabinerMappings); await fixture.flow.karabinerMappings.check(); await fixture.flow.karabinerMappings.apply()
        let other = file.deletingLastPathComponent().appendingPathComponent("other.json")
        try bytes.write(to: other)
        await fixture.flow.karabinerDeployment.bind(url: other, profile: "Synthetic")
        XCTAssertEqual(fixture.flow.karabinerDeployment.issueKey, "phase3.rebindBlocked")
        XCTAssertTrue(fixture.flow.karabinerDeployment.connected)
        XCTAssertTrue(fixture.flow.karabinerMappings.canManage)
        XCTAssertEqual(try Data(contentsOf: other), bytes)
        let loaded = try await EncryptedKarabinerTargetStore(store: store).load()
        let reference = try XCTUnwrap(loaded)
        var stale = false
        XCTAssertEqual(try URL(resolvingBookmarkData: reference.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale).resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
    }
    func testDeploymentWatchesAtomicExternalReplacementAndWithdrawsConfirmation() async throws {
        let (fixture, file, _, _) = try await deployment()
        let model = fixture.flow.karabinerMappings
        await fixture.flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        try stage(model); await model.check(); await model.apply()
        let changed = XCTestExpectation(description: "External replacement reconciled")
        var delivered = false
        model.onChange = {
            if !delivered, model.lastLedger?.batches.last?.state == .externallyChanged { delivered = true; changed.fulfill() }
        }
        let external = try Data(contentsOf: file) + Data(" ".utf8)
        try external.write(to: file, options: .atomic)
        await fulfillment(of: [changed], timeout: 5)
        XCTAssertNil(model.prepared); XCTAssertFalse(model.riskConfirmed)
        XCTAssertEqual(try Data(contentsOf: file), external)
    }
    func testDeploymentCancellationAndInvalidTargetDoNotSaveAuthorization() async throws {
        let (fixture, file, store, _) = try await deployment()
        fixture.flow.karabinerDeployment.selectTarget = { nil }
        await fixture.flow.karabinerDeployment.requestApplication(profile: "Synthetic")
        XCTAssertFalse(fixture.flow.karabinerDeployment.connected)
        try Data("invalid".utf8).write(to: file)
        await fixture.flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        XCTAssertFalse(fixture.flow.karabinerDeployment.connected)
        XCTAssertEqual(fixture.flow.karabinerDeployment.issueKey, "phase3.bindingFailed")
        let saved = try await EncryptedKarabinerTargetStore(store: store).load()
        XCTAssertNil(saved)
    }
    func testVersionChangeWithdrawsPreparedWriteAuthority() async throws {
        let (fixture, file, store, gate) = try await deployment()
        let version = DeploymentVersionProbe()
        fixture.flow.karabinerDeployment.configure(store: store, gate: gate,
            dependencies: KarabinerDeploymentDependencies(version: { version.value() },
                authority: { value, _ in value == "fixture-v1" ? .temporaryConfiguration : .readOnly }))
        await fixture.flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        try stage(fixture.flow.karabinerMappings); await fixture.flow.karabinerMappings.check()
        XCTAssertTrue(fixture.flow.karabinerMappings.canApply)
        version.set(nil)
        XCTAssertFalse(fixture.flow.karabinerMappings.canApply)
        await fixture.flow.karabinerMappings.apply()
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testCurrentObservationChangeCannotReusePreparedWrite() async throws {
        let (fixture, file, _, _) = try await deployment()
        var observed: [ChordBucket]? = []
        fixture.flow.karabinerDeployment.observations = { observed }
        await fixture.flow.karabinerDeployment.bind(url: file, profile: "Synthetic")
        try stage(fixture.flow.karabinerMappings); await fixture.flow.karabinerMappings.check()
        XCTAssertTrue(fixture.flow.karabinerMappings.canApply)
        observed = [ChordBucket(chord: try XCTUnwrap(fixture.flow.karabinerMappings.drafts.first).trigger, appBucket: .bundleID("com.example.editor"))]
        XCTAssertFalse(fixture.flow.karabinerMappings.canApply)
        await fixture.flow.karabinerMappings.apply()
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        await fixture.flow.karabinerMappings.check()
        XCTAssertTrue(fixture.flow.karabinerMappings.prepared?.requiresRiskConfirmation == true)
        XCTAssertFalse(fixture.flow.karabinerMappings.canApply)
    }
    func testLateRecoveryRetentionCannotCrossPrivacyOrSourceChange() async throws {
        let (fixture, _, _, _) = try await deployment()
        let original = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["KC_NO"]]}"#.utf8)
        let model = fixture.flow.firmwareCopies
        model.selectedOriginal = { original }
        let ticket = try XCTUnwrap(model.selectionTicket())
        fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
        await model.retainVIA(original, ticket: ticket)
        XCTAssertTrue(model.records.isEmpty)
        let current = try XCTUnwrap(model.selectionTicket())
        model.selectedOriginal = { nil }
        await model.retainVIA(original, ticket: current)
        XCTAssertTrue(model.records.isEmpty)
    }
    func testNativeDeploymentRequestAndRecoveryCopyButtonsInBothLocales() throws {
        ScreenEvidence.prepare()
        var fixture: FlowFixture?
        var target: URL?
        ScreenEvidence.awaitMain {
            do { let value = try await self.deployment(); fixture = value.0; target = value.1 }
            catch { XCTFail("\(error)") }
        }
        let flow = try XCTUnwrap(fixture?.flow)
        let file = try XCTUnwrap(target)
        flow.karabinerDeployment.selectTarget = { file }
        let original = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["KC_NO"]],"macros":["private restore marker"]}"#.utf8)
        flow.firmwareCopies.selectedOriginal = { original }
        for locale in ["en", "zh-Hans"] {
            let view = NSHostingView(rootView: Form {
                KarabinerDeploymentSection(model: flow.karabinerDeployment, selectedProfile: "Synthetic", text: NativeText(locale: locale))
                FirmwareCopiesSection(model: flow.firmwareCopies, viaBytes: original, text: NativeText(locale: locale))
            }.formStyle(.grouped).frame(width: 850, height: 1000))
            view.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 1000), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
            defer { window.contentView = nil; window.close() }
            NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
            let bound = XCTestExpectation(description: "Native application target bound")
            var delivered = false
            flow.karabinerDeployment.onChange = {
                if !delivered, flow.karabinerDeployment.connected, !flow.karabinerDeployment.working { delivered = true; bound.fulfill() }
            }
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase3.prepareApplication", in: view)))
            ScreenEvidence.awaitMain {
                let result = await XCTWaiter.fulfillment(of: [bound], timeout: 5)
                XCTAssertEqual(result, .completed)
            }
            let previousCount = flow.firmwareCopies.records.count
            let retained = XCTestExpectation(description: "Native recovery copy retained")
            var retainedDelivered = false
            flow.firmwareCopies.onChange = {
                if !retainedDelivered, flow.firmwareCopies.records.count == previousCount + 1 { retainedDelivered = true; retained.fulfill() }
            }
            NativeEvidence.update(view)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase4.retainVIA", in: view)))
            ScreenEvidence.awaitMain {
                let result = await XCTWaiter.fulfillment(of: [retained], timeout: 5)
                XCTAssertEqual(result, .completed)
            }
            let record = try XCTUnwrap(flow.firmwareCopies.records.last)
            let export = file.deletingLastPathComponent().appendingPathComponent("native-restore-" + locale + ".json")
            flow.firmwareCopies.selectExport = { _ in export }
            let exported = XCTestExpectation(description: "Native recovery copy exported")
            var exportedDelivered = false
            flow.firmwareCopies.onChange = {
                if !exportedDelivered, (try? Data(contentsOf: export)) == original { exportedDelivered = true; exported.fulfill() }
            }
            NativeEvidence.update(view); NativeEvidence.update(view)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node(record.id.uuidString, in: view)))
            ScreenEvidence.awaitMain {
                let result = await XCTWaiter.fulfillment(of: [exported], timeout: 5)
                XCTAssertEqual(result, .completed)
            }
            XCTAssertEqual(try Data(contentsOf: export), original)
            XCTAssertEqual(record.axes.complete, false)
            if let output = NativeEvidence.outputRoot() {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try ScreenEvidence.capturePNG(view).write(to: output.appendingPathComponent("deployment-copies-" + locale + ".png"))
            }
        }
    }
    private let bytes = Data(#"{"profiles":[{"name":"Synthetic","selected":true,"complex_modifications":{"rules":[]}}]}"#.utf8)
    private func ready() async throws -> (FlowFixture, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("phase3-flow-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let fixture = try FlowFixture(directory: root, environment: ["KEYRECORD_FLOW_FIXTURE": root.path])
        fixture.showConsentIfNeeded(); await fixture.flow.accept(); fixture.flow.sync(from: fixture.orchestrator.state)
        let file = root.appendingPathComponent("copy.json")
        try bytes.write(to: file)
        await fixture.flow.karabinerImport.load(url: file, ticket: try XCTUnwrap(fixture.flow.karabinerImport.selectionTicket()))
        return (fixture, file)
    }
    private func stage(_ model: KarabinerMappingModel) throws {
        model.stage(output: Chord(keyCode: try KeyCode(8), modifiers: ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none)),
            trigger: Chord(keyCode: try KeyCode(111), modifiers: ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)), scope: .global)
    }
    func testCopyPreviewExportDraftRetentionAndPrivacyRevocation() async throws {
        let (fixture, _) = try await ready()
        let model = fixture.flow.karabinerMappings
        try stage(model)
        fixture.flow.intendedBackend = .via
        fixture.flow.intendedBackend = .karabiner
        XCTAssertEqual(model.drafts.count, 1)
        await model.check()
        XCTAssertNotNil(model.prepared)
        XCTAssertFalse(model.canApply)
        let exported = try JSONSerialization.jsonObject(with: model.exportRules()) as? [String: Any]
        let pendingExport = try model.exportDocument()
        XCTAssertEqual((exported?["rules"] as? [Any])?.count, 1)
        fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertTrue(model.drafts.isEmpty)
        XCTAssertNil(model.prepared)
        XCTAssertThrowsError(try model.exportRules())
        XCTAssertThrowsError(try pendingExport.permission?.use {})
        fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertNil(model.prepared)
        XCTAssertFalse(model.canApply)
    }
    func testDraftChangesWithdrawDiffAndRiskConfirmation() async throws {
        let (fixture, _) = try await ready()
        let model = fixture.flow.karabinerMappings
        try stage(model); await model.check(); model.riskConfirmed = true
        var draft = try XCTUnwrap(model.drafts.first)
        draft.devices = [MappingDevice(vendorID: 1, productID: 2)]
        model.update(draft)
        XCTAssertNil(model.prepared); XCTAssertFalse(model.riskConfirmed)
        await model.check()
        XCTAssertNotNil(model.prepared)
        fixture.flow.karabinerImport.profile = nil
        XCTAssertNil(model.prepared)
        XCTAssertFalse(model.riskConfirmed)
    }
    func testTruncatedProfileLabelCannotSelectAnotherProfileIdentity() async throws {
        let (fixture, file) = try await ready()
        let prefix = String(repeating: "p", count: 128)
        let longName = prefix + "-long"
        let data = try JSONSerialization.data(withJSONObject: ["profiles": [["name": prefix], ["name": longName, "selected": true]]])
        try data.write(to: file, options: .atomic)
        fixture.flow.karabinerImport.clear()
        await fixture.flow.karabinerImport.load(url: file, ticket: try XCTUnwrap(fixture.flow.karabinerImport.selectionTicket()))
        try stage(fixture.flow.karabinerMappings)
        await fixture.flow.karabinerMappings.check()
        XCTAssertEqual(fixture.flow.karabinerMappings.prepared?.plan.diff.profile, longName)
        XCTAssertEqual(fixture.flow.karabinerMappings.drafts.first?.profile, longName)
    }
    func testNativeBatchCheckAndUnavailableApplyInBothLocales() throws {
        ScreenEvidence.prepare()
        var fixture: FlowFixture?
        ScreenEvidence.awaitMain {
            do { fixture = try await self.ready().0 } catch { XCTFail("\(error)") }
        }
        let flow = try XCTUnwrap(fixture?.flow)
        try stage(flow.karabinerMappings)
        for locale in ["en", "zh-Hans"] {
            flow.karabinerMappings.invalidate()
            let checked = XCTestExpectation(description: "Batch check published")
            flow.karabinerMappings.onChange = { if flow.karabinerMappings.prepared != nil { checked.fulfill() } }
            let text = NativeText(locale: locale)
            let view = NSHostingView(rootView: Form { KarabinerMappingSection(model: flow.karabinerMappings, text: text) }
                .formStyle(.grouped).frame(width: 800, height: 820).background(Color(nsColor: .windowBackgroundColor)))
            view.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
            defer { window.contentView = nil; window.close() }
            NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase3.check", in: view)))
            ScreenEvidence.awaitMain {
                let result = await XCTWaiter.fulfillment(of: [checked], timeout: 5)
                XCTAssertEqual(result, .completed)
            }
            NativeEvidence.update(view); NativeEvidence.update(view)
            XCTAssertNotNil(flow.karabinerMappings.prepared)
            let apply = try NativeEvidence.node("phase3.apply", in: view)
            XCTAssertFalse(KRAXEnabled(apply))
            XCTAssertNotNil(try NativeEvidence.node("phase3.diff", in: view))
            if let output = NativeEvidence.outputRoot() {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try ScreenEvidence.capturePNG(view).write(to: output.appendingPathComponent("karabiner-batch-\(locale).png"))
            }
        }
    }
    func testNativeInjectedApplyDisableRestoreAndExternalAdopt() throws {
        ScreenEvidence.prepare()
        var preparedFixture: FlowFixture?
        var configurationURL: URL?
        ScreenEvidence.awaitMain {
            do {
                let (fixture, file) = try await self.ready()
                preparedFixture = fixture; configurationURL = file
                let keys = NativeMappingFixtureKeys()
                let store = ObjectStore(root: file.deletingLastPathComponent().appendingPathComponent("mapping-objects"), keySource: keys)
                _ = try await store.bootstrap(); await keys.seed()
                try await store.initializeFreshInstallation(version: KeyVersion(rawValue: 1))
                let gate = KeyAvailabilityGate(); gate.update(.unlocked)
                let context = KarabinerRuntimeContext(version: "fixture", authority: .temporaryConfiguration,
                    capabilities: BackendCapabilityCatalog.reference(.karabiner), observations: [])
                let port = try KarabinerFilePort(target: file, gate: gate, runtime: { context })
                let coordinator = KarabinerTransactionCoordinator(configuration: port,
                    store: try EncryptedKarabinerTransactionStore(store: store, namespace: UUID()))
                await fixture.flow.karabinerMappings.attach(coordinator)
                try self.stage(fixture.flow.karabinerMappings)
                await fixture.flow.karabinerMappings.check()
            } catch { XCTFail("\(error)") }
        }
        let fixture = try XCTUnwrap(preparedFixture)
        let model = fixture.flow.karabinerMappings
        let view = NSHostingView(rootView: Form { KarabinerMappingSection(model: model, text: NativeText(locale: "en")) }
            .formStyle(.grouped).frame(width: 900, height: 1200).background(Color(nsColor: .windowBackgroundColor)))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
        func press(_ identifier: String, kind: KarabinerOperationKind, count: Int) throws {
            let completed = XCTestExpectation(description: identifier)
            model.onChange = { if !model.working, model.lastLedger?.batches.count == count,
                model.lastLedger?.batches.last?.kind == kind { completed.fulfill() } }
            NativeEvidence.update(view)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node(identifier, in: view)))
            ScreenEvidence.awaitMain {
                let result = await XCTWaiter.fulfillment(of: [completed], timeout: 5)
                XCTAssertEqual(result, .completed)
            }
            NativeEvidence.update(view)
        }
        try press("phase3.apply", kind: .apply, count: 1)
        XCTAssertEqual(model.lastLedger?.batches.last?.state, .pendingVerification)
        try press("phase3.disable", kind: .disable, count: 2)
        XCTAssertTrue(model.lastLedger?.disabled == true)
        try press("phase3.restore", kind: .restore, count: 3)
        XCTAssertFalse(model.lastLedger?.disabled == true)
        let file = try XCTUnwrap(configurationURL)
        let before = try Data(contentsOf: file)
        try (before + Data(" ".utf8)).write(to: file, options: .atomic)
        ScreenEvidence.awaitMain { await model.verify() }
        XCTAssertEqual(model.lastLedger?.batches.last?.state, .externallyChanged)
        NativeEvidence.update(view)
        let adopted = XCTestExpectation(description: "External adoption published")
        model.onChange = {
            if !model.working, model.lastLedger?.batches.last?.state == .pendingVerification { adopted.fulfill() }
        }
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase3.adopt", in: view)))
        ScreenEvidence.awaitMain {
            let result = await XCTWaiter.fulfillment(of: [adopted], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
        XCTAssertEqual(try Data(contentsOf: file), before + Data(" ".utf8))
        XCTAssertEqual(model.lastLedger?.desired.count, 1)
    }
}

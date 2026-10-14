import XCTest
import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordMappings
import KeyRecordDeviceRead
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
private final class NativeVialHIDFixture: VialHIDEndpoint, @unchecked Sendable {
    static let definition = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4AB8AG5dAD2IicZUNsMXT+Tj0LL2o1xY9+vhKXbIvBy+vt7ajJ9ByJ+U3t83EJIzjavDD0/txhM7o8p2unsGnnWbxEuUfVifBNNdOsvnERH+MjQdNyzfGKOpZsOfDPQyS8tONaoxr0YNL+3+QwvQXI28Cr7JAAAAOXSVpUTMuNUAAYoBfQAAAJKyS9ixxGf7AgAAAAAEWVo=")!
    static let encoderDefinition = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4ACMAHNdAD2IisaUL8LEIpnpbzWhi9MuaJSxOkspsVw55Xn7bInuMyewnJZLH9loZQHt+8O/0aPdImbC/zOhSY0hKRF6Qo860nDK00pvvQj4zzfzFDhGIM4qAJCwnLNQi6XluttcNvwdRtrS0/ZXMW7fRhPfGKahBwAAAGoknprQ9flsAAGPAY0BAACxXyIPscRn+wIAAAAABFla")!
    private let lock = NSLock()
    private var receive: (@Sendable (Result<VialHIDFrame, VialHIDError>) -> Void)?
    private var reports: [VialReadRequest] = []
    private var closes = 0
    private let pause: VialReadRequest?
    private let mismatch: Bool
    private let encoders: Bool
    private let encoderMismatch: Bool
    private let basicNames: Bool
    private let modifierNames: Bool
    private let layerTapNames: Bool
    private let modifierTapNames: Bool
    private let oneShotNames: Bool
    private let persistentLayerNames: Bool
    private let staticLayerNames: Bool
    private let definitionOverride: Data?
    let paused = XCTestExpectation(description: "Selected HID report paused")
    init(pause: VialReadRequest? = nil, mismatch: Bool = false, encoders: Bool = false, encoderMismatch: Bool = false,
         basicNames: Bool = false, modifierNames: Bool = false, layerTapNames: Bool = false, modifierTapNames: Bool = false, oneShotNames: Bool = false, persistentLayerNames: Bool = false, staticLayerNames: Bool = false, definitionOverride: Data? = nil) {
        self.pause = pause; self.mismatch = mismatch; self.encoders = encoders; self.encoderMismatch = encoderMismatch
        self.basicNames = basicNames
        self.modifierNames = modifierNames
        self.layerTapNames = layerTapNames
        self.modifierTapNames = modifierTapNames
        self.oneShotNames = oneShotNames
        self.persistentLayerNames = persistentLayerNames
        self.staticLayerNames = staticLayerNames
        self.definitionOverride = definitionOverride
    }
    var requests: [VialReadRequest] { lock.withLock { reports } }
    var closeCount: Int { lock.withLock { closes } }
    func start(receive: @escaping @Sendable (Result<VialHIDFrame, VialHIDError>) -> Void) { lock.withLock { self.receive = receive } }
    func send(_ request: VialReadRequest, timeoutMilliseconds: Int, completion: @escaping @Sendable (Result<Void, VialHIDError>) -> Void) {
        lock.withLock { reports.append(request) }
        if request == pause { paused.fulfill(); return }
        emit(request); completion(.success(()))
    }
    func emit(_ request: VialReadRequest) {
        let definition = definitionOverride ?? (encoders ? Self.encoderDefinition : Self.definition)
        var bytes = request.bytes
        switch bytes[0] {
        case 1: bytes[1] = 0; bytes[2] = 9
        case 0x11: bytes[1] = 1
        case 0x12: bytes.replaceSubrange(4..<10, with: [0, mismatch ? 7 : 6, 255, 255, 0, basicNames ? 0x58 : 0x28])
            if modifierNames { bytes[8] = 3 }
            if layerTapNames { bytes[8] = 0x40 }
            if modifierTapNames { bytes[8] = 0x23 }
            if oneShotNames { bytes[8] = 0x52; bytes[9] = 0xa3 }
            if persistentLayerNames { bytes[8] = 0x52; bytes[9] = 0xe0 }
            if staticLayerNames { bytes[8] = 0x7c; bytes[9] = 0x77 }
        case 0xfe:
            switch bytes[1] {
            case 0:
                bytes = Array(repeating: 0, count: 32); bytes[0] = 6
                bytes.replaceSubrange(4..<12, with: Array(repeating: 255, count: 8))
            case 1:
                bytes = Array(repeating: 0, count: 32)
                for index in 0..<4 { bytes[index] = UInt8(truncatingIfNeeded: definition.count >> (index * 8)) }
            case 2:
                let start = (Int(bytes[2]) | Int(bytes[3]) << 8) * 32
                bytes = Array(definition[start..<min(start + 32, definition.count)])
                bytes += Array(repeating: 0, count: 32 - bytes.count)
            case 3:
                XCTAssertTrue(encoders); XCTAssertEqual(request.bytes[3], 2)
                bytes.replaceSubrange(0..<4, with: [0, basicNames ? 0x34 : 0x28, 0x12, encoderMismatch ? 0x35 : 0x34])
                if modifierNames { bytes[0] = 0x0a; bytes[2] = 0x19 }
                if layerTapNames { bytes[0] = 0x40; bytes[2] = 0x40 }
                if modifierTapNames { bytes[0] = 0x2a; bytes[2] = 0x39 }
                if oneShotNames { bytes.replaceSubrange(0..<4, with: [0x52, 0xa7, 0x52, encoderMismatch ? 0xb9 : 0xb8]) }
                if persistentLayerNames { bytes.replaceSubrange(0..<4, with: [0x52, 0xe0, 0x52, encoderMismatch ? 0xfe : 0xff]) }
                if staticLayerNames { bytes.replaceSubrange(0..<4, with: [0x7c, 0x78, 0x7c, encoderMismatch ? 0x77 : 0x7b]) }
            default: XCTFail("Unexpected Vial query")
            }
        default: XCTFail("Unexpected HID command")
        }
        lock.withLock { receive }?(.success(.init(reportID: 0, bytes: bytes)))
    }
    func disconnect() { lock.withLock { receive }?(.failure(.disconnected)) }
    func close() { lock.withLock { closes += 1 } }
}
private final class DeploymentVersionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String? = "fixture-v1"
    func value() -> String? { lock.withLock { current } }
    func set(_ value: String?) { lock.withLock { current = value } }
}

@MainActor
final class KarabinerMappingFlowTests: XCTestCase {
    func testReadbackCancellationInsideDevicePickerCannotOpenDevice() async throws {
        let (fixture, file, store, gate) = try await deployment()
        let record = try await claimedVial(fixture, file: file, store: store, gate: gate, readback: nil)
        let model = fixture.flow.firmwareCopies
        let support = FirmwareSupportDirectory(entries: [FirmwareCompatibility(backend: .vial,
            device: record.device, axes: record.axes, supportedOutputs: ["KC_C"])])
        let device = VialHIDDevice(registryEntryID: 12, vendorID: 0x1234, productID: 0x5678, name: "Synthetic")
        var opens = 0
        let selector = VialDeviceSelection(devices: { [device] }, choose: { _, _ in
            model.cancelVialReadback()
            return device
        }, open: { _ in opens += 1; return NativeVialHIDFixture() })
        model.configure(store: store, gate: gate, support: support, versionAxes: { _ in record.axes },
            vialConnection: { record, authorize in
                try selector.openSelectedDevice(record: record, support: support, text: NativeText(locale: "en"), authorize: authorize)
            })
        await model.refresh()
        await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(opens, 0); XCTAssertFalse(model.working)
        XCTAssertEqual(model.records.last?.state, .importClaimed)
    }
    func testDeviceSelectionRefusesUnknownCancelledUnlistedAndRevokedChoices() async throws {
        let (fixture, file, store, originalGate) = try await deployment()
        let record = try await claimedVial(fixture, file: file, store: store, gate: originalGate, readback: nil)
        let device = VialHIDDevice(registryEntryID: 12, vendorID: 0x1234, productID: 0x5678, name: "Synthetic")
        let supported = FirmwareSupportDirectory(entries: [FirmwareCompatibility(backend: .vial,
            device: record.device, axes: record.axes, supportedOutputs: ["KC_C"])])
        for scenario in ["unknown", "cancel", "unlisted", "locked-in-picker", "locked-on-open"] {
            let gate = KeyAvailabilityGate(); gate.update(.unlocked)
            let generation = try gate.begin()
            let endpoint = NativeVialHIDFixture()
            var discoveries = 0, opens = 0
            let selector = VialDeviceSelection(devices: { discoveries += 1; return [device] }, choose: { _, _ in
                if scenario == "cancel" { return nil }
                if scenario == "unlisted" { return VialHIDDevice(registryEntryID: 99, vendorID: 1, productID: 1, name: "Other") }
                if scenario == "locked-in-picker" { gate.update(.locked) }
                return device
            }, open: { _ in
                opens += 1
                if scenario == "locked-on-open" { gate.update(.locked) }
                return endpoint
            })
            XCTAssertThrowsError(try selector.openSelectedDevice(record: record,
                support: scenario == "unknown" ? FirmwareSupportDirectory() : supported,
                text: NativeText(locale: "en"), authorize: { try gate.check(generation) }))
            XCTAssertEqual(discoveries, scenario == "unknown" ? 0 : 1)
            XCTAssertEqual(opens, scenario == "locked-on-open" ? 1 : 0)
            XCTAssertEqual(endpoint.closeCount, scenario == "locked-on-open" ? 1 : 0)
            XCTAssertTrue(endpoint.requests.isEmpty)
        }
    }

    func testNativeVialDevicePickerOpensOnlyExplicitSelection() throws {
        ScreenEvidence.prepare()
        var saved: FirmwareBatchRecord?
        ScreenEvidence.awaitMain {
            do {
                let (fixture, file, store, gate) = try await self.deployment()
                saved = try await self.claimedVial(fixture, file: file, store: store, gate: gate, readback: nil)
            } catch { XCTFail("\(error)") }
        }
        let record = try XCTUnwrap(saved)
        let support = FirmwareSupportDirectory(entries: [FirmwareCompatibility(backend: .vial,
            device: record.device, axes: record.axes, supportedOutputs: ["KC_C"])])
        let device = VialHIDDevice(registryEntryID: 12, vendorID: 0x1234, productID: 0x5678, name: "Synthetic keyboard")
        for locale in ["en", "zh-Hans"] {
            let endpoint = NativeVialHIDFixture()
            var opened: [VialHIDDevice] = []
            var selector = VialDeviceSelection()
            selector.devices = { [device] }
            selector.open = { opened.append($0); return endpoint }
            DispatchQueue.main.async {
                do {
                    let content = try XCTUnwrap(NSApp.modalWindow?.contentView?.superview)
                    func buttons(_ view: NSView) -> [NSButton] {
                        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
                    }
                    let button = try XCTUnwrap(buttons(content).first {
                        $0.accessibilityIdentifier() == "vial.select.confirm"
                    })
                    XCTAssertEqual(button.title, NativeText(locale: locale)("phase4.readSelectedDevice"))
                    button.performClick(nil)
                } catch { XCTFail("\(error)"); NSApp.abortModal() }
            }
            let connection = try selector.openSelectedDevice(record: record, support: support,
                                                    text: NativeText(locale: locale), authorize: {})
            XCTAssertEqual(opened, [device]); XCTAssertTrue(endpoint.requests.isEmpty)
            connection.close(); XCTAssertEqual(endpoint.closeCount, 1)
        }
    }
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
    private func qualifiedFirmware(_ model: FirmwareCopiesModel, store: ObjectStore, gate: KeyAvailabilityGate,
                                   backend: FirmwareBackend = .via, outputs: Set<String> = ["KC_C"]) {
        let axes = fixtureAxes
        model.configure(store: store, gate: gate,
            support: FirmwareSupportDirectory(entries: [FirmwareCompatibility(backend: backend, device: "42", axes: axes, supportedOutputs: outputs)]),
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
        XCTAssertFalse(KRAXEnabled(try NativeEvidence.node("patch-" + record.id.uuidString, in: view)))
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("stage-" + record.id.uuidString, in: view)))
        NativeEvidence.update(view)
        let previewed = XCTestExpectation(description: "Native selected slot preview")
        var previewDelivered = false
        model.onChange = { if !previewDelivered, model.patchPreviews[record.id] != nil { previewDelivered = true; previewed.fulfill() } }
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("preview-" + record.id.uuidString, in: view)))
        ScreenEvidence.awaitMain {
            let result = await XCTWaiter.fulfillment(of: [previewed], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
        NativeEvidence.update(view)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path))
        XCTAssertEqual(model.records.last?.state, .draft)
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
    func testPatchDraftPreviewInvalidatesOnEditAndDoesNotChooseAFileOrPersistChanges() async throws {
        let (fixture, _, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        qualifiedFirmware(model, store: store, gate: gate, outputs: ["KC_C", "KC_A"])
        let bytes = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["KC_NO","KC_NO"]],"macros":["opaque"]}"#.utf8)
        model.selectedOriginal = { bytes }
        await model.retainVIA(bytes, ticket: try XCTUnwrap(model.selectionTicket()))
        let record = try XCTUnwrap(model.records.last)
        let ticket = try XCTUnwrap(model.selectionTicket())
        var selections = 0; model.selectExport = { _ in selections += 1; return nil }
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false), record: record, ticket: ticket)
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 1), output: "KC_A", automatic: false), record: record, ticket: ticket)
        await model.previewPatch(record, ticket: ticket)
        XCTAssertEqual(model.patchPreviews[record.id]?.differences.map(\.before), ["KC_NO", "KC_NO"])
        XCTAssertTrue(model.canExportPreview(record)); XCTAssertEqual(selections, 0)
        let operations = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let ledger = try await operations.ledger()
        let original = try await operations.original(record.id)
        XCTAssertEqual(ledger.records.first, record); XCTAssertNil(ledger.pending); XCTAssertEqual(original, bytes)
        model.removePatchChange(slot: .init(layer: 0, column: 0), record: record, ticket: ticket)
        model.removePatchChange(slot: .init(layer: 0, column: 0), record: record, ticket: ticket)
        XCTAssertEqual(model.patchDrafts[record.id]?.map(\.slot), [.init(layer: 0, column: 1)])
        XCTAssertNil(model.patchPreviews[record.id]); XCTAssertFalse(model.canExportPreview(record))
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 1), output: "KC_C", automatic: false), record: record, ticket: ticket)
        XCTAssertEqual(model.patchDrafts[record.id]?.count, 1)
        await model.previewPatch(record, ticket: ticket)
        XCTAssertEqual(model.patchPreviews[record.id]?.differences.first?.change.output, "KC_C")
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 9), output: "KC_A", automatic: false), record: record, ticket: ticket)
        await model.previewPatch(record, ticket: ticket)
        XCTAssertNil(model.patchPreviews[record.id]); XCTAssertEqual(model.patchIssueKeys[record.id], "phase4.patchIssue.slot")
        XCTAssertNil(model.issueKey)
        await model.exportPreview(record, ticket: ticket)
        XCTAssertEqual(selections, 0)
    }
    func testPatchPreviewCannotExportAfterNewOriginalOrPrivacySessionChange() async throws {
        let (fixture, _, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        qualifiedFirmware(model, store: store, gate: gate)
        let first = try await retainOriginal(model)
        let old = try XCTUnwrap(model.selectionTicket())
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false), record: first, ticket: old)
        await model.previewPatch(first, ticket: old)
        XCTAssertTrue(model.canExportPreview(first))
        let second = try await retainOriginal(model)
        XCTAssertNil(model.patchPreviews[first.id]); XCTAssertFalse(model.canExportPreview(first))
        var selections = 0; model.selectExport = { _ in selections += 1; return nil }
        await model.exportPreview(first, ticket: old)
        XCTAssertEqual(selections, 0)
        gate.update(.locked); fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertTrue(model.patchDrafts.isEmpty); XCTAssertTrue(model.patchPreviews.isEmpty)
        gate.update(.unlocked); fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
        await model.refresh()
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false), record: second, ticket: old)
        await model.previewPatch(second, ticket: old)
        XCTAssertTrue(model.patchDrafts.isEmpty); XCTAssertTrue(model.patchPreviews.isEmpty)
        XCTAssertFalse(model.canExportPreview(second))
    }
    func testPatchFailureReasonsPreserveDraftAndCorrectWithoutExport() async throws {
        let (fixture, _, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        qualifiedFirmware(model, store: store, gate: gate)
        let bytes = Data(#"{"vendorProductId":42,"layers":[["MO(1)","KC_NO","KC_A","QK_BOOT"],["KC_NO","KC_NO","KC_NO","KC_NO"],["KC_NO","KC_NO","KC_NO","KC_NO"]],"macros":["opaque private content"]}"#.utf8)
        model.selectedOriginal = { bytes }
        await model.retainVIA(bytes, ticket: try XCTUnwrap(model.selectionTicket()))
        let record = try XCTUnwrap(model.records.last)
        let ticket = try XCTUnwrap(model.selectionTicket())
        let operations = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let initial = try await operations.ledger()
        var selections = 0; model.selectExport = { _ in selections += 1; return nil }
        let cases: [(FirmwareSlotChange, String)] = [
            (.init(slot: .init(layer: 0, column: 9), output: "KC_C", automatic: false), "phase4.patchIssue.slot"),
            (.init(slot: .init(layer: 0, column: 1), output: "MACRO_PRIVATE_TOKEN", automatic: false), "phase4.patchIssue.output"),
            (.init(slot: .init(layer: 0, column: 3), output: "KC_C", automatic: false), "phase4.patchIssue.protected"),
            (.init(slot: .init(layer: 0, column: 2), output: "KC_C", automatic: true), "phase4.patchIssue.occupied"),
            (.init(slot: .init(layer: 2, column: 1), output: "KC_C", automatic: false), "phase4.patchIssue.layer")
        ]
        for (change, key) in cases {
            model.stagePatchChange(change, record: record, ticket: ticket)
            await model.previewPatch(record, ticket: ticket)
            XCTAssertEqual(model.patchIssueKeys[record.id], key)
            XCTAssertEqual(model.patchDrafts[record.id], [change]); XCTAssertNil(model.patchPreviews[record.id])
            XCTAssertFalse(model.canExportPreview(record)); XCTAssertFalse(model.working); XCTAssertNil(model.issueKey)
            await model.exportPreview(record, ticket: ticket)
            let ledger = try await operations.ledger()
            let original = try await operations.original(record.id)
            XCTAssertEqual(ledger, initial); XCTAssertEqual(original, bytes); XCTAssertEqual(selections, 0)
            for locale in ["en", "zh-Hans"] {
                let message = NativeText(locale: locale)(key)
                XCTAssertNotEqual(message, key); XCTAssertFalse(message.contains("MACRO_PRIVATE_TOKEN"))
                XCTAssertFalse(message.contains("opaque private content"))
            }
            model.removePatchChange(slot: change.slot, record: record, ticket: ticket)
            XCTAssertNil(model.patchIssueKeys[record.id])
        }
        model.stagePatchChange(.init(slot: .init(layer: 1, column: 1), output: "KC_C", automatic: false), record: record, ticket: ticket)
        await model.previewPatch(record, ticket: ticket)
        XCTAssertTrue(model.canExportPreview(record)); XCTAssertTrue(model.patchIssueKeys.isEmpty)
        XCTAssertEqual(selections, 0)
    }
    func testPatchFailureStaysWithItsDeviceAndCannotCrossPrivacySession() async throws {
        let (fixture, _, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        let axes = fixtureAxes
        model.configure(store: store, gate: gate, support: FirmwareSupportDirectory(entries: ["42", "43"].map {
            FirmwareCompatibility(backend: .via, device: $0, axes: axes, supportedOutputs: ["KC_C"])
        }), versionAxes: { _ in axes })
        let firstBytes = Data(#"{"vendorProductId":42,"layers":[["KC_NO"]]}"#.utf8)
        model.selectedOriginal = { firstBytes }
        await model.retainVIA(firstBytes, ticket: try XCTUnwrap(model.selectionTicket()))
        let first = try XCTUnwrap(model.records.last)
        let old = try XCTUnwrap(model.selectionTicket())
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 9), output: "KC_C", automatic: false), record: first, ticket: old)
        await model.previewPatch(first, ticket: old)
        let secondBytes = Data(#"{"vendorProductId":43,"layers":[["KC_NO"]]}"#.utf8)
        model.selectedOriginal = { secondBytes }
        await model.retainVIA(secondBytes, ticket: try XCTUnwrap(model.selectionTicket()))
        let second = try XCTUnwrap(model.records.last)
        model.stagePatchChange(.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false), record: second, ticket: old)
        await model.previewPatch(second, ticket: old)
        XCTAssertEqual(model.patchIssueKeys, [first.id: "phase4.patchIssue.slot"])
        XCTAssertTrue(model.canExportPreview(second)); XCTAssertFalse(model.canExportPreview(first))
        gate.update(.locked); fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertTrue(model.patchIssueKeys.isEmpty)
        gate.update(.unlocked); fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
        await model.refresh()
        await model.previewPatch(first, ticket: old)
        XCTAssertTrue(model.patchIssueKeys.isEmpty); XCTAssertTrue(model.patchPreviews.isEmpty)
    }
    func testNativePatchFailureCorrectionForBothBackendsAndLanguages() throws {
        ScreenEvidence.prepare()
        for backend in [FirmwareBackend.via, .vial] {
            for locale in ["en", "zh-Hans"] {
                var fixture: FlowFixture?
                var retained: FirmwareBatchRecord?
                var target: URL?
                let original = Data((backend == .via ? #"{"vendorProductId":42,"layers":[["KC_NO"]],"macro":["opaque"]}"# :
                    #"{"version":1,"uid":"42","layout":[[["KC_NO"]]],"macro":["opaque"]}"#).utf8)
                ScreenEvidence.awaitMain {
                    do {
                        let result = try await self.deployment(); fixture = result.0; target = result.1
                        let model = result.0.flow.firmwareCopies
                        self.qualifiedFirmware(model, store: result.2, gate: result.3, backend: backend)
                        if backend == .via {
                            model.selectedOriginal = { original }
                            await model.retainVIA(original, ticket: try XCTUnwrap(model.selectionTicket()))
                        } else {
                            let file = result.1.deletingLastPathComponent().appendingPathComponent("correction-original.vil")
                            try original.write(to: file); model.selectVial = { file }
                            await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
                        }
                        retained = model.records.last
                    } catch { XCTFail("Fixture setup failed: \(error)") }
                }
                let model = try XCTUnwrap(fixture?.flow.firmwareCopies)
                let record = try XCTUnwrap(retained)
                let ticket = try XCTUnwrap(model.selectionTicket())
                model.stagePatchChange(.init(slot: .init(layer: 0, column: 9), output: "KC_C", automatic: false), record: record, ticket: ticket)
                let artifact = try XCTUnwrap(target).deletingLastPathComponent().appendingPathComponent("corrected-patch.json")
                var selections = 0; model.selectExport = { _ in selections += 1; return artifact }
                let text = NativeText(locale: locale)
                let view = NSHostingView(rootView: Form { FirmwareCopiesSection(model: model, viaBytes: nil, text: text) }
                    .formStyle(.grouped).frame(width: 1000, height: 1400))
                view.sizingOptions = []
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1400), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
                defer { window.contentView = nil; window.close() }
                NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
                func pressPreview(expectIssue: Bool) throws {
                    let done = XCTestExpectation(description: "Native correction preview")
                    var delivered = false
                    model.onChange = {
                        let completed = expectIssue ? model.patchIssueKeys[record.id] != nil : model.patchPreviews[record.id] != nil
                        if !delivered, !model.working, completed { delivered = true; done.fulfill() }
                    }
                    XCTAssertTrue(KRAXPress(try NativeEvidence.node("preview-" + record.id.uuidString, in: view)))
                    ScreenEvidence.awaitMain {
                        let result = await XCTWaiter.fulfillment(of: [done], timeout: 5)
                        XCTAssertEqual(result, .completed)
                    }
                    NativeEvidence.update(view)
                }
                try pressPreview(expectIssue: true)
                let issue = try NativeEvidence.node("patch-issue-" + record.id.uuidString, in: view)
                XCTAssertEqual(KRAXLabel(issue), text("phase4.patchIssue.slot"))
                XCTAssertFalse(KRAXEnabled(try NativeEvidence.node("patch-" + record.id.uuidString, in: view)))
                XCTAssertEqual(selections, 0); XCTAssertEqual(model.records.last, record)
                XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path))
                if let root = NativeEvidence.outputRoot() {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    let name = "firmware-correction-" + backend.rawValue + "-" + locale
                    try ScreenEvidence.capturePNG(view).write(to: root.appendingPathComponent(name + ".png"))
                    try Data(("\(KRAXIdentifier(issue) ?? "-") | \(KRAXLabel(issue) ?? "") | \(KRAXFrame(issue))").utf8)
                        .write(to: root.appendingPathComponent(name + ".ax.txt"))
                }
                XCTAssertTrue(KRAXPress(try NativeEvidence.node("remove-patch-" + record.id.uuidString + "-0-0-9", in: view)))
                NativeEvidence.update(view); XCTAssertTrue(model.patchIssueKeys.isEmpty)
                XCTAssertFalse(NativeEvidence.elements(in: view).contains { KRAXIdentifier($0) == "patch-issue-" + record.id.uuidString })
                XCTAssertTrue(KRAXPress(try NativeEvidence.node("stage-" + record.id.uuidString, in: view)))
                NativeEvidence.update(view)
                try pressPreview(expectIssue: false)
                XCTAssertTrue(KRAXEnabled(try NativeEvidence.node("patch-" + record.id.uuidString, in: view)))
                let done = XCTestExpectation(description: "Corrected fixture export")
                var delivered = false
                model.onChange = { if !delivered, model.records.last?.state == .awaitingUserImport { delivered = true; done.fulfill() } }
                XCTAssertTrue(KRAXPress(try NativeEvidence.node("patch-" + record.id.uuidString, in: view)))
                ScreenEvidence.awaitMain {
                    let result = await XCTWaiter.fulfillment(of: [done], timeout: 5)
                    XCTAssertEqual(result, .completed)
                }
                XCTAssertEqual(selections, 1)
                XCTAssertEqual(try Data(contentsOf: artifact), Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "KC_NO", with: "KC_C").utf8))
                XCTAssertNil(model.records.last?.verifiedAt)
            }
        }
    }
    func testNativeMultiSlotPreviewAndExportForBothBackendsAndLanguages() throws {
        ScreenEvidence.prepare()
        for backend in [FirmwareBackend.via, .vial] {
            for locale in ["en", "zh-Hans"] {
                var fixture: FlowFixture?
                var retained: FirmwareBatchRecord?
                var target: URL?
                let original: Data
                if backend == .via {
                    original = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["KC_NO","KC_NO"]],"macros":["opaque"],"unknown": { "spaces" : [1,2] }}"#.utf8)
                } else {
                    original = Data(#"{"version":1,"uid":"42","layout":[[["KC_NO","CUSTOM"],["KC_NO","KC_NO"]]],"macros":["opaque"],"unknown": { "spaces" : [1,2] }}"#.utf8)
                }
                ScreenEvidence.awaitMain {
                    do {
                        let result = try await self.deployment(); fixture = result.0; target = result.1
                        let model = result.0.flow.firmwareCopies
                        self.qualifiedFirmware(model, store: result.2, gate: result.3, backend: backend, outputs: ["KC_C", "KC_A"])
                        if backend == .via {
                            model.selectedOriginal = { original }
                            await model.retainVIA(original, ticket: try XCTUnwrap(model.selectionTicket()))
                        } else {
                            let file = result.1.deletingLastPathComponent().appendingPathComponent("preview-original.vil")
                            try original.write(to: file); model.selectVial = { file }
                            await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
                        }
                        retained = model.records.last
                    } catch { XCTFail("Fixture setup failed: \(error)") }
                }
                let model = try XCTUnwrap(fixture?.flow.firmwareCopies)
                let record = try XCTUnwrap(retained)
                let ticket = try XCTUnwrap(model.selectionTicket())
                let first = FirmwareSlotChange(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: false)
                let second = FirmwareSlotChange(slot: .init(layer: 0, row: backend == .vial ? 1 : 0, column: 1), output: "KC_A", automatic: false)
                model.stagePatchChange(first, record: record, ticket: ticket)
                model.stagePatchChange(second, record: record, ticket: ticket)
                let artifact = try XCTUnwrap(target).deletingLastPathComponent().appendingPathComponent("reviewed-patch.json")
                var selections = 0; model.selectExport = { _ in selections += 1; return artifact }
                let text = NativeText(locale: locale)
                let view = NSHostingView(rootView: Form { FirmwareCopiesSection(model: model, viaBytes: nil, text: text) }
                    .formStyle(.grouped).frame(width: 1000, height: 1500))
                view.sizingOptions = []
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1500), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
                defer { window.contentView = nil; window.close() }
                NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
                XCTAssertFalse(KRAXEnabled(try NativeEvidence.node("patch-" + record.id.uuidString, in: view)))
                XCTAssertTrue(KRAXPress(try NativeEvidence.node("remove-patch-" + record.id.uuidString + "-0-0-0", in: view)))
                NativeEvidence.update(view); XCTAssertEqual(model.patchDrafts[record.id], [second])
                XCTAssertTrue(KRAXPress(try NativeEvidence.node("stage-" + record.id.uuidString, in: view)))
                NativeEvidence.update(view); XCTAssertEqual(model.patchDrafts[record.id], [second, first])
                let previewed = XCTestExpectation(description: "Multi-slot native preview")
                var previewDelivered = false
                model.onChange = { if !previewDelivered, model.patchPreviews[record.id] != nil { previewDelivered = true; previewed.fulfill() } }
                XCTAssertTrue(KRAXPress(try NativeEvidence.node("preview-" + record.id.uuidString, in: view)))
                ScreenEvidence.awaitMain {
                    let result = await XCTWaiter.fulfillment(of: [previewed], timeout: 5)
                    XCTAssertEqual(result, .completed)
                }
                NativeEvidence.update(view)
                let slotLabel = backend == .vial ? String(format: text("phase4.vialSlot"), 0, 1, 1) : String(format: text("phase4.viaSlot"), 0, 1)
                XCTAssertTrue(KRAXEnabled(try NativeEvidence.node("remove-patch-" + record.id.uuidString + "-0-0-0", in: view)))
                XCTAssertTrue(KRAXEnabled(try NativeEvidence.node("remove-patch-" + record.id.uuidString + (backend == .vial ? "-0-1-1" : "-0-0-1"), in: view)))
                XCTAssertEqual(KRAXLabel(try NativeEvidence.node("patch-diff-" + record.id.uuidString + (backend == .vial ? "-0-1-1" : "-0-0-1"), in: view)), slotLabel + ": KC_NO \u{2192} KC_A")
                XCTAssertEqual(selections, 0); XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path))
                XCTAssertEqual(model.records.last?.state, .draft)
                if let root = NativeEvidence.outputRoot() {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try ScreenEvidence.capturePNG(view).write(to: root.appendingPathComponent("firmware-preview-" + backend.rawValue + "-" + locale + ".png"))
                    let rows = NativeEvidence.elements(in: view).filter { KRAXIdentifier($0)?.hasPrefix("patch-diff-") == true }.map {
                        "\(KRAXIdentifier($0) ?? "-") | \(KRAXRole($0) ?? "-") | \(KRAXLabel($0) ?? "") | \(KRAXFrame($0))"
                    }
                    try Data(rows.joined(separator: "\n").utf8).write(to: root.appendingPathComponent("firmware-preview-" + backend.rawValue + "-" + locale + ".ax.txt"))
                }
                let exported = XCTestExpectation(description: "Reviewed multi-slot fixture export")
                var exportDelivered = false
                model.onChange = { if !exportDelivered, model.records.last?.state == .awaitingUserImport { exportDelivered = true; exported.fulfill() } }
                XCTAssertTrue(KRAXPress(try NativeEvidence.node("patch-" + record.id.uuidString, in: view)))
                ScreenEvidence.awaitMain {
                    let result = await XCTWaiter.fulfillment(of: [exported], timeout: 5)
                    XCTAssertEqual(result, .completed)
                }
                XCTAssertEqual(selections, 1); XCTAssertNil(model.patchPreviews[record.id]); XCTAssertNil(model.patchDrafts[record.id])
                XCTAssertEqual(model.records.last?.changes, [second, first])
                let actual = try Data(contentsOf: artifact)
                let expected: Data
                if backend == .via {
                    expected = Data(#"{"name":"Fixture","vendorProductId":42,"layers":[["KC_C","KC_A"]],"macros":["opaque"],"unknown": { "spaces" : [1,2] }}"#.utf8)
                } else {
                    expected = Data(#"{"version":1,"uid":"42","layout":[[["KC_C","CUSTOM"],["KC_NO","KC_A"]]],"macros":["opaque"],"unknown": { "spaces" : [1,2] }}"#.utf8)
                }
                XCTAssertEqual(actual, expected)
                XCTAssertNil(model.records.last?.verifiedAt)
            }
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
    func testVialOfficialMetadataAndHolesRemainReadOnlyInDefaultComposition() async throws {
        let (fixture, file, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        model.configure(store: store, gate: gate)
        let selected = file.deletingLastPathComponent().appendingPathComponent("official-default.vil")
        try Data(#"{"version":1,"uid":18446744073709551615,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO",-1,"KC_ENT"]]]}"#.utf8).write(to: selected)
        model.selectVial = { selected }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        let record = try XCTUnwrap(model.records.last)
        XCTAssertEqual(record.axes.deviceProtocol, "via-9/vial-6")
        XCTAssertEqual(record.axes.keycodeDialect, VialKeycodeDialect.name)
        XCTAssertNil(record.axes.definitionSchema); XCTAssertNil(record.axes.importer)
        XCTAssertFalse(model.canGenerate(record)); XCTAssertFalse(model.canVerifyVial(record))
        XCTAssertNil(model.issueKey)
    }
    func testVialDeviceConnectionFlowsThroughNativeButtonAndEncryptedTransaction() throws {
        try verifyNativeVialButton(modifierNames: false)
    }
    func testVialCombinedModifierNamesFlowThroughNativeButtonAndEncryptedTransaction() throws {
        try verifyNativeVialButton(modifierNames: true)
    }
    func testVialCanonicalLayerTapNamesFlowThroughNativeButtonAndEncryptedTransaction() throws {
        try verifyNativeVialButton(modifierNames: false, layerTapNames: true)
    }
    func testVialStaticModifierTapNamesFlowThroughNativeButtonAndEncryptedTransaction() throws {
        try verifyNativeVialButton(modifierNames: true, modifierTapNames: true)
    }
    func testVialOneShotModifierNamesFlowThroughNativeButtonAndEncryptedTransaction() throws {
        try verifyNativeVialButton(modifierNames: false, oneShotNames: true)
    }
    func testVialPersistentDefaultLayerNamesFlowThroughNativeButtonAndEncryptedTransaction() throws {
        try verifyNativeVialButton(modifierNames: false, persistentLayerNames: true)
    }
    func testVialStaticLayerActionsFlowThroughNativeButtonAndEncryptedTransaction() throws {
        try verifyNativeVialButton(modifierNames: false, staticLayerNames: true)
    }
    private func verifyNativeVialButton(modifierNames: Bool, layerTapNames: Bool = false, modifierTapNames: Bool = false, oneShotNames: Bool = false, persistentLayerNames: Bool = false, staticLayerNames: Bool = false) throws {
        ScreenEvidence.prepare()
        var retainedFixture: FlowFixture?
        var patchURL: URL?
        var transportPort: NativeVialHIDFixture?
        var originalText = #"{"version":1,"uid":18446744073709551615,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO",-1,"KC_KP_ENTER"]]],"macro":[],"encoder_layout":[[[-1,-1],[-1,-1],["KC_QUOTE","RSFT(KC_QUOTE)"]]],"settings":{}}"#
        if modifierNames {
            originalText = originalText.replacingOccurrences(of: "KC_KP_ENTER", with: "C_S(KC_KP_ENTER)")
                .replacingOccurrences(of: #""KC_QUOTE","RSFT(KC_QUOTE)""#, with: #""SCMD(KC_QUOTE)","RCG(KC_QUOTE)""#)
        }
        if layerTapNames {
            originalText = originalText.replacingOccurrences(of: "KC_KP_ENTER", with: "LT0(KC_KP_ENTER)")
                .replacingOccurrences(of: #""KC_QUOTE","RSFT(KC_QUOTE)""#, with: #""LT0(KC_QUOTE)","LT0(KC_QUOTE)""#)
        }
        if modifierTapNames {
            for prefix in ["C_S", "SCMD", "RCG"] {
                originalText = originalText.replacingOccurrences(of: prefix + "(", with: prefix + "_T(")
            }
        }
        if oneShotNames {
            originalText = originalText.replacingOccurrences(of: "KC_KP_ENTER", with: "OSM(MOD_LCTL|MOD_LSFT)")
                .replacingOccurrences(of: #""KC_QUOTE","RSFT(KC_QUOTE)""#, with: #""OSM(MOD_MEH)","OSM(MOD_RGUI)""#)
        }
        if persistentLayerNames {
            originalText = originalText.replacingOccurrences(of: "KC_KP_ENTER", with: "PDF(0)")
                .replacingOccurrences(of: #""KC_QUOTE","RSFT(KC_QUOTE)""#, with: #""PDF(0)","PDF(31)""#)
        }
        if staticLayerNames {
            originalText = originalText.replacingOccurrences(of: "KC_KP_ENTER", with: "FN_MO13")
                .replacingOccurrences(of: #""KC_QUOTE","RSFT(KC_QUOTE)""#, with: #""FN_MO23","QK_LAYER_LOCK""#)
        }
        let bytes = Data(originalText.utf8)
        ScreenEvidence.awaitMain {
            do {
                let (fixture, file, store, gate) = try await self.deployment()
                retainedFixture = fixture
                let model = fixture.flow.firmwareCopies
                let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: VialDeviceDefinition.schema, importer: "offline-importer")
                let transport = NativeVialHIDFixture(encoders: true, basicNames: true, modifierNames: modifierNames, layerTapNames: layerTapNames, modifierTapNames: modifierTapNames, oneShotNames: oneShotNames, persistentLayerNames: persistentLayerNames, staticLayerNames: staticLayerNames)
                transportPort = transport
                model.configure(store: store, gate: gate, support: .init(entries: [.init(backend: .vial,
                    device: "18446744073709551615", axes: axes, supportedOutputs: ["KC_C"])]),
                    versionAxes: { _ in axes }, vialConnection: { _, _ in
                        VialDeviceReadConnection(endpoint: transport, vendorID: 0x1234, productID: 0x5678)
                    })
                let original = file.deletingLastPathComponent().appendingPathComponent("official-adapter.vil")
                try bytes.write(to: original); model.selectVial = { original }
                await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
                let record = try XCTUnwrap(model.records.last)
                let patch = file.deletingLastPathComponent().appendingPathComponent("official-adapter-patch.vil")
                patchURL = patch; model.selectExport = { _ in patch }
                await model.exportChanges(record, changes: [.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: true)], ticket: try XCTUnwrap(model.selectionTicket()))
                await model.perform(.claimImport, record: try XCTUnwrap(model.records.last), ticket: try XCTUnwrap(model.selectionTicket()))
            } catch { XCTFail("\(error)") }
        }
        let model = try XCTUnwrap(retainedFixture?.flow.firmwareCopies)
        let patch = try XCTUnwrap(patchURL), transport = try XCTUnwrap(transportPort)
        let claimed = try XCTUnwrap(model.records.last)
        XCTAssertTrue(model.canVerifyVial(claimed))
        let view = NSHostingView(rootView: Form {
            FirmwareCopiesSection(model: model, viaBytes: nil, text: NativeText(locale: "en"))
        }.formStyle(.grouped).frame(width: 900, height: 1200))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
        let verified = XCTestExpectation(description: "Protocol adapter completed product readback")
        var delivered = false
        model.onChange = {
            if !delivered, model.records.last?.state == .verified { delivered = true; verified.fulfill() }
        }
        XCTAssertTrue(KRAXPress(try NativeEvidence.node("readback-" + claimed.id.uuidString, in: view)))
        ScreenEvidence.awaitMain {
            let waitResult = await XCTWaiter.fulfillment(of: [verified], timeout: 5)
            XCTAssertEqual(waitResult, .completed)
        }
        XCTAssertEqual(model.records.last?.state, .verified); XCTAssertNil(model.issueKey)
        NativeEvidence.update(view)
        if let directory = NativeEvidence.outputRoot() {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filename = persistentLayerNames ? "vial-persistent-layer-readback-en.png" : (oneShotNames ? "vial-one-shot-readback-en.png" : (modifierTapNames ? "vial-modifier-tap-readback-en.png" : (layerTapNames ? "vial-layer-tap-readback-en.png" : (modifierNames ? "vial-modifiers-readback-en.png" : "vial-basic-readback-en.png"))))
            try ScreenEvidence.capturePNG(view).write(to: directory.appendingPathComponent(staticLayerNames ? "vial-static-layer-readback-en.png" : filename))
        }
        var requests: [VialReadRequest] = []
        requests = transport.requests
        XCTAssertEqual(requests.count, 17)
        XCTAssertEqual(Array(requests.prefix(3)), [.viaProtocol, .identity, .definitionSize])
        XCTAssertEqual(Array(requests.suffix(7)), [.viaProtocol, .identity, .layerCount, try .keymap(offset: 0, length: 6),
            .encoder(layer: 0, index: 2), .identity, .layerCount])
        XCTAssertEqual(transport.closeCount, 1)
        XCTAssertEqual(try Data(contentsOf: patch), Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "KC_NO", with: "KC_C").utf8))
    }
    private func claimedHID(_ endpoint: NativeVialHIDFixture, vendorID: UInt16 = 0x1234,
                            original: String? = nil) async throws -> (FlowFixture, ObjectStore, KeyAvailabilityGate, FirmwareBatchRecord) {
        let (fixture, file, store, gate) = try await deployment()
        let model = fixture.flow.firmwareCopies
        let bytes = Data((original ?? #"{"version":1,"uid":18446744073709551615,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO",-1,"KC_ENT"]]]}"#).utf8)
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial,
            definitionSchema: VialDeviceDefinition.schema, importer: "offline-importer")
        model.configure(store: store, gate: gate, support: .init(entries: [.init(backend: .vial,
            device: "18446744073709551615", axes: axes, supportedOutputs: ["KC_C"])]),
            versionAxes: { _ in axes }, vialConnection: { _, _ in
                VialDeviceReadConnection(endpoint: endpoint, vendorID: vendorID, productID: 0x5678)
            })
        let selected = file.deletingLastPathComponent().appendingPathComponent("hid-original.vil")
        try bytes.write(to: selected); model.selectVial = { selected }
        await model.retainVial(ticket: try XCTUnwrap(model.selectionTicket()))
        model.selectExport = { _ in file.deletingLastPathComponent().appendingPathComponent("hid-patched.vil") }
        await model.exportChanges(try XCTUnwrap(model.records.last),
            changes: [.init(slot: .init(layer: 0, column: 0), output: "KC_C", automatic: true)],
            ticket: try XCTUnwrap(model.selectionTicket()))
        await model.perform(.claimImport, record: try XCTUnwrap(model.records.last), ticket: try XCTUnwrap(model.selectionTicket()))
        let record = try XCTUnwrap(model.records.last)
        XCTAssertEqual(record.state, .importClaimed)
        return (fixture, store, gate, record)
    }
    func testVialHIDRejectsIndependentIdentityAndOccupiedPositionMismatchBeforeKeymap() async throws {
        for wrongVendor in [true, false] {
            let endpoint = NativeVialHIDFixture()
            let (fixture, store, gate, record) = try await claimedHID(endpoint, vendorID: wrongVendor ? 1 : 0x1234,
                original: wrongVendor ? nil : #"{"version":1,"uid":18446744073709551615,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO","KC_ENT",-1]]]}"#)
            let model = fixture.flow.firmwareCopies
            await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
            XCTAssertEqual(model.records.last?.state, .importClaimed); XCTAssertNotNil(model.issueKey)
            XCTAssertFalse(endpoint.requests.contains(where: { $0.bytes[0] == 0x12 }))
            XCTAssertEqual(endpoint.closeCount, 1); XCTAssertFalse(model.working)
            let ledger = try await FirmwareOperationCoordinator(store: store,
                resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
            XCTAssertNil(ledger.records.last?.verifiedAt)
        }
    }
    func testDecoratedVialDefinitionReachesCompleteReadbackAndPersistsMismatch() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("evidence/phase4/fixtures/synthetic/vial6-definition-topology.json"))) as? [String: Any])
        let cases = try XCTUnwrap(fixtures["cases"] as? [[String: Any]])
        let encoded = try XCTUnwrap(cases.first { $0["name"] as? String == "alignment-7" }?["compressed"] as? String)
        let definition = try XCTUnwrap(Data(base64Encoded: encoded))
        for mismatch in [false, true] {
            let endpoint = NativeVialHIDFixture(encoders: true, encoderMismatch: mismatch, definitionOverride: definition)
            let original = #"{"version":1,"uid":18446744073709551615,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO",-1,"KC_ENT"]]],"encoder_layout":[[[-1,-1],[-1,-1],["KC_ENT","0x1234"]]]}"#
            let (fixture, store, gate, record) = try await claimedHID(endpoint, original: original)
            let model = fixture.flow.firmwareCopies
            await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
            XCTAssertEqual(model.records.last?.state, mismatch ? .externallyChanged : .verified)
            XCTAssertNil(model.issueKey); XCTAssertEqual(endpoint.closeCount, 1)
            XCTAssertTrue(endpoint.requests.contains(.encoder(layer: 0, index: 2)))
            let ledger = try await FirmwareOperationCoordinator(store: store,
                resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
            XCTAssertEqual(ledger.records.last?.state, mismatch ? .externallyChanged : .verified)
            XCTAssertNotNil(ledger.records.last?.verifiedAt)
        }
    }
    func testVialHIDKeymapMismatchIsRecordedByExistingTransaction() async throws {
        let endpoint = NativeVialHIDFixture(mismatch: true)
        let (fixture, store, gate, record) = try await claimedHID(endpoint)
        let model = fixture.flow.firmwareCopies
        await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.last?.state, .externallyChanged); XCTAssertNotNil(model.records.last?.verifiedAt)
        XCTAssertNil(model.issueKey); XCTAssertEqual(endpoint.requests.count, 16); XCTAssertEqual(endpoint.closeCount, 1)
        let ledger = try await FirmwareOperationCoordinator(store: store,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
        XCTAssertEqual(ledger.records.last?.state, .externallyChanged)
    }
    private var encoderOriginal: String {
        #"{"version":1,"uid":18446744073709551615,"via_protocol":9,"vial_protocol":6,"layout":[[["KC_NO",-1,"C_S(KC_KP_ENTER)"]]],"encoder_layout":[[[-1,-1],[-1,-1],["SCMD(KC_QUOTE)","RCG(KC_QUOTE)"]]]}"#
    }
    private var oneShotEncoderOriginal: String {
        encoderOriginal.replacingOccurrences(of: "C_S(KC_KP_ENTER)", with: "OSM(MOD_LCTL|MOD_LSFT)")
            .replacingOccurrences(of: "SCMD(KC_QUOTE)", with: "OSM(MOD_MEH)")
            .replacingOccurrences(of: "RCG(KC_QUOTE)", with: "OSM(MOD_RGUI)")
    }
    private var persistentLayerEncoderOriginal: String {
        encoderOriginal.replacingOccurrences(of: "C_S(KC_KP_ENTER)", with: "PDF(0)")
            .replacingOccurrences(of: "SCMD(KC_QUOTE)", with: "PDF(0)")
            .replacingOccurrences(of: "RCG(KC_QUOTE)", with: "PDF(31)")
    }
    private var staticLayerEncoderOriginal: String {
        encoderOriginal.replacingOccurrences(of: "C_S(KC_KP_ENTER)", with: "FN_MO13")
            .replacingOccurrences(of: "SCMD(KC_QUOTE)", with: "FN_MO23")
            .replacingOccurrences(of: "RCG(KC_QUOTE)", with: "QK_LAYER_LOCK")
    }
    func testVialHIDEncoderChangeWithMatchingMatrixRecordsExternalChangeAndReopens() async throws {
        try await verifyEncoderExternalChange(modifierTapNames: false)
    }
    func testVialHIDModifierTapEncoderOnlyChangeRecordsExternalChangeAndReopens() async throws {
        try await verifyEncoderExternalChange(modifierTapNames: true)
    }
    func testVialHIDOneShotEncoderOnlyChangeRecordsExternalChangeAndReopens() async throws {
        try await verifyEncoderExternalChange(modifierTapNames: false, oneShotNames: true)
    }
    func testVialHIDPersistentDefaultLayerEncoderOnlyChangeRecordsExternalChangeAndReopens() async throws {
        try await verifyEncoderExternalChange(modifierTapNames: false, persistentLayerNames: true)
    }
    func testVialHIDStaticLayerActionEncoderOnlyChangeRecordsExternalChangeAndReopens() async throws {
        try await verifyEncoderExternalChange(modifierTapNames: false, staticLayerNames: true)
    }
    private func verifyEncoderExternalChange(modifierTapNames: Bool, oneShotNames: Bool = false, persistentLayerNames: Bool = false, staticLayerNames: Bool = false) async throws {
        let endpoint = NativeVialHIDFixture(encoders: true, encoderMismatch: true, basicNames: true, modifierNames: true, modifierTapNames: modifierTapNames, oneShotNames: oneShotNames, persistentLayerNames: persistentLayerNames, staticLayerNames: staticLayerNames)
        let original = modifierTapNames ? encoderOriginal.replacingOccurrences(of: "C_S(", with: "C_S_T(")
            .replacingOccurrences(of: "SCMD(", with: "SCMD_T(").replacingOccurrences(of: "RCG(", with: "RCG_T(") : encoderOriginal
        let (fixture, store, gate, record) = try await claimedHID(endpoint, original: staticLayerNames ? staticLayerEncoderOriginal : (persistentLayerNames ? persistentLayerEncoderOriginal : (oneShotNames ? oneShotEncoderOriginal : original)))
        let model = fixture.flow.firmwareCopies
        await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.last?.state, .externallyChanged)
        XCTAssertEqual(endpoint.closeCount, 1)
        let reopened = try await FirmwareOperationCoordinator(store: store,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).reconcile()
        XCTAssertEqual(reopened.records.last?.state, .externallyChanged)
    }
    func testVialHIDEncoderPositionMismatchStopsBeforeMatrixAndEncoderQueries() async throws {
        let endpoint = NativeVialHIDFixture(encoders: true)
        let (fixture, store, gate, record) = try await claimedHID(endpoint)
        let model = fixture.flow.firmwareCopies
        await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.last?.state, .importClaimed)
        XCTAssertNotNil(model.issueKey); XCTAssertEqual(endpoint.closeCount, 1)
        XCTAssertFalse(endpoint.requests.contains { $0.bytes[0] == 0x12 || ($0.bytes[0] == 0xfe && $0.bytes[1] == 3) })
        let ledger = try await FirmwareOperationCoordinator(store: store,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
        XCTAssertNil(ledger.records.last?.verifiedAt)
    }
    func testVialHIDEncoderCancellationAndPrivacyClosePendingReportsAndIgnoreLateReply() async throws {
        try await verifyEncoderCancellationAndPrivacy(modifierTapNames: false)
    }
    func testVialHIDModifierTapEncoderCancellationAndPrivacyIgnoreLateReply() async throws {
        try await verifyEncoderCancellationAndPrivacy(modifierTapNames: true)
    }
    func testVialHIDOneShotEncoderCancellationAndPrivacyIgnoreLateReply() async throws {
        try await verifyEncoderCancellationAndPrivacy(modifierTapNames: false, oneShotNames: true)
    }
    func testVialHIDPersistentDefaultLayerEncoderCancellationAndPrivacyIgnoreLateReply() async throws {
        try await verifyEncoderCancellationAndPrivacy(modifierTapNames: false, persistentLayerNames: true)
    }
    func testVialHIDStaticLayerActionEncoderCancellationAndPrivacyIgnoreLateReply() async throws {
        try await verifyEncoderCancellationAndPrivacy(modifierTapNames: false, staticLayerNames: true)
    }
    private func verifyEncoderCancellationAndPrivacy(modifierTapNames: Bool, oneShotNames: Bool = false, persistentLayerNames: Bool = false, staticLayerNames: Bool = false) async throws {
        for privacy in [false, true] {
            let pausedRequest = VialReadRequest.encoder(layer: 0, index: 2)
            let endpoint = NativeVialHIDFixture(pause: pausedRequest, encoders: true, basicNames: true, modifierNames: true, modifierTapNames: modifierTapNames, oneShotNames: oneShotNames, persistentLayerNames: persistentLayerNames, staticLayerNames: staticLayerNames)
            let original = modifierTapNames ? encoderOriginal.replacingOccurrences(of: "C_S(", with: "C_S_T(")
                .replacingOccurrences(of: "SCMD(", with: "SCMD_T(").replacingOccurrences(of: "RCG(", with: "RCG_T(") : encoderOriginal
            let (fixture, store, gate, record) = try await claimedHID(endpoint, original: staticLayerNames ? staticLayerEncoderOriginal : (persistentLayerNames ? persistentLayerEncoderOriginal : (oneShotNames ? oneShotEncoderOriginal : original)))
            let model = fixture.flow.firmwareCopies, ticket = try XCTUnwrap(model.selectionTicket())
            let task = Task { await model.verifyVial(record, ticket: ticket) }
            await fulfillment(of: [endpoint.paused], timeout: 5)
            let before = endpoint.requests.count
            if privacy { gate.update(.locked); model.clear(); gate.update(.unlocked) }
            else { task.cancel() }
            await task.value
            endpoint.emit(pausedRequest)
            XCTAssertEqual(endpoint.requests.count, before); XCTAssertEqual(endpoint.closeCount, 1)
            let ledger = try await FirmwareOperationCoordinator(store: store,
                resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
            XCTAssertEqual(ledger.records.last?.state, .importClaimed); XCTAssertNil(ledger.records.last?.verifiedAt)
        }
    }
    func testVialHIDUnknownNamedEncoderActionCannotBecomeVerificationEvidence() async throws {
        try await verifyUnknownEncoderAction(modifierTapNames: false)
    }
    func testVialHIDUnknownModifierTapChildCannotBecomeVerificationEvidence() async throws {
        try await verifyUnknownEncoderAction(modifierTapNames: true)
    }
    func testVialHIDUnknownOneShotModifierCannotBecomeVerificationEvidence() async throws {
        try await verifyUnknownEncoderAction(modifierTapNames: false, oneShotNames: true)
    }
    func testVialHIDUnknownPersistentDefaultLayerCannotBecomeVerificationEvidence() async throws {
        try await verifyUnknownEncoderAction(modifierTapNames: false, persistentLayerNames: true)
    }
    func testVialHIDUnqualifiedStaticLayerAliasCannotBecomeVerificationEvidence() async throws {
        try await verifyUnknownEncoderAction(modifierTapNames: false, staticLayerNames: true)
    }
    private func verifyUnknownEncoderAction(modifierTapNames: Bool, oneShotNames: Bool = false, persistentLayerNames: Bool = false, staticLayerNames: Bool = false) async throws {
        let endpoint = NativeVialHIDFixture(encoders: true, basicNames: true, modifierNames: true, modifierTapNames: modifierTapNames, oneShotNames: oneShotNames, persistentLayerNames: persistentLayerNames, staticLayerNames: staticLayerNames)
        let original = modifierTapNames ? encoderOriginal.replacingOccurrences(of: "C_S(", with: "C_S_T(")
            .replacingOccurrences(of: "SCMD(", with: "SCMD_T(").replacingOccurrences(of: "RCG(KC_QUOTE)", with: "RCG_T(USER00)")
            : encoderOriginal.replacingOccurrences(of: "RCG(KC_QUOTE)", with: "USER00")
        let (fixture, store, gate, record) = try await claimedHID(endpoint,
            original: staticLayerNames ? staticLayerEncoderOriginal.replacingOccurrences(of: "QK_LAYER_LOCK", with: "QK_LLCK") : (persistentLayerNames ? persistentLayerEncoderOriginal.replacingOccurrences(of: "PDF(31)", with: "PDF(USER00)") : (oneShotNames ? oneShotEncoderOriginal.replacingOccurrences(of: "OSM(MOD_RGUI)", with: "OSM(USER00)") : original)))
        let model = fixture.flow.firmwareCopies
        await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertEqual(model.records.last?.state, .importClaimed)
        XCTAssertNotNil(model.issueKey); XCTAssertEqual(endpoint.closeCount, 1)
        let ledger = try await FirmwareOperationCoordinator(store: store,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
        XCTAssertEqual(ledger.records.last?.state, .importClaimed); XCTAssertNil(ledger.records.last?.verifiedAt)
    }
    func testVialHIDCancelDisconnectPrivacyAndReselectionClosePendingReports() async throws {
        for action in 0..<5 {
            let pausedRequest = try action % 2 == 0 ? VialReadRequest.definitionPage(0) : .keymap(offset: 0, length: 6)
            let endpoint = NativeVialHIDFixture(pause: pausedRequest)
            let (fixture, store, gate, record) = try await claimedHID(endpoint)
            let model = fixture.flow.firmwareCopies
            let ticket = try XCTUnwrap(model.selectionTicket())
            let task = Task { await model.verifyVial(record, ticket: ticket) }
            let arrived = await XCTWaiter.fulfillment(of: [endpoint.paused], timeout: 5)
            XCTAssertEqual(arrived, .completed)
            XCTAssertTrue(model.working)
            switch action {
            case 0: task.cancel()
            case 1: endpoint.disconnect()
            case 2:
                gate.update(.locked); fixture.observeLocked(); fixture.flow.sync(from: fixture.orchestrator.state)
                gate.update(.unlocked); fixture.observe(); fixture.flow.sync(from: fixture.orchestrator.state)
                XCTAssertEqual(endpoint.closeCount, 1)
            case 3:
                model.configure(store: store, gate: gate)
                XCTAssertEqual(endpoint.closeCount, 1)
            default:
                model.cancelVialReadback()
                XCTAssertEqual(endpoint.closeCount, 1)
            }
            await task.value
            let count = endpoint.requests.count
            endpoint.emit(pausedRequest)
            await model.refresh()
            XCTAssertEqual(endpoint.requests.count, count); XCTAssertEqual(endpoint.closeCount, 1)
            XCTAssertEqual(model.records.last?.state, .importClaimed); XCTAssertNil(model.records.last?.verifiedAt)
            XCTAssertFalse(model.working)
            if action >= 2 { XCTAssertNil(model.issueKey) } else { XCTAssertNotNil(model.issueKey) }
            let ledger = try await FirmwareOperationCoordinator(store: store,
                resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
            XCTAssertNil(ledger.records.last?.verifiedAt)
        }
    }
    func testVialHIDUnavailableCompatibilityAndCancelledTaskNeverOpenConnection() async throws {
        let endpoint = NativeVialHIDFixture()
        let (fixture, store, gate, record) = try await claimedHID(endpoint)
        let model = fixture.flow.firmwareCopies
        let ticket = try XCTUnwrap(model.selectionTicket())
        let task = Task { await model.verifyVial(record, ticket: ticket) }
        task.cancel(); await task.value
        XCTAssertTrue(endpoint.requests.isEmpty); XCTAssertEqual(endpoint.closeCount, 0)
        model.configure(store: store, gate: gate, vialConnection: { _, _ in
            XCTFail("Unknown support must not open HID")
            return VialDeviceReadConnection(endpoint: endpoint, vendorID: 0x1234, productID: 0x5678)
        })
        await model.refresh()
        let current = try XCTUnwrap(model.records.last)
        XCTAssertFalse(model.canVerifyVial(current))
        await model.verifyVial(current, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertTrue(endpoint.requests.isEmpty); XCTAssertEqual(endpoint.closeCount, 0)
    }
    func testVialHIDRetryUsesFreshConnectionAndOldCompletionCannotOverwriteIt() async throws {
        let pending = NativeVialHIDFixture(pause: .identity), fresh = NativeVialHIDFixture()
        let (fixture, store, gate, record) = try await claimedHID(pending)
        let model = fixture.flow.firmwareCopies
        var opens = 0
        model.configure(store: store, gate: gate, support: .init(entries: [.init(backend: .vial,
            device: record.device, axes: record.axes, supportedOutputs: ["KC_C"])]),
            vialConnection: { _, _ in
                opens += 1
                return VialDeviceReadConnection(endpoint: opens == 1 ? pending : fresh, vendorID: 0x1234, productID: 0x5678)
            })
        await model.refresh()
        let ticket = try XCTUnwrap(model.selectionTicket())
        let old = Task { await model.verifyVial(record, ticket: ticket) }
        let arrived = await XCTWaiter.fulfillment(of: [pending.paused], timeout: 5)
        XCTAssertEqual(arrived, .completed)
        await model.verifyVial(record, ticket: ticket)
        XCTAssertEqual(opens, 1)
        model.cancelVialReadback()
        await model.verifyVial(record, ticket: try XCTUnwrap(model.selectionTicket()))
        await old.value; pending.emit(.identity)
        XCTAssertEqual(model.records.last?.state, .verified); XCTAssertNil(model.issueKey)
        XCTAssertFalse(model.working); XCTAssertEqual(opens, 2)
        XCTAssertEqual(pending.requests.count, 2); XCTAssertEqual(pending.closeCount, 1)
        XCTAssertEqual(fresh.requests.count, 16); XCTAssertEqual(fresh.closeCount, 1)
        let reopened = try await FirmwareOperationCoordinator(store: store,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) }).ledger()
        XCTAssertEqual(reopened.records.last?.state, .verified)
        XCTAssertEqual(reopened.records.last?.verificationSource, "vialKeymapReadback")
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
    func testUninstallRecoveryCollisionDoesNotReportReadyOrRemoveRulesAndCanRetry() async throws {
        for deleteData in [false, true] {
            let (fixture, file, store, gate) = try await deployment()
            let model = fixture.flow.firmwareCopies
            let first = try await retainOriginal(model)
            let secondBytes = Data(#"{"vendorProductId":43,"layers":[["KC_B"]]}"#.utf8)
            model.selectedOriginal = { secondBytes }
            await model.retainVIA(secondBytes, ticket: try XCTUnwrap(model.selectionTicket()))
            let second = try XCTUnwrap(model.records.last)
            XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(model.records.count, 2)
            let copy = file.deletingLastPathComponent().appendingPathComponent("shared-recovery.json")
            model.selectExport = { _ in copy }
            var calls: [String] = []
            model.configureUninstall(.init(stopCapture: { calls.append("capture") }, removeRules: { calls.append("rules") },
                removeLogin: { calls.append("login") }, eraseData: { calls.append("data") },
                editing: { fixture.flow.karabinerMappings.maintenance = $0 }))
            await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()),
                request: try model.fixtureUninstallRequest(choice: 0, deleteData: deleteData, discard: false))
            XCTAssertEqual(calls, ["capture"]); XCTAssertFalse(model.uninstallReady)
            XCTAssertEqual(model.issueKey, "phase4.operationFailed"); XCTAssertEqual(model.uninstallStage, .captureStopped)
            XCTAssertFalse(model.working); XCTAssertFalse(fixture.flow.karabinerMappings.maintenance)
            let fresh = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
            let originalFirst = try await fresh.original(first.id), originalSecond = try await fresh.original(second.id)
            XCTAssertEqual(originalSecond, secondBytes)
            let previous = try await UninstallPreparationCoordinator.previousPreparation(store: store)
            XCTAssertNil(previous)
            calls = []
            let separate = file.deletingLastPathComponent().appendingPathComponent("separate-recovery.json")
            model.selectExport = { $0.id == first.id ? copy : separate }
            await model.prepareUninstall(ticket: try XCTUnwrap(model.selectionTicket()),
                request: try model.fixtureUninstallRequest(choice: 0, deleteData: deleteData, discard: false))
            XCTAssertEqual(calls, deleteData ? ["capture", "rules", "login", "data"] : ["capture", "rules", "login"])
            XCTAssertTrue(model.uninstallReady); XCTAssertNil(model.issueKey)
            XCTAssertEqual(try Data(contentsOf: copy), originalFirst)
            XCTAssertEqual(try Data(contentsOf: separate), secondBytes)
            XCTAssertFalse(fixture.flow.karabinerMappings.maintenance)
        }
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

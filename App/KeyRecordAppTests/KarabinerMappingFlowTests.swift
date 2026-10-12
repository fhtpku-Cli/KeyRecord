import XCTest
import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordMappings
import KeyRecordStore

private actor NativeMappingFixtureKeys: ObjectStoreKeySource {
    var present = false
    func seed() { present = true }
    func namespaceKeyVersions() -> Set<KeyVersion> { present ? [KeyVersion(rawValue: 1)] : [] }
    func material(for version: KeyVersion) throws -> Data { Data(repeating: 0xb3, count: 32) }
}

@MainActor
final class KarabinerMappingFlowTests: XCTestCase {
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

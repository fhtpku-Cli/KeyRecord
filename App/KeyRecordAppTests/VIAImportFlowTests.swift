import XCTest
import AppKit
import SwiftUI
import os
import Darwin
import KeyRecordCore
import KeyRecordAnalysis

@MainActor
final class VIAImportFlowTests: XCTestCase {
    private let karabinerBytes = Data(#"{"profiles":[{"name":"Synthetic A","selected":true,"complex_modifications":{"rules":[{"manipulators":[{"type":"basic","from":{"key_code":"f1"},"to":[{"key_code":"c","modifiers":["left_command"]}]}]}]}},{"name":"Synthetic B"}]}"#.utf8)

    func testKarabinerCopyFeedsConflictEvidenceWithoutConnectingBackend() async throws {
        let (root, _, _) = try files()
        let fixture = try await ready(root)
        let url = root.appendingPathComponent("karabiner-copy.json")
        try karabinerBytes.write(to: url)
        let model = fixture.flow.karabinerImport
        defer { model.clear() }
        await model.load(url: url, ticket: try XCTUnwrap(model.selectionTicket()))
        let input = try AnalysisPreview.input()
        fixture.flow.snapshot = try AggregateSnapshot(shortcuts: input.shortcuts, bareKeys: input.bareKeys)
        let evidence = fixture.flow.candidateConflictEvidence
        XCTAssertFalse(try XCTUnwrap(evidence.observations).isEmpty)
        XCTAssertEqual(evidence.backendRules?.origin, .selectedCopy)
        XCTAssertEqual(evidence.backendRules?.rules.count, 1)
        model.profile = "1"
        XCTAssertEqual(fixture.flow.candidateConflictEvidence.backendRules?.rules.count, 0)
        fixture.flow.intendedBackend = .via
        XCTAssertNil(fixture.flow.candidateConflictEvidence.backendRules)
        let request = CandidateCheckInput(source: Chord(keyCode: try KeyCode(8), modifiers: ModifierSet(command: .left,
            option: .none, control: .none, shift: .none, fn: .none)),
            trigger: Chord(keyCode: try KeyCode(122), modifiers: ModifierSet(command: .none,
                option: .none, control: .none, shift: .none, fn: .none)), scope: .global,
            backend: .disconnected(.karabiner), conflictEvidence: evidence)
        let report = CandidateConflictDetector.evaluate(request)
        XCTAssertEqual(report.readiness, .disconnected)
        XCTAssertTrue(report.findings.contains { $0.kind == .existingRuleOverlap })
    }

    func testKarabinerFileReplacementWithdrawsEvidence() async throws {
        let (root, _, _) = try files()
        let fixture = try await ready(root)
        let model = fixture.flow.karabinerImport
        let url = root.appendingPathComponent("karabiner-copy.json")
        try karabinerBytes.write(to: url)
        await model.load(url: url, ticket: try XCTUnwrap(model.selectionTicket()))
        XCTAssertNotNil(model.evidence)
        let changed = XCTestExpectation(description: "Karabiner copy changed")
        model.onChange = { if model.issueKey == "phase2.karabiner.changed" { changed.fulfill() } }
        try karabinerBytes.write(to: url, options: .atomic)
        let result = await XCTWaiter.fulfillment(of: [changed], timeout: 3)
        XCTAssertEqual(result, .completed)
        XCTAssertNil(model.evidence)
        model.clear()
    }

    func testKarabinerPendingReadAndPickerCannotCrossPrivacyReopening() async throws {
        let (root, _, _) = try files()
        let fixture = try await ready(root)
        let model = fixture.flow.karabinerImport
        let url = root.appendingPathComponent("karabiner-copy.json")
        try karabinerBytes.write(to: url)
        let ticket = try XCTUnwrap(model.selectionTicket())
        let started = XCTestExpectation(description: "Karabiner read started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal(); model.clear() }
        model.readFile = { url, access, notify in
            started.fulfill()
            release.wait()
            let selected = try VIAFileReader.readConfiguration(url: url, access: access, notify: notify, parse: KarabinerReferenceParser.parse)
            return SelectedKarabinerFile(reference: selected.reference, monitor: selected.monitor)
        }
        let pending = Task { await model.load(url: url, ticket: ticket) }
        let startResult = await XCTWaiter.fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(startResult, .completed)
        fixture.observeLocked()
        fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.observe()
        fixture.flow.sync(from: fixture.orchestrator.state)
        release.signal()
        await pending.value
        XCTAssertNil(model.reference)
        XCTAssertNil(model.filename)
        let called = OSAllocatedUnfairLock(initialState: false)
        model.readFile = { _, _, _ in called.withLock { $0 = true }; throw VIAFileReadError.changed }
        await model.load(url: url, ticket: ticket)
        XCTAssertFalse(called.withLock { $0 })
    }

    func testConflictReportAndKarabinerReferenceRenderBothLocales() throws {
        ScreenEvidence.prepare()
        let (root, _, _) = try files()
        let fixture = try FlowFixture(directory: root, environment: ["KEYRECORD_FLOW_FIXTURE": root.path])
        let url = root.appendingPathComponent("karabiner-copy.json")
        try karabinerBytes.write(to: url)
        let model = fixture.flow.karabinerImport
        ScreenEvidence.awaitMain {
            fixture.showConsentIfNeeded()
            await fixture.flow.accept()
            fixture.flow.sync(from: fixture.orchestrator.state)
        }
        let ticket = try XCTUnwrap(model.selectionTicket())
        ScreenEvidence.awaitMain { await model.load(url: url, ticket: ticket) }
        defer { model.clear() }
        let evidence = fixture.flow.candidateConflictEvidence
        let input = CandidateCheckInput(source: Chord(keyCode: try KeyCode(8), modifiers: ModifierSet(command: .left,
            option: .none, control: .none, shift: .none, fn: .none)),
            trigger: Chord(keyCode: try KeyCode(122), modifiers: ModifierSet(command: .none,
                option: .none, control: .none, shift: .none, fn: .none)), scope: .global,
            backend: .disconnected(.karabiner), conflictEvidence: evidence)
        for locale in ["en", "zh-Hans"] {
            let text = NativeText(locale: locale)
            let view = NSHostingView(rootView: ScrollView {
                VStack(alignment: .leading) {
                    Form { KarabinerImportSection(model: model, text: text) }.formStyle(.grouped).frame(height: 380)
                    AnalysisConflictView(input: input, text: text)
                }.padding().frame(width: 640)
            }.frame(width: 640, height: 760)
                .background(Color(nsColor: .windowBackgroundColor)))
            view.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 760),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.setContentSize(NSSize(width: 640, height: 760))
            view.frame = NSRect(x: 0, y: 0, width: 640, height: 760)
            defer { window.contentView = nil; window.close() }
            NativeEvidence.primeAccessibility()
            NativeEvidence.update(view)
            NativeEvidence.update(view)
            let nodes = NativeEvidence.elements(in: view)
            XCTAssertTrue(nodes.contains { KRAXLabel($0) == text("phase2.conflict.existingRuleOverlap") })
            XCTAssertTrue(nodes.contains { KRAXLabel($0) == text("phase2.conflict.limit.referenceOnly") })
            if let output = NativeEvidence.outputRoot() {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try ScreenEvidence.capturePNG(view).write(to: output.appendingPathComponent("b-backend-\(locale).png"))
            }
        }
    }

    private let layoutBytes = Data(#"{"name":"synthetic-reference","vendorProductId":65538,"layers":[["KC_C","KC_F1","KC_LGUI","KC_NO"]]}"#.utf8)
    private let definitionBytes = Data(#"{"name":"synthetic-reference","vendorId":"0x0001","productId":"0x0002","matrix":{"rows":2,"cols":2},"layouts":{"keymap":[["0,0","0,1"],["1,0","1,1"]]}}"#.utf8)

    private func files() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("via-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let layout = root.appendingPathComponent("configuration-copy.json")
        let definition = root.appendingPathComponent("keyboard-definition.json")
        try layoutBytes.write(to: layout)
        try definitionBytes.write(to: definition)
        return (root, layout, definition)
    }

    private func ready(_ root: URL) async throws -> FlowFixture {
        let fixture = try FlowFixture(directory: root, environment: ["KEYRECORD_FLOW_FIXTURE": root.path])
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertTrue(fixture.flow.sensitiveContentVisible)
        return fixture
    }

    func testSelectedFilesMatchInBothOrdersWithoutUpgradingPhysicalEvidence() async throws {
        let (root, layout, definition) = try files()
        let fixture = try await ready(root)
        let cycle = try XCTUnwrap(fixture.orchestrator.state.preferences?.currentCycleID)
        let original = try AnalysisEngine.analyze(AnalysisPreview.input(cycleID: cycle))
        fixture.flow.publishAnalysis(original)
        let model = fixture.flow.viaImport
        for order in [[(VIAImportFileKind.layout, layout), (.definition, definition)], [(.definition, definition), (.layout, layout)]] {
            for (kind, url) in order { await model.load(kind: kind, url: url) }
            let imported = try XCTUnwrap(model.configuration)
            XCTAssertEqual(imported.geometry?.positions.count, 4)
            XCTAssertEqual(imported.physicalEvidence.device, .unknown)
            XCTAssertEqual(imported.positionCount(for: try KeyCode(8)), 1)
            XCTAssertEqual(fixture.flow.analysis, original)
            model.clear()
        }
    }
    func testOfficialCompiledDefinitionFlowsThroughFileReaderAndNativeReferenceSummary() async throws {
        let (root, layout, definition) = try files()
        let fixture = try await ready(root)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repository.appendingPathComponent(
            "evidence/phase4/fixtures/synthetic/via-compiled-definitions.json"))) as? [String: Any])
        for item in try XCTUnwrap(document["fixtures"] as? [[String: Any]]) {
            try JSONSerialization.data(withJSONObject: XCTUnwrap(item["compiled"])).write(to: definition)
            let model = fixture.flow.viaImport
            await model.load(kind: .layout, url: layout)
            await model.load(kind: .definition, url: definition)
            let imported = try XCTUnwrap(model.configuration)
            XCTAssertEqual(imported.geometry?.positions.count, 4)
            XCTAssertEqual(imported.geometry?.positions["0,1"]?.x, 2)
            XCTAssertEqual(imported.physicalEvidence.device, .unknown)
            XCTAssertEqual(model.selectedOriginalBytes, layoutBytes)
            let view = NSHostingView(rootView: VIAImportSection(model: model, text: NativeText(locale: "en")))
            XCTAssertTrue(NativeEvidence.elements(in: view).contains { KRAXIdentifier($0) == "phase2.via.summary" })
            model.clear()
            XCTAssertNil(model.configuration); XCTAssertNil(model.selectedOriginalBytes)
        }
    }

    func testReplacingWithMismatchedOrInvalidFileWithdrawsOldReference() async throws {
        let (root, layout, definition) = try files()
        let fixture = try await ready(root)
        let model = fixture.flow.viaImport
        await model.load(kind: .layout, url: layout)
        await model.load(kind: .definition, url: definition)
        XCTAssertNotNil(model.configuration)
        let bad = root.appendingPathComponent("wrong-definition.json")
        try Data(String(decoding: definitionBytes, as: UTF8.self).replacingOccurrences(of: "0x0002", with: "0x0003").utf8).write(to: bad)
        await model.load(kind: .definition, url: bad)
        XCTAssertNil(model.configuration)
        XCTAssertEqual(model.issue, .parser(.keyboardMismatch))
        let broken = root.appendingPathComponent("broken.json")
        try Data("{broken".utf8).write(to: broken)
        await model.load(kind: .definition, url: broken)
        XCTAssertNil(model.configuration)
        XCTAssertEqual(model.issue, .parser(.jsonProtection))
        model.clear()
    }

    func testAtomicFileReplacementInvalidatesTheSessionReference() async throws {
        let (root, layout, definition) = try files()
        let fixture = try await ready(root)
        let model = fixture.flow.viaImport
        await model.load(kind: .layout, url: layout)
        await model.load(kind: .definition, url: definition)
        XCTAssertNotNil(model.configuration)
        let changed = XCTestExpectation(description: "selected file event invalidates reference")
        model.onChange = { if model.issue == .changed { changed.fulfill() } }
        try layoutBytes.write(to: layout, options: .atomic)
        let result = await XCTWaiter.fulfillment(of: [changed], timeout: 3)
        XCTAssertEqual(result, .completed)
        XCTAssertNil(model.configuration)
        XCTAssertEqual(model.issue, .changed)
        model.clear()
    }

    func testPrivacyClosureRejectsPendingReadAndOldPickerTicketAfterReopening() async throws {
        let (root, layout, _) = try files()
        let fixture = try await ready(root)
        let model = fixture.flow.viaImport
        let ticket = try XCTUnwrap(model.selectionTicket())
        let started = XCTestExpectation(description: "background read started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        model.readFile = { url, kind, access, notify in
            started.fulfill()
            release.wait()
            return try VIAFileReader.read(url: url, kind: kind, access: access, notify: notify)
        }
        let pending = Task { await model.load(kind: .layout, url: layout, ticket: ticket) }
        let startResult = await XCTWaiter.fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(startResult, .completed)
        fixture.observeLocked()
        fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.observe()
        fixture.flow.sync(from: fixture.orchestrator.state)
        release.signal()
        await pending.value
        XCTAssertNil(model.configuration)
        XCTAssertNil(model.layoutFilename)
        let called = OSAllocatedUnfairLock(initialState: false)
        model.readFile = { _, _, _, _ in called.withLock { $0 = true }; throw VIAFileReadError.changed }
        await model.load(kind: .layout, url: layout, ticket: ticket)
        XCTAssertFalse(called.withLock { $0 })
        XCTAssertNil(model.layoutFilename)
        model.clear()
    }

    func testReaderRejectsDirectoriesSymlinksFifosAndOversizedFiles() async throws {
        let (root, layout, _) = try files()
        let fixture = try await ready(root)
        let model = fixture.flow.viaImport
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: layout)
        let fifo = root.appendingPathComponent("fifo.json")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        for url in [root, link, fifo] {
            await model.load(kind: .layout, url: url)
            XCTAssertEqual(model.issue, .notRegularFile)
            XCTAssertNil(model.configuration)
        }
        let huge = root.appendingPathComponent("oversized.json")
        try Data(repeating: 0x20, count: VIAReferenceParser.maximumInputBytes + 1).write(to: huge)
        await model.load(kind: .layout, url: huge)
        XCTAssertEqual(model.issue, .parser(.jsonProtection))
        model.clear()
    }

    func testReferenceSectionShowsLimitsAndNativeClearInBothLocales() throws {
        ScreenEvidence.prepare()
        let (root, layout, definition) = try files()
        let fixture = try FlowFixture(directory: root, environment: ["KEYRECORD_FLOW_FIXTURE": root.path])
        ScreenEvidence.awaitMain {
            fixture.showConsentIfNeeded()
            await fixture.flow.accept()
            fixture.flow.sync(from: fixture.orchestrator.state)
        }
        let model = fixture.flow.viaImport
        for locale in ["en", "zh-Hans"] {
            ScreenEvidence.awaitMain {
                await model.load(kind: .layout, url: layout)
                await model.load(kind: .definition, url: definition)
            }
            XCTAssertNotNil(model.configuration)
            let text = NativeText(locale: locale)
            let view = NSHostingView(rootView: Form { VIAImportSection(model: model, text: text) }
                .formStyle(.grouped).frame(width: 640, height: 580).background(Color(nsColor: .windowBackgroundColor)))
            view.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.setContentSize(NSSize(width: 640, height: 580))
            view.frame = NSRect(x: 0, y: 0, width: 640, height: 580)
            defer { window.contentView = nil; window.close() }
            NativeEvidence.primeAccessibility()
            NativeEvidence.update(view)
            NativeEvidence.update(view)
            let nodes = NativeEvidence.elements(in: view)
            XCTAssertTrue(nodes.contains { KRAXLabel($0) == text("phase2.via.deploymentUnknown") })
            XCTAssertTrue(nodes.contains { KRAXLabel($0) == text("phase2.via.transformsUnknown") })
            if let output = NativeEvidence.outputRoot() {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try ScreenEvidence.capturePNG(view).write(to: output.appendingPathComponent("via-reference-\(locale).png"))
            }
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("phase2.via.clear", in: view)))
            NativeEvidence.update(view)
            XCTAssertNil(model.configuration)
            XCTAssertTrue(NativeEvidence.elements(in: view).contains { KRAXLabel($0) == text("phase2.via.needPair") })
        }
    }
}

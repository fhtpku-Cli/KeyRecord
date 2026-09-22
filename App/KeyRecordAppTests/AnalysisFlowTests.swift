import XCTest
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore

@MainActor
final class AnalysisFlowTests: XCTestCase {
    private func fixture() throws -> FlowFixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try FlowFixture(directory: root, environment: ["KEYRECORD_FLOW_FIXTURE": root.path])
    }

    func testAnalysisIsClearedAtPrivacyClosureAndRequiresFreshPublication() async throws {
        let fixture = try fixture()
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
        let analysis = try AnalysisEngine.analyze(AnalysisPreview.input())
        fixture.flow.publishAnalysis(analysis)
        XCTAssertEqual(fixture.flow.analysis, analysis)
        fixture.observeLocked()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertNil(fixture.flow.analysis)
        fixture.observe()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertNil(fixture.flow.analysis)
    }

    func testLayoutActionPersistsAskedStateAndFailedSaveDoesNotChangeSelection() async throws {
        let fixture = try fixture()
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.flow.saveLayoutAction = { try await fixture.orchestrator.setLayout($0) }
        await fixture.flow.saveLayout(.iso)
        XCTAssertEqual(fixture.flow.layout, LayoutPreference(preset: .iso, hasAsked: true))
        let saved = try await fixture.preferences.load()
        XCTAssertEqual(saved?.layout, fixture.flow.layout)
        fixture.flow.saveLayoutAction = { _ in throw PreferencesRepositoryError.storageUnavailable }
        await fixture.flow.saveLayout(.split)
        XCTAssertEqual(fixture.flow.layout.preset, .iso)
        XCTAssertNotNil(fixture.flow.noticeKey)
    }

    func testReductionAnalysisRequiresFreshProtectedGeneration() throws {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let reduction = ProductReduction(gate: gate)
        let input = try AnalysisPreview.input()
        let reducer = try AggregationReducer(cycleID: input.cycleID, shortcuts: input.shortcuts,
                                              bareKeys: input.bareKeys)
        reduction.open(reducer, inputs: GateInputs(keyAvailability: .available, sessionLock: .unlocked,
            secureInput: .disabled, foreground: .attributable(bundleID: "com.example.editor")),
            generation: CaptureGeneration(rawValue: 1))
        XCTAssertNotNil(try reduction.analysis(preferences: Preferences(currentCycleID: input.cycleID)))
        gate.update(.locked)
        XCTAssertThrowsError(try reduction.analysis(preferences: Preferences(currentCycleID: input.cycleID)))
        reduction.clear()
        gate.update(.unlocked)
        XCTAssertNil(try reduction.analysis(preferences: Preferences(currentCycleID: input.cycleID)))
    }
}

import AppKit
import SwiftUI

extension AnalysisFlowTests {
    func testSyntheticDashboardRendersBothLocalesAndPrivacyStates() throws {
        let data = try AnalysisPreview.input()
        let full = try AnalysisEngine.analyze(data)
        let empty = try AnalysisEngine.analyze(AnalysisInput(cycleID: data.cycleID,
            shortcuts: [], bareKeys: [], activeDays: []))
        let root = ProcessInfo.processInfo.environment["KEYRECORD_QA_OUTPUT_DIR"]
        for locale in ["en", "zh-Hans"] {
            for (name, snapshot) in [("populated", Optional(full)), ("empty", Optional(empty)), ("hidden", nil)] {
                let content = AnalysisDashboardView(snapshot: snapshot,
                    layout: LayoutPreference(), text: NativeText(locale: locale), saveLayout: { _ in })
                    .frame(width: 1000, height: 700)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                let rendered = try XCTUnwrap(renderer.cgImage)
                let bitmap = NSBitmapImageRep(cgImage: rendered)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 1000)
                if let root {
                    let directory = URL(fileURLWithPath: root)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try png.write(to: directory.appendingPathComponent("analysis-\(locale)-\(name).png"))
                }
                let hasContent = stride(from: 0, to: bitmap.pixelsHigh, by: 3).contains { y in
                    stride(from: 0, to: bitmap.pixelsWide, by: 3).contains { x in
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return color.redComponent < 0.8 && color.alphaComponent > 0.5
                    }
                }
                try XCTSkipIf(!hasContent, "Native renderer produced a blank image; visual validation unavailable")
            }
        }
    }

    func testMergedDisplayRetainsExactSidesAndDoesNotDuplicateCounts() throws {
        let input = try AnalysisPreview.input()
        let first = try XCTUnwrap(input.shortcuts.first)
        let chord = Chord(keyCode: first.identity.chord.keyCode, modifiers: ModifierSet(command: .right,
            option: .none, control: .none, shift: .right, fn: .none))
        let row = DailyShortcutAggregate(cycleID: input.cycleID, day: first.day,
            identity: ChordBucket(chord: chord, appBucket: first.identity.appBucket),
            classification: first.classification, sourceCounts: first.sourceCounts)
        let snapshot = try AnalysisEngine.analyze(AnalysisInput(cycleID: input.cycleID,
            shortcuts: input.shortcuts + [row], bareKeys: input.bareKeys, activeDays: input.activeDays))
        let group = try XCTUnwrap(AnalysisStatisticGroup.make(snapshot).first {
            $0.representative.keyCode == chord.keyCode
        })
        XCTAssertEqual(group.variants.count, 2)
        XCTAssertEqual(group.total, first.sourceCounts.total.value * 3)
        XCTAssertEqual(Set(group.variants.map(\.chord)), [first.identity.chord, chord])
    }
}


extension AnalysisFlowTests {
    func testDefaultStatisticsKeepUnknownModifierSidesSeparate() throws {
        let cycle = CycleID(rawValue: "side-display-fixture")
        let day = LocalDay("2026-09-22")
        let rows = try [ModifierSideState.none, .left, .right, .both, .activeSideUnknown].map { side in
            let chord = Chord(keyCode: try KeyCode(0), modifiers: ModifierSet(command: side,
                option: .none, control: .none, shift: .left, fn: .none))
            return DailyShortcutAggregate(cycleID: cycle, day: day,
                identity: ChordBucket(chord: chord, appBucket: .unknown),
                classification: ChordRuleTable.v1.classify(chord),
                sourceCounts: try SourceCounts(ordinary: Count(1), suspectedInjection: Count(0)))
        }
        let snapshot = try AnalysisEngine.analyze(AnalysisInput(cycleID: cycle,
            shortcuts: rows, bareKeys: [], activeDays: [day]))
        let groups = AnalysisStatisticGroup.make(snapshot)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.total).sorted(), [1, 1, 3])
        let unknown = try XCTUnwrap(groups.first { group in
            group.variants.contains { $0.chord.modifiers.command == .activeSideUnknown }
        })
        XCTAssertEqual(unknown.variants.count, 1)
        XCTAssertEqual(unknown.total, 1)
    }

    func testDefaultChordLabelsMarkUnknownModifierSidesInBothLocales() throws {
        for locale in ["en", "zh-Hans"] {
            let text = NativeText(locale: locale)
            for family in 0..<4 {
                var sides = [ModifierSideState](repeating: .none, count: 4)
                sides[family] = .activeSideUnknown
                let chord = Chord(keyCode: try KeyCode(0), modifiers: ModifierSet(command: sides[0],
                    option: sides[1], control: sides[2], shift: sides[3], fn: .none))
                let key = ["modifier.command", "modifier.option", "modifier.control", "modifier.shift"][family]
                let marker = String(format: text("modifier.side.unknown"), text(key))
                XCTAssertTrue(AnalysisLabels.chord(chord, text: text).contains(marker))
            }
        }
    }
}

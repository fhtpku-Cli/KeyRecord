import XCTest
import AppKit
import SwiftUI
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
        let cycle = try XCTUnwrap(fixture.orchestrator.state.preferences?.currentCycleID)
        let analysis = try AnalysisEngine.analyze(AnalysisPreview.input(cycleID: cycle))
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

    func testClosedKeyGateKeepsFirstRunConsentVisible() throws {
        let fixture = try fixture()
        fixture.flow.sync(from: LifecycleState(phase: .consent))
        fixture.flow.showCaptureBlocked()
        XCTAssertTrue(fixture.flow.awaitingConsent)
        XCTAssertTrue(fixture.flow.showsConsent)
        XCTAssertEqual(fixture.flow.state, .blocked)
        fixture.flow.sync(from: LifecycleState(phase: .failed,
            failure: .preferencesLoadFailed(.protectedDataUnavailable)))
        fixture.flow.showCaptureBlocked()
        XCTAssertTrue(fixture.flow.showsConsent)
        fixture.flow.sync(from: LifecycleState(phase: .paused,
            preferences: Preferences(currentCycleID: CycleID(rawValue: "kept"))))
        fixture.flow.showCaptureBlocked()
        XCTAssertFalse(fixture.flow.showsConsent)
    }

    func testOpeningStatisticsDoesNotStartOrResumeCapture() async throws {
        let fixture = try fixture()
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        await fixture.flow.pause()
        var started = false
        var resumed = false
        fixture.flow.actions.start = { started = true }
        fixture.flow.actions.resume = { resumed = true }
        let starts = await fixture.capture.startCount
        let phase = fixture.orchestrator.phase
        fixture.flow.presentStatistics()
        XCTAssertFalse(started)
        XCTAssertFalse(resumed)
        let startsAfter = await fixture.capture.startCount
        XCTAssertEqual(fixture.orchestrator.phase, phase)
        XCTAssertEqual(fixture.flow.statisticsSection, .overview)
        XCTAssertEqual(startsAfter, starts)
    }

    func testStaleAnalysisCannotCrossCycleOrPrivacyClosure() async throws {
        let fixture = try fixture()
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
        let current = try XCTUnwrap(fixture.orchestrator.state.preferences?.currentCycleID)
        let fresh = try AnalysisEngine.analyze(AnalysisPreview.input(cycleID: current))
        fixture.flow.publishAnalysis(fresh)
        XCTAssertEqual(fixture.flow.analysis?.cycleID, current)
        let stale = try AnalysisEngine.analyze(AnalysisPreview.input(cycleID: CycleID(rawValue: "previous-cycle")))
        fixture.flow.publishAnalysis(stale)
        XCTAssertNil(fixture.flow.analysis)
        fixture.flow.publishAnalysis(fresh)
        fixture.observeLocked()
        fixture.flow.sync(from: fixture.orchestrator.state)
        XCTAssertNil(fixture.flow.analysis)
        XCTAssertFalse(fixture.flow.hasUnseenRecommendations)
        XCTAssertEqual(fixture.flow.statisticsMenuTitle(NativeText(locale: "en")),
                       NativeText(locale: "en")("action.statistics"))
    }

    func testIgnoreFailureRollsBackAndRestoreSurvivesMissingObservation() async throws {
        let fixture = try fixture()
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.flow.saveIgnoredAction = { try await fixture.orchestrator.setIgnoredRecommendationKeys($0) }
        let id = "008:left:none:none:left:none"
        await fixture.flow.ignoreRecommendation(id)
        XCTAssertEqual(fixture.flow.ignoredRecommendationKeys, [id])
        XCTAssertTrue(fixture.flow.canUndoIgnoreChange)
        let saved = try await fixture.preferences.load()
        XCTAssertEqual(saved?.ignoredRecommendationKeys, [id])
        XCTAssertEqual(saved?.excludedBundleIDs, [])
        fixture.flow.saveIgnoredAction = { _ in throw PreferencesRepositoryError.storageUnavailable }
        await fixture.flow.ignoreRecommendation("other")
        XCTAssertEqual(fixture.flow.ignoredRecommendationKeys, [id])
        XCTAssertEqual(fixture.flow.noticeKey, "phase2.preferenceSaveFailed")
        fixture.flow.saveIgnoredAction = { try await fixture.orchestrator.setIgnoredRecommendationKeys($0) }
        await fixture.flow.undoIgnoredRecommendationChange()
        XCTAssertTrue(fixture.flow.ignoredRecommendationKeys.isEmpty)
        let absent = IgnoredRecommendationList.entries(persisted: [id], candidates: [])
        XCTAssertFalse(absent[0].hasCurrentObservation)
        XCTAssertNotNil(absent[0].chord)
    }

    func testRecommendationBadgeAppearsOncePerNewTopItem() {
        var attention = RecommendationAttention()
        attention.observe(topIDs: ["a", "b"], contentVisible: true, currentlyViewing: false)
        XCTAssertFalse(attention.hasUnseen)
        attention.observe(topIDs: ["a", "b"], contentVisible: true, currentlyViewing: false)
        XCTAssertFalse(attention.hasUnseen)
        attention.observe(topIDs: ["a", "b", "c"], contentVisible: true, currentlyViewing: false)
        XCTAssertTrue(attention.hasUnseen)
        attention.markRecommendationAreaOpened(topIDs: ["a", "b", "c"])
        XCTAssertFalse(attention.hasUnseen)
        attention.observe(topIDs: ["a", "b", "c"], contentVisible: false, currentlyViewing: false)
        XCTAssertFalse(attention.hasUnseen)
        attention.observe(topIDs: ["a", "b", "c", "d"], contentVisible: true, currentlyViewing: true)
        XCTAssertFalse(attention.hasUnseen)
    }

    func testOverlappingIgnoresKeepBothSelectionsAndUndoOnlyTheLast() async throws {
        try await checkOverlappingIgnores(firstSaveFails: false)
    }

    func testQueuedIgnoreUsesSavedStateAfterEarlierFailure() async throws {
        try await checkOverlappingIgnores(firstSaveFails: true)
    }

    private func checkOverlappingIgnores(firstSaveFails: Bool) async throws {
        let fixture = try fixture()
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
        let saving = expectation(description: "First ignore saving")
        var release: CheckedContinuation<Void, Never>?
        var attempts = 0
        fixture.flow.saveIgnoredAction = { keys in
            attempts += 1
            if attempts == 1 {
                await withCheckedContinuation { release = $0; saving.fulfill() }
                if firstSaveFails { throw PreferencesRepositoryError.storageUnavailable }
            }
            try await fixture.orchestrator.setIgnoredRecommendationKeys(keys)
        }
        let first = Task { await fixture.flow.ignoreRecommendation("a") }
        await fulfillment(of: [saving], timeout: 2)
        let entered = expectation(description: "Second ignore entered")
        let second = Task { entered.fulfill(); await fixture.flow.ignoreRecommendation("b") }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertEqual(attempts, 1)
        release?.resume()
        await first.value
        await second.value
        let expected: Set<String> = firstSaveFails ? ["b"] : ["a", "b"]
        XCTAssertEqual(fixture.flow.ignoredRecommendationKeys, expected)
        let saved = try await fixture.preferences.load()
        XCTAssertEqual(saved?.ignoredRecommendationKeys, expected)
        XCTAssertNil(fixture.flow.noticeKey)
        await fixture.flow.undoIgnoredRecommendationChange()
        let beforeLast: Set<String> = firstSaveFails ? [] : ["a"]
        XCTAssertEqual(fixture.flow.ignoredRecommendationKeys, beforeLast)
        let undone = try await fixture.preferences.load()
        XCTAssertEqual(undone?.ignoredRecommendationKeys, beforeLast)
    }

    func testUndoWaitsForOverlappingRestore() async throws {
        let fixture = try fixture()
        fixture.showConsentIfNeeded()
        await fixture.flow.accept()
        fixture.flow.sync(from: fixture.orchestrator.state)
        fixture.flow.saveIgnoredAction = { try await fixture.orchestrator.setIgnoredRecommendationKeys($0) }
        await fixture.flow.ignoreRecommendation("a")
        await fixture.flow.ignoreRecommendation("b")
        let saving = expectation(description: "Restore saving")
        var release: CheckedContinuation<Void, Never>?
        var attempts = 0
        fixture.flow.saveIgnoredAction = { keys in
            attempts += 1
            if attempts == 1 {
                await withCheckedContinuation { release = $0; saving.fulfill() }
            }
            try await fixture.orchestrator.setIgnoredRecommendationKeys(keys)
        }
        let restore = Task { await fixture.flow.restoreRecommendation("a") }
        await fulfillment(of: [saving], timeout: 2)
        let entered = expectation(description: "Undo entered")
        let undo = Task { entered.fulfill(); await fixture.flow.undoIgnoredRecommendationChange() }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertEqual(attempts, 1)
        release?.resume()
        await restore.value
        await undo.value
        XCTAssertEqual(fixture.flow.ignoredRecommendationKeys, ["a", "b"])
        let saved = try await fixture.preferences.load()
        XCTAssertEqual(saved?.ignoredRecommendationKeys, ["a", "b"])
        XCTAssertFalse(fixture.flow.canUndoIgnoreChange)
    }

    func testCandidatesPageDisplaysPreferenceSaveFailure() throws {
        ScreenEvidence.prepare()
        let snapshot = try AnalysisEngine.analyze(AnalysisPreview.input())
        let text = NativeText(locale: "zh-Hans")
        let view = NSHostingView(rootView: AnalysisDashboardView(snapshot: snapshot,
            layout: LayoutPreference(), text: text,
            preferenceNoticeKey: "phase2.preferenceSaveFailed", saveLayout: { _ in },
            surface: .candidates).frame(width: 1000, height: 700))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.setContentSize(NSSize(width: 1000, height: 700))
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(view)
        NativeEvidence.update(view)
        let nodes = NativeEvidence.elements(in: view)
        let notices = nodes.filter { KRAXLabel($0) == text("phase2.preferenceSaveFailed") }
        XCTAssertEqual(notices.count, 1)
        let notice = try XCTUnwrap(notices.first)
        XCTAssertGreaterThan(KRAXFrame(notice).width, 0)
        XCTAssertGreaterThan(KRAXFrame(notice).height, 0)
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
        let shortcutsOnly = try AnalysisEngine.analyze(AnalysisInput(cycleID: data.cycleID,
            shortcuts: data.shortcuts, bareKeys: [], activeDays: data.activeDays))
        let root = ProcessInfo.processInfo.environment["KEYRECORD_QA_OUTPUT_DIR"]
        for locale in ["en", "zh-Hans"] {
            for (name, snapshot) in [("populated", Optional(full)), ("shortcuts-only", Optional(shortcutsOnly)),
                                     ("empty", Optional(empty)), ("hidden", nil)] {
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

@MainActor
final class ProductSnapshotPublicationTests: XCTestCase {
    private func fixture() async throws -> (LifecycleHarness, AppFlowObservable, ProductReduction, Preferences) {
        let harness = LifecycleHarness()
        await harness.collectOpen()
        let input = try AnalysisPreview.input(cycleID: harness.cycleID)
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: harness.orchestrator), protectedGate: gate)
        flow.sync(from: harness.orchestrator.state)
        let reduction = ProductReduction(gate: gate)
        reduction.open(try AggregationReducer(cycleID: input.cycleID, shortcuts: input.shortcuts,
                                             bareKeys: input.bareKeys),
                       inputs: GateInputs(keyAvailability: .available, sessionLock: .unlocked,
                                          secureInput: .disabled,
                                          foreground: .attributable(bundleID: "com.example.editor")),
                       generation: CaptureGeneration(rawValue: 1))
        return (harness, flow, reduction, Preferences(currentCycleID: input.cycleID))
    }

    func testVisiblePublicationCountsAtFlowBoundaryIncludingAnalysis() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        let diagnostics = CaptureDiagnosticsRecorder()
        flow.configureDiagnostics(diagnostics)

        try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
            captureSessionLive: true, readSnapshot: { try reduction.snapshot() },
            readAnalysis: { try reduction.analysis(preferences: preferences) })
        XCTAssertEqual(diagnostics.runSummary.snapshotPublicationCount, 1)
        XCTAssertEqual(diagnostics.runSummary.analysisPublicationCount, 1)

        harness.orchestrator.observe(.unknown)
        flow.sync(from: harness.orchestrator.state)
        flow.snapshot = try reduction.snapshot()
        flow.publishAnalysis(try reduction.analysis(preferences: preferences))
        XCTAssertNil(flow.snapshot)
        XCTAssertNil(flow.analysis)
        XCTAssertEqual(diagnostics.runSummary.snapshotPublicationCount, 1)
        XCTAssertEqual(diagnostics.runSummary.analysisPublicationCount, 1)
    }

    func testAnalysisFailureDoesNotEscapeIntoPulseShutdown() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        flow.publishAnalysis(try reduction.analysis(preferences: preferences))
        XCTAssertNotNil(flow.analysis)
        var shutdownRequested = false
        do {
            try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
                captureSessionLive: true, readSnapshot: { try reduction.snapshot() },
                readAnalysis: { throw AnalysisError.classificationMismatch })
        } catch { shutdownRequested = true }
        XCTAssertFalse(shutdownRequested)
        XCTAssertNil(flow.analysis)
        XCTAssertNotNil(flow.snapshot)
        XCTAssertEqual(flow.noticeKey, "phase2.analysisUnavailable")
        XCTAssertNoThrow(try reduction.gate.begin())
    }

    func testDeadSessionCannotRepublishAfterSyncHidesContent() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        flow.publishAnalysis(try reduction.analysis(preferences: preferences))
        flow.snapshot = nil
        flow.update(phase: .blocked)
        var reads = 0
        for _ in 0..<2 {
            try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
                captureSessionLive: false, readSnapshot: { reads += 1; return try reduction.snapshot() },
                readAnalysis: { reads += 1; return try reduction.analysis(preferences: preferences) })
            XCTAssertNil(flow.snapshot)
            XCTAssertNil(flow.analysis)
            XCTAssertEqual(flow.state, .blocked)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertNoThrow(try reduction.gate.begin(), "dead source must not discard retained totals")
    }

    func testDeadThenLiveRefreshPreservesRegisteredLoginItem() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        await harness.orchestrator.setLoginItem(enabled: true)
        flow.sync(from: harness.orchestrator.state)
        XCTAssertTrue(flow.loginItemEnabled)
        for live in [false, false, true] {
            try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
                captureSessionLive: live, readSnapshot: { try reduction.snapshot() },
                readAnalysis: { try reduction.analysis(preferences: preferences) })
            XCTAssertEqual(flow.state, live ? .collecting : .blocked)
            XCTAssertTrue(flow.loginItemEnabled)
            XCTAssertEqual(harness.orchestrator.state.loginItem, .registered)
            if live {
                XCTAssertNotNil(flow.snapshot)
                XCTAssertNotNil(flow.analysis)
            } else {
                XCTAssertNil(flow.snapshot)
                XCTAssertNil(flow.analysis)
            }
        }
    }

    func testGateClosureBetweenReadsStillEscapesForProtectedShutdown() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        XCTAssertThrowsError(try ProductSnapshotPublication.refresh(flow: flow,
            state: harness.orchestrator.state, captureSessionLive: true,
            readSnapshot: { try reduction.snapshot() }, readAnalysis: {
                reduction.gate.update(.locked)
                return try reduction.analysis(preferences: preferences)
            })) { XCTAssertEqual($0 as? KeyringError, .locked) }
    }

    func testLiveRefreshAndRecoveryPublishRetainedCounts() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        let expected = try reduction.snapshot()
        flow.snapshot = nil
        flow.update(phase: .blocked)
        try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
            captureSessionLive: true, readSnapshot: { try reduction.snapshot() },
            readAnalysis: { try reduction.analysis(preferences: preferences) })
        XCTAssertEqual(flow.state, .collecting)
        XCTAssertEqual(flow.snapshot, expected)
        XCTAssertFalse(try XCTUnwrap(flow.analysis).topRecommendations.isEmpty)
    }

    func testRealAnalysisValidationFailurePreservesReadableAggregate() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        let row = try XCTUnwrap(AnalysisPreview.input().shortcuts.first)
        let invalid = DailyShortcutAggregate(cycleID: row.cycleID, day: row.day,
            identity: row.identity, classification: ShortcutClassification(kind: .stateful, scope: .normal),
            sourceCounts: row.sourceCounts)
        reduction.open(try AggregationReducer(cycleID: row.cycleID, shortcuts: [invalid], bareKeys: []),
            inputs: GateInputs(keyAvailability: .available, sessionLock: .unlocked,
                secureInput: .disabled, foreground: .attributable(bundleID: "com.example.editor")),
            generation: CaptureGeneration(rawValue: 2))
        XCTAssertThrowsError(try reduction.analysis(preferences: preferences)) {
            XCTAssertEqual($0 as? AnalysisError, .classificationMismatch)
        }
        try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
            captureSessionLive: true, readSnapshot: { try reduction.snapshot() },
            readAnalysis: { try reduction.analysis(preferences: preferences) })
        XCTAssertEqual(flow.snapshot?.shortcutTotal, row.sourceCounts.total.value)
        XCTAssertNil(flow.analysis)
        XCTAssertEqual(flow.noticeKey, "phase2.analysisUnavailable")
        XCTAssertNoThrow(try reduction.gate.begin())
    }

    func testPausedSessionCanStillDisplayRetainedStatistics() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        await harness.orchestrator.pause()
        flow.sync(from: harness.orchestrator.state)
        XCTAssertEqual(harness.orchestrator.phase, .paused)
        try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
            captureSessionLive: false, readSnapshot: { try reduction.snapshot() },
            readAnalysis: { try reduction.analysis(preferences: preferences) })
        XCTAssertNotNil(flow.snapshot)
        XCTAssertNotNil(flow.analysis)
    }

    func testPausedPrivacyClosureKeepsResumeAvailableAndRechecksReadiness() async throws {
        for safe in [true, false] {
            // Given: a paused window with retained content, then a privacy-only teardown.
            let (harness, flow, reduction, preferences) = try await fixture()
            await harness.orchestrator.pause()
            try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
                captureSessionLive: false, readSnapshot: { try reduction.snapshot() },
                readAnalysis: { try reduction.analysis(preferences: preferences) })
            XCTAssertNotNil(flow.snapshot)
            reduction.gate.update(.unknown)
            reduction.clear()
            harness.orchestrator.observe(.unknown)
            flow.sync(from: harness.orchestrator.state)
            flow.showCaptureBlocked()

            // Then: privacy clears content, but persisted paused intent keeps an explicit action.
            XCTAssertNil(flow.snapshot)
            XCTAssertNil(flow.analysis)
            XCTAssertFalse(flow.sensitiveContentVisible)
            XCTAssertEqual(harness.orchestrator.state.preferences?.expectedCollecting, false)
            XCTAssertTrue(flow.menuState.canResume, "privacy closure must not strand the paused window")
            guard flow.menuState.canResume else { continue }
            let checksBefore = await harness.readiness.checkCount
            let startsBefore = await harness.capture.startCount
            await harness.readiness.setResult(safe ? .success(LifecycleHarnessConditions.open)
                                                  : .failure(.secureInputActive))
            flow.actions.resume = {
                await harness.orchestrator.resume()
                flow.sync(from: harness.orchestrator.state)
            }

            // When: the owner explicitly uses the enabled Resume action.
            await flow.resume()

            // Then: fresh readiness permits safe recovery, never unsafe capture.
            let checksAfter = await harness.readiness.checkCount
            let startsAfter = await harness.capture.startCount
            XCTAssertEqual(checksAfter, checksBefore + 1)
            XCTAssertEqual(startsAfter, startsBefore + (safe ? 1 : 0))
            XCTAssertEqual(flow.state, safe ? .collecting : .blocked)
            if !safe { XCTAssertFalse(flow.sensitiveContentVisible) }
        }
    }

    func testPrivacyClosureSkipsAllPublicationReads() async throws {
        let (harness, flow, reduction, preferences) = try await fixture()
        flow.publishAnalysis(try reduction.analysis(preferences: preferences))
        harness.orchestrator.observe(RuntimeConditions(keyAvailability: .available,
            sessionLock: .locked, secureInput: .disabled,
            foreground: .attributable(bundleID: "com.example.editor")))
        var reads = 0
        try ProductSnapshotPublication.refresh(flow: flow, state: harness.orchestrator.state,
            captureSessionLive: true, readSnapshot: { reads += 1; return try reduction.snapshot() },
            readAnalysis: { reads += 1; return try reduction.analysis(preferences: preferences) })
        XCTAssertEqual(reads, 0)
        XCTAssertNil(flow.snapshot)
        XCTAssertNil(flow.analysis)
    }

    func testSnapshotReadErrorIsNotDowngradedToPreviewFailure() async throws {
        let (harness, flow, _, _) = try await fixture()
        var analysisRead = false
        XCTAssertThrowsError(try ProductSnapshotPublication.refresh(flow: flow,
            state: harness.orchestrator.state, captureSessionLive: true,
            readSnapshot: { throw KeyringError.staleGeneration },
            readAnalysis: { analysisRead = true; return nil })) {
                XCTAssertEqual($0 as? KeyringError, .staleGeneration)
            }
        XCTAssertFalse(analysisRead)
    }
}

#if DEBUG
import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

@MainActor
enum AnalysisPreview {
    static var configured: Bool {
        ProcessInfo.processInfo.environment["KEYRECORD_ANALYSIS_PREVIEW"] == "1"
    }
    private static var window: NSWindow?

    static func boot() {
        let panel = NSWindow(contentRect: NSRect(origin: .zero, size: NativeLayout.aggregateMinimum),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Synthetic analysis preview"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AnalysisPreviewRoot())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    static func input(layout: LayoutPreference = LayoutPreference()) throws -> AnalysisInput {
        let cycle = CycleID(rawValue: "synthetic-phase2")
        let days = [LocalDay("2026-09-01"), LocalDay("2026-09-02")]
        var shortcuts: [DailyShortcutAggregate] = []
        for (index, code) in [8, 9, 7, 0, 1, 2, 48, 20].enumerated() {
            let chord = Chord(keyCode: try KeyCode(code), modifiers: ModifierSet(command: .left,
                option: .none, control: .none, shift: index == 6 ? .none : .left, fn: .none))
            for day in days {
                let counts = try SourceCounts(ordinary: Count(index == 5 ? 4 : Int64(22 - index)),
                    suspectedInjection: Count(index == 4 ? 5 : 0))
                shortcuts.append(DailyShortcutAggregate(cycleID: cycle, day: day,
                    identity: ChordBucket(chord: chord, appBucket: .bundleID("com.example.editor")),
                    classification: ChordRuleTable.v1.classify(chord), sourceCounts: counts))
            }
        }
        let unknownChord = Chord(keyCode: try KeyCode(6), modifiers: ModifierSet(command: .activeSideUnknown,
            option: .none, control: .left, shift: .none, fn: .unknown))
        for day in days {
            shortcuts.append(DailyShortcutAggregate(cycleID: cycle, day: day,
                identity: ChordBucket(chord: unknownChord, appBucket: .unknown),
                classification: ChordRuleTable.v1.classify(unknownChord),
                sourceCounts: try SourceCounts(ordinary: Count(10), suspectedInjection: Count(0))))
        }
        let bare = try [0, 1, 2, 49, 36].enumerated().map { index, code in
            DailyBareKeyAggregate(cycleID: cycle, day: days[0], keyCode: try KeyCode(code),
                sourceCounts: try SourceCounts(ordinary: Count(Int64((index + 1) * 12)),
                    suspectedInjection: Count(0)))
        }
        return AnalysisInput(cycleID: cycle, shortcuts: shortcuts, bareKeys: bare,
                             activeDays: days, layout: layout)
    }
}

private struct AnalysisPreviewRoot: View {
    @State private var locale = "en"
    @State private var mode = "populated"
    @State private var layout = LayoutPreference()
    private var snapshot: AnalysisSnapshot? {
        if mode == "hidden" { return nil }
        do {
            let input = try AnalysisPreview.input(layout: layout)
            if mode == "empty" {
                return try AnalysisEngine.analyze(AnalysisInput(cycleID: input.cycleID,
                    shortcuts: [], bareKeys: [], activeDays: [], layout: layout))
            }
            return try AnalysisEngine.analyze(input)
        } catch { return nil }
    }
    private var languagePicker: some View {
        Picker("Language / 语言", selection: $locale) {
            Text("English").tag("en")
            Text("简体中文").tag("zh-Hans")
        }
        .fixedSize()
        .accessibilityIdentifier("preview.language")
    }

    private var fixturePicker: some View {
        Picker("Fixture / 场景", selection: $mode) {
            Text("Populated / 有数据").tag("populated")
            Text("Empty / 空").tag("empty")
            Text("Hidden / 隐藏").tag("hidden")
        }
        .fixedSize()
        .accessibilityIdentifier("preview.mode")
    }

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text("Synthetic data only / 仅合成数据").font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NativeLayout.group) {
                        languagePicker
                        fixturePicker
                    }
                    VStack(alignment: .leading, spacing: NativeLayout.compact) {
                        languagePicker
                        fixturePicker
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NativeLayout.group)
            AnalysisDashboardView(snapshot: snapshot, layout: layout, text: NativeText(locale: locale),
                saveLayout: { layout = LayoutPreference(preset: $0, hasAsked: true) })
        }
        .frame(minWidth: NativeLayout.minimum.width, minHeight: NativeLayout.minimum.height)
    }
}
#endif

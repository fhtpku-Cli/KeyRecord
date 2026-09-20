import AppKit
import KeyRecordCore
import SwiftUI
import XCTest

@MainActor
final class PrimitiveStateTests: XCTestCase {
    func testHappyStateSemantics() {
        XCTAssertEqual(Set(PrimitiveState.allCases.map(\.statusKey)).count, 5)
        XCTAssertEqual(PrimitiveState.allCases.map(\.symbol),
                       ["circle", "pause.circle", "record.circle", "lock.circle", "exclamationmark.triangle"])
        XCTAssertEqual(PrimitiveState.allCases.map(\.actionKey),
                       ["action.start", "action.resume", "action.pause", "action.settings", "action.retry"])
    }

    func testHappyMatrix() throws { try matrix(stress: false) }
    func testFailureStressMatrix() throws { try matrix(stress: true) }

    func testFailureEmptyLabel() throws {
        for locale in ["en", "zh-Hans"] {
            try exercise(PrimitiveFixture(state: .blocked, locale: locale, dark: false, stress: true, empty: true))
        }
    }

    func testFailureReducedMotionPolicy() {
        var transaction = Transaction(animation: .default)
        NativeMotion.apply(to: &transaction, reducedMotion: true)
        XCTAssertNil(transaction.animation)
        XCTAssertTrue(transaction.disablesAnimations)
    }

    func testHappyLocalizedWindowTitle() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let selection = HarnessSelection(locale: "en") { [weak window] title in window?.title = title }
        window.title = selection.windowTitle
        let view = NSHostingView(rootView: PrimitiveHarness(selection: selection))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(view)
        XCTAssertEqual(window.title, NativeText(locale: "en")("harness.title"))
        try NativeEvidence.snapshot(view, fixture: PrimitiveFixture(state: .unstarted, locale: "en", dark: false, stress: false), suffix: "-window-title")
        selection.locale = "zh-Hans"
        NativeEvidence.update(view)
        XCTAssertEqual(window.title, NativeText(locale: "zh-Hans")("harness.title"))
        XCTAssertNotEqual(window.title, NativeText(locale: "en")("harness.title"))
        try NativeEvidence.snapshot(view, fixture: PrimitiveFixture(state: .unstarted, locale: "zh-Hans", dark: false, stress: false), suffix: "-window-title")
        selection.locale = "en"
        NativeEvidence.update(view)
        XCTAssertEqual(window.title, NativeText(locale: "en")("harness.title"))
    }

    private func matrix(stress: Bool) throws {
        for locale in ["en", "zh-Hans"] {
            for dark in [false, true] {
                for state in PrimitiveState.allCases {
                    try exercise(PrimitiveFixture(state: state, locale: locale, dark: dark, stress: stress))
                }
            }
        }
    }

    private func exercise(_ fixture: PrimitiveFixture) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        var presses = 0
        var actions: [String] = []
        let view = NSHostingView(rootView: PrimitiveShowcase(fixture: fixture) { presses += 1 }
            .environment(\.primitiveActionObserver, { actions.append($0) }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        window.contentView = view
        window.appearance = NSAppearance(named: fixture.stress
            ? (fixture.dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (fixture.dark ? .darkAqua : .aqua))
        window.makeKeyAndOrderFront(nil)
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(view)
        let sizes = fixture.stress ? [view.bounds.size, NativeLayout.minimum, NativeLayout.aggregateMinimum] : [view.bounds.size]
        for (index, size) in sizes.enumerated() {
            window.setContentSize(size)
            NativeEvidence.update(view)
            let suffix = (fixture.empty ? "-empty" : "") + (index == 0 ? "" : "-\(Int(size.width))x\(Int(size.height))")
            try NativeEvidence.scrollTop(view)
            try NativeEvidence.snapshot(view, fixture: fixture, suffix: suffix)
            try NativeEvidence.assertLabels(view, fixture: fixture)
            try NativeEvidence.scrollBottom(view)
            try NativeEvidence.assertVisible("destructive.confirm", in: view)
            try NativeEvidence.assertVisible("destructive.cancel", in: view)
            try NativeEvidence.assertVisible("settings.exclusions", in: view)
            try NativeEvidence.snapshot(view, fixture: fixture, suffix: suffix + "-bottom")
            try NativeEvidence.assertKeyboard(view)
            let before = presses
            actions.removeAll()
            for id in PrimitiveFocus.order {
                let element = try NativeEvidence.node(id, in: view)
                XCTAssertTrue(KRAXEnabled(element), id)
                _ = KRAXPress(element)
            }
            XCTAssertEqual(presses, before + 6)
            try NativeEvidence.key("\r", code: 36, window: window)
            XCTAssertEqual(presses, before + 7)
            try NativeEvidence.key("\u{1b}", code: 53, window: window)
            XCTAssertEqual(presses, before + 8)
            XCTAssertEqual(actions, PrimitiveFocus.order + ["capture.primary", "destructive.cancel"])
        }
    }
}

// Product chord titles must preserve every stored modifier distinction.
@MainActor
final class ModifierDisplayTests: XCTestCase {
    private func bucket(_ modifiers: ModifierSet) throws -> ChordBucket {
        ChordBucket(chord: Chord(keyCode: try KeyCode(8), modifiers: modifiers),
                    appBucket: .bundleID("com.example.editor"))
    }

    func testEverySideStateIsDistinctForEveryFamilyInBothLanguages() throws {
        for locale in ["en", "zh-Hans"] {
            let names = locale == "en" ? ["Command", "Option", "Control", "Shift"]
                : ["命令", "Option", "Control", "Shift"]
            let suffixes = locale == "en" ? ["", " (left)", " (right)", " (both sides)", " (side unknown)"]
                : ["", "（左侧）", "（右侧）", "（双侧）", "（侧别未知）"]
            let ending = locale == "en" ? "Key 8 · App: com.example.editor" : "按键 8 · 应用：com.example.editor"
            for family in 0..<4 {
                var titles: [String] = []
                for (index, state) in ModifierSideState.allCases.enumerated() {
                    // Given: only one modifier family varies; all other fields stay equal.
                    let modifiers = ModifierSet(command: family == 0 ? state : .none,
                        option: family == 1 ? state : .none, control: family == 2 ? state : .none,
                        shift: family == 3 ? state : .none, fn: .none)
                    // When: format the actual product row title.
                    let title = ChordDescriptor.name(try bucket(modifiers), text: NativeText(locale: locale))
                    // Then: no side distinction is lost, and none stays omitted.
                    XCTAssertEqual(title, (state == .none ? "" : names[family] + suffixes[index] + "-") + ending)
                    titles.append(title)
                }
                XCTAssertEqual(Set(titles).count, ModifierSideState.allCases.count)
            }
        }
    }

    func testFnUnknownIsExplicitAndModifierOrderIsStable() throws {
        for locale in ["en", "zh-Hans"] {
            let text = NativeText(locale: locale)
            let ending = locale == "en" ? "Key 8 · App: com.example.editor" : "按键 8 · 应用：com.example.editor"
            for state in FnState.allCases {
                let modifiers = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: state)
                let prefix = state == .none ? "" : state == .active ? "Fn-"
                    : locale == "en" ? "Fn\u{00a0}(state\u{00a0}unknown)-" : "Fn（状态未知）-"
                XCTAssertEqual(ChordDescriptor.name(try bucket(modifiers), text: text), prefix + ending)
            }
            let mixed = ModifierSet(command: .left, option: .right, control: .both,
                                    shift: .activeSideUnknown, fn: .active)
            let prefix = locale == "en"
                ? "Command (left)-Option (right)-Control (both sides)-Shift (side unknown)-Fn-"
                : "命令（左侧）-Option（右侧）-Control（双侧）-Shift（侧别未知）-Fn-"
            XCTAssertEqual(ChordDescriptor.name(try bucket(mixed), text: text), prefix + ending)
        }
    }
}

extension ModifierDisplayTests {
    func testRealAggregateRowsRemainDistinctAndWrapInBothLanguages() throws {
        // Given: the formerly identical titles have distinct stored counts (3 + 6).
        let unknown = try bucket(ModifierSet(command: .activeSideUnknown, option: .none,
                                            control: .none, shift: .none, fn: .none))
        let left = try bucket(ModifierSet(command: .left, option: .none,
                                         control: .none, shift: .none, fn: .none))
        let longest = try bucket(ModifierSet())
        let snapshot = try AggregateSnapshot(rows: [
            KeyRecordCore.AggregateRow(identity: .shortcut(unknown), total: 3,
                classification: .discrete, sourceConfidence: .ordinary),
            KeyRecordCore.AggregateRow(identity: .shortcut(left), total: 6,
                classification: .discrete, sourceConfidence: .ordinary),
            KeyRecordCore.AggregateRow(identity: .shortcut(longest), total: 1,
                classification: .discrete, sourceConfidence: .ordinary),
        ])
        XCTAssertEqual(snapshot.rows.prefix(2).reduce(0) { $0 + $1.total }, 9)
        XCTAssertEqual(snapshot.shortcutTotal, 10)
        ScreenEvidence.prepare()
        var manifest: [[String: String]] = []
        for locale in ["en", "zh-Hans"] {
            for dark in [false, true] {
                for width in [1000.0, 420.0] {
                    // When: the real SwiftUI aggregate screen renders in a hostless window.
                    let size = CGSize(width: width, height: 700)
                    let text = NativeText(locale: locale)
                    let root = AggregateFlowView(snapshot: snapshot, text: text)
                        .padding(NativeLayout.page).frame(width: width, height: size.height)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.locale, Locale(identifier: locale))
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let view = NSHostingView(rootView: root)
                    view.sizingOptions = []
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = view
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.makeKeyAndOrderFront(nil)
                    defer { window.contentView = nil; window.close() }
                    view.frame = NSRect(origin: .zero, size: size)
                    NativeEvidence.primeAccessibility()
                    NativeEvidence.update(view)
                    NativeEvidence.update(view)
                    // Then: three complete distinct titles fit, with original counts intact.
                    let rows = NativeEvidence.elements(in: view).filter { KRAXIdentifier($0) == "aggregates.row" }
                    let expected = [unknown, left, longest].map { ChordDescriptor.name($0, text: text) }
                    XCTAssertEqual(rows.compactMap { KRAXLabel($0) }, expected)
                    XCTAssertEqual(Set(expected).count, 3)
                    let scroll = try NativeEvidence.scrollView(in: view)
                    for row in rows {
                        let frame = KRAXFrame(row)
                        XCTAssertGreaterThan(frame.height, 0)
                        XCTAssertTrue(KRAXFrame(scroll).insetBy(dx: -1, dy: -1).contains(frame), "Row overflows: \(frame)")
                    }
                    for (row, count) in zip(rows, [3, 6, 1]) {
                        XCTAssertTrue((KRAXValue(row) ?? "").contains(String(format: text("aggregate.observed"), count)))
                    }
                    XCTAssertEqual(KRAXLabel(try NativeEvidence.node("aggregates.shortcutTotal", in: view)),
                                   String(format: text("aggregate.totalShortcuts"), 10))
                    let stem = "modifier-\(locale)-\(dark ? "dark" : "light")-\(Int(width))x700"
                    let directory = try ScreenEvidence.outputDirectory()
                    try ScreenEvidence.capturePNG(view).write(to: directory.appendingPathComponent(stem + ".png"))
                    try Data(ScreenEvidence.axDump(view).utf8).write(to: directory.appendingPathComponent(stem + ".ax.txt"))
                    manifest.append(["image": stem + ".png", "accessibility": stem + ".ax.txt",
                                     "locale": locale, "appearance": dark ? "dark" : "light",
                                     "size": "\(Int(width))x700", "surface": "AggregateFlowView",
                                     "fixture": "same-key-app counts3unknown+6left; count1 all-modifiers-unknown"])
                }
            }
        }
        let directory = try ScreenEvidence.outputDirectory()
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("manifest.json"))
    }
}

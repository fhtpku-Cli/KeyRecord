import AppKit
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

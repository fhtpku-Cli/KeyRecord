import AppKit
import SwiftUI
import XCTest
import KeyRecordCore

@MainActor
final class T22AccessibilityTests: XCTestCase {
    func testSmallSettingsEveryControlIsScrollReachable() throws {
        for locale in MatrixContent.locales {
            var fixture = MatrixFixture(state: .collecting, locale: locale, appearance: .dark)
            fixture.size = NativeLayout.minimum
            fixture.stress = true
            fixture.largeType = true
            let rendered = ScreenEvidence.render(.settings, fixture: fixture)
            defer { ScreenEvidence.close(rendered) }
            let ids = MatrixContent.choices(stress: true).map { "settings.exclusions.\($0.bundleID)" }
                + ScreenKind.settings.interactiveIDs
            for id in ids { try NativeEvidence.reveal(id, in: rendered.view) }
        }
    }

    func testReturnTriggersOnlyDeclaredPrimaryDefaultAction() throws {
        ScreenEvidence.prepare()
        let journal = MatrixJournal()
        let view = NSHostingView(rootView: PrimaryAction(state: .unstarted, text: NativeText(locale: "en")) {
            journal.record("primary")
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(view)
        XCTAssertTrue(KRAXFocus(try NativeEvidence.node("capture.primary", in: view)))
        try NativeEvidence.key("\r", code: 36, window: window)
        XCTAssertEqual(journal.events, ["primary"])
    }
    func testRequestedViewportAndBackingDimensions() throws {
        for size in [NativeLayout.minimum, NativeLayout.aggregateMinimum] {
            var fixture = MatrixFixture(state: .collecting, locale: "en", appearance: .light)
            fixture.size = size
            for kind in ScreenKind.allCases {
                let rendered = ScreenEvidence.render(kind, fixture: fixture)
                defer { ScreenEvidence.close(rendered) }
                XCTAssertEqual(rendered.view.bounds.size, size, kind.rawValue)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: ScreenEvidence.capturePNG(rendered.view)))
                let backing = rendered.view.convertToBacking(NSRect(origin: .zero, size: size))
                XCTAssertEqual(bitmap.pixelsWide, Int(backing.width), kind.rawValue)
                XCTAssertEqual(bitmap.pixelsHigh, Int(backing.height), kind.rawValue)
            }
        }
    }

    func testOrderedAXFocusCoversEveryEnabledControlForwardAndBackward() throws {
        for kind in ScreenKind.allCases {
            let fixture = MatrixFixture(state: .collecting, locale: "en", appearance: .light)
            let rendered = ScreenEvidence.render(kind, fixture: fixture)
            defer { ScreenEvidence.close(rendered) }
            var expected = kind.interactiveIDs
            if kind == .settings {
                expected = MatrixContent.choices(stress: false).map { "settings.exclusions.\($0.bundleID)" } + expected
            }
            expected = try expected.filter { KRAXEnabled(try NativeEvidence.node($0, in: rendered.view)) }
            var ordered: [NSObject] = []
            var visited = Set<ObjectIdentifier>()
            func walk(_ node: NSObject) {
                guard visited.insert(ObjectIdentifier(node)).inserted else { return }
                ordered.append(node)
                for child in KRAXOrderedChildren(node) { walk(child) }
            }
            walk(rendered.view)
            let controls = ScreenEvidence.interactiveElements(rendered.view).filter { KRAXEnabled($0) }
            let identities = Set(controls.map(ObjectIdentifier.init))
            let focusOrder = ordered.filter { identities.contains(ObjectIdentifier($0)) }
            XCTAssertEqual(focusOrder.compactMap { KRAXIdentifier($0) }, expected, kind.rawValue)
            XCTAssertEqual(Set(focusOrder.map(ObjectIdentifier.init)), identities)
            for element in focusOrder {
                XCTAssertTrue(KRAXFocusable(element), "\(KRAXIdentifier(element) ?? "anonymous"): focused selector must be allowed")
            }
            // This is the ordered AX fallback, not a claim that a hostless Tab event
            // drove Full Keyboard Access. AX traversal terminates at either end.
            var iterator = focusOrder.makeIterator()
            for id in expected { XCTAssertEqual(iterator.next().flatMap { KRAXIdentifier($0) }, id) }
            XCTAssertNil(iterator.next())
            var backward = focusOrder.reversed().makeIterator()
            for id in expected.reversed() { XCTAssertEqual(backward.next().flatMap { KRAXIdentifier($0) }, id) }
            XCTAssertNil(backward.next())
        }
    }

    func testBothDestructiveDialogsRejectReturnAndEscapeCancels() throws {
        for kind in [ScreenKind.dialogReset, .dialogDelete] {
            let rendered = ScreenEvidence.render(kind, fixture: MatrixFixture(
                state: .collecting, locale: "en", appearance: .light))
            defer { ScreenEvidence.close(rendered) }
            let pending = rendered.flow.dialog
            XCTAssertTrue(KRAXFocus(try NativeEvidence.node("dialog.confirm", in: rendered.view)))
            try NativeEvidence.key("\r", code: 36, window: rendered.window)
            XCTAssertEqual(rendered.flow.dialog, pending)
            XCTAssertTrue(rendered.journal.events.isEmpty)
            XCTAssertTrue(KRAXFocus(try NativeEvidence.node("dialog.cancel", in: rendered.view)))
            try NativeEvidence.key("\u{1b}", code: 53, window: rendered.window)
            ScreenEvidence.waitUntil("escape cancels", in: rendered.view) { rendered.flow.dialog == .none }
            XCTAssertTrue(rendered.journal.events.isEmpty)
        }
    }
}

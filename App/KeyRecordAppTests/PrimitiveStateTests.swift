import AppKit
import SwiftUI
import XCTest

@MainActor
final class PrimitiveStateTests: XCTestCase {
    func testHappyStateSemantics() {
        // Given every presentation state, when mapped, then text and symbols differ.
        XCTAssertEqual(Set(PrimitiveState.allCases.map(\.statusKey)).count, 5)
        XCTAssertEqual(Set(PrimitiveState.allCases.map(\.symbol)).count, 5)
        XCTAssertEqual(PrimitiveState.allCases.map(\.actionKey),
                       ["action.start", "action.resume", "action.pause", "action.settings", "action.retry"])
    }

    func testHappyMatrix() throws {
        try matrix(stress: false)
    }

    func testFailureStressMatrix() throws {
        try matrix(stress: true)
    }

    func testFailureEmptyLabel() {
        for locale in ["en", "zh-Hans"] {
            let text = NativeText(locale: locale)
            XCTAssertFalse(text.aggregateName("").isEmpty)
            XCTAssertNotEqual(text.aggregateName(""), "aggregate.empty")
        }
    }

    func testFailureReducedMotionPolicy() {
        var transaction = Transaction(animation: .default)
        NativeMotion.apply(to: &transaction, reducedMotion: true)
        XCTAssertNil(transaction.animation)
        XCTAssertTrue(transaction.disablesAnimations)
    }

    private func matrix(stress: Bool) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        for locale in ["en", "zh-Hans"] {
            for dark in [false, true] {
                for state in PrimitiveState.allCases {
                    // Given deterministic fixtures, when hosted, then inspect real AX and bitmap.
                    var presses = 0
                    let text = NativeText(locale: locale)
                    let fixture = PrimitiveFixture(state: state, locale: locale, dark: dark, stress: stress)
                    let view = NSHostingView(rootView: PrimitiveShowcase(fixture: fixture) { presses += 1 })
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 900),
                                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    window.contentView = view
                    view.frame = NSRect(x: 0, y: 0, width: 640, height: 900)
                    window.appearance = NSAppearance(named: stress
                        ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                        : (dark ? .darkAqua : .aqua))
                    view.layoutSubtreeIfNeeded()
                    window.makeKeyAndOrderFront(nil)
                    view.displayIfNeeded()
                    let laidOut = expectation(description: "Native view update turn")
                    DispatchQueue.main.async { laidOut.fulfill() }
                    wait(for: [laidOut], timeout: 5)
                    try NativeEvidence.snapshot(view, fixture: fixture)
                    let elements = NativeEvidence.elements(in: view)
                    try NativeEvidence.assertFocusOrder(window: window, elements: elements)
                    for id in ["consent.accept", "consent.reject", "capture.primary", "settings.exclusions",
                               "destructive.cancel", "destructive.confirm"] {
                        let element = try XCTUnwrap(elements.first { $0.accessibilityIdentifier() == id }, id)
                        let button = try XCTUnwrap(element as? NSButton)
                        XCTAssertEqual(button.cell?.accessibilityRole(), .button, id)
                        XCTAssertEqual(button.font, NSFont.preferredFont(forTextStyle: stress ? .title2 : .body))
                        XCTAssertFalse(NativeEvidence.name(element).isEmpty, id)
                        XCTAssertTrue(element.isAccessibilityEnabled(), id)
                        _ = button.accessibilityPerformPress()
                    }
                    XCTAssertEqual(presses, 6)
                    let status = try XCTUnwrap(elements.first { $0.accessibilityIdentifier() == "capture.status" })
                    XCTAssertTrue(NativeEvidence.name(status).contains(text(state.statusKey)))
                    XCTAssertEqual(status.accessibilityValue() as? String, text(state.statusKey))
                    let row = try XCTUnwrap(elements.first { $0.accessibilityIdentifier() == "aggregates.row" })
                    XCTAssertFalse(NativeEvidence.name(row).isEmpty)
                    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
                    window.sendEvent(event)
                    XCTAssertEqual(presses, 7)
                    let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
                    window.sendEvent(escape)
                    XCTAssertEqual(presses, 8)
                    NativeEvidence.assertTextFits(view)
                    try NativeEvidence.snapshot(view, fixture: fixture)
                    if stress {
                        for size in [NativeLayout.minimum, NativeLayout.aggregateMinimum] {
                            window.setContentSize(size)
                            view.layoutSubtreeIfNeeded()
                            NativeEvidence.assertTextFits(view)
                            try NativeEvidence.snapshot(view, fixture: fixture,
                                suffix: "-\(Int(size.width))x\(Int(size.height))")
                        }
                    }
                    window.contentView = nil
                    window.close()
                }
            }
        }
    }
}

import AppKit
import SwiftUI
import XCTest

@MainActor
enum NativeEvidence {
    static func elements(in root: NSAccessibilityElementProtocol) -> [any NSAccessibilityProtocol] {
        var result: [any NSAccessibilityProtocol] = []
        var visited = Set<ObjectIdentifier>()
        func walk(_ node: Any) {
            guard let element = node as? any NSAccessibilityProtocol else { return }
            guard visited.insert(ObjectIdentifier(element)).inserted else { return }
            result.append(element)
            for child in element.accessibilityChildren() ?? [] { walk(child) }
            if let view = node as? NSView {
                for child in view.subviews { walk(child) }
            }
        }
        walk(root)
        return result
    }

    static func name(_ element: any NSAccessibilityProtocol) -> String {
        element.accessibilityLabel() ?? element.accessibilityTitle() ?? (element.accessibilityValue() as? String) ?? ""
    }

    static func assertTextFits(_ view: NSView) {
        for element in elements(in: view) {
            guard let field = element as? NSTextField, let cell = field.cell else { continue }
            let required = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: .greatestFiniteMagnitude))
            XCTAssertGreaterThanOrEqual(field.bounds.height + 1, required.height, field.stringValue)
            XCTAssertLessThanOrEqual(field.bounds.width, view.bounds.width)
        }
    }

    static func assertFocusOrder(window: NSWindow, elements: [any NSAccessibilityProtocol]) throws {
        let ids = ["consent.accept", "consent.reject", "capture.primary", "settings.exclusions", "destructive.cancel", "destructive.confirm"]
        let buttons = try ids.map { id in
            try XCTUnwrap(elements.first { $0.accessibilityIdentifier() == id } as? NSButton)
        }
        window.recalculateKeyViewLoop()
        XCTAssertTrue(window.makeFirstResponder(buttons[0]))
        for button in buttons.dropFirst() {
            window.selectNextKeyView(nil)
            XCTAssertTrue(window.firstResponder === button, button.title)
        }
        for button in buttons.dropLast().reversed() {
            window.selectPreviousKeyView(nil)
            XCTAssertTrue(window.firstResponder === button, button.title)
        }
    }

    static func snapshot(_ view: NSView, fixture: PrimitiveFixture, suffix: String = "") throws {
        let bundle = Bundle(for: ResourceAnchor.self).bundleURL
        let build = bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let attempt = build.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = attempt.appendingPathComponent("task-10/\(fixture.stress ? "failure" : "happy")/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = "\(fixture.locale)-\(fixture.dark ? "dark" : "light")-\(fixture.state.rawValue)\(suffix)"
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            try Data("BLOCKED: NSView.bitmapImageRepForCachingDisplay(in:) returned nil\n".utf8)
                .write(to: directory.appendingPathComponent(stem + ".blocked.txt"))
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000)
        try png.write(to: directory.appendingPathComponent(stem + ".png"))
        let ax = elements(in: view).map { element in
            let role = (element as? NSControl)?.cell?.accessibilityRole() ?? element.accessibilityRole()
            return "\(element.accessibilityIdentifier() ?? "-") | \(role?.rawValue ?? "-") | \(name(element))"
        }
        try Data(ax.joined(separator: "\n").utf8).write(to: directory.appendingPathComponent(stem + ".ax.txt"))
    }
}

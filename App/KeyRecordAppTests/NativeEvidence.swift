import AppKit
import SwiftUI
import XCTest
import ApplicationServices

@MainActor
enum NativeEvidence {
    static func primeAccessibility() {
        var role: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()),
            kAXRoleAttribute as CFString, &role)
        print("Self AX initialization result: \(result.rawValue); tree assertions determine availability")
    }

    static func elements(in root: NSObject, includeScrollChrome: Bool = true) -> [NSObject] {
        var result: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        func walk(_ node: NSObject) {
            guard visited.insert(ObjectIdentifier(node)).inserted else { return }
            if !includeScrollChrome && KRAXRole(node) == "AXScrollBar" { return }
            result.append(node)
            for child in KRAXChildren(node) { walk(child) }
        }
        walk(root)
        return result
    }

    static func update(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let turn = XCTestExpectation(description: "SwiftUI rendering and AX update")
        DispatchQueue.main.async { turn.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [turn], timeout: 5), .completed)
        view.layoutSubtreeIfNeeded()
    }

    static func node(_ id: String, in view: NSView) throws -> NSObject {
        let matches = elements(in: view).filter { KRAXIdentifier($0) == id }
        XCTAssertEqual(matches.count, 1, "AX identifier must resolve exactly once: \(id)")
        return try XCTUnwrap(matches.first, id)
    }

    static func scrollView(in view: NSView) throws -> NSScrollView {
        try XCTUnwrap(elements(in: view).compactMap { $0 as? NSScrollView }.first)
    }

    static func scrollTop(_ view: NSView) throws {
        let scroll = try scrollView(in: view)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        update(view)
    }

    static func scrollBottom(_ view: NSView) throws {
        let scroll = try scrollView(in: view)
        let document = try XCTUnwrap(scroll.documentView)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        update(view)
    }

    static func reveal(_ id: String, in view: NSView) throws {
        let scroll = try scrollView(in: view)
        let document = try XCTUnwrap(scroll.documentView)
        let window = try XCTUnwrap(view.window)
        let rect = document.convert(window.convertFromScreen(KRAXFrame(try node(id, in: view))), from: nil)
        document.scrollToVisible(rect)
        scroll.reflectScrolledClipView(scroll.contentView)
        update(view)
        try assertVisible(id, in: view)
    }

    static func assertVisible(_ id: String, in view: NSView) throws {
        let frame = KRAXFrame(try node(id, in: view))
        let scroll = try scrollView(in: view)
        let bounds = KRAXFrame(scroll).intersection(KRAXFrame(view))
        XCTAssertGreaterThan(frame.width, 0, id)
        XCTAssertGreaterThan(frame.height, 0, id)
        XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(frame), "\(id): \(frame) outside \(bounds)")
    }

    static func assertLabels(_ view: NSView, fixture: PrimitiveFixture) throws {
        let text = NativeText(locale: fixture.locale)
        for key in ["harness.title", "harness.disclaimer", "consent.title", "consent.disclosure", "consent.accept",
                    "consent.reject", fixture.state.statusKey, fixture.state.actionKey, "aggregate.sample",
                    "aggregate.empty", "aggregate.emptyValue", "aggregate.value", "settings.exclusions", "destructive.title",
                    "destructive.warning", "action.cancel", "destructive.confirm"] {
            XCTAssertFalse(text(key).isEmpty, key)
            XCTAssertNotEqual(text(key), key, "Missing selected-locale catalog entry: \(key)")
        }
        let aggregate = fixture.empty ? text("aggregate.empty") : fixture.stress
            ? String(repeating: text("aggregate.sample") + " · ", count: 8) : text("aggregate.sample")
        let labels = ["harness.title": text("harness.title"), "harness.disclaimer": text("harness.disclaimer"),
            "consent.panel": text("consent.title"), "consent.disclosure": text("consent.disclosure"),
            "consent.accept": text("consent.accept"), "consent.reject": text("consent.reject"),
            "capture.status": text(fixture.state.statusKey), "capture.symbol": text(fixture.state.statusKey),
            "capture.primary": text(fixture.state.actionKey), "aggregates.row": aggregate,
            "settings.exclusions": text("settings.exclusions"), "destructive.panel": text("destructive.title"),
            "destructive.warning": text("destructive.warning"), "destructive.cancel": text("action.cancel"),
            "destructive.confirm": text("destructive.confirm")]
        XCTAssertEqual(labels.count, 15)
        for id in labels.keys.sorted() {
            let element = try node(id, in: view)
            XCTAssertEqual(KRAXLabel(element), labels[id], id)
            let role: String
            if PrimitiveFocus.order.contains(id) { role = "AXButton" }
            else if id == "capture.symbol" { role = "AXImage" }
            else if id.hasSuffix(".panel") { role = "AXHeading" }
            else { role = "AXStaticText" }
            XCTAssertEqual(KRAXRole(element), role, id)
            try reveal(id, in: view)
        }
        let interactive = elements(in: view, includeScrollChrome: false).filter { KRAXRole($0) == "AXButton" }
        XCTAssertEqual(interactive.count, 6)
        XCTAssertEqual(Set(interactive.compactMap { KRAXIdentifier($0) }), Set(PrimitiveFocus.order))
        XCTAssertEqual(KRAXValue(try node("aggregates.row", in: view)), text(fixture.empty ? "aggregate.emptyValue" : "aggregate.value"))
        XCTAssertEqual(KRAXValue(try node("capture.status", in: view)), text(fixture.state.statusKey))
    }

    static func assertKeyboard(_ view: NSView) throws {
        let window = try XCTUnwrap(view.window)
        _ = KRAXFocus(try node("consent.accept", in: view))
        update(view)
        for id in PrimitiveFocus.order {
            XCTAssertTrue(KRAXFocused(try node(id, in: view)), id)
            try assertVisible(id, in: view)
            try key("\t", code: 48, window: window)
        }
        for id in PrimitiveFocus.order.reversed() {
            try key("\t", code: 48, window: window, shift: true)
            XCTAssertTrue(KRAXFocused(try node(id, in: view)), id)
            try assertVisible(id, in: view)
        }
    }

    static func key(_ characters: String, code: UInt16, window: NSWindow, shift: Bool = false) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
        window.sendEvent(event)
        if let view = window.contentView { update(view) }
    }

    static func snapshot(_ view: NSView, fixture: PrimitiveFixture, suffix: String = "") throws {
        func idle(_ layer: CALayer?) -> Bool {
            guard let layer else { return true }
            if let presentation = layer.presentation(), !(layer.animationKeys() ?? []).isEmpty {
                // AppKit can retain completed animation keys; compare the rendered state.
                guard presentation.bounds == layer.bounds, presentation.position == layer.position,
                      presentation.opacity == layer.opacity,
                      presentation.cornerRadius == layer.cornerRadius,
                      presentation.shadowRadius == layer.shadowRadius,
                      presentation.shadowOpacity == layer.shadowOpacity,
                      CATransform3DEqualToTransform(presentation.transform, layer.transform) else { return false }
            }
            return (layer.sublayers ?? []).allSatisfy { idle($0) }
        }
        update(view)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { idle(view.layer) }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, "Snapshot layers must finish their native animations")
        let attempt = Bundle(for: ResourceAnchor.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
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
        let ax = elements(in: view).map {
            "\(KRAXIdentifier($0) ?? "-") | \(KRAXRole($0) ?? "-") | \(KRAXLabel($0) ?? "") | \(KRAXValue($0) ?? "") | \(KRAXFrame($0))"
        }
        let dump = ["window-title: \(view.window?.title ?? "")"] + ax
        try Data(dump.joined(separator: "\n").utf8).write(to: directory.appendingPathComponent(stem + ".ax.txt"))
    }
}

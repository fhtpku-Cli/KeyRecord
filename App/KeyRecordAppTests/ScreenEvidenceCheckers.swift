import AppKit
import SwiftUI
import XCTest
import KeyRecordCore

extension ScreenEvidence {
    // MARK: Geometry and focus checkers (return violations; empty means pass)

    static func overflowViolations(_ view: NSView, ids: [String]) -> [String] {
        var violations: [String] = []
        let windowFrame = view.window?.convertToScreen(view.convert(view.bounds, to: nil)) ?? .zero
        let scroll = NativeEvidence.elements(in: view).compactMap { $0 as? NSScrollView }.first
        for id in ids {
            let matches = NativeEvidence.elements(in: view).filter { KRAXIdentifier($0) == id }
            if matches.isEmpty { violations.append("\(id): identifier missing"); continue }
            for element in matches {
                var frame = KRAXFrame(element)
                if !windowFrame.insetBy(dx: -1, dy: -1).contains(frame), let scroll,
                   let document = scroll.documentView {
                    // Off-screen content may be reachable by scrolling; reveal then re-measure.
                    let local = view.window?.convertFromScreen(frame) ?? frame
                    document.scrollToVisible(document.convert(local, from: nil))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    NativeEvidence.update(view)
                    frame = KRAXFrame(element)
                }
                guard frame.width > 0, frame.height > 0 else {
                    violations.append("\(id): zero-size frame")
                    continue
                }
                if !windowFrame.insetBy(dx: -1, dy: -1).contains(frame) {
                    violations.append("\(id): frame \(frame) outside window \(windowFrame)")
                }
            }
        }
        return violations
    }

    static func interactiveElements(_ view: NSView) -> [NSObject] {
        let roles: Set<String> = ["AXButton", "AXCheckBox", "AXPopUpButton", "AXRadioButton", "AXTextField"]
        return NativeEvidence.elements(in: view, includeScrollChrome: false).filter {
            guard let role = KRAXRole($0) else { return false }
            return roles.contains(role)
        }
    }

    static func enabledMap(_ view: NSView, ids: [String]) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for id in ids {
            let matches = NativeEvidence.elements(in: view).filter { KRAXIdentifier($0) == id }
            result[id] = matches.count == 1 ? KRAXEnabled(matches[0]) : false
        }
        return result
    }

    /// True when the same content renders different pixels across light/dark appearances,
    /// which only semantic (appearance-responsive) colors can do.
    static func isAppearanceResponsive(_ make: () -> AnyView) throws -> Bool {
        func png(_ appearance: MatrixAppearance) throws -> Data {
            prepare()
            let view = NSHostingView(rootView: make()
                .environment(\.colorScheme, appearance.dark ? .dark : .light))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: NativeLayout.minimum),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.appearance = NSAppearance(named: appearance.name)
            window.makeKeyAndOrderFront(nil)
            defer { window.contentView = nil; window.close() }
            NativeEvidence.primeAccessibility()
            return try capturePNG(view)
        }
        return try png(.light) != png(.dark)
    }

    /// Forward then reverse AX-focus walk over enabled buttons in tree order. Checkboxes
    /// and pop-up buttons do not accept AX focus in a hostless session (same Full Keyboard
    /// Access gate as Tab traversal); they are covered by name/enabled/AXPress assertions.
    static func focusWalkViolations(_ view: NSView) -> [String] {
        let buttons = interactiveElements(view).filter { KRAXRole($0) == "AXButton" && KRAXEnabled($0) }
        var violations: [String] = []
        for element in buttons + buttons.reversed() {
            let id = KRAXIdentifier(element) ?? "<anonymous>"
            guard KRAXFocus(element), KRAXFocused(element) else {
                violations.append("\(id): AX focus not settable")
                continue
            }
            let frame = KRAXFrame(element)
            if frame.width <= 0 || frame.height <= 0 { violations.append("\(id): focused element has zero frame") }
        }
        return violations
    }

    /// Flags labels that leak raw dotted localization keys (missing catalog entries) and
    /// interactive/static elements with no readable label at all.
    static func rawLabelViolations(_ view: NSView) -> [String] {
        rawLabelViolations(elements: NativeEvidence.elements(in: view, includeScrollChrome: false))
    }

    static func rawLabelViolations(elements: [NSObject]) -> [String] {
        var violations: [String] = []
        for element in elements {
            guard let role = KRAXRole(element),
                  ["AXButton", "AXCheckBox", "AXPopUpButton", "AXRadioButton", "AXTextField", "AXStaticText", "AXHeading"].contains(role) else { continue }
            let id = KRAXIdentifier(element) ?? "<anonymous>"
            let label = KRAXLabel(element) ?? ""
            if label.isEmpty {
                violations.append("\(id): empty label")
            } else if label.range(of: #"^[a-z][a-z0-9]*(\.[A-Za-z0-9-]+){2,}$"#, options: .regularExpression) != nil {
                violations.append("\(id): label is a raw key: \(label)")
            }
        }
        return violations
    }
}

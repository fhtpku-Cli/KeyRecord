import AppKit
import SwiftUI
import XCTest
import KeyRecordCore

// MARK: - Task 22 failure lane: stress renders and negative checker fixtures

@MainActor
final class ScreenStressTests: XCTestCase {
    func testFailureEmptyInteractiveLabelIsRejected() {
        let bad = NSAccessibilityElement()
        bad.setAccessibilityRole(.button)
        bad.setAccessibilityIdentifier("fixture.unlabelled")
        XCTAssertEqual(ScreenEvidence.rawLabelViolations(elements: [bad]), ["fixture.unlabelled: empty label"])
        bad.setAccessibilityLabel("Accessible action")
        XCTAssertEqual(ScreenEvidence.rawLabelViolations(elements: [bad]), [])
    }
    // Long CJK names, accessibility5 Dynamic Type, high contrast and Reduce Motion at the
    // 640x480 minimum: essential content stays reachable (scrolling allowed).
    func testFailureStressLongCJKLargeType() throws {
        for locale in MatrixContent.locales {
            for appearance in [MatrixAppearance.light, .dark] {
                var fixture = MatrixFixture(state: .collecting, locale: locale, appearance: appearance)
                fixture.stress = true
                fixture.largeType = true
                fixture.reduceMotion = true
                fixture.size = NativeLayout.minimum
                for kind in [ScreenKind.consent, .settings, .aggregate, .dialogDelete] {
                    let rendered = try ScreenEvidence.record(kind, fixture: fixture)
                    defer { ScreenEvidence.close(rendered) }
                    var ids = kind.uniqueIDs + kind.interactiveIDs
                    if kind == .settings {
                        ids += MatrixContent.choices(stress: true).map { "settings.exclusions.\($0.bundleID)" }
                    }
                    if kind == .aggregate {
                        ids += ["aggregates.row", "aggregates.bare"]
                    }
                    XCTAssertEqual(ScreenEvidence.overflowViolations(rendered.view, ids: ids), [],
                                   "\(kind.rawValue) [\(fixture.stem)]")
                    XCTAssertEqual(ScreenEvidence.rawLabelViolations(rendered.view), [],
                                   "\(kind.rawValue) [\(fixture.stem)]")
                }
            }
        }
    }

    // Empty aggregate copy, retry action on error, and locked gating: no counts or rows
    // may be present in the tree while locked, even with retained raw totals.
    func testFailureEmptyErrorLockedContent() throws {
        for (locale, appearance) in [("en", MatrixAppearance.light), ("zh-Hans", MatrixAppearance.dark)] {
            let fixture = MatrixFixture(state: .collecting, locale: locale, appearance: appearance)
            let empty = try ScreenEvidence.record(.aggregateEmpty, fixture: fixture)
            defer { ScreenEvidence.close(empty) }
            let text = NativeText(locale: locale)
            let emptyNode = try NativeEvidence.node("aggregates.empty", in: empty.view)
            XCTAssertEqual(KRAXLabel(emptyNode), text("aggregate.emptyState"))
            XCTAssertTrue(NativeEvidence.elements(in: empty.view).allSatisfy {
                KRAXIdentifier($0) != "aggregates.row" && KRAXIdentifier($0) != "aggregates.bare"
            })

            let errorMenu = try ScreenEvidence.record(.menu, fixture: MatrixFixture(
                state: .error, locale: locale, appearance: appearance))
            defer { ScreenEvidence.close(errorMenu) }
            XCTAssertEqual(KRAXValue(try NativeEvidence.node("capture.status", in: errorMenu.view)),
                           text("status.error"))
        }

        let driver = MatrixDriver(state: MatrixContent.lifecycleState(for: .collecting))
        let model = Phase1FlowModel(lifecycle: driver)
        let flow = AppFlowObservable(flow: model, actions: FlowActions())
        flow.update(phase: .collecting)
        flow.snapshot = MatrixContent.snapshot(stress: false)
        XCTAssertNotNil(flow.snapshot)
        driver.state = LifecycleState.blockedForRetry(
            preferences: Preferences(currentCycleID: CycleID(rawValue: "t22-cycle")),
            reason: .sessionLocked)
        XCTAssertFalse(model.sensitiveContentVisible)
        XCTAssertNil(flow.snapshot, "locked gating must hide retained totals")
        let locked = try ScreenEvidence.record(.aggregateLocked, fixture: MatrixFixture(
            state: .blocked, locale: "en", appearance: .light))
        defer { ScreenEvidence.close(locked) }
        XCTAssertNotNil(try? NativeEvidence.node("aggregates.locked", in: locked.view))
        for element in NativeEvidence.elements(in: locked.view) {
            let label = KRAXLabel(element) ?? ""
            XCTAssertFalse(label.contains("observed"), "locked tree must not leak counts: \(label)")
            XCTAssertFalse(label.contains("观测"), "locked tree must not leak counts: \(label)")
        }
    }

    // The audit must reject a catalog with a missing referenced key, an orphan key,
    // a parity gap, an empty value and an untranslated identical value.
    func testFailureLocalizationAuditDetectsMissingAndOrphan() throws {
        let missingBoth = LocalizationAudit.referencedKeys(in: #"Text(text("new.key.absentBoth"))"#)
        XCTAssertEqual(missingBoth, ["new.key.absentBoth"])
        let emptyCatalogs: [[String: String]] = [[:], [:]]
        for catalog in emptyCatalogs {
            XCTAssertEqual(LocalizationAudit.audit(catalog: catalog, referenced: missingBoth),
                           ["missing catalog entry for referenced key: new.key.absentBoth"])
        }
        XCTAssertEqual(LocalizationAudit.referencedKeys(in: #"Text(text("menu.open"))"#), ["menu.open"])
        let referenced: Set<String> = ["alpha.one", "beta.two"]
        var catalog = ["alpha.one": "One"]
        XCTAssertEqual(LocalizationAudit.audit(catalog: catalog, referenced: referenced),
                       ["missing catalog entry for referenced key: beta.two"])
        catalog["gamma.three"] = "Three"
        catalog["beta.two"] = "Two"
        XCTAssertEqual(LocalizationAudit.audit(catalog: catalog, referenced: referenced),
                       ["orphaned catalog entry never referenced: gamma.three"])
        XCTAssertEqual(LocalizationAudit.audit(catalog: ["alpha.one": "One", "beta.two": "Two"],
                                               referenced: referenced), [])

        let en = ["alpha.one": "One", "beta.two": "Two", "delta.four": "Same", "app.name": "KeyRecord"]
        let zh = ["alpha.one": "一", "beta.two": "", "delta.four": "Same", "app.name": "KeyRecord"]
        let violations = LocalizationAudit.auditPair(en: en, zh: zh)
        XCTAssertTrue(violations.contains("empty value: beta.two"))
        XCTAssertTrue(violations.contains("untranslated value identical across locales: delta.four"))
        XCTAssertFalse(violations.contains { $0.contains("app.name") })
        XCTAssertEqual(LocalizationAudit.auditPair(en: ["alpha.one": "One"], zh: [:]),
                       ["locale parity gap: alpha.one"])
    }

    // A view whose label leaks a raw dotted key must trip the missing-localization detector.
    func testFailureRenderedLabelAuditFlagsRawKey() throws {
        ScreenEvidence.prepare()
        let text = NativeText(locale: "en")
        XCTAssertEqual(text("t22.bogus.missing.key"), "t22.bogus.missing.key",
                       "missing bundle entries fall back to the raw key")
        let bad = NSHostingView(rootView: VStack {
            Text(text("t22.bogus.missing.key")).accessibilityIdentifier("t22.bogus")
            Button(text("consent.accept")) {}.accessibilityIdentifier("t22.good")
        }.padding(24))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NativeLayout.minimum),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bad
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(bad)
        let tree = NativeEvidence.elements(in: bad).map { "\(KRAXIdentifier($0) ?? "-")|\(KRAXRole($0) ?? "-")|\(KRAXLabel($0) ?? "")" }
        let violations = ScreenEvidence.rawLabelViolations(bad)
        XCTAssertEqual(violations, ["t22.bogus: label is a raw key: t22.bogus.missing.key"], tree.joined(separator: "\n"))
    }

    // A fixed, non-wrapping long line inside a narrow frame must trip the clipping detector.
    func testFailureClippingDetectorFlagsOverflow() throws {
        ScreenEvidence.prepare()
        let bad = NSHostingView(rootView:
            HStack(spacing: 0) {
                Text(String(repeating: "unclipped-single-line-", count: 20))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("t22.clipped")
                Spacer(minLength: 0)
            }
            .frame(width: 200, height: 40, alignment: .leading)
            .clipped())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bad
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(bad)
        let matches = NativeEvidence.elements(in: bad).filter { KRAXIdentifier($0) == "t22.clipped" }
        let frames = matches.map { String(describing: KRAXFrame($0)) }
        let violations = ScreenEvidence.overflowViolations(bad, ids: ["t22.clipped"])
        XCTAssertEqual(violations.count, 1, "frames=\(frames) window=\(window.frame)")
        XCTAssertTrue(violations.first?.contains("t22.clipped") ?? false,
                      violations.joined(separator: "; "))
    }

    // The color scan must flag hardcoded RGB/absolute colors with file:line detail.
    func testFailureHardcodedColorScanFindsViolations() throws {
        let bad = """
        let a = Color(red: 1, green: 0, blue: 0)
        let b = NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1)
        Text("x").foregroundColor(.white)
        let c = Color.black
        """
        let violations = SourceInspection.hardcodedColorViolations(bad, file: "Fixture.swift")
        XCTAssertEqual(violations.count, 4)
        XCTAssertTrue(violations.allSatisfy { $0.hasPrefix("Fixture.swift:") })
        XCTAssertEqual(violations.map { String($0.split(separator: ":")[1]) }, ["1", "2", "3", "4"])
        let clean = """
        Text("x").foregroundStyle(.secondary)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(.primary)
        """
        XCTAssertEqual(SourceInspection.hardcodedColorViolations(clean, file: "Clean.swift"), [])
    }

    // A hardcoded-color fixture renders identical pixels in light and dark and must be
    // flagged non-responsive; the semantic product screens respond (checked in happy).
    func testFailureAppearanceUnresponsiveColorDetected() throws {
        let hardcoded = try ScreenEvidence.isAppearanceResponsive {
            AnyView(Text("fixture").foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.3))
                .padding(40).background(Color(red: 0.9, green: 0.9, blue: 0.9)))
        }
        XCTAssertFalse(hardcoded, "hardcoded colors must be detected as appearance-unresponsive")
        let semantic = try ScreenEvidence.isAppearanceResponsive {
            AnyView(Text("fixture").foregroundStyle(.primary)
                .padding(40).background(Color(nsColor: .windowBackgroundColor)))
        }
        XCTAssertTrue(semantic, "semantic colors must render differently across appearances")
    }
}




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

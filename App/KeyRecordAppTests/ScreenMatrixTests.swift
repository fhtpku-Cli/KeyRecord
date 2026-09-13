import AppKit
import SwiftUI
import XCTest
import KeyRecordCore

// MARK: - Task 22 happy lane: full state x appearance x locale x motion screen matrix

@MainActor
final class ScreenMatrixTests: XCTestCase {
    private static let appearances: [MatrixAppearance] = [.light, .dark]

    private func expectedLabels(_ kind: ScreenKind, fixture: MatrixFixture,
                                text: NativeText) -> [String: String] {
        let state = PrimitiveState(phase: fixture.state.phase)
        switch kind {
        case .consent:
            return ["consent.panel": text("consent.title"), "consent.disclosure": text("consent.disclosure"),
                    "consent.accept": text("consent.accept"), "consent.reject": text("consent.reject")]
        case .menu:
            return ["capture.symbol": text(state.statusKey), "capture.status": text(state.statusKey),
                    "menu.start": text("action.start"), "menu.pause": text("action.pause"),
                    "menu.resume": text("action.resume"), "menu.settings": text("action.settings"),
                    "menu.quit": text("action.quit")]
        case .settings:
            return ["settings.login": text("settings.login"), "settings.reset": text("settings.reset"),
                    "settings.delete": text("settings.delete")]
        case .aggregate:
            let snapshot = MatrixContent.snapshot(stress: fixture.stress)
            return ["aggregates.panel": text("aggregate.title"),
                    "aggregates.shortcutTotal": String(format: text("aggregate.totalShortcuts"), snapshot.shortcutTotal),
                    "aggregates.bareTotal": String(format: text("aggregate.totalBare"), snapshot.bareKeyTotal)]
        case .aggregateEmpty:
            return ["aggregates.panel": text("aggregate.title"), "aggregates.empty": text("aggregate.emptyState")]
        case .aggregateLocked:
            return ["aggregates.panel": text("aggregate.title"), "aggregates.locked": text("aggregate.locked")]
        case .dialogReset:
            return ["dialog.panel": text("dialog.reset.title"), "dialog.message": text("dialog.reset.message"),
                    "dialog.confirm": text("dialog.reset.confirm"), "dialog.cancel": text("dialog.reset.cancel")]
        case .dialogDelete:
            return ["dialog.panel": text("dialog.delete.title"), "dialog.message": text("dialog.delete.message"),
                    "dialog.confirm": text("dialog.delete.confirm"), "dialog.cancel": text("dialog.delete.cancel")]
        }
    }

    private func assertScreen(_ rendered: ScreenEvidence.Rendered, kind: ScreenKind,
                              fixture: MatrixFixture) throws {
        let text = NativeText(locale: fixture.locale)
        for (id, expected) in expectedLabels(kind, fixture: fixture, text: text) {
            let element = try NativeEvidence.node(id, in: rendered.view)
            XCTAssertEqual(KRAXLabel(element), expected, "\(id) [\(fixture.stem)]")
        }
        var geometryIDs = kind.uniqueIDs + kind.interactiveIDs
        if kind == .settings && !fixture.emptyChoices {
            geometryIDs += MatrixContent.choices(stress: fixture.stress).map { "settings.exclusions.\($0.bundleID)" }
        }
        if kind == .aggregate {
            geometryIDs += ["aggregates.row", "aggregates.bare"]
        }
        XCTAssertEqual(ScreenEvidence.overflowViolations(rendered.view, ids: geometryIDs), [],
                       "\(kind.rawValue) [\(fixture.stem)]")
        XCTAssertEqual(ScreenEvidence.rawLabelViolations(rendered.view), [], "\(kind.rawValue) [\(fixture.stem)]")
        if !kind.interactiveIDs.isEmpty {
            XCTAssertEqual(ScreenEvidence.focusWalkViolations(rendered.view), [],
                           "\(kind.rawValue) [\(fixture.stem)]")
        }
    }

    // 6 states x light/dark x EN/zh-Hans render consent/menu/settings plus the aggregate
    // screen (populated when sensitive content is visible, lock placeholder otherwise);
    // collecting also renders both destructive dialogs. Every record is rendered twice
    // and must be byte-identical before the PNG + AX pair is written.
    func testHappyScreenMatrix() throws {
        for locale in MatrixContent.locales {
            for appearance in Self.appearances {
                for state in MatrixState.allCases {
                    let fixture = MatrixFixture(state: state, locale: locale, appearance: appearance)
                    let screens: [ScreenKind] = [.consent, .menu, .settings,
                                                 state.showsAggregates ? .aggregate : .aggregateLocked]
                    for kind in screens {
                        let rendered = try ScreenEvidence.record(kind, fixture: fixture)
                        try assertScreen(rendered, kind: kind, fixture: fixture)
                        ScreenEvidence.close(rendered)
                    }
                    guard state == .collecting else { continue }
                    for kind in [ScreenKind.dialogReset, .dialogDelete] {
                        let rendered = try ScreenEvidence.record(kind, fixture: fixture)
                        try assertScreen(rendered, kind: kind, fixture: fixture)
                        ScreenEvidence.close(rendered)
                    }
                }
            }
        }
    }

    func testHappyReducedMotionMatrix() throws {
        for locale in MatrixContent.locales {
            for appearance in Self.appearances {
                for state in MatrixState.allCases {
                    var fixture = MatrixFixture(state: state, locale: locale, appearance: appearance)
                    fixture.reduceMotion = true
                    for kind in ScreenKind.allCases where kind != .aggregate || state.showsAggregates {
                        if kind == .dialogReset && state != .collecting && state != .paused { continue }
                        if kind == .dialogDelete && state == .unstarted { continue }
                        let rendered = try ScreenEvidence.record(kind, fixture: fixture)
                        try assertScreen(rendered, kind: kind, fixture: fixture)
                        ScreenEvidence.close(rendered)
                    }
                }
            }
        }
        // The macOS 26 SDK exposes accessibilityReduceMotion as get-only; the product's
        // Reduce Motion policy is the transaction-level NativeMotion gate (DESIGN 6).
        var disabled = Transaction(animation: .default)
        NativeMotion.apply(to: &disabled, reducedMotion: true)
        XCTAssertNil(disabled.animation)
        XCTAssertTrue(disabled.disablesAnimations)
        var enabled = Transaction(animation: .default)
        NativeMotion.apply(to: &enabled, reducedMotion: false)
        XCTAssertNotNil(enabled.animation)
        XCTAssertFalse(enabled.disablesAnimations)
    }

    // System Increase Contrast is T23; Q22 measures semantic colors and rendered ink.
    func testHappyAppearanceSemantics() throws {
        for state in MatrixState.allCases {
            let light = ScreenEvidence.render(.menu, fixture: MatrixFixture(
                state: state, locale: "en", appearance: .light))
            let lightPNG = try ScreenEvidence.capturePNG(light.view)
            ScreenEvidence.close(light)
            let dark = ScreenEvidence.render(.menu, fixture: MatrixFixture(
                state: state, locale: "en", appearance: .dark))
            let darkPNG = try ScreenEvidence.capturePNG(dark.view)
            ScreenEvidence.close(dark)
            XCTAssertNotEqual(lightPNG, darkPNG, "semantic colors must respond to appearance [\(state.rawValue)]")
        }
    }

    // Long CJK app names, large counts, empty/error/locked copy at both window minima;
    // content may be scroll-reachable but never clipped away.
    func testHappyGeometryMatrix() throws {
        for size in [NativeLayout.minimum, NativeLayout.aggregateMinimum] {
            for locale in MatrixContent.locales {
                for appearance in Self.appearances {
                    var fixture = MatrixFixture(state: .collecting, locale: locale, appearance: appearance)
                    fixture.stress = true
                    fixture.size = size
                    for kind in ScreenKind.allCases {
                        let rendered = try ScreenEvidence.record(kind, fixture: fixture)
                        try assertScreen(rendered, kind: kind, fixture: fixture)
                        ScreenEvidence.close(rendered)
                    }
                }
            }
        }
    }

    func testHappyKeyboardAndActivation() throws {
        let consent = ScreenEvidence.render(.consent, fixture: MatrixFixture(
            state: .consent, locale: "en", appearance: .light))
        defer { ScreenEvidence.close(consent) }
        XCTAssertEqual(ScreenEvidence.focusWalkViolations(consent.view), [])
        _ = KRAXPress(try NativeEvidence.node("consent.accept", in: consent.view))
        ScreenEvidence.waitUntil("consent-accept", in: consent.view) { consent.journal.events.contains("accept") }

        for state in MatrixState.allCases {
            let menu = ScreenEvidence.render(.menu, fixture: MatrixFixture(
                state: state, locale: "en", appearance: .light))
            defer { ScreenEvidence.close(menu) }
            let primitive = PrimitiveState(phase: state.phase)
            let expected = ["menu.start": primitive == .unstarted,
                            "menu.pause": primitive == .collecting,
                            "menu.resume": primitive == .paused,
                            "menu.settings": true, "menu.quit": true]
            XCTAssertEqual(ScreenEvidence.enabledMap(menu.view, ids: Array(expected.keys)), expected,
                           "\(state.rawValue)")
            menu.journal.reset()
            for (id, enabled) in expected where ["menu.start", "menu.pause", "menu.resume"].contains(id) {
                let pressed = KRAXPress(try NativeEvidence.node(id, in: menu.view))
                let event = String(id.dropFirst("menu.".count))
                if enabled {
                    XCTAssertTrue(pressed, "\(id) [\(state.rawValue)]")
                    ScreenEvidence.waitUntil("menu-\(event)", in: menu.view) { menu.journal.events.contains(event) }
                } else {
                    XCTAssertFalse(pressed, "disabled \(id) must reject activation [\(state.rawValue)]")
                    XCTAssertFalse(menu.journal.events.contains(event), "\(id) [\(state.rawValue)]")
                }
            }
        }

        let dialog = ScreenEvidence.render(.dialogReset, fixture: MatrixFixture(
            state: .collecting, locale: "en", appearance: .light))
        defer { ScreenEvidence.close(dialog) }
        XCTAssertEqual(ScreenEvidence.focusWalkViolations(dialog.view), [])
        // DESIGN 6: even with confirm focused, Return has no default action on a destructive dialog.
        _ = KRAXFocus(try NativeEvidence.node("dialog.confirm", in: dialog.view))
        try NativeEvidence.key("\r", code: 36, window: dialog.window)
        NativeEvidence.update(dialog.view)
        XCTAssertEqual(dialog.flow.dialog, .resetConfirmation(.standard()))
        XCTAssertFalse(dialog.journal.events.contains("cycleReset"))
        // Escape cancels once a dialog control has focus; no side effects run.
        _ = KRAXFocus(try NativeEvidence.node("dialog.cancel", in: dialog.view))
        try NativeEvidence.key("\u{1b}", code: 53, window: dialog.window)
        ScreenEvidence.waitUntil("dialog-escape", in: dialog.view) { dialog.flow.dialog == .none }
        XCTAssertFalse(dialog.journal.events.contains("cycleReset"))
        // AX press on confirm performs the reset.
        dialog.flow.requestReset()
        NativeEvidence.update(dialog.view)
        _ = KRAXPress(try NativeEvidence.node("dialog.confirm", in: dialog.view))
        ScreenEvidence.waitUntil("dialog-confirm-reset", in: dialog.view) { dialog.journal.events.contains("cycleReset") }
        ScreenEvidence.waitUntil("dialog-confirm-none", in: dialog.view) { dialog.flow.dialog == .none }

        let settings = ScreenEvidence.render(.settings, fixture: MatrixFixture(
            state: .collecting, locale: "en", appearance: .light))
        defer { ScreenEvidence.close(settings) }
        _ = KRAXPress(try NativeEvidence.node("settings.exclusions.com.example.editor", in: settings.view))
        ScreenEvidence.waitUntil("settings-exclusions", in: settings.view) { settings.journal.events.contains("setExclusions:com.example.chat,com.example.editor") }
        XCTAssertTrue(settings.journal.events.contains("setExclusions:com.example.chat,com.example.editor"))
        _ = KRAXPress(try NativeEvidence.node("settings.login", in: settings.view))
        ScreenEvidence.waitUntil("settings-login", in: settings.view) { settings.journal.events.contains("setLoginItem:true") }
        _ = KRAXPress(try NativeEvidence.node("settings.delete", in: settings.view))
        ScreenEvidence.waitUntil("settings-delete-dialog", in: settings.view) { settings.flow.dialog == .deleteConfirmation(.deleteStandard()) }

        for (locale, appearance) in [("en", MatrixAppearance.light), ("zh-Hans", MatrixAppearance.dark)] {
            for kind in [ScreenKind.consent, .dialogReset] {
                let fixture = MatrixFixture(state: .collecting, locale: locale, appearance: appearance)
                let rendered = try ScreenEvidence.record(kind, fixture: fixture)
                try assertScreen(rendered, kind: kind, fixture: fixture)
                ScreenEvidence.close(rendered)
            }
        }
    }

    func testHappyLocalizationAudit() throws {
        let en = LocalizationAudit.parseCatalog(try String(
            contentsOf: LocalizationAudit.catalogURL("en"), encoding: .utf8))
        let zh = LocalizationAudit.parseCatalog(try String(
            contentsOf: LocalizationAudit.catalogURL("zh-Hans"), encoding: .utf8))
        XCTAssertEqual(LocalizationAudit.auditPair(en: en, zh: zh), [])
        let sources = try LocalizationAudit.appSources()
        let literals = sources.reduce(into: Set<String>()) {
            $0.formUnion(LocalizationAudit.referencedKeys(in: $1.text))
        }
        let referenced = literals.union(LocalizationAudit.dynamicKeys())
        XCTAssertEqual(LocalizationAudit.audit(catalog: en, referenced: referenced), [])
        XCTAssertEqual(LocalizationAudit.audit(catalog: zh, referenced: referenced), [])
        let identical = Set(en.keys.filter { en[$0] == zh[$0] })
        XCTAssertEqual(identical, LocalizationAudit.identicalAllowlist)
    }

    func testHappySourceInspection() throws {
        for source in try LocalizationAudit.appSources() {
            XCTAssertEqual(SourceInspection.hardcodedColorViolations(source.text, file: source.name), [])
        }
        XCTAssertEqual(NativeLayout.minimum, CGSize(width: 640, height: 480))
        XCTAssertEqual(NativeLayout.aggregateMinimum, CGSize(width: 1000, height: 700))
    }

    // Menu enablement across all twelve lifecycle phases plus a compact fitting width;
    // real NSScreen edge positioning is signed-host work and stays with T23.
    func testHappyMenuEdgeLayoutModel() throws {
        let expectations: [(LifecyclePhase, Bool, Bool, Bool)] = [
            (.unstarted, true, false, false), (.consent, true, false, false),
            (.collecting, false, true, false), (.starting, false, true, false),
            (.resuming, false, true, false), (.paused, false, false, true),
            (.pausing, false, false, true), (.stopping, false, false, true),
            (.stopped, false, false, true), (.reopening, false, false, false),
            (.blocked, false, false, false), (.failed, false, false, false),
        ]
        for (phase, canStart, canPause, canResume) in expectations {
            let menu = MenuBarState(state: PrimitiveState(phase: phase))
            XCTAssertEqual(menu.canStart, canStart, "\(phase)")
            XCTAssertEqual(menu.canPause, canPause, "\(phase)")
            XCTAssertEqual(menu.canResume, canResume, "\(phase)")
        }
        for locale in MatrixContent.locales {
            let menu = ScreenEvidence.render(.menu, fixture: MatrixFixture(
                state: .collecting, locale: locale, appearance: .light))
            defer { ScreenEvidence.close(menu) }
            let bounds = ScreenEvidence.interactiveElements(menu.view).map(KRAXFrame)
                .reduce(CGRect.null) { $0.union($1) }
            let size = CGSize(width: bounds.width + 2 * NativeLayout.page,
                              height: bounds.height + 2 * NativeLayout.page)
            XCTAssertLessThanOrEqual(size.width, 400, "compact menu content [\(locale)]")
            for screen in [CGRect(x: 0, y: 0, width: 640, height: 480),
                           CGRect(x: -1000, y: 100, width: 1000, height: 700)] {
                for anchor in [CGPoint(x: screen.minX, y: screen.maxY), CGPoint(x: screen.maxX, y: screen.maxY),
                               CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX, y: screen.minY)] {
                    let placed = MatrixContent.menuFrame(anchor: anchor, size: size, visibleFrame: screen)
                    XCTAssertTrue(screen.contains(placed))
                    for element in ScreenEvidence.interactiveElements(menu.view) {
                        let translated = KRAXFrame(element).offsetBy(dx: placed.minX + NativeLayout.page - bounds.minX,
                                                                    dy: placed.minY + NativeLayout.page - bounds.minY)
                        XCTAssertTrue(placed.contains(translated), KRAXIdentifier(element) ?? "anonymous")
                    }
                    XCTAssertEqual(placed.minX, anchor.x == screen.minX ? screen.minX : screen.maxX - size.width)
                    XCTAssertEqual(placed.minY, anchor.y == screen.minY ? screen.minY : screen.maxY - size.height)
                }
            }
        }
    }
}

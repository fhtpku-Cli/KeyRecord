import AppKit
import SwiftUI
import XCTest
import KeyRecordCore

extension ScreenMatrixTests {
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

    func testLocalizationAuditIgnoresPersistenceKeysAndAccessibilityIdentifiers() {
        let source = #"""
        static let defaultsKey = "debug.localCaptureEnabled"
        cause.setAccessibilityIdentifier("menu.startupFailure")
        static let diagnosisIdentifier = "menu.developer.diagnosis"
        Text(text("menu.open"))
        """#
        XCTAssertEqual(LocalizationAudit.referencedKeys(in: source), ["menu.open"])
    }

    func testLocalizationAuditFiltersOnlyAccessibilityCallSites() {
        let source = #"""
        Text("Panel").accessibilityIdentifier("phase2.onlyIdentifier")
        view.setAccessibilityIdentifier (
            "phase2.nativeIdentifier"
        )
        Text(text(isReady ? "phase2.shared" : "phase2.other"))
            .accessibilityIdentifier("phase2.shared")
        """#
        XCTAssertEqual(LocalizationAudit.referencedKeys(in: source), ["phase2.shared", "phase2.other"])
    }

    func testLocalizationAuditDetectsMissingDynamicTranslations() throws {
        var catalog = LocalizationAudit.parseCatalog(try String(
            contentsOf: LocalizationAudit.catalogURL("en"), encoding: .utf8))
        let sources = try LocalizationAudit.appSources()
        let referenced = sources.reduce(into: LocalizationAudit.dynamicKeys()) {
            $0.formUnion(LocalizationAudit.referencedKeys(in: $1.text))
        }
        for key in ["phase2.key.Return", "phase2.layout.ansi", "phase2.status.eligible"] {
            catalog.removeValue(forKey: key)
        }
        catalog["phase2.key.Space"] = " "
        XCTAssertEqual(LocalizationAudit.audit(catalog: catalog, referenced: referenced), [
            "missing catalog entry for referenced key: phase2.key.Return",
            "missing catalog entry for referenced key: phase2.layout.ansi",
            "missing catalog entry for referenced key: phase2.status.eligible",
            "empty value: phase2.key.Space",
        ])
        XCTAssertEqual(LocalizationAudit.auditPair(
            en: ["phase2.layout.ansi": "ANSI", "phase2.untranslated": "Same"],
            zh: ["phase2.layout.ansi": "ANSI", "phase2.untranslated": "Same"]),
            ["untranslated value identical across locales: phase2.untranslated"])
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

import AppKit
import SwiftUI
import XCTest
import KeyRecordCore

// MARK: - Task 22 screen evidence engine (builds on the task-10 NativeEvidence primitives)

@MainActor
enum ScreenEvidence {
    /// The Q22 wrapper exports this so evidence lands in task-22/<scenario>/screenshots.
    static let scenarioKey = "KEYRECORD_T22_SCENARIO"

    struct Rendered {
        let window: NSWindow
        let view: NSView
        let flow: AppFlowObservable
        let journal: MatrixJournal
    }

    static func prepare() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
    }

    /// Runs main-actor work from a synchronous test; XCTWaiter spins the run loop so
    /// queued tasks complete (async test bodies break NativeEvidence.update timing).
    static func awaitMain(_ work: @escaping @MainActor () async -> Void) {
        let turn = XCTestExpectation(description: "main-actor work")
        Task { @MainActor in await work(); turn.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [turn], timeout: 5), .completed)
    }

    /// Polls a main-actor predicate. Layout/display must run FIRST to commit the SwiftUI
    /// mutation (a Toggle binding only schedules its Task at transaction commit); the
    /// subsequent run-loop spin drains the scheduled main-actor action.
    static func waitUntil(_ label: String, in view: NSView, timeout: TimeInterval = 5,
                         predicate: @escaping @MainActor () -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            NativeEvidence.update(view)
            if predicate() { return }
            if ProcessInfo.processInfo.systemUptime > deadline {
                XCTFail("waitUntil: \(label)")
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    static func makeFlow(_ fixture: MatrixFixture, journal: MatrixJournal) -> AppFlowObservable {
        let model = Phase1FlowModel(lifecycle: MatrixDriver(state: MatrixContent.lifecycleState(for: fixture.state)),
                                    cycleReset: MatrixReset(journal: journal),
                                    localDataEraser: MatrixEraser(journal: journal))
        let flow = AppFlowObservable(flow: model, actions: FlowActions(
            accept: { journal.record("accept") },
            decline: { journal.record("decline") },
            start: { journal.record("start") },
            pause: { journal.record("pause") },
            resume: { journal.record("resume") },
            quit: { journal.record("quit") },
            setExclusions: { journal.record("setExclusions:\($0.sorted().joined(separator: ","))") },
            setLoginItem: { journal.record("setLoginItem:\($0)") },
            setLanguage: { journal.record("setLanguage:\($0)") },
            loadChoices: { fixture.emptyChoices ? [] : MatrixContent.choices(stress: fixture.stress) },
            openSettings: { journal.record("openSettings") }))
        flow.update(phase: fixture.state.phase)
        if fixture.state.showsAggregates { flow.snapshot = MatrixContent.snapshot(stress: fixture.stress) }
        return flow
    }

    static func screen(_ kind: ScreenKind, flow: AppFlowObservable, text: NativeText) -> AnyView {
        switch kind {
        case .consent:
            return AnyView(ConsentFlowView(flow: flow, text: text))
        case .menu:
            return AnyView(VStack(alignment: .leading, spacing: NativeLayout.compact) {
                MenuBarMenuContent(flow: flow, text: text)
            })
        case .settings:
            return AnyView(SettingsFlowView(flow: flow, text: text))
        case .aggregate:
            return AnyView(AggregateFlowView(snapshot: flow.snapshot, text: text))
        case .aggregateEmpty:
            return AnyView(AggregateFlowView(snapshot: AggregateSnapshot(rows: []), text: text))
        case .aggregateLocked:
            return AnyView(AggregateFlowView(snapshot: nil, text: text))
        case .dialogReset:
            flow.requestReset()
            return AnyView(FlowDialogView(flow: flow, text: text))
        case .dialogDelete:
            flow.requestDeleteLocalData()
            return AnyView(FlowDialogView(flow: flow, text: text))
        }
    }

    static func render(_ kind: ScreenKind, fixture: MatrixFixture) -> Rendered {
        prepare()
        let journal = MatrixJournal()
        let flow = makeFlow(fixture, journal: journal)
        awaitMain { await flow.refresh() }
        let text = NativeText(locale: fixture.locale)
        let content = screen(kind, flow: flow, text: text)
        let root = content
            .padding(NativeLayout.page)
            .frame(width: fixture.size.width, height: fixture.size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.locale, Locale(identifier: fixture.locale))
            .environment(\.colorScheme, fixture.appearance.dark ? .dark : .light)
            .environment(\.dynamicTypeSize, fixture.largeType ? .accessibility5 : .large)
            .nativeMotionPolicy()
            .environment(\.nativeReduceMotion, fixture.reduceMotion || fixture.stress)
        let view = NSHostingView(rootView: root)
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fixture.size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = view
        window.appearance = NSAppearance(named: fixture.appearance.name)
        window.makeKeyAndOrderFront(nil)
        window.setContentSize(fixture.size)
        view.frame = NSRect(origin: .zero, size: fixture.size)
        NativeEvidence.primeAccessibility()
        NativeEvidence.update(view)
        NativeEvidence.update(view)
        XCTAssertEqual(view.bounds.size, fixture.size)
        return Rendered(window: window, view: view, flow: flow, journal: journal)
    }

    static func close(_ rendered: Rendered) {
        rendered.window.contentView = nil
        rendered.window.close()
    }

    // MARK: Bitmap + AX capture (offscreen cache display; determinism enforced by record())

    static func capturePNG(_ view: NSView) throws -> Data {
        NativeEvidence.update(view)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds),
                                   "Window Server bitmap unavailable")
        view.cacheDisplay(in: view.bounds, to: bitmap)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 20)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 20)) {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.99,
                                           "Capture must include an opaque backdrop")
            }
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000)
        return png
    }

    static func axDump(_ view: NSView) -> String {
        let lines = NativeEvidence.elements(in: view).map {
            "\(KRAXIdentifier($0) ?? "-") | \(KRAXRole($0) ?? "-") | \(KRAXLabel($0) ?? "") | \(KRAXValue($0) ?? "") | \(KRAXFrame($0)) | enabled=\(KRAXEnabled($0)) | focusable=\(KRAXFocusable($0))"
        }
        return (["window-title: \(view.window?.title ?? "")"] + lines).joined(separator: "\n")
    }

    // MARK: Evidence output

    static func scenario() -> String {
        let raw = ProcessInfo.processInfo.environment[scenarioKey] ?? "ad-hoc"
        let allowed = Set("abcdefghijklmnopqrstuvwxyz-")
        return raw.allSatisfy { allowed.contains($0) } && !raw.isEmpty ? raw : "ad-hoc"
    }

    static func outputDirectory() throws -> URL {
        let attempt = Bundle(for: ResourceAnchor.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = attempt.appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Renders the same screen twice from scratch and requires byte-identical PNG and AX
    /// dump (the task-22 determinism contract), then writes one PNG + one AX file.
    @discardableResult
    static func record(_ kind: ScreenKind, fixture: MatrixFixture, suffix: String = "") throws -> Rendered {
        let first = render(kind, fixture: fixture)
        let pngA = try capturePNG(first.view)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: pngA))
        let backing = first.view.convertToBacking(NSRect(origin: .zero, size: fixture.size))
        XCTAssertEqual(bitmap.pixelsWide, Int(backing.width))
        XCTAssertEqual(bitmap.pixelsHigh, Int(backing.height))
        let axA = axDump(first.view)
        let second = render(kind, fixture: fixture)
        let pngB = try capturePNG(second.view)
        let axB = axDump(second.view)
        close(second)
        XCTAssertEqual(pngA, pngB, "\(kind.rawValue) \(fixture.stem): repeated render must be byte-identical")
        XCTAssertEqual(axA, axB, "\(kind.rawValue) \(fixture.stem): repeated AX dump must be identical")
        let stem = fixture.stem + "-\(kind.rawValue)" + (fixture.stress ? "-stress" : "")
            + (fixture.largeType ? "-large" : "")
            + (fixture.size == NativeLayout.aggregateMinimum ? "" : "-\(Int(fixture.size.width))x\(Int(fixture.size.height))")
            + suffix
        let directory = try outputDirectory()
        try pngA.write(to: directory.appendingPathComponent(stem + ".png"))
        try Data((axA + "\n").utf8).write(to: directory.appendingPathComponent(stem + ".ax.txt"))
        return first
    }

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

// MARK: - Recording destructive ports

actor MatrixReset: CycleResetting {
    private var calls = 0
    let journal: MatrixJournal
    init(journal: MatrixJournal) { self.journal = journal }
    func performCycleReset() async {
        calls += 1
        await journal.record("cycleReset")
    }
    func callCount() -> Int { calls }
}

actor MatrixEraser: LocalDataErasing {
    private var calls = 0
    let journal: MatrixJournal
    init(journal: MatrixJournal) { self.journal = journal }
    func eraseAllLocalData() async {
        calls += 1
        await journal.record("eraseAllLocalData")
    }
    func callCount() -> Int { calls }
}

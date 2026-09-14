#if DEBUG
import AppKit
import SwiftUI
import KeyRecordCore

// DEBUG-only, launch-environment-gated test composition. Release compiles this file to
// nothing; the env token exists nowhere outside DEBUG compilation units.

enum FlowTestComposition {
    static let fixtureKey = "KEYRECORD_FLOW_FIXTURE"
    static let foregroundKey = "KEYRECORD_FLOW_FOREGROUND"
    static let cycleKey = "KEYRECORD_FLOW_CYCLE"
    static let loginRejectKey = "KEYRECORD_FLOW_LOGIN_REJECT"
    static let localeKey = "KEYRECORD_FLOW_LOCALE"

    static var environmentConfigured: Bool {
        !(ProcessInfo.processInfo.environment[fixtureKey] ?? "").isEmpty
    }
    @MainActor static func make() -> FlowFixture? {
        guard let directory = ProcessInfo.processInfo.environment[fixtureKey], !directory.isEmpty else { return nil }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        return try? FlowFixture(directory: url, environment: ProcessInfo.processInfo.environment)
    }
    @MainActor static func boot(_ fixture: FlowFixture) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyRecord")
        item.button?.setAccessibilityIdentifier("menu.open")
        let target = FlowFixtureMenuTarget(fixture: fixture)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = target
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: ""); status.setAccessibilityIdentifier("menu.status"); menu.addItem(status)
        for (id, selector, key) in [("start", #selector(FlowFixtureMenuTarget.start), ""),
                                   ("pause", #selector(FlowFixtureMenuTarget.pause), ""),
                                   ("resume", #selector(FlowFixtureMenuTarget.resume), ""),
                                   ("settings", #selector(FlowFixtureMenuTarget.settings), ","),
                                   ("quit", #selector(FlowFixtureMenuTarget.quit), "q")] {
            let entry = NSMenuItem(title: id, action: selector, keyEquivalent: key)
            entry.target = target; entry.setAccessibilityIdentifier("menu.\(id)"); menu.addItem(entry)
        }
        item.menu = menu
        fixture.showWindow()
        return item
    }
}
final class FlowFixtureJournal: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    init(url: URL) { self.url = url }
    func append(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        let data = Data((event + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else { try? data.write(to: url) }
    }
    static func read(_ url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
actor FileFixturePreferences: PreferencesPersisting {
    let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> Preferences? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
    }
    func save(_ preferences: Preferences) throws {
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
    func erase() { try? FileManager.default.removeItem(at: url) }
}
private actor JournalingKeyAndFlush: LifecycleKeyProviding, LifecycleFlushing {
    let journal: FlowFixtureJournal
    init(journal: FlowFixtureJournal) { self.journal = journal }
    func provisionAfterConsent() { journal.append("keyProvision") }
    func flushWhileUnlocked() { journal.append("flushWhileUnlocked") }
}
actor JournalingCapture: LifecycleCaptureControlling {
    let journal: FlowFixtureJournal
    private(set) var startCount = 0
    init(journal: FlowFixtureJournal) { self.journal = journal }
    func start() { startCount += 1; journal.append("captureStart") }
    func stop() { journal.append("captureStop") }
}
private actor FixedReadiness: RestartReadinessChecking {
    let conditions: RuntimeConditions
    init(conditions: RuntimeConditions) { self.conditions = conditions }
    func verifyRestartReadiness() -> RuntimeConditions { conditions }
}
private actor ConfiguredLogin: LoginItemBackend {
    let journal: FlowFixtureJournal
    let rejects: Bool
    init(journal: FlowFixtureJournal, rejects: Bool) { self.journal = journal; self.rejects = rejects }
    func register() throws {
        if rejects { journal.append("loginRejected"); throw LoginItemSystemRejection.registrationDenied }
        journal.append("loginRegistered")
    }
    func unregister() throws {
        if rejects { journal.append("loginUnrejected"); throw LoginItemSystemRejection.unregistrationDenied }
        journal.append("loginUnregistered")
    }
}
private actor FixedCycleID: CycleIDGenerator {
    let cycleID: CycleID
    init(cycleID: CycleID) { self.cycleID = cycleID }
    func nextCycleID() -> CycleID { cycleID }
}
actor FlowFixtureCycleReset: CycleResetting {
    let journal: FlowFixtureJournal
    private(set) var callCount = 0
    init(journal: FlowFixtureJournal) { self.journal = journal }
    func performCycleReset() { callCount += 1; journal.append("cycleReset") }
}
actor FlowFixtureEraser: LocalDataErasing {
    let journal: FlowFixtureJournal
    let preferences: FileFixturePreferences
    private(set) var callCount = 0
    init(journal: FlowFixtureJournal, preferences: FileFixturePreferences) {
        self.journal = journal; self.preferences = preferences
    }
    func eraseAllLocalData() async {
        callCount += 1
        await preferences.erase()
        journal.append("eraseAllLocalData")
    }
}
@MainActor
final class FlowFixture: ObservableObject {
    @Published var selection = 0
    let orchestrator: LifecycleOrchestrator
    let flow: AppFlowObservable
    let journalURL: URL
    let capture: JournalingCapture
    let reset: FlowFixtureCycleReset
    let eraser: FlowFixtureEraser
    let preferences: FileFixturePreferences
    let foreground: String
    let locale: String
    private var window: NSWindow?

    init(directory: URL, environment: [String: String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        foreground = environment[FlowTestComposition.foregroundKey] ?? "com.example.editor"
        locale = environment[FlowTestComposition.localeKey] ?? "en"
        journalURL = directory.appendingPathComponent("results.journal")
        let journal = FlowFixtureJournal(url: journalURL)
        preferences = FileFixturePreferences(url: directory.appendingPathComponent("preferences.json"))
        let conditions = RuntimeConditions(
            keyAvailability: .available, sessionLock: .unlocked, secureInput: .disabled,
            foreground: .attributable(bundleID: foreground))
        capture = JournalingCapture(journal: journal)
        reset = FlowFixtureCycleReset(journal: journal)
        eraser = FlowFixtureEraser(journal: journal, preferences: preferences)
        let keyAndFlush = JournalingKeyAndFlush(journal: journal)
        orchestrator = LifecycleOrchestrator(ports: LifecyclePorts(
            preferences: preferences, keys: keyAndFlush, capture: capture, flush: keyAndFlush,
            readiness: FixedReadiness(conditions: conditions),
            login: ConfiguredLogin(journal: journal,
                                   rejects: environment[FlowTestComposition.loginRejectKey] == "1"),
            cycleIDs: FixedCycleID(cycleID: CycleID(rawValue: environment[FlowTestComposition.cycleKey]
                                                     ?? "fixture-cycle"))))
        flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: orchestrator,
                                                       cycleReset: reset, localDataEraser: eraser))
        let weakOrchestrator = orchestrator
        flow.actions = FlowActions(
            accept: { [weak self] in await weakOrchestrator.acceptConsent(); self?.observe(locked: false)
                self?.flow.snapshot = try? AggregateSnapshot(rows: []) },
            decline: { weakOrchestrator.denyConsent() },
            start: { [weak self] in
                weakOrchestrator.requestConsent(); await weakOrchestrator.acceptConsent(); self?.observe(locked: false)
            },
            pause: { await weakOrchestrator.pause() },
            resume: { [weak self] in await weakOrchestrator.resume(); self?.observe(locked: false) },
            quit: { await weakOrchestrator.quit() },
            setExclusions: { [weak self] excluded in
                await weakOrchestrator.setExclusions(excluded); self?.observe(locked: false)
            },
            setLoginItem: { await weakOrchestrator.setLoginItem(enabled: $0) },
            loadChoices: { [weak self] in
                guard let self else { return [] }
                let excluded = (try? await self.preferences.load())?.excludedBundleIDs ?? []
                return [AppChoice(bundleID: self.foreground, name: self.foreground,
                                  isExcluded: excluded.contains(self.foreground), isForeground: true)]
            })
    }
    func observe(locked: Bool = false) {
        orchestrator.observe(RuntimeConditions(
            keyAvailability: .available, sessionLock: locked ? .locked : .unlocked,
            secureInput: .disabled, foreground: .attributable(bundleID: foreground)))
    }
    func observeLocked() { observe(locked: true) }
    func showConsentIfNeeded() {
        if orchestrator.state.phase == .unstarted { orchestrator.requestConsent() }
        flow.sync(from: orchestrator.state)
    }
    var journalEvents: [String] { FlowFixtureJournal.read(journalURL) }
    func showWindow() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(origin: .zero, size: NativeLayout.aggregateMinimum),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "KeyRecord flow fixture"; panel.minSize = NativeLayout.minimum
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.contentView = NSHostingView(rootView: FlowFixtureRootView(fixture: self))
            panel.center(); window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class FlowFixtureMenuTarget: NSObject, NSMenuDelegate {
    let fixture: FlowFixture
    init(fixture: FlowFixture) { self.fixture = fixture }
    @objc func start() { Task { @MainActor in await fixture.flow.start() } }
    @objc func pause() { Task { @MainActor in await fixture.flow.pause() } }
    @objc func resume() { Task { @MainActor in await fixture.flow.resume() } }
    @objc func settings() { fixture.selection = 2; fixture.showWindow() }
    @objc func quit() { NSApp.terminate(nil) }
    func menuWillOpen(_ menu: NSMenu) {
        fixture.flow.sync(from: fixture.orchestrator.state)
        let menuState = fixture.flow.menuState
        let enabled: [String: Bool] = ["menu.start": menuState.canStart,
                                        "menu.pause": menuState.canPause, "menu.resume": menuState.canResume]
        for item in menu.items {
            guard let id = item.accessibilityIdentifier() as? String else { continue }
            if id == "menu.status" { item.title = "status.\(menuState.state.rawValue)" }
            else { item.isEnabled = enabled[id] ?? true }
        }
    }
}
struct FlowFixtureRootView: View {
    @ObservedObject var fixture: FlowFixture
    var body: some View {
        let text = NativeText(locale: fixture.locale)
        TabView(selection: $fixture.selection) {
            ConsentFlowView(flow: fixture.flow, text: text).tabItem { Text(text("flowpreview.tab.consent")) }.tag(0)
            AggregateFlowView(snapshot: fixture.flow.snapshot, text: text).tabItem { Text(text("flowpreview.tab.aggregates")) }.tag(1)
            SettingsFlowView(flow: fixture.flow, text: text).tabItem { Text(text("flowpreview.tab.settings")) }.tag(2)
        }
        .padding(NativeLayout.group)
        .frame(minWidth: NativeLayout.minimum.width, minHeight: NativeLayout.minimum.height)
        .onAppear { fixture.showConsentIfNeeded() }.task { await fixture.flow.refresh() }
    }
}
#endif

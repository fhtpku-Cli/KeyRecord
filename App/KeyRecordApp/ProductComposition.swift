import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

@MainActor
final class ProductMaintenanceHooks {
    var stop: () -> Void = {}
    var start: () -> Void = {}
}

@MainActor
final class ProductComposition: NSObject, NSMenuDelegate {
    let lifecycle: LifecycleOrchestrator
    let flow: AppFlowObservable
    let gate: KeyAvailabilityGate
    let reduction: ProductReduction
    let scheduler: FlushScheduler
    let flush: ProductFlush
    let capture: ProductCapture
    let store: ObjectStore
    private var window: NSWindow?
    private var pulse: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    private var text: NativeText { NativeText(locale: flow.language) }

    static func make() async throws -> ProductComposition {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("com.keyrecord.app/store", isDirectory: true)
        let gate = KeyAvailabilityGate()
        let namespace = try KeychainNamespace("com.keyrecord.app")
        // T7 has no qualified system-lock witness. Never replace this boundary with
        // an environment switch, cached unlocked assumption, or fake-success backend.
        let backend = BlockedLiveKeychain()
        let source = ProductKeySource(backend: backend, namespace: namespace, gate: gate)
        let store = ObjectStore(root: root, keySource: source)
        let consent = ProductConsent()
        let keyring = KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace),
            ports: KeyringPorts(backend: backend, entropy: SystemMasterMaterial(), creation: consent,
                                references: store, clock: ProductClock()), gate: gate)
        let clock = SystemFlushClock()
        let writer = SerialObjectWriter(writer: FencedObjectWriter(store: store, gate: gate), clock: clock)
        let persistence = ProductPersistence(store: store, keyring: keyring, consent: consent, gate: gate,
                                             writer: writer, ownedRoot: root)
        let reduction = ProductReduction(gate: gate)
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: clock)
        let queue = CaptureQueue()
        let eventSource = await ListenOnlyEventSource.system(queue: queue, qualification: UnqualifiedCapture())
        let capture = ProductCapture(source: eventSource, queue: queue, reduction: reduction,
            persistence: persistence, scheduler: scheduler, foreground: SystemForegroundProvider())
        let flush = ProductFlush(reduction: reduction, scheduler: scheduler)
        let login = ProductLogin.make()
        let deletion = LocalDeletionCoordinator(ownedRoot: root.path, fileSystem: FileSystemDeletionAdapter(),
            keychain: KeychainDeletionAdapter(keyring: keyring), loginItems: ProductDeletionLogin(login: login))
        let lifecycle = LifecycleOrchestrator(ports: LifecyclePorts(preferences: persistence, keys: persistence,
            capture: capture, flush: flush, readiness: capture, login: login, cycleIDs: ProductCycleIDs()))
        let hooks = ProductMaintenanceHooks()
        let destruction = ProductDestruction(store: store, gate: gate, flush: flush, capture: capture,
            deletion: deletion, scheduler: scheduler, writer: writer, beforeMaintenance: { hooks.stop() },
            afterReset: { await lifecycle.reloadAfterCycleReset(); hooks.start() }, clear: { reduction.clear() })
        let flow = AppFlowObservable(flow: Phase1FlowModel(lifecycle: lifecycle,
            cycleReset: destruction, localDataEraser: destruction))
        return ProductComposition(lifecycle: lifecycle, flow: flow, gate: gate, reduction: reduction,
                                  scheduler: scheduler, flush: flush, capture: capture, store: store, hooks: hooks)
    }

    private init(lifecycle: LifecycleOrchestrator, flow: AppFlowObservable, gate: KeyAvailabilityGate,
                 reduction: ProductReduction, scheduler: FlushScheduler, flush: ProductFlush,
                 capture: ProductCapture, store: ObjectStore, hooks: ProductMaintenanceHooks) {
        self.lifecycle = lifecycle; self.flow = flow; self.gate = gate; self.reduction = reduction
        self.scheduler = scheduler; self.flush = flush; self.capture = capture; self.store = store
        super.init()
        hooks.stop = { [weak self] in
            self?.pulse?.cancel(); self?.pulse = nil
            self?.flow.snapshot = nil
            self?.flow.update(phase: .blocked)
        }
        hooks.start = { [weak self] in self?.sync(); self?.startPulseIfCollecting() }
        flow.actions = FlowActions(
            accept: { [weak self] in await self?.accept() },
            decline: { lifecycle.denyConsent() },
            start: { [weak self] in lifecycle.requestConsent(); self?.showWindow() },
            pause: { [weak self] in await lifecycle.pause(); self?.sync() },
            resume: { [weak self] in await lifecycle.resume(); self?.sync() },
            quit: { [weak self] in await self?.requestQuit() },
            setExclusions: { [weak self] ids in await lifecycle.setExclusions(ids); self?.sync() },
            setLoginItem: { [weak self] enabled in await lifecycle.setLoginItem(enabled: enabled); self?.sync() },
            openSettings: { [weak self] in self?.showWindow() })
        let queue = capture.queue
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil,
                queue: nil) { [weak self, gate, reduction, queue] _ in
                    gate.update(.unknown)
                    queue.revoke()
                    reduction.clear()
                    Task { @MainActor in await self?.closeProtectedState() }
                })
        }
        sync()
    }

    func boot() async -> NSStatusItem {
        await ProductStartup.restore(flow: flow, lifecycle: lifecycle, preferredLanguages: Locale.preferredLanguages)
        sync()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyRecord")
        item.button?.setAccessibilityIdentifier("menu.open")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "BLOCKED — T7", action: nil, keyEquivalent: ""))
        for (key, selector) in [("action.start", #selector(start)), ("action.pause", #selector(pauseCollection)),
                                ("action.resume", #selector(resumeCollection)), ("action.settings", #selector(settings)),
                                ("action.quit", #selector(quit))] {
            let entry = NSMenuItem(title: text(key), action: selector, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        return item
    }

    private func accept() async {
        do { _ = try await capture.verifyRestartReadiness() }
        catch { sync(); return }
        await lifecycle.acceptConsent()
        sync()
        startPulseIfCollecting()
    }

    private func startPulseIfCollecting() {
        guard lifecycle.phase == .collecting else { return }
        pulse?.cancel()
        pulse = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                do {
                    try await self.flush.pulse()
                    self.flow.snapshot = try self.reduction.snapshot()
                }
                catch is CountError {
                    await self.closeProtectedState()
                    self.flow.noticeKey = "flow.actionUnavailable"
                    self.flow.update(phase: .failed)
                    return
                } catch {
                    if !Task.isCancelled { await self.closeProtectedState() }
                    return
                }
            }
        }
    }

    private func sync() {
        flow.sync(from: lifecycle.state)
        if let locale = lifecycle.state.preferences?.locale { flow.language = locale.rawValue }
        switch lifecycle.state.notice {
        case .pauseFlushFailed, .quitFlushFailed: flow.noticeKey = "flow.actionUnavailable"
        default: break
        }
        if (try? gate.begin()) == nil { flow.snapshot = nil; flow.update(phase: .blocked) }
    }

    private func closeProtectedState() async {
        gate.update(.unknown)
        reduction.clear()
        flow.snapshot = nil
        lifecycle.observe(RuntimeConditions(keyAvailability: .unknown, sessionLock: .unknown,
                                            secureInput: .unknown, foreground: .unknown))
        sync()
        await scheduler.close(.unknown)
        await capture.stop()
        await store.closeProtectedSession()
    }

    func requestQuit() async {
        if await prepareQuit() { NSApp.terminate(nil) }
    }

    func prepareQuit() async -> Bool {
        if lifecycle.phase == .unstarted || lifecycle.phase == .consent {
            return true
        }
        await lifecycle.quit()
        sync()
        return lifecycle.phase == .stopped
    }

    @objc private func start() { lifecycle.requestConsent(); showWindow() }
    @objc private func pauseCollection() { Task { await flow.pause() } }
    @objc private func resumeCollection() { Task { await flow.resume() } }
    @objc private func settings() { showWindow() }
    @objc private func quit() { Task { await requestQuit() } }
    func menuWillOpen(_ menu: NSMenu) {
        sync()
        let keys = ["action.start", "action.pause", "action.resume", "action.settings", "action.quit"]
        for (item, key) in zip(menu.items.dropFirst(), keys) { item.title = text(key) }
    }

    private func showWindow() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(origin: .zero, size: NativeLayout.aggregateMinimum),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "KeyRecord"
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.contentView = NSHostingView(rootView: ProductScreens(flow: flow))
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ProductScreens: View {
    @ObservedObject var flow: AppFlowObservable
    private var text: NativeText { NativeText(locale: flow.language) }
    var body: some View {
        TabView {
            ConsentFlowView(flow: flow, text: text).tabItem { Text(text("flowpreview.tab.consent")) }
            AggregateFlowView(snapshot: flow.snapshot, text: text).tabItem { Text(text("flowpreview.tab.aggregates")) }
            SettingsFlowView(flow: flow, text: text).tabItem { Text(text("flowpreview.tab.settings")) }
        }
        .frame(minWidth: NativeLayout.minimum.width, minHeight: NativeLayout.minimum.height)
        .nativeMotionPolicy()
    }
}

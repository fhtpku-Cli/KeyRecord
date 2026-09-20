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

#if DEBUG
/// Injectable seam over the distributed notification centre so lock/unlock observer
/// registration is testable without touching the real system session (KR-01).
@MainActor
protocol LockNotificationCentering {
    func addObserver(for name: Notification.Name, handler: @escaping @MainActor () -> Void) -> any NSObjectProtocol
}

@MainActor
struct DistributedLockNotifications: LockNotificationCentering {
    func addObserver(for name: Notification.Name,
                     handler: @escaping @MainActor () -> Void) -> any NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: nil) { _ in
            Task { @MainActor in handler() }
        }
    }
}
#endif

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
    #if DEBUG
    private(set) var localCapture: LocalDevelopmentCapture?
    private(set) var localSessionLock: (any SessionLockProvider)?
    private var lockNotifications: any LockNotificationCentering = DistributedLockNotifications()
    private var developerMenu: LocalDevelopmentCaptureMenu?
    #endif
    private var exclusionCandidates: any ExclusionCandidateSource = WorkspaceExclusionCandidates()
    private var runtimeCoordinator: CaptureRuntimeCoordinator?
    private let manualRecoveryFence = ManualRecoveryFence()
    #if DEBUG
    /// Batch 6: layered diagnostics. DEBUG-only; Release never constructs it.
    /// Exists because the 2026-09-18 live run ended with capture provably not starting and
    /// zero observable signal to say which layer stopped.
    let diagnostics = CaptureDiagnosticsRecorder()
    #endif
    /// Whether a capture session is currently established. Set only by the paths that
    /// actually start or stop the event source, so the UI cannot infer liveness from
    /// phase or gate state alone (KR-08).
    private(set) var captureSessionLive = false
    private var window: NSWindow?
    private var statusItem: NSMenuItem?
    private var pulse: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    private var text: NativeText { NativeText(locale: flow.language) }

    static func make() async throws -> ProductComposition {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("com.keyrecord.app/store", isDirectory: true)
        let fs = AtomicFileSystem()
        try fs.preparePrivateRoot(at: root.deletingLastPathComponent())
        try fs.preparePrivateRoot(at: root)
        let gate = KeyAvailabilityGate()
        let namespace = try KeychainNamespace("com.keyrecord.app")
        // T7 has no qualified system-lock witness. Never replace this boundary with
        // an environment switch, cached unlocked assumption, or fake-success backend.
        #if DEBUG
        // DEBUG self-use: armed by the persistent Developer menu toggle (UserDefaults)
        // or the KEYRECORD_LOCAL_CAPTURE=1 automation env. Non-armed Debug and all
        // Release builds stay Blocked.
        let backend: any KeychainBackend = LocalDevelopmentCaptureArmament.isArmed
            ? LocalKeychainBackend() : BlockedLiveKeychain()
        #else
        let backend: any KeychainBackend = BlockedLiveKeychain()
        #endif
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
        #if DEBUG
        let localCapture: LocalDevelopmentCapture? = LocalDevelopmentCaptureArmament.isArmed
            ? LocalDevelopmentCapture() : nil
        let qualification: any CaptureQualification = localCapture ?? UnqualifiedCapture()
        let sessionLock: any SessionLockProvider = localCapture == nil
            ? UnqualifiedSessionLockProvider() : SystemSessionLockProvider()
        let eventSource = await ListenOnlyEventSource.system(queue: queue, qualification: qualification,
                                                             sessionLock: sessionLock)
        let capture = ProductCapture(source: eventSource, queue: queue, reduction: reduction,
            persistence: persistence, scheduler: scheduler, foreground: SystemForegroundProvider(),
            qualification: qualification, sessionLock: sessionLock)
        #else
        let eventSource = await ListenOnlyEventSource.system(queue: queue, qualification: UnqualifiedCapture())
        let capture = ProductCapture(source: eventSource, queue: queue, reduction: reduction,
            persistence: persistence, scheduler: scheduler, foreground: SystemForegroundProvider())
        #endif
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
        #if DEBUG
        // KR-01: the session-lock provider is handed to the initializer, NOT assigned after
        // it returns. The old code ran `if let sessionLock = localSessionLock` inside the
        // initializer while the property was still nil, so the screenIsLocked /
        // screenIsUnlocked observers were never registered at all.
        let composition = ProductComposition(lifecycle: lifecycle, flow: flow, gate: gate, reduction: reduction,
                                  scheduler: scheduler, flush: flush, capture: capture, store: store, hooks: hooks,
                                  localCapture: localCapture,
                                  localSessionLock: localCapture == nil ? nil : sessionLock)
        #else
        let composition = ProductComposition(lifecycle: lifecycle, flow: flow, gate: gate, reduction: reduction,
                                  scheduler: scheduler, flush: flush, capture: capture, store: store, hooks: hooks)
        #endif
        #if DEBUG
        reduction.configureDiagnostics(composition.diagnostics)
        await scheduler.setDiagnostics(composition.diagnostics)
        await eventSource.setDiagnostics(composition.diagnostics)
        composition.diagnostics.configureCounterInstrumentation()
        #endif
        return composition
    }

    #if DEBUG
    private init(lifecycle: LifecycleOrchestrator, flow: AppFlowObservable, gate: KeyAvailabilityGate,
                 reduction: ProductReduction, scheduler: FlushScheduler, flush: ProductFlush,
                 capture: ProductCapture, store: ObjectStore, hooks: ProductMaintenanceHooks,
                 localCapture: LocalDevelopmentCapture?, localSessionLock: (any SessionLockProvider)?,
                 notifications: any LockNotificationCentering = DistributedLockNotifications()) {
        self.lifecycle = lifecycle; self.flow = flow; self.gate = gate; self.reduction = reduction
        self.scheduler = scheduler; self.flush = flush; self.capture = capture; self.store = store
        // Assigned BEFORE super.init()/observer registration so the lock wiring below sees them.
        self.localCapture = localCapture
        self.localSessionLock = localSessionLock
        self.lockNotifications = notifications
        super.init()
        installActions(hooks: hooks)
        registerLifecycleObservers(hooks: hooks)
        sync()
    }
    #endif

    #if !DEBUG
    private init(lifecycle: LifecycleOrchestrator, flow: AppFlowObservable, gate: KeyAvailabilityGate,
                 reduction: ProductReduction, scheduler: FlushScheduler, flush: ProductFlush,
                 capture: ProductCapture, store: ObjectStore, hooks: ProductMaintenanceHooks) {
        self.lifecycle = lifecycle; self.flow = flow; self.gate = gate; self.reduction = reduction
        self.scheduler = scheduler; self.flush = flush; self.capture = capture; self.store = store
        super.init()
        installActions(hooks: hooks)
        registerLifecycleObservers(hooks: hooks)
        sync()
    }
    #endif

    private func installActions(hooks: ProductMaintenanceHooks) {
        let lifecycle = self.lifecycle
        hooks.stop = { [weak self] in
            self?.stopPulse()
            self?.flow.snapshot = nil
            self?.flow.update(phase: .blocked)
        }
        hooks.start = { [weak self] in self?.syncRuntime() }
        flow.actions = FlowActions(
            accept: { [weak self] in await self?.accept() },
            decline: { lifecycle.denyConsent() },
            start: { [weak self] in await self?.startOrRetry(); self?.showWindow() },
            pause: { [weak self] in await lifecycle.pause(); await self?.syncRuntimeRefreshingLiveness() },
            resume: { [weak self] in await self?.resume() },
            quit: { [weak self] in await self?.requestQuit() },
            setExclusions: { [weak self] ids in await self?.applyExclusions(ids) },
            setLoginItem: { [weak self] enabled in await lifecycle.setLoginItem(enabled: enabled); self?.syncRuntime() },
            loadChoices: { [weak self] in await self?.loadExclusionChoices() ?? [] },
            openSettings: { [weak self] in self?.showWindow() })
    }

    private func registerLifecycleObservers(hooks: ProductMaintenanceHooks) {
        let gate = self.gate
        let reduction = self.reduction
        let queue = capture.queue
        let manualRecoveryFence = self.manualRecoveryFence
        // Sleep may lock the session, so close capture on sleep. Do NOT close on
        // sessionDidResignActive: that fires whenever the user switches to another app,
        // which is normal foreground use, not a lock. Actual screen-lock transitions are
        // observed separately via development lock-provider notifications (DEBUG) / the
        // qualified host (T7) and must be the only thing that gates capture off mid-session.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: nil
        ) { [weak self, gate, reduction, queue, manualRecoveryFence] _ in
            manualRecoveryFence.invalidate()
            gate.update(.unknown)
            queue.revoke()
            reduction.clear()
            Task { @MainActor in
                self?.lifecycle.requireRecovery(reason: .keyUnavailable)
                await self?.closeProtectedState()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.handleRuntimeAvailable() }
            })
        #if DEBUG
        // KR-01: registration now happens with a non-nil provider, because it was injected
        // into the initializer instead of assigned after the initializer returned.
        guard localSessionLock != nil else { return }
        observers.append(lockNotifications.addObserver(for: Self.screenLockedNotification) { [weak self] in
            Task { @MainActor in await self?.handleSessionLocked() }
        })
        observers.append(lockNotifications.addObserver(for: Self.screenUnlockedNotification) { [weak self] in
            Task { @MainActor in await self?.handleSessionUnlocked() }
        })
        #endif
    }

    #if DEBUG
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    /// Lock/sleep contract: revoke immediately, clear queued events and sensitive
    /// snapshots, close the scheduler and key gate, then stop the source.
    func handleSessionLocked() async {
        manualRecoveryFence.invalidate()
        gate.update(.locked)
        capture.queue.revoke()
        reduction.clear()
        lifecycle.requireRecovery(reason: .sessionLocked)
        await closeProtectedState()
    }

    /// KR-01/lock contract: unlock only exposes an explicit retry path. The key gate stays
    /// closed until that action confirms the user still expects collection and a fresh
    /// lock/readiness check passes.
    func handleSessionUnlocked() async {
        handleRuntimeAvailable()
    }
    #endif

    private func handleRuntimeAvailable() {
        syncRuntime()
    }

    private func startOrRetry() async {
        guard lifecycle.phase == .blocked || lifecycle.phase == .failed else {
            lifecycle.requestConsent()
            return
        }
        if lifecycle.phase == .blocked,
           lifecycle.state.preferences?.expectedCollecting != true {
            syncRuntime()
            return
        }
        await performManualCaptureEntry { [lifecycle] in await lifecycle.retry() }
    }

    private func prepareExplicitCaptureStart(_ attempt: ManualRecoveryAttempt) async -> Bool {
        #if DEBUG
        guard let sessionLock = localSessionLock else {
            gate.update(.unknown)
            lifecycle.requireRecovery(reason: .sessionLocked)
            syncRuntime()
            return false
        }
        let lockState = await sessionLock.sessionLockState()
        guard manualRecoveryFence.isCurrent(attempt) else { return false }
        guard lockState == .unlocked else {
            gate.update(.unknown)
            lifecycle.requireRecovery(reason: .sessionLocked)
            syncRuntime()
            return false
        }
        gate.update(.unlocked)
        _ = await capture.requestInputMonitoringPermission()
        guard manualRecoveryFence.isCurrent(attempt) else { return false }
        await runtimeCoordinator?.clearUserStop()
        return manualRecoveryFence.isCurrent(attempt)
        #else
        gate.update(.unknown)
        lifecycle.requireRecovery(reason: .keyUnavailable)
        syncRuntime()
        return false
        #endif
    }

    private func performManualCaptureEntry(_ start: @MainActor () async -> Void) async {
        let completed = await manualRecoveryFence.perform(
            prepare: { [weak self] attempt in
                await self?.prepareExplicitCaptureStart(attempt) ?? false
            },
            start: start,
            abort: { [weak self] in await self?.abortManualCaptureEntry() })
        if completed, lifecycle.phase != .collecting { gate.update(.unknown) }
        await syncRuntimeRefreshingLiveness()
    }

    private func abortManualCaptureEntry() async {
        await closeProtectedState()
        lifecycle.requireRecovery(reason: .keyUnavailable)
        syncRuntime()
    }

    func boot() async -> NSStatusItem {
        #if DEBUG
        // Prime the gate from the real session-lock state BEFORE restore() reloads
        // preferences (which calls gate.begin()); a locked/unknown Mac stays closed.
        let armed = localCapture != nil
        var observedLock: SessionLockState?
        if armed, let sessionLock = localSessionLock {
            let state = await sessionLock.sessionLockState()
            observedLock = state
            if state == .unlocked { gate.update(.unlocked) }
        }
        // Record the startup inputs that decide whether protected data is readable at all.
        let primed = (try? gate.begin()) != nil
        diagnostics.record {
            $0.armedAtStartup = armed
            $0.lockStateAtStartup = observedLock
            $0.keyGatePrimed = primed
        }
        #endif
        defer {
            #if DEBUG
            // Surface the REAL store error; the orchestrator collapses everything that is
            // not a PreferencesRepositoryError into `.protectedDataUnavailable`.
            let underlying = ProductPersistence.lastLoadFailure
            let gateOpenAtFailure = ProductPersistence.lastLoadGateOpen
            let enumerated = ProductPersistence.lastEnumeratedVersionCount
            diagnostics.record {
                $0.underlyingLoadFailure = underlying
                $0.keyGateOpenAtLoadFailure = gateOpenAtFailure
                $0.enumeratedKeyVersionCount = enumerated
            }
            #endif
        }
        await attachRuntimeCoordinator()
        await ProductStartup.restore(flow: flow, lifecycle: lifecycle, preferredLanguages: Locale.preferredLanguages)
        // KR-03: boot is a path INTO collecting when expectedCollecting was persisted, so
        // it must reconcile pulse ownership like any other entry. Previously only the
        // first-accept path started the pulse, so a restart collected into memory with no
        // periodic flush and no periodic snapshot refresh.
        // KR-08: establish real liveness before the first paint, so the menu bar can never
        // show a stale "Collecting" inherited from the restored preference alone.
        await syncRuntimeRefreshingLiveness()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyRecord")
        item.button?.setAccessibilityIdentifier("menu.open")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        self.statusItem = statusItem
        menu.addItem(statusItem)
        for (key, selector) in [("action.start", #selector(start)), ("action.pause", #selector(pauseCollection)),
                                ("action.resume", #selector(resumeCollection)), ("action.settings", #selector(settings)),
                                ("action.quit", #selector(quit))] {
            let entry = NSMenuItem(title: text(key), action: selector, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        #if DEBUG
        let developerMenu = LocalDevelopmentCaptureMenu(qualification: localCapture, transaction: self)
        developerMenu.diagnosisProvider = { [weak self] in
            self?.diagnostics.snapshot.diagnosis ?? "Diagnosis: unavailable"
        }
        developerMenu.addItems(to: menu)
        self.developerMenu = developerMenu
        #endif
        item.menu = menu
        return item
    }

    private func accept() async {
        // KR-06: the readiness check is NOT duplicated here. The lifecycle's own
        // `.verifyRestartReadiness` effect performs it and writes the returned
        // RuntimeConditions into state. Pre-checking here and discarding the result was
        // exactly what left conditions at `.unknown` while the phase said collecting.
        await performManualCaptureEntry { [lifecycle] in await lifecycle.acceptConsent() }
    }

    private func resume() async {
        await performManualCaptureEntry { [lifecycle] in await lifecycle.resume() }
    }

    /// KR-02: build and attach the single serial recovery coordinator, and route every
    /// typed invalidation from the live event source into it.
    ///
    /// `openSession` deliberately does NOT call `ProductCapture.start()`: that reloads the
    /// aggregate from disk and would discard counted-but-unflushed deltas. Recovery only
    /// recomputes gate inputs from fresh provider reads and re-establishes the session, so
    /// the in-memory increment survives while the generation fence still rejects every
    /// event from the previous session.
    private func attachRuntimeCoordinator() async {
        let capture = self.capture
        let coordinator = CaptureRuntimeCoordinator(
            checks: ProductRuntimeChecks(capture: capture),
            closeSession: { [weak self] in
                await capture.stop()
                // Authoritative: the session is gone, so the UI must stop claiming it.
                await MainActor.run { self?.captureSessionLive = false }
            },
            openSession: { [weak self] _ in
                guard let self else { return false }
                guard let preferences = await self.currentPreferences() else { return false }
                let exclusion = await capture.reapplyPolicy(preferences: preferences)
                // closeSession stopped the source, so recovery must start a new session.
                // reapplyPolicy only recomputes policy; without this the coordinator
                // always observed a dead session and reported startFailed forever.
                var live = await capture.hasLiveSession()
                if !live, exclusion != .unknown {
                    live = await capture.resumeSession(preferences: preferences)
                }
                await MainActor.run {
                    self.captureSessionLive = live
                    #if DEBUG
                    self.diagnostics.record { $0.captureSessionLive = live }
                    #endif
                }
                return exclusion != .unknown && live
            })
        runtimeCoordinator = coordinator
        await capture.source.setInvalidationSink { reason in
            Task { await coordinator.handle(.invalidated(reason)) }
        }
    }

    private func currentPreferences() async -> Preferences? {
        lifecycle.state.preferences
    }

    #if DEBUG
    /// Pulls the coordinator's verdict into diagnostics. Without this, a session the
    /// coordinator closed after a successful start left the reducer in `.collecting`
    /// with no recorded reason, and layer 0 could only say "no reason recorded".
    private func refreshCoordinatorDiagnosis() async {
        // Re-read the lock every refresh: the boot sample goes stale the moment the Mac
        // locks or unlocks, and a stale "locked" is indistinguishable from a real one.
        if let sessionLock = localSessionLock {
            let live = await sessionLock.sessionLockState()
            diagnostics.record { $0.currentLockState = live }
        }
        guard let coordinator = runtimeCoordinator else { return }
        let outcome = await coordinator.statistics().outcome
        let mirrored: CaptureDiagnostics.RuntimeBlockReason?
        switch outcome {
        case .blocked(let reason):
            switch reason {
            case .userStopped: mirrored = .userStopped
            case .notExpectingCollecting: mirrored = .notExpectingCollecting
            case .permissionRequired: mirrored = .permissionRequired
            case .privacyChecksFailed: mirrored = .privacyChecksFailed
            case .startFailed: mirrored = .startFailed
            }
        case .recovered, .coalesced, .none: mirrored = nil
        }
        diagnostics.record { $0.runtimeBlockReason = mirrored }
    }
    #endif

    /// KR-04: the production exclusions picker's real data source. Previously production
    /// `FlowActions` left `loadChoices` at its default empty closure, so the settings list
    /// was permanently empty while previews and UI doubles looked correct.
    ///
    /// Failure to enumerate is surfaced as an explicit notice; it is never presented as
    /// "there are no applications". Saved exclusions still render so they stay removable.
    func loadExclusionChoices() async -> [AppChoice] {
        let excluded = lifecycle.state.preferences?.excludedBundleIDs ?? []
        let foreground = await capture.foregroundBundleID()
        do {
            let running = try exclusionCandidates.runningApplications()
            let choices = ExclusionChoiceMerge.choices(running: running, excluded: excluded,
                                                       foregroundBundleID: foreground)
            if choices.isEmpty { flow.noticeKey = nil }
            return choices
        } catch {
            flow.noticeKey = "flow.actionUnavailable"
            // Fail visibly but keep saved exclusions removable.
            return ExclusionChoiceMerge.choices(running: [], excluded: excluded,
                                                foregroundBundleID: foreground)
        }
    }

    /// KR-04: persist the exclusion set, then propagate it to the REAL runtime policy.
    /// Persisting alone only updated Core/UI, leaving the CaptureQueue still attributing
    /// events to a newly excluded app.
    func applyExclusions(_ ids: Set<String>) async {
        await lifecycle.setExclusions(ids)
        if let runtimeCoordinator {
            // Same serial entry point as every invalidation (KR-02), so an exclusion change
            // cannot race a concurrent foreground/tap recovery.
            await runtimeCoordinator.handle(.exclusionsChanged)
        } else if let preferences = lifecycle.state.preferences {
            await capture.reapplyPolicy(preferences: preferences)
        }
        syncRuntime()
    }

    /// Single place where lifecycle state is mirrored into the UI *and* the pulse is
    /// reconciled. KR-03: the pulse is a resource owned by the collecting phase, not a
    /// side effect of the accept action, so every path that enters or leaves collecting
    /// converges here.
    private func syncRuntime() {
        sync()
        reconcilePulse()
    }

    /// Re-reads liveness from the capture layer, then syncs. Used after any transition that
    /// may have started or torn down the event source.
    private func syncRuntimeRefreshingLiveness() async {
        captureSessionLive = await capture.hasLiveSession()
        #if DEBUG
        await refreshCoordinatorDiagnosis()
        #endif
        syncRuntime()
    }

    /// KR-03: idempotent. Exactly one pulse exists while the lifecycle is collecting and
    /// the key gate is open; none exists otherwise. Repeated calls never create a second
    /// task, and every exit from collecting cancels the current one.
    private func reconcilePulse() {
        let shouldRun = lifecycle.phase == .collecting && (try? gate.begin()) != nil
        guard shouldRun else {
            stopPulse()
            return
        }
        guard pulse == nil else { return }
        pulse = makePulse()
    }

    private func stopPulse() {
        pulse?.cancel()
        pulse = nil
    }

    /// Visible to tests: how many pulse tasks are currently owned (0 or 1, never more).
    var activePulseCount: Int { pulse == nil ? 0 : 1 }

    private func makePulse() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                do {
                    try await self.flush.pulse()
                    // Keep liveness honest without polling the system: this tick already
                    // exists, and a dead session must not keep rendering as Collecting.
                    let live = await self.capture.hasLiveSession()
                    if live != self.captureSessionLive {
                        self.captureSessionLive = live
                        self.sync()
                    }
                    self.flow.snapshot = try self.reduction.snapshot()
                }
                catch is CountError {
                    await self.closeProtectedState()
                    self.flow.noticeKey = "flow.actionUnavailable"
                    self.flow.update(phase: .failed)
                    // The task is ending: release ownership so a later recovery can
                    // rebuild exactly one pulse instead of finding a stale handle.
                    self.releasePulseOwnership()
                    return
                } catch {
                    if !Task.isCancelled { await self.closeProtectedState() }
                    self.releasePulseOwnership()
                    return
                }
            }
        }
    }

    /// Called by a pulse body that is exiting on its own; clears the handle only if it
    /// still refers to a finished task, so a concurrently installed pulse is never dropped.
    private func releasePulseOwnership() {
        if pulse?.isCancelled == false { pulse = nil }
    }

    private func sync() {
        flow.sync(from: lifecycle.state)
        if let locale = lifecycle.state.preferences?.locale { flow.language = locale.rawValue }
        switch lifecycle.state.notice {
        case .pauseFlushFailed, .quitFlushFailed: flow.noticeKey = "flow.actionUnavailable"
        default: break
        }
        let gateOpen = (try? gate.begin()) != nil
        let sessionLive = captureSessionLive
        if !gateOpen || (lifecycle.phase == .collecting && !sessionLive) {
            // Never present sensitive aggregates behind a "Collecting" label that is not
            // backed by a live session.
            flow.snapshot = nil
            flow.update(phase: .blocked)
        }
        statusItem?.title = Self.statusTitle(phase: lifecycle.phase,
                                            reason: lifecycle.state.blockedReason,
                                            gateOpen: gateOpen, captureSessionLive: sessionLive)
        #if DEBUG
        let phase = lifecycle.phase
        let reason = lifecycle.state.blockedReason
        let failure = lifecycle.state.failure
        let visible = flow.sensitiveContentVisible
        let expectedCollecting = lifecycle.state.preferences?.expectedCollecting
        diagnostics.record {
            $0.phase = phase
            $0.blockedReason = reason
            $0.failure = failure
            $0.sensitiveContentVisible = visible
            $0.captureSessionLive = sessionLive
            $0.loadedExpectedCollecting = expectedCollecting
        }
        #endif
    }

    /// Delegates to `CaptureStatusPresentation` in Core (KR-08), so the rule that a
    /// "Collecting" claim requires a live capture session has a single definition and is
    /// testable without the App composition graph.
    static func statusTitle(phase: LifecyclePhase, reason: BlockedReason?, gateOpen: Bool,
                            captureSessionLive: Bool) -> String {
        CaptureStatusPresentation.title(phase: phase, reason: reason, gateOpen: gateOpen,
                                        captureSessionLive: captureSessionLive)
    }

    private func closeProtectedState() async {
        gate.update(.unknown)
        reduction.clear()
        flow.snapshot = nil
        lifecycle.observe(RuntimeConditions(keyAvailability: .unknown, sessionLock: .unknown,
                                            secureInput: .unknown, foreground: .unknown))
        // Leaving the protected state is an exit from collecting: drop the pulse before the
        // scheduler and source close, so no pulse body can write across the fence.
        stopPulse()
        captureSessionLive = false
        sync()
        await scheduler.close(.unknown)
        await capture.stop()
        await store.closeProtectedSession()
    }

    func requestQuit() async {
        if await prepareQuit() { NSApp.terminate(nil) }
    }

    /// Answers `.terminateLater`. Returning false makes AppKit CANCEL termination, so this
    /// must only be false when there is genuinely unsaved work AND the user has been told.
    ///
    /// Live 2026-09-18: two SIGTERMs failed and the process needed SIGKILL. Cause: the app
    /// sat in `.collecting` with no live capture session (KR-08), quit tried to flush a
    /// session that never existed, the flush did not succeed, the reducer correctly refused
    /// to claim `.stopped` (contract 8), and quit was cancelled with nothing surfaced — an
    /// app that cannot be closed.
    ///
    /// A dead source may still leave retained aggregate or staged changes after recovery
    /// fails. Quit may bypass a failed flush only when both stores report no unsaved work.
    func prepareQuit() async -> Bool {
        if lifecycle.phase == .unstarted || lifecycle.phase == .consent {
            return true
        }
        let reductionDirtyBefore = reduction.hasUnflushedChanges()
        let schedulerDirtyBefore = await scheduler.hasPendingChanges()
        await lifecycle.quit()
        syncRuntime()
        if lifecycle.phase == .stopped { return true }
        let reductionDirtyAfter = reduction.hasUnflushedChanges()
        let schedulerDirtyAfter = await scheduler.hasPendingChanges()
        if !reductionDirtyBefore && !schedulerDirtyBefore
            && !reductionDirtyAfter && !schedulerDirtyAfter { return true }
        // Refused: contract 8 forbids claiming the data was saved. Surface why, so the
        // menu bar does not simply appear to ignore Quit.
        flow.noticeKey = "flow.actionUnavailable"
        return false
    }

    @objc private func start() { Task { await startOrRetry(); showWindow() } }
    @objc private func pauseCollection() { Task { await flow.pause() } }
    @objc private func resumeCollection() { Task { await flow.resume() } }
    @objc private func settings() { showWindow() }
    @objc private func quit() { Task { await requestQuit() } }
    func menuWillOpen(_ menu: NSMenu) {
        // KR-08 follow-up: opening the menu must re-READ liveness, not reuse the cached
        // value. The first fix only refreshed the cache on boot/pause/resume/close, so a
        // session that died afterwards still rendered as "Collecting" — the same
        // stale-state bug moved one level down. The menu is repainted asynchronously right
        // after; the synchronous pass below keeps titles correct in the meantime.
        Task { @MainActor in await self.syncRuntimeRefreshingLiveness() }
        syncRuntime()
        let keys = ["action.start", "action.pause", "action.resume", "action.settings", "action.quit"]
        for (item, key) in zip(menu.items.dropFirst(), keys) { item.title = text(key) }
        #if DEBUG
        developerMenu?.refresh()
        #endif
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

#if DEBUG
extension ProductComposition: LocalCaptureTransacting {
    /// KR-05: a real stop. Revoke delivery, drop the pulse, close the scheduler and key
    /// gate, and stop the event source — all before the menu is allowed to read "Off".
    func stopLocalCapture() async {
        manualRecoveryFence.invalidate()
        await runtimeCoordinator?.handle(.userStopped)
        capture.queue.revoke()
        reduction.clear()
        lifecycle.requireRecovery(reason: .keyUnavailable)
        await closeProtectedState()
    }

    /// Re-arming restores eligibility only. Capture is NOT started here, so switching back
    /// On cannot bypass consent, permission, lock, Secure Input or foreground checks; the
    /// user still has to Start/Retry, which runs the full verified-readiness path.
    func rearmLocalCapture() async {
        // Explicit user action re-arms automatic recovery; it does not itself start capture.
        await runtimeCoordinator?.clearUserStop()
        syncRuntime()
    }
}
#endif

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

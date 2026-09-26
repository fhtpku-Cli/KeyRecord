import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

@MainActor
final class ProductMaintenanceHooks {
    var stop: () -> Void = {}
    var start: () -> Void = {}
    var fail: (MaintenanceFailureStage) async -> Void = { _ in }
    var erased: () -> Void = {}
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

/// What one manual capture entry decided. Carries nothing in Release.
@MainActor
final class ManualEntryTrace {
    #if DEBUG
    var detail = CapturePrivacyActionDetail()
    #endif
}

/// Host-facing inputs of the composition. Production fills every field from the system;
/// the wiring in `ProductComposition.assemble` is shared by every caller.
@MainActor
struct ProductHostBoundaries {
    let storeRoot: URL
    let namespace: KeychainNamespace
    let backend: any KeychainBackend
    let login: any LoginItemBackend
    #if DEBUG
    var localCapture: LocalDevelopmentCapture?
    var sessionLock: any SessionLockProvider = UnqualifiedSessionLockProvider()
    var foreground: any FrontmostAppProvider = SystemForegroundProvider()
    var secureInput: any SecureInputProvider = SystemSecureInputProvider()
    var eventSource: @MainActor (CaptureQueue, any CaptureQualification, any SessionLockProvider) async
        -> ListenOnlyEventSource
    var lockNotifications: any LockNotificationCentering = DistributedLockNotifications()
    var terminate: @MainActor () -> Void = { NSApp.terminate(nil) }
    #endif
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
    #if DEBUG
    private(set) var localCapture: LocalDevelopmentCapture?
    private(set) var localSessionLock: (any SessionLockProvider)?
    private var lockNotifications: any LockNotificationCentering = DistributedLockNotifications()
    private var developerMenu: LocalDevelopmentCaptureMenu?
    #endif
    private var exclusionCandidates: any ExclusionCandidateSource = WorkspaceExclusionCandidates()
    private var runtimeCoordinator: CaptureRuntimeCoordinator?
    private let manualRecoveryFence = ManualRecoveryFence()
    private var pausedPrivacyTask: Task<Void, Never>?
    private var secureInputMonitor: Task<Void, Never>?
    /// Bumped whenever the poller is cancelled so an in-flight read cannot act for a later session.
    private var secureInputMonitorGeneration = 0
    /// `hooks.stop` holds runtime tasks while lifecycle may still say `collecting`.
    private var holdRuntimeTasks = false
    /// Set when failed maintenance left the writer or store unable to accept a normal Start.
    private var maintenanceRecovery: MaintenanceFailureStage?
    private var resumeSuspendedWriter: () async throws -> Void = {}
    private var completeRecoveredReset: () async throws -> Bool = { false }
    #if DEBUG
    private(set) var secureInputMonitorStarts = 0
    #endif
    /// Last Secure Input read by the collecting monitor; `.unknown` until the first read.
    private var lastSecureInput: SecureInputState = .unknown
    #if DEBUG
    /// Batch 6: layered diagnostics. DEBUG-only; Release never constructs it.
    /// Exists because the 2026-09-18 live run ended with capture provably not starting and
    /// zero observable signal to say which layer stopped.
    let diagnostics = CaptureDiagnosticsRecorder()
    private var diagnosticSummaryWritten = false
    private var closedIntervalTask: Task<Void, Never>?
    private var systemWitnessTask: Task<Void, Never>?
    private var closingProtectedState = false
    var terminateApplication: @MainActor () -> Void = { NSApp.terminate(nil) }
    #endif
    /// Whether a capture session is currently established. Set only by the paths that
    /// actually start or stop the event source, so the UI cannot infer liveness from
    /// phase or gate state alone (KR-08).
    private(set) var captureSessionLive = false
    private var quitApprovedForTermination = false
    private var window: NSWindow?
    private var statusItem: NSMenuItem?
    private weak var menuBarButton: NSStatusBarButton?
    private var pulse: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    private var text: NativeText { NativeText(locale: flow.language) }

    static func productionStoreRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("com.keyrecord.app/store", isDirectory: true)
    }

    static func make() async throws -> ProductComposition {
        #if DEBUG
        try await assemble(try systemBoundaries(storeRoot: nil, namespace: nil))
        #else
        try await assemble(ProductHostBoundaries(storeRoot: try productionStoreRoot(),
            namespace: try KeychainNamespace("com.keyrecord.app"), backend: BlockedLiveKeychain(),
            login: ProductLogin.make()))
        #endif
    }

    #if DEBUG
    static func makeTrial(storeRoot: URL, namespace: String) async throws -> ProductComposition {
        try await assemble(try systemBoundaries(storeRoot: storeRoot, namespace: namespace))
    }

    /// Hostless tests supply every host boundary; the wiring below is the production wiring.
    static func makeSynthetic(_ boundaries: ProductHostBoundaries) async throws -> ProductComposition {
        try await assemble(boundaries)
    }

    private static func systemBoundaries(storeRoot: URL?, namespace name: String?) throws -> ProductHostBoundaries {
        // T7 has no qualified system-lock witness. Never replace this boundary with
        // an environment switch, cached unlocked assumption, or fake-success backend.
        // DEBUG self-use: armed by the persistent Developer menu toggle (UserDefaults)
        // or the KEYRECORD_LOCAL_CAPTURE=1 automation env. Non-armed Debug and all
        // Release builds stay Blocked.
        let localCapture: LocalDevelopmentCapture? = LocalDevelopmentCaptureArmament.isArmed
            ? LocalDevelopmentCapture() : nil
        let backend: any KeychainBackend = localCapture != nil ? LocalKeychainBackend() : BlockedLiveKeychain()
        return ProductHostBoundaries(
            storeRoot: try storeRoot ?? productionStoreRoot(),
            namespace: try KeychainNamespace(name ?? "com.keyrecord.app"),
            backend: backend, login: ProductLogin.make(),
            localCapture: localCapture,
            sessionLock: localCapture == nil ? UnqualifiedSessionLockProvider() : SystemSessionLockProvider(),
            eventSource: { queue, qualification, sessionLock in
                await ListenOnlyEventSource.system(queue: queue, qualification: qualification,
                                                   sessionLock: sessionLock)
            })
    }
    #endif

    private static func assemble(_ host: ProductHostBoundaries) async throws -> ProductComposition {
        let root = host.storeRoot
        let namespace = host.namespace
        let fs = AtomicFileSystem()
        try fs.preparePrivateRoot(at: root.deletingLastPathComponent())
        try fs.preparePrivateRoot(at: root)
        let gate = KeyAvailabilityGate()
        let backend = host.backend
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
        let localCapture = host.localCapture
        let qualification: any CaptureQualification = localCapture ?? UnqualifiedCapture()
        let sessionLock = host.sessionLock
        let eventSource = await host.eventSource(queue, qualification, sessionLock)
        let capture = ProductCapture(source: eventSource, queue: queue, reduction: reduction,
            persistence: persistence, scheduler: scheduler, foreground: host.foreground,
            secureInput: host.secureInput, qualification: qualification, sessionLock: sessionLock)
        #else
        let eventSource = await ListenOnlyEventSource.system(queue: queue, qualification: UnqualifiedCapture())
        let capture = ProductCapture(source: eventSource, queue: queue, reduction: reduction,
            persistence: persistence, scheduler: scheduler, foreground: SystemForegroundProvider())
        #endif
        let flush = ProductFlush(reduction: reduction, scheduler: scheduler)
        let login = host.login
        let deletion = LocalDeletionCoordinator(ownedRoot: root.path, fileSystem: FileSystemDeletionAdapter(),
            keychain: KeychainDeletionAdapter(keyring: keyring), loginItems: ProductDeletionLogin(login: login))
        let lifecycle = LifecycleOrchestrator(ports: LifecyclePorts(preferences: persistence, keys: persistence,
            capture: capture, flush: flush, readiness: capture, login: login, cycleIDs: ProductCycleIDs()))
        let hooks = ProductMaintenanceHooks()
        let destruction = ProductDestruction(store: store, gate: gate, flush: flush, capture: capture,
            deletion: deletion, scheduler: scheduler, writer: writer, beforeMaintenance: { hooks.stop() },
            afterReset: { await lifecycle.reloadAfterCycleReset(); hooks.start() },
            afterFailure: { stage in await hooks.fail(stage) },
            afterErase: { hooks.erased() }, clear: { reduction.clear() })
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
                                  localSessionLock: localCapture == nil ? nil : sessionLock,
                                  notifications: host.lockNotifications)
        composition.terminateApplication = host.terminate
        #else
        let composition = ProductComposition(lifecycle: lifecycle, flow: flow, gate: gate, reduction: reduction,
                                  scheduler: scheduler, flush: flush, capture: capture, store: store, hooks: hooks)
        #endif
        composition.resumeSuspendedWriter = { try await destruction.resumeWriterIfIdle() }
        composition.completeRecoveredReset = { try await destruction.completeRecoveredReset() }
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
            self?.holdRuntimeTasks = true
            self?.stopPulse()
            self?.stopSecureInputMonitor()
            self?.pausedPrivacyTask?.cancel()
            self?.pausedPrivacyTask = nil
            #if DEBUG
            self?.closedIntervalTask?.cancel()
            self?.closedIntervalTask = nil
            #endif
            self?.flow.snapshot = nil
            self?.flow.update(phase: .blocked)
        }
        hooks.start = { [weak self] in
            self?.maintenanceRecovery = nil
            self?.holdRuntimeTasks = false
            self?.syncRuntime()
        }
        hooks.fail = { [weak self] stage in await self?.recoverAfterFailedMaintenance(stage) }
        hooks.erased = { [weak self] in
            self?.maintenanceRecovery = nil
            self?.holdRuntimeTasks = false
        }
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
        flow.saveLayoutAction = { [weak self] layout in
            try await lifecycle.setLayout(layout)
            self?.syncRuntime()
        }
    }

    private func registerLifecycleObservers(hooks: ProductMaintenanceHooks) {
        let reduction = self.reduction
        let queue = capture.queue
        let manualRecoveryFence = self.manualRecoveryFence
        // Sleep and session resignation are privacy boundaries. Ordinary app switches
        // arrive as foregroundChanged and retain their pending aggregate.
        for notification in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: notification, object: nil, queue: nil
            ) { [weak self, reduction, queue, manualRecoveryFence] notification in
                reduction.revokeProtectedState(queue: queue, recoveryFence: manualRecoveryFence)
                #if DEBUG
                let trigger = notification.name == NSWorkspace.willSleepNotification
                    ? "workspaceWillSleep" : "sessionResigned"
                #endif
                Task { @MainActor in
                    #if DEBUG
                    self?.diagnostics.notePrivacyTrigger(trigger)
                    #endif
                    await self?.handlePrivacyInvalidation()
                }
            })
        }
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
        diagnostics.notePrivacyTrigger("screenLockedNotification")
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

    func startOrRetry() async {
        let trace = ManualEntryTrace()
        #if DEBUG
        let action = await beginTracedAction("start", trace: trace)
        #endif
        guard lifecycle.phase == .blocked || lifecycle.phase == .failed else {
            lifecycle.requestConsent()
            #if DEBUG
            trace.detail.earlyReturn = "not-blocked-or-failed"
            await endTracedAction(action, trace: trace)
            #endif
            return
        }
        if lifecycle.phase == .blocked,
           lifecycle.state.preferences?.expectedCollecting != true {
            syncRuntime()
            #if DEBUG
            trace.detail.earlyReturn = "not-expecting-collecting"
            await endTracedAction(action, trace: trace)
            #endif
            return
        }
        await performManualCaptureEntry(trace: trace) { [lifecycle] in await lifecycle.retry() }
        #if DEBUG
        await endTracedAction(action, trace: trace)
        #endif
    }

    private func prepareExplicitCaptureStart(_ attempt: ManualRecoveryAttempt, trace: ManualEntryTrace) async -> Bool {
        #if DEBUG
        guard let sessionLock = localSessionLock else {
            trace.detail.prepareOutcome = "sessionLockProviderMissing"
            diagnostics.notePrivacyTrigger("sessionLockProviderMissing")
            await handlePrivacyInvalidation()
            return false
        }
        let lockState = await sessionLock.sessionLockState()
        trace.detail.prepareLockRead = String(describing: lockState)
        guard manualRecoveryFence.isCurrent(attempt) else {
            trace.detail.prepareOutcome = "fenceStaleAfterLockRead"
            return false
        }
        guard lockState == .unlocked else {
            trace.detail.prepareOutcome = "lockNotUnlocked"
            diagnostics.notePrivacyTrigger("sessionLockReadNotUnlocked")
            await handlePrivacyInvalidation()
            return false
        }
        gate.update(.unlocked)
        let permission = await capture.requestInputMonitoringPermission()
        trace.detail.permissionStatus = String(describing: permission)
        guard manualRecoveryFence.isCurrent(attempt) else {
            trace.detail.prepareOutcome = "fenceStaleAfterPermission"
            return false
        }
        await runtimeCoordinator?.clearUserStop()
        let current = manualRecoveryFence.isCurrent(attempt)
        trace.detail.prepareOutcome = current ? "ready" : "fenceStaleAfterClearUserStop"
        return current
        #else
        gate.update(.unknown)
        lifecycle.requireRecovery(reason: .keyUnavailable)
        syncRuntime()
        return false
        #endif
    }

    private func performManualCaptureEntry(trace: ManualEntryTrace,
                                           _ start: @MainActor () async -> Void) async {
        holdRuntimeTasks = false
        let completed = await manualRecoveryFence.perform(
            prepare: { [weak self] attempt in
                await self?.prepareExplicitCaptureStart(attempt, trace: trace) ?? false
            },
            start: { [weak self] in
                guard await self?.commitDurableCountsBeforeRestart() == true else {
                    self?.flow.noticeKey = "flow.actionUnavailable"
                    return
                }
                #if DEBUG
                trace.detail.lifecycleCommandRun = true
                #endif
                await start()
            },
            abort: { [weak self] in
                #if DEBUG
                trace.detail.abortRun = true
                #endif
                await self?.abortManualCaptureEntry()
            })
        if completed, lifecycle.phase != .collecting {
            let schedulerPending = await scheduler.hasPendingChanges()
            let unsaved = reduction.hasUnflushedChanges() || schedulerPending
            // Closing the gate would make a failed flush unreadable. Keep it open so the
            // next Start can persist the pending counts instead of discarding them.
            if !unsaved, maintenanceRecovery == nil { gate.update(.unknown) }
        }
        await syncRuntimeRefreshingLiveness()
    }

    private func abortManualCaptureEntry() async {
        await closeProtectedState()
        lifecycle.requireRecovery(reason: .keyUnavailable)
        syncRuntime()
    }

    func boot() async -> NSStatusItem {
        await restoreRuntime()
        return installStatusItem()
    }

    /// Everything `boot` does before the status item exists.
    func restoreRuntime() async {
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
        await ProductStartup.restore(flow: flow, lifecycle: lifecycle, preferredLanguages: Locale.preferredLanguages,
            pausedRestoration: ProductPausedRestoration(gate: gate, reduction: reduction,
                conditions: { [capture] in try await capture.verifyRestartReadiness() },
                load: { [store, gate] cycle in
                    try await AggregatePersistence.restore(cycleID: cycle, store: store, gate: gate)
                }))
        // KR-03: boot is a path INTO collecting when expectedCollecting was persisted, so
        // it must reconcile pulse ownership like any other entry. Previously only the
        // first-accept path started the pulse, so a restart collected into memory with no
        // periodic flush and no periodic snapshot refresh.
        // KR-08: establish real liveness before the first paint, so the menu bar can never
        // show a stale "Collecting" inherited from the restored preference alone.
        await syncRuntimeRefreshingLiveness()
    }

    private func installStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyRecord")
        item.button?.setAccessibilityIdentifier("menu.open")
        menuBarButton = item.button
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
        let trace = ManualEntryTrace()
        #if DEBUG
        let action = await beginTracedAction("accept", trace: trace)
        #endif
        await performManualCaptureEntry(trace: trace) { [lifecycle] in await lifecycle.acceptConsent() }
        #if DEBUG
        await endTracedAction(action, trace: trace)
        #endif
    }

    func resume() async {
        let trace = ManualEntryTrace()
        #if DEBUG
        let action = await beginTracedAction("resume", trace: trace)
        #endif
        await performManualCaptureEntry(trace: trace) { [lifecycle] in await lifecycle.resume() }
        #if DEBUG
        await endTracedAction(action, trace: trace)
        #endif
    }

    #if DEBUG
    private struct TracedAction {
        let name: String
        let id: Int
        let readinessSequence: Int
    }

    private func beginTracedAction(_ name: String, trace: ManualEntryTrace) async -> TracedAction {
        trace.detail.phaseBefore = String(describing: lifecycle.phase)
        let id = diagnostics.beginAction(name, detail: trace.detail)
        return TracedAction(name: name, id: id,
                            readinessSequence: await capture.readinessObservation().sequence)
    }

    /// The readiness result is whatever `verifyRestartReadiness` returned during the action;
    /// `readinessCalls` > 1 means another caller (for example recovery) may have interleaved.
    private func endTracedAction(_ action: TracedAction, trace: ManualEntryTrace) async {
        let readiness = await capture.readinessObservation()
        let calls = readiness.sequence - action.readinessSequence
        trace.detail.readinessCalls = calls
        trace.detail.readinessOutcome = calls > 0 ? readiness.outcome : nil
        trace.detail.phaseAfter = String(describing: lifecycle.phase)
        trace.detail.blockedReasonAfter = lifecycle.state.blockedReason.map { String(describing: $0) }
        trace.detail.failureAfter = lifecycle.state.failure.map { String(describing: $0) }
        trace.detail.sessionLiveAfter = await capture.hasLiveSession()
        trace.detail.keyGateOpenAfter = (try? gate.begin()) != nil
        diagnostics.endAction(action.name, id: action.id, detail: trace.detail)
    }
    #endif

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
            checks: ProductRuntimeChecks(capture: capture, privacyFailed: { [weak self] in
                await self?.handlePrivacyInvalidation()
            }),
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
                    self.diagnostics.notePrivacyInterval()
                    #endif
                }
                return exclusion != .unknown && live
            })
        runtimeCoordinator = coordinator
        let reduction = self.reduction
        let queue = capture.queue
        let recoveryFence = manualRecoveryFence
        await capture.source.setInvalidationSink { [weak self] reason in
            if !reason.allowsAutomaticRecovery {
                reduction.revokeProtectedState(queue: queue, recoveryFence: recoveryFence)
                Task { @MainActor in
                    #if DEBUG
                    self?.diagnostics.notePrivacyTrigger("captureInvalidationNoAutoRecovery")
                    #endif
                    await self?.handlePrivacyInvalidation()
                    await coordinator.handle(.invalidated(reason))
                }
            } else {
                Task { @MainActor in
                    let outcome = await coordinator.handle(.invalidated(reason))
                    await self?.settleFailedRecovery(outcome)
                }
            }
        }
    }

    /// A failed automatic rebuild leaves no session and no trigger that would retry it, so
    /// the lifecycle must stop claiming collecting and hand recovery to an explicit Start.
    /// Retained counts are flushed first; Start reloads the aggregate from disk.
    private func settleFailedRecovery(_ outcome: CaptureRuntimeOutcome) async {
        // While Secure Input is not known to be off, the rebuild is expected to fail and the
        // Secure Input monitor retries once it clears.
        guard outcome == .blocked(.startFailed), lifecycle.phase == .collecting,
              !(await capture.hasLiveSession()) else { return }
        let secureInput = await capture.secureInputState()
        guard secureInput == .disabled else {
            lastSecureInput = secureInput
            return
        }
        try? await flush.flushWhileUnlocked()
        guard lifecycle.phase == .collecting, !(await capture.hasLiveSession()) else { return }
        lifecycle.requireRecovery(reason: .keyUnavailable)
        await syncRuntimeRefreshingLiveness()
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
            await settleFailedRecovery(await runtimeCoordinator.handle(.exclusionsChanged))
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
        reconcilePausedPrivacy()
        reconcileSecureInputMonitor()
        reconcilePulse()
    }

    /// Capture reads Secure Input only when a session starts and macOS posts no change
    /// notification, so a collecting lifecycle polls it. Turning on closes the session at
    /// once; turning off asks the coordinator to rebuild it under fresh checks.
    /// The 250 ms sleep is the polling interval, not a guaranteed maximum response time.
    private func reconcileSecureInputMonitor() {
        guard lifecycle.phase == .collecting, !holdRuntimeTasks else {
            stopSecureInputMonitor()
            return
        }
        guard secureInputMonitor == nil else { return }
        let generation = secureInputMonitorGeneration
        #if DEBUG
        secureInputMonitorStarts += 1
        #endif
        secureInputMonitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let state = await self.capture.secureInputState()
                guard !Task.isCancelled, self.monitorIsCurrent(generation) else { break }
                let previous = self.lastSecureInput
                self.lastSecureInput = state
                let live = await self.capture.hasLiveSession()
                guard self.monitorIsCurrent(generation) else { break }
                if state != .disabled, live || self.flow.sensitiveContentVisible {
                    if live { self.capture.queue.revoke() }
                    self.captureSessionLive = false
                    self.lifecycle.observe(self.lifecycle.state.conditions.with(secureInput: state))
                    #if DEBUG
                    self.diagnostics.notePrivacyTrigger("secureInputMonitor-\(state)")
                    #endif
                    self.syncRuntime()
                    if live {
                        await self.runtimeCoordinator?.handle(.invalidated(.secureInputChanged))
                        guard self.monitorIsCurrent(generation) else { break }
                    }
                    let refreshedLive = await self.capture.hasLiveSession()
                    guard self.monitorIsCurrent(generation) else { break }
                    self.captureSessionLive = refreshedLive
                    self.syncRuntime()
                } else if state == .disabled,
                          (previous != .disabled && !live) || self.lifecycle.state.conditions.secureInput != .disabled {
                    if !live {
                        let outcome = await self.runtimeCoordinator?.handle(.invalidated(.secureInputChanged))
                        guard self.monitorIsCurrent(generation) else { break }
                        if let outcome { await self.settleFailedRecovery(outcome) }
                        guard self.monitorIsCurrent(generation) else { break }
                    }
                    let resumed = await self.capture.hasLiveSession()
                    guard self.monitorIsCurrent(generation) else { break }
                    if resumed {
                        self.lifecycle.observe(self.lifecycle.state.conditions.with(secureInput: .disabled))
                    }
                    self.captureSessionLive = resumed
                    self.syncRuntime()
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
            }
            self?.releaseSecureInputMonitorOwnership(generation)
        }
    }

    private func monitorIsCurrent(_ generation: Int) -> Bool {
        !holdRuntimeTasks && secureInputMonitorGeneration == generation && lifecycle.phase == .collecting
    }

    private func stopSecureInputMonitor() {
        secureInputMonitor?.cancel()
        secureInputMonitor = nil
        lastSecureInput = .unknown
        secureInputMonitorGeneration &+= 1
    }

    /// A poller that exited on its own must drop the handle only if it is still the owner,
    /// matching `releasePulseOwnership`.
    private func releaseSecureInputMonitorOwnership(_ generation: Int) {
        guard secureInputMonitorGeneration == generation else { return }
        secureInputMonitor = nil
    }

    private func recoverAfterFailedMaintenance(_ stage: MaintenanceFailureStage) async {
        maintenanceRecovery = stage == .beforeQuiesce ? nil : stage
        holdRuntimeTasks = false
        captureSessionLive = await capture.hasLiveSession()
        if lifecycle.phase == .collecting, !captureSessionLive {
            // Do not flush here. A failed save is not a reason to drop pending counts, and
            // Start persists them before the scheduler reopen that would discard them.
            lifecycle.requireRecovery(reason: .keyUnavailable)
            await syncRuntimeRefreshingLiveness()
        } else {
            syncRuntime()
        }
    }

    /// Explicit Start/Resume/Accept must not reopen the scheduler over unsaved counts or a
    /// suspended writer. Lock revocation still discards through `closeProtectedState`.
    private func commitDurableCountsBeforeRestart() async -> Bool {
        if maintenanceRecovery == .unfinishedErase { return false }
        switch maintenanceRecovery {
        case .writerBusy, .writerSuspended:
            do {
                try await resumeSuspendedWriter()
                if maintenanceRecovery == .writerBusy || maintenanceRecovery == .writerSuspended {
                    maintenanceRecovery = nil
                }
            } catch {
                maintenanceRecovery = .writerBusy
                return false
            }
        case .unfinishedReset, .unfinishedErase, .beforeQuiesce, nil:
            break
        }
        do {
            if try await completeRecoveredReset() {
                maintenanceRecovery = nil
                holdRuntimeTasks = false
                await syncRuntimeRefreshingLiveness()
            }
            let schedulerPending = await scheduler.hasPendingChanges()
            if reduction.hasUnflushedChanges() || schedulerPending {
                try await flush.flushWhileUnlocked()
            }
        } catch is LifecycleFlushError {
            maintenanceRecovery = .writerBusy
            return false
        } catch {
            maintenanceRecovery = .unfinishedReset
            return false
        }
        return true
    }

    private func reconcilePausedPrivacy() {
        guard lifecycle.phase == .paused, flow.sensitiveContentVisible,
              (try? gate.begin()) != nil else {
            pausedPrivacyTask?.cancel()
            pausedPrivacyTask = nil
            return
        }
        guard pausedPrivacyTask == nil else { return }
        pausedPrivacyTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                let generation = try? self.gate.begin()
                let conditions = try? await self.capture.verifyRestartReadiness()
                guard !Task.isCancelled, self.lifecycle.phase == .paused else { return }
                guard let generation, (try? self.gate.check(generation)) != nil, let conditions,
                      SensitiveVisibility.isVisible(LifecycleState(phase: .paused, conditions: conditions)) else {
                    await self.closeProtectedState()
                    return
                }
                self.lifecycle.observe(conditions)
            }
        }
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
        let shouldRun = lifecycle.phase == .collecting && !holdRuntimeTasks && (try? gate.begin()) != nil
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

    /// Stops the collecting pulse and Secure Input poller and waits until those tasks
    /// leave their current turn. Cancelling alone does not finish a write they already started.
    func stopBackgroundMaintenanceForFixture() async {
        let pulseTask = pulse
        let monitor = secureInputMonitor
        stopPulse()
        stopSecureInputMonitor()
        await pulseTask?.value
        await monitor?.value
    }

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
                    let snapshot = try ProductSnapshotPublication.refresh(
                        flow: self.flow, state: self.lifecycle.state, captureSessionLive: live,
                        readSnapshot: {
                            do { return try self.reduction.snapshot() }
                            catch {
                                #if DEBUG
                                self.diagnostics.recordSnapshotReadFailure()
                                #endif
                                throw error
                            }
                        }, readAnalysis: {
                            guard let preferences = self.lifecycle.state.preferences else { return nil }
                            return try self.reduction.analysis(preferences: preferences)
                        })
                    self.updateRecommendationBadge()
                    #if DEBUG
                    if let snapshot {
                        self.diagnostics.recordPublication(shortcutTotal: snapshot.shortcutTotal,
                                                           bareKeyTotal: snapshot.bareKeyTotal)
                    }
                    #endif
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
        let visible = flow.sensitiveContentVisible
        #if DEBUG
        diagnostics.record {
            $0.phase = lifecycle.phase
            $0.blockedReason = lifecycle.state.blockedReason
            $0.failure = lifecycle.state.failure
            $0.sensitiveContentVisible = visible
            $0.captureSessionLive = sessionLive
            $0.loadedExpectedCollecting = lifecycle.state.preferences?.expectedCollecting
        }
        diagnostics.notePrivacyInterval()
        #endif
        if !gateOpen || (lifecycle.phase == .collecting && !sessionLive) {
            // Never present sensitive aggregates behind a "Collecting" label that is not
            // backed by a live session.
            flow.showCaptureBlocked()
        } else if visible, let preferences = lifecycle.state.preferences {
            #if DEBUG
            diagnostics.endClosedInterval(cause: "protectedDisplayReauthorized")
            #endif
            do {
                try ProductSnapshotPublication.refreshAnalysis(flow: flow) {
                    try reduction.analysis(preferences: preferences)
                }
            }
            catch {
                flow.publishAnalysis(nil)
                flow.noticeKey = "flow.actionUnavailable"
            }
        }
        statusItem?.title = Self.statusTitle(phase: lifecycle.phase,
                                            reason: lifecycle.state.blockedReason,
                                            gateOpen: gateOpen, captureSessionLive: sessionLive)
        if flow.analysis?.topRecommendations.isEmpty == false {
            statusItem?.title += " · " + text("phase2.newRecommendations")
        }
        updateRecommendationBadge()
        #if DEBUG
        if !sessionLive && !visible {
            // Written after revocation, so events already past the gate are not new input.
            diagnostics.beginClosedInterval(cause: closingProtectedState
                                            ? "protectedStateClosed" : "closedStateObserved")
        } else {
            // Normal ends happen earlier, at session start or protected re-display. Reaching
            // here with the interval open means the reopening step had no recorded boundary.
            diagnostics.endClosedInterval(cause: sessionLive
                                          ? "sessionObservedLiveWithoutBoundary" : "visibleWithoutReadBoundary")
        }
        reconcileClosedIntervalJournal()
        #endif
    }

    #if DEBUG
    func enablePrivacyIntervalJournal(path: String) {
        diagnostics.enablePrivacyIntervalJournal(path: path)
    }

    /// Samples counters while a closed interval stays open. It does not read protected data.
    private func reconcileClosedIntervalJournal() {
        guard diagnostics.privacyJournalEnabled, diagnostics.hasOpenClosedInterval else {
            closedIntervalTask?.cancel()
            closedIntervalTask = nil
            return
        }
        guard closedIntervalTask == nil else { return }
        closedIntervalTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, !Task.isCancelled, self.diagnostics.hasOpenClosedInterval else { return }
                let witness = await self.capture.diagnosticInputWitness()
                self.diagnostics.observeClosedInterval(lockReadStatus: witness.lock,
                                                       secureInputReadStatus: witness.secure,
                                                       lockComponents: witness.lockComponents)
            }
        }
    }

    static let systemWitnessLimitSeconds = 300

    /// Explicitly enabled, bounded sampling of the lock and Secure Input providers. It runs
    /// in every phase, including collecting, so it does not depend on the product closing.
    /// It reads only coarse provider states; never protected data or event content.
    @discardableResult
    func startSystemWitness(seconds: Int, interval: Duration = .seconds(1)) -> Bool {
        guard diagnostics.privacyJournalEnabled, seconds > 0,
              seconds <= Self.systemWitnessLimitSeconds, systemWitnessTask == nil else { return false }
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        systemWitnessTask = Task { [weak self] in
            while !Task.isCancelled, ContinuousClock.now < deadline {
                guard let self else { return }
                let read = await self.capture.diagnosticInputWitness()
                let cached = self.lifecycle.state.conditions
                self.diagnostics.recordWitness(lockReadStatus: read.lock, secureInputReadStatus: read.secure,
                    lockComponents: read.lockComponents,
                    cachedLockState: String(describing: cached.sessionLock),
                    cachedSecureInputState: String(describing: cached.secureInput))
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
        return true
    }

    /// One bounded window per launch: a stopped or finished witness is not restarted.
    func stopSystemWitness() {
        systemWitnessTask?.cancel()
    }

    func writeDiagnosticSummaryOnTermination(to path: String?) {
        guard !diagnosticSummaryWritten else { return }
        diagnosticSummaryWritten = true
        do {
            try diagnostics.writeRunSummary(to: path)
        } catch {
            fputs("KeyRecord diagnostic summary write failed\n", stderr)
        }
    }
    #endif

    /// Delegates to `CaptureStatusPresentation` in Core (KR-08), so the rule that a
    /// "Collecting" claim requires a live capture session has a single definition and is
    /// testable without the App composition graph.
    static func statusTitle(phase: LifecyclePhase, reason: BlockedReason?, gateOpen: Bool,
                            captureSessionLive: Bool) -> String {
        CaptureStatusPresentation.title(phase: phase, reason: reason, gateOpen: gateOpen,
                                        captureSessionLive: captureSessionLive)
    }

    private func handlePrivacyInvalidation() async {
        lifecycle.requireRecovery(reason: .sessionLocked)
        await closeProtectedState()
    }

    private func updateRecommendationBadge() {
        let available = flow.analysis?.topRecommendations.isEmpty == false
        menuBarButton?.title = available ? "•" : ""
        menuBarButton?.setAccessibilityLabel(available ? text("phase2.newRecommendations") : text("app.name"))
    }

    private func closeProtectedState() async {
        stopSecureInputMonitor()
        pausedPrivacyTask?.cancel()
        pausedPrivacyTask = nil
        #if DEBUG
        closedIntervalTask?.cancel()
        closedIntervalTask = nil
        #endif
        reduction.revokeProtectedState(queue: capture.queue, recoveryFence: manualRecoveryFence)
        flow.snapshot = nil
        lifecycle.observe(RuntimeConditions(keyAvailability: .unknown, sessionLock: .unknown,
                                            secureInput: .unknown, foreground: .unknown))
        // Leaving the protected state is an exit from collecting: drop the pulse before the
        // scheduler and source close, so no pulse body can write across the fence.
        stopPulse()
        captureSessionLive = false
        #if DEBUG
        closingProtectedState = true
        #endif
        sync()
        #if DEBUG
        closingProtectedState = false
        #endif
        await scheduler.close(.unknown)
        await capture.stop()
        await store.closeProtectedSession()
    }

    func requestQuit() async {
        guard await prepareQuit(invocation: "menu") else { return }
        // `terminate` asks the delegate synchronously inside this main-actor job. A
        // `.terminateLater` reply task could not start until this job ends, which it never
        // does, so the delegate reuses the decision just made.
        quitApprovedForTermination = true
        defer { quitApprovedForTermination = false }
        #if DEBUG
        terminateApplication()
        #else
        NSApp.terminate(nil)
        #endif
    }

    /// AppKit termination entry. Any phase that may still hold unsaved work answers
    /// `.terminateLater` and replies with a fresh `prepareQuit`.
    func terminationReply(_ reply: @escaping @MainActor (Bool) -> Void) -> NSApplication.TerminateReply {
        if quitApprovedForTermination { return .terminateNow }
        guard lifecycle.phase != .stopped, lifecycle.phase != .unstarted,
              lifecycle.phase != .consent else { return .terminateNow }
        Task { reply(await prepareQuit(invocation: "applicationShouldTerminate")) }
        return .terminateLater
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
    func prepareQuit(invocation: String = "menu") async -> Bool {
        #if DEBUG
        var detail = CapturePrivacyActionDetail()
        detail.invocation = invocation
        detail.phaseBefore = String(describing: lifecycle.phase)
        let action = diagnostics.beginAction("quit", detail: detail)
        let flushBefore = await flush.lifecycleFlushObservation()
        #endif
        if lifecycle.phase == .unstarted || lifecycle.phase == .consent {
            #if DEBUG
            detail.earlyReturn = "not-started"
            detail.quitDecision = "terminate"
            await endQuitAction(action, detail: detail, flushBefore: flushBefore)
            #endif
            return true
        }
        let reductionDirtyBefore = reduction.hasUnflushedChanges()
        let schedulerDirtyBefore = await scheduler.hasPendingChanges()
        #if DEBUG
        detail.reductionUnsavedBefore = reductionDirtyBefore
        detail.schedulerUnsavedBefore = schedulerDirtyBefore
        #endif
        await lifecycle.quit()
        syncRuntime()
        if lifecycle.phase == .stopped {
            #if DEBUG
            detail.quitDecision = "terminate"
            await endQuitAction(action, detail: detail, flushBefore: flushBefore)
            #endif
            return true
        }
        let reductionDirtyAfter = reduction.hasUnflushedChanges()
        let schedulerDirtyAfter = await scheduler.hasPendingChanges()
        #if DEBUG
        detail.reductionUnsavedAfter = reductionDirtyAfter
        detail.schedulerUnsavedAfter = schedulerDirtyAfter
        #endif
        if !reductionDirtyBefore && !schedulerDirtyBefore
            && !reductionDirtyAfter && !schedulerDirtyAfter {
            #if DEBUG
            detail.quitDecision = "terminate"
            await endQuitAction(action, detail: detail, flushBefore: flushBefore)
            #endif
            return true
        }
        // Refused: contract 8 forbids claiming the data was saved. Surface why, so the
        // menu bar does not simply appear to ignore Quit.
        flow.noticeKey = "flow.actionUnavailable"
        #if DEBUG
        detail.quitDecision = "cancel"
        await endQuitAction(action, detail: detail, flushBefore: flushBefore)
        #endif
        return false
    }

    #if DEBUG
    private func endQuitAction(_ id: Int, detail: CapturePrivacyActionDetail,
                               flushBefore: ProductLifecycleFlushObservation) async {
        var detail = detail
        let flushAfter = await flush.lifecycleFlushObservation()
        let calls = flushAfter.invocations - flushBefore.invocations
        detail.lifecycleFlushCalls = calls
        detail.lifecycleFlushOutcome = calls > 0 ? flushAfter.lastOutcome : "notInvoked"
        detail.noticeAfter = lifecycle.state.notice.map { String(describing: $0) }
        detail.phaseAfter = String(describing: lifecycle.phase)
        detail.blockedReasonAfter = lifecycle.state.blockedReason.map { String(describing: $0) }
        detail.failureAfter = lifecycle.state.failure.map { String(describing: $0) }
        detail.sessionLiveAfter = await capture.hasLiveSession()
        detail.keyGateOpenAfter = (try? gate.begin()) != nil
        diagnostics.endAction("quit", id: id, detail: detail)
    }
    #endif

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
            AnalysisDashboardView(snapshot: flow.analysis, layout: flow.layout, text: text,
                                  saveLayout: { await flow.saveLayout($0) })
                .tabItem { Text(text("flowpreview.tab.aggregates")) }
            SettingsFlowView(flow: flow, text: text).tabItem { Text(text("flowpreview.tab.settings")) }
        }
        .frame(minWidth: NativeLayout.minimum.width, minHeight: NativeLayout.minimum.height)
        .nativeMotionPolicy()
    }
}

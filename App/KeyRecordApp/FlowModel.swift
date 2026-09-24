import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore

@MainActor
enum ProductStartup {
    static func restore(flow: AppFlowObservable, lifecycle: LifecycleOrchestrator,
                        preferredLanguages: [String], pausedRestoration: ProductPausedRestoration? = nil) async {
        await lifecycle.reload()
        ProductLanguage.bind(flow: flow, lifecycle: lifecycle, preferredLanguages: preferredLanguages)
        await pausedRestoration?.restore(flow: flow, lifecycle: lifecycle)
        flow.sync(from: lifecycle.state)
        if lifecycle.state.failure != nil { flow.noticeKey = "flow.actionUnavailable" }
    }
}

@MainActor
struct ProductPausedRestoration {
    let gate: KeyAvailabilityGate
    let reduction: ProductReduction
    let conditions: () async throws -> RuntimeConditions
    let load: (CycleID) async throws -> AggregationReducer

    func restore(flow: AppFlowObservable, lifecycle: LifecycleOrchestrator) async {
        guard lifecycle.phase == .paused, let preferences = lifecycle.state.preferences,
              !preferences.expectedCollecting else { return }
        do {
            let generation = try gate.begin()
            let before = try await conditions()
            guard SensitiveVisibility.isVisible(LifecycleState(phase: .paused, conditions: before)) else {
                throw KeyringError.locked
            }
            let aggregate = try await load(preferences.currentCycleID)
            let after = try await conditions()
            guard lifecycle.phase == .paused, lifecycle.state.preferences == preferences else { return }
            guard SensitiveVisibility.isVisible(LifecycleState(phase: .paused, conditions: after)) else {
                throw KeyringError.locked
            }
            try gate.check(generation)
            try Task.checkCancellation()
            try reduction.restoreReadOnly(aggregate, generation: generation)
            lifecycle.observe(after)
            _ = try ProductSnapshotPublication.refresh(flow: flow, state: lifecycle.state,
                captureSessionLive: false, readSnapshot: { try reduction.snapshot() },
                readAnalysis: { try reduction.analysis(preferences: preferences) })
        } catch {
            guard lifecycle.phase == .paused, lifecycle.state.preferences == preferences else { return }
            reduction.clear()
            lifecycle.observe(.unknown)
            flow.snapshot = nil
            flow.noticeKey = "flow.actionUnavailable"
        }
    }
}

@MainActor
enum ProductLanguage {
    static func bind(flow: AppFlowObservable, lifecycle: LifecycleOrchestrator,
                     preferredLanguages: [String]) {
        let fallback = lifecycle.state.failure == nil
            ? (preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en") : flow.language
        flow.language = lifecycle.state.preferences?.locale.rawValue ?? fallback
        flow.actions.setLanguage = { [weak flow] code in
            guard let flow else { return }
            do {
                guard let locale = ProductLocale(rawValue: code) else {
                    throw PreferencesRepositoryError.storageUnavailable
                }
                try await lifecycle.setLocale(locale)
            } catch {
                flow.noticeKey = "flow.actionUnavailable"
            }
            flow.language = lifecycle.state.preferences?.locale.rawValue ?? fallback
        }
    }
}

// MARK: - Menu-bar value state

/// Pure menu snapshot: the SwiftUI menu and previews take this value, never a controller.
struct MenuBarState: Equatable {
    public let state: PrimitiveState
    init(state: PrimitiveState) { self.state = state }

    var canStart: Bool { state == .unstarted }
    var canPause: Bool { state == .collecting }
    var canResume: Bool { state == .paused }
}

extension PrimitiveState {
    /// Maps the 12 lifecycle phases onto the five task-10 status words. Busy phases
    /// present the steady state they are entering/leaving; reopen is a blocked context.
    init(phase: LifecyclePhase) {
        switch phase {
        case .unstarted, .consent: self = .unstarted
        case .collecting, .starting, .resuming: self = .collecting
        case .paused, .pausing, .stopping, .stopped: self = .paused
        case .reopening, .blocked: self = .blocked
        case .failed: self = .error
        }
    }
}

// MARK: - Excluded applications picker data

struct AppChoice: Identifiable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let isExcluded: Bool
    public let isForeground: Bool

    init(bundleID: String, name: String, isExcluded: Bool, isForeground: Bool) {
        self.bundleID = bundleID
        self.name = name
        self.isExcluded = isExcluded
        self.isForeground = isForeground
    }
    var id: String { bundleID }
}

// MARK: - Composition-root intents

/// Product wiring is attached by the AppDelegate composition root (T19); defaults are
/// no-ops so screens and previews compile and run without capture or storage.
struct FlowActions {
    var accept: @MainActor () async -> Void
    var decline: @MainActor () -> Void
    var start: @MainActor () async -> Void
    var pause: @MainActor () async -> Void
    var resume: @MainActor () async -> Void
    var quit: @MainActor () async -> Void
    var setExclusions: @MainActor (Set<String>) async -> Void
    var setLoginItem: @MainActor (Bool) async -> Void
    var setLanguage: @MainActor (String) async -> Void
    var loadChoices: @MainActor () async -> [AppChoice]
    var openSettings: @MainActor () -> Void

    init(
        accept: @escaping @MainActor () async -> Void = { @MainActor in },
        decline: @escaping @MainActor () -> Void = { @MainActor in },
        start: @escaping @MainActor () async -> Void = { @MainActor in },
        pause: @escaping @MainActor () async -> Void = { @MainActor in },
        resume: @escaping @MainActor () async -> Void = { @MainActor in },
        quit: @escaping @MainActor () async -> Void = { @MainActor in },
        setExclusions: @escaping @MainActor (Set<String>) async -> Void = { @MainActor _ in },
        setLoginItem: @escaping @MainActor (Bool) async -> Void = { @MainActor _ in },
        setLanguage: @escaping @MainActor (String) async -> Void = { @MainActor _ in },
        loadChoices: @escaping @MainActor () async -> [AppChoice] = { @MainActor in [] },
        openSettings: @escaping @MainActor () -> Void = { @MainActor in }
    ) {
        self.accept = accept
        self.decline = decline
        self.start = start
        self.pause = pause
        self.resume = resume
        self.quit = quit
        self.setExclusions = setExclusions
        self.setLoginItem = setLoginItem
        self.setLanguage = setLanguage
        self.loadChoices = loadChoices
        self.openSettings = openSettings
    }
}

// MARK: - Screen observable

@MainActor
enum ProductSnapshotPublication {
    @discardableResult
    static func refresh(flow: AppFlowObservable, state: LifecycleState,
                        captureSessionLive: Bool,
                        readSnapshot: () throws -> AggregateSnapshot?,
                        readAnalysis: () throws -> AnalysisSnapshot?) throws -> AggregateSnapshot? {
        flow.sync(from: state)
        let deadSession = state.phase == .collecting && !captureSessionLive
        guard SensitiveVisibility.isVisible(state), !deadSession else {
            flow.snapshot = nil
            if deadSession { flow.showCaptureBlocked() }
            return nil
        }
        let snapshot = try readSnapshot()
        flow.snapshot = snapshot
        if state.preferences != nil {
            try refreshAnalysis(flow: flow, read: readAnalysis)
        }
        return snapshot
    }

    static func refreshAnalysis(flow: AppFlowObservable,
                                read: () throws -> AnalysisSnapshot?) throws {
        do { flow.publishAnalysis(try read()) }
        catch is AnalysisError {
            flow.publishAnalysis(nil)
            flow.noticeKey = "flow.actionUnavailable"
        }
    }
}

@MainActor
final class AppFlowObservable: ObservableObject {
    @Published private(set) var dialog: FlowDialog = .none
    @Published private(set) var state: PrimitiveState = .unstarted
    @Published private(set) var choices: [AppChoice] = []
    @Published var loginItemEnabled = false
    @Published var loginItemErrorKey: String?
    @Published var language = "en"
    @Published var noticeKey: String?
    @Published private var rawAnalysis: AnalysisSnapshot?
    @Published private(set) var layout = LayoutPreference()
    var saveLayoutAction: (@MainActor (LayoutPreference) async throws -> Void)?

    private let flow: Phase1FlowModel
    var actions: FlowActions

    init(flow: Phase1FlowModel, actions: FlowActions = FlowActions()) {
        self.flow = flow
        self.actions = actions
        flow.onChange = { [weak self] in self?.mirror() }
        mirror()
    }

    var menuState: MenuBarState { MenuBarState(state: state) }

    /// Gating stays in Core: a locked/error context reads nil even with raw totals set.
    var snapshot: AggregateSnapshot? {
        get { flow.displayedAggregate }
        set {
            if newValue == nil { rawAnalysis = nil }
            flow.displayedAggregate = newValue
        }
    }

    var analysis: AnalysisSnapshot? { sensitiveContentVisible ? rawAnalysis : nil }

    func publishAnalysis(_ snapshot: AnalysisSnapshot?) {
        rawAnalysis = sensitiveContentVisible ? snapshot : nil
    }

    func saveLayout(_ preset: LayoutPreset) async {
        guard sensitiveContentVisible, let saveLayoutAction else { return }
        let selected = LayoutPreference(preset: preset, hasAsked: true)
        do {
            try await saveLayoutAction(selected)
            layout = selected
        } catch { noticeKey = "flow.actionUnavailable" }
    }

    var sensitiveContentVisible: Bool { flow.sensitiveContentVisible }

    func update(phase: LifecyclePhase, loginItemEnabled: Bool = false,
                       loginItemErrorKey: String? = nil) {
        state = PrimitiveState(phase: phase)
        self.loginItemEnabled = loginItemEnabled
        self.loginItemErrorKey = loginItemErrorKey
        mirror()
    }

    func showCaptureBlocked() {
        snapshot = nil
        // Paused intent still needs the explicit Resume action after privacy teardown.
        if state != .paused { state = .blocked }
        mirror()
    }

    /// Composition-root mirror after an orchestrator transition: the reducer keeps
    /// deciding login rejection wording; the observable only exposes its localized key.
    func sync(from lifecycleState: LifecycleState) {
        layout = lifecycleState.preferences?.layout ?? LayoutPreference()
        if !SensitiveVisibility.isVisible(lifecycleState) { rawAnalysis = nil }
        state = PrimitiveState(phase: lifecycleState.phase)
        loginItemEnabled = lifecycleState.loginItem == .registered
        loginItemErrorKey = LoginItemPolicy.rejection(from: lifecycleState.notice) != nil
            ? "settings.login.error" : nil
        mirror()
    }

    func accept() async { await actions.accept(); await refresh() }
    func decline() { actions.decline(); mirror() }
    func start() async { await actions.start(); await refresh() }
    func pause() async { await actions.pause(); await refresh() }
    func resume() async { await actions.resume(); await refresh() }
    func quit() async { await actions.quit(); await refresh() }
    func openSettings() { actions.openSettings() }

    func requestReset() { flow.requestReset(); mirror() }
    func requestDeleteLocalData() { flow.requestDeleteLocalData(); mirror() }

    func choose(_ choice: DialogChoice) async {
        do {
            try await flow.choose(choice)
        } catch FlowError.actionUnavailable {
            noticeKey = "flow.actionUnavailable"
        } catch {
            noticeKey = "flow.actionUnavailable"
        }
        mirror()
    }

    func setExclusion(bundleID: String, enabled: Bool) async {
        var excluded = Set(choices.filter(\.isExcluded).map(\.bundleID))
        if enabled { excluded.insert(bundleID) } else { excluded.remove(bundleID) }
        await actions.setExclusions(excluded)
        await refresh()
    }

    func setLoginItem(enabled: Bool) async {
        await actions.setLoginItem(enabled)
        await refresh()
    }

    func setLanguage(_ code: String) async {
        await actions.setLanguage(code)
    }

    func dismissNotice() { noticeKey = nil }

    func refresh() async {
        choices = await actions.loadChoices()
        mirror()
    }

    private func mirror() {
        if !sensitiveContentVisible { rawAnalysis = nil }
        dialog = flow.dialog
        objectWillChange.send()
    }
}

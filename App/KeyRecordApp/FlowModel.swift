import SwiftUI
import KeyRecordCore

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
    var loadChoices: @MainActor () -> [AppChoice]
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
        loadChoices: @escaping @MainActor () -> [AppChoice] = { @MainActor in [] },
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
final class AppFlowObservable: ObservableObject {
    @Published private(set) var dialog: FlowDialog = .none
    @Published private(set) var state: PrimitiveState = .unstarted
    @Published private(set) var choices: [AppChoice] = []
    @Published var loginItemEnabled = false
    @Published var loginItemErrorKey: String?
    @Published var language = "en"
    @Published var noticeKey: String?

    private let flow: Phase1FlowModel
    private let actions: FlowActions

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
        set { flow.displayedAggregate = newValue }
    }

    var sensitiveContentVisible: Bool { flow.sensitiveContentVisible }

    func update(phase: LifecyclePhase, loginItemEnabled: Bool = false,
                       loginItemErrorKey: String? = nil) {
        state = PrimitiveState(phase: phase)
        self.loginItemEnabled = loginItemEnabled
        self.loginItemErrorKey = loginItemErrorKey
        mirror()
    }

    func accept() async { await actions.accept(); refresh() }
    func decline() { actions.decline(); refresh() }
    func start() async { await actions.start(); refresh() }
    func pause() async { await actions.pause(); refresh() }
    func resume() async { await actions.resume(); refresh() }
    func quit() async { await actions.quit(); refresh() }
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
        refresh()
    }

    func setLoginItem(enabled: Bool) async {
        await actions.setLoginItem(enabled)
        refresh()
    }

    func setLanguage(_ code: String) async {
        language = code
        await actions.setLanguage(code)
    }

    func dismissNotice() { noticeKey = nil }

    func refresh() {
        choices = actions.loadChoices()
        mirror()
    }

    private func mirror() {
        dialog = flow.dialog
        choices = actions.loadChoices()
        objectWillChange.send()
    }
}

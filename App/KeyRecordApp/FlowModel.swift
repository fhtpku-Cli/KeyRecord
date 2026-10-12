import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore
import KeyRecordMappings

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
enum StatisticsSection: String, Hashable {
    case overview, candidates, settings
}

/// Session-only attention for newly displayable Top 5 items. Cold start records the
/// current set without treating it as new. Privacy closure drops the pending marker
/// and does not expose identities or counts.
struct RecommendationAttention: Equatable {
    private(set) var established = false
    private var seen: Set<String> = []
    private(set) var hasUnseen = false

    mutating func observe(topIDs: [String], contentVisible: Bool, currentlyViewing: Bool) {
        guard contentVisible else {
            hasUnseen = false
            return
        }
        let current = Set(topIDs)
        if !established {
            seen = current
            established = true
            hasUnseen = false
            return
        }
        if currentlyViewing {
            seen.formUnion(current)
            hasUnseen = false
            return
        }
        let fresh = current.subtracting(seen)
        if !fresh.isEmpty { hasUnseen = true }
        if current.isEmpty { hasUnseen = false }
    }

    mutating func markRecommendationAreaOpened(topIDs: [String]) {
        seen.formUnion(topIDs)
        hasUnseen = false
        if !established {
            established = true
        }
    }
}

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
            flow.noticeKey = "phase2.analysisUnavailable"
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
    @Published private(set) var ignoredRecommendationKeys: Set<String> = []
    @Published private(set) var keyboardPoolConfirmed: Set<KeyCode> = []
    @Published var statisticsSection: StatisticsSection = .overview
    @Published var intendedBackend: RecommendationBackend = .karabiner
    let viaImport = VIAImportModel()
    let karabinerImport = KarabinerImportModel()
    let karabinerMappings = KarabinerMappingModel()
    lazy var karabinerDeployment = KarabinerDeploymentModel(mappings: karabinerMappings)
    let firmwareCopies = FirmwareCopiesModel()

    var candidateConflictEvidence: CandidateConflictEvidence {
        let observations = snapshot.map { snapshot in
            snapshot.rows.compactMap { row -> ChordBucket? in
                guard row.total > 0, case .shortcut(let bucket) = row.identity else { return nil }
                return bucket
            }
        }
        return CandidateConflictEvidence(observations: observations,
            backendRules: intendedBackend == .karabiner ? karabinerImport.evidence : nil,
            profile: intendedBackend == .karabiner ? karabinerImport.profile : nil)
    }
    /// First-run consent stays available when a closed key gate forces the status to blocked.
    @Published private(set) var awaitingConsent = false
    @Published private(set) var hasSavedPreferences = false
    var showsConsent: Bool { !hasSavedPreferences }
    @Published var statisticsWindowOpen = false
    @Published private(set) var canUndoIgnoreChange = false
    private var recommendationAttention = RecommendationAttention()
    private var presentationCycleID: CycleID?
    private var ignoreUndoBaseline: Set<String>?
    private var pendingIgnoreChange: Task<Void, Never>?
    private var pendingKeyboardPoolChange: Task<Void, Never>?

    private enum IgnoreChange {
        case ignore(String), restore(String), undo
    }
    var saveLayoutAction: (@MainActor (LayoutPreference) async throws -> Void)?
    var saveIgnoredAction: (@MainActor (Set<String>) async throws -> Void)?
    var saveKeyboardPoolAction: (@MainActor (Set<KeyCode>) async throws -> Void)?
    #if DEBUG
    private var diagnostics: CaptureDiagnosticsRecorder?

    func configureDiagnostics(_ recorder: CaptureDiagnosticsRecorder) {
        diagnostics = recorder
    }
    #endif

    private let flow: Phase1FlowModel
    private let protectedGate: KeyAvailabilityGate?
    private var snapshotGeneration: CaptureGeneration?
    private var analysisGeneration: CaptureGeneration?
    var actions: FlowActions

    init(flow: Phase1FlowModel, actions: FlowActions = FlowActions(),
         protectedGate: KeyAvailabilityGate? = nil) {
        self.flow = flow
        self.actions = actions
        self.protectedGate = protectedGate
        viaImport.protectedGate = protectedGate
        viaImport.canRead = { [weak self] in self?.sensitiveContentVisible == true }
        viaImport.onChange = { [weak self] in self?.objectWillChange.send() }
        karabinerImport.protectedGate = protectedGate
        karabinerImport.canRead = { [weak self] in self?.sensitiveContentVisible == true }
        karabinerImport.onChange = { [weak self] in self?.karabinerMappings.invalidate(); self?.objectWillChange.send() }
        karabinerMappings.canRead = { [weak self] in self?.sensitiveContentVisible == true }
        karabinerMappings.protectedGate = protectedGate
        karabinerMappings.configuration = { [weak self] in self?.karabinerDeployment.selectedConfiguration ?? self?.karabinerImport.selectedConfiguration }
        karabinerMappings.observations = { [weak self] in self?.candidateConflictEvidence.observations }
        karabinerMappings.synchronizeRuntime = { [weak self] in self?.karabinerDeployment.updateObservations() }
        karabinerMappings.onChange = { [weak self] in self?.objectWillChange.send() }
        karabinerDeployment.canRead = { [weak self] in self?.sensitiveContentVisible == true }
        karabinerDeployment.observations = { [weak self] in self?.candidateConflictEvidence.observations }
        karabinerDeployment.onChange = { [weak self] in self?.objectWillChange.send() }
        firmwareCopies.canRead = { [weak self] in self?.sensitiveContentVisible == true }
        firmwareCopies.selectedOriginal = { [weak self] in self?.viaImport.selectedOriginalBytes }
        firmwareCopies.onChange = { [weak self] in self?.objectWillChange.send() }
        karabinerMappings.defaultName = { [weak self] chord, scope in
            let text = NativeText(locale: self?.language ?? "en")
            let target = if case .application(let app) = scope { app } else { text("phase2.global") }
            return AnalysisLabels.chord(chord, text: text) + " · " + target
        }
        flow.onChange = { [weak self] in self?.mirror() }
        mirror()
    }

    var menuState: MenuBarState { MenuBarState(state: state) }

    var snapshot: AggregateSnapshot? {
        get { readPresentation(snapshotGeneration) { flow.displayedAggregate } }
        set {
            guard let visible = newValue else {
                snapshotGeneration = nil
                analysisGeneration = nil
                rawAnalysis = nil
                flow.displayedAggregate = nil
                noteRecommendations([])
                return
            }
            if !publishPresentation({ generation in
                snapshotGeneration = generation
                flow.displayedAggregate = visible
                #if DEBUG
                diagnostics?.recordPublication(shortcutTotal: visible.shortcutTotal, bareKeyTotal: visible.bareKeyTotal)
                #endif
            }) {
                snapshotGeneration = nil
                flow.displayedAggregate = nil
            }
        }
    }

    var analysis: AnalysisSnapshot? { readPresentation(analysisGeneration) { rawAnalysis } }

    func publishAnalysis(_ snapshot: AnalysisSnapshot?) {
        guard let snapshot else {
            rawAnalysis = nil
            analysisGeneration = nil
            noteRecommendations([])
            return
        }
        if let presentationCycleID, snapshot.cycleID != presentationCycleID {
            rawAnalysis = nil
            analysisGeneration = nil
            noteRecommendations([])
            return
        }
        if !publishPresentation({ generation in
            analysisGeneration = generation
            rawAnalysis = snapshot
            #if DEBUG
            diagnostics?.recordAnalysisPublication()
            #endif
        }) {
            rawAnalysis = nil
            analysisGeneration = nil
        }
        if noticeKey == "phase2.analysisUnavailable", rawAnalysis != nil { noticeKey = nil }
        noteRecommendations(analysis?.topRecommendations.map(\.id) ?? [])
    }

    var hasUnseenRecommendations: Bool { recommendationAttention.hasUnseen }

    func statisticsMenuTitle(_ text: NativeText) -> String {
        guard sensitiveContentVisible, recommendationAttention.hasUnseen else { return text("action.statistics") }
        return text("phase2.newRecommendations")
    }

    func presentStatistics() {
        statisticsSection = .overview
        statisticsWindowOpen = true
        markRecommendationsReviewed()
    }

    func presentAllCandidates() {
        statisticsSection = .candidates
        statisticsWindowOpen = true
        markRecommendationsReviewed()
    }

    func presentSettings() {
        statisticsSection = .settings
        statisticsWindowOpen = true
    }

    func markRecommendationsReviewed() {
        recommendationAttention.markRecommendationAreaOpened(topIDs: analysis?.topRecommendations.map(\.id) ?? [])
        objectWillChange.send()
    }

    func saveLayout(_ preset: LayoutPreset) async {
        guard sensitiveContentVisible, let saveLayoutAction else {
            if sensitiveContentVisible { noticeKey = "phase2.preferenceSaveFailed" }
            return
        }
        let selected = LayoutPreference(preset: preset, hasAsked: true)
        let previous = layout
        do {
            try await saveLayoutAction(selected)
            layout = selected
            if noticeKey == "phase2.preferenceSaveFailed" { noticeKey = nil }
        } catch {
            layout = previous
            noticeKey = "phase2.preferenceSaveFailed"
        }
    }

    func ignoreRecommendation(_ id: String) async {
        await enqueueIgnoreChange(.ignore(id))
    }

    func setFunctionKey(_ key: KeyCode, confirmed: Bool) async {
        guard sensitiveContentVisible, LogicalPreviews.functionKeyValues.contains(key.value) else { return }
        let generation: CaptureGeneration?
        do { generation = try protectedGate?.begin() }
        catch { return }
        let cycle = presentationCycleID
        let previous = pendingKeyboardPoolChange
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            @MainActor func isCurrent() -> Bool {
                guard self.sensitiveContentVisible, self.presentationCycleID == cycle else { return false }
                if let generation { return (try? self.protectedGate?.check(generation)) != nil }
                return true
            }
            guard isCurrent() else { return }
            guard let save = self.saveKeyboardPoolAction else {
                self.noticeKey = "phase2.preferenceSaveFailed"
                return
            }
            var next = self.keyboardPoolConfirmed
            if confirmed { next.insert(key) } else { next.remove(key) }
            do {
                try await save(next)
                guard isCurrent() else { return }
                self.keyboardPoolConfirmed = next
                if self.noticeKey == "phase2.preferenceSaveFailed" { self.noticeKey = nil }
            } catch {
                if isCurrent() { self.noticeKey = "phase2.preferenceSaveFailed" }
            }
        }
        pendingKeyboardPoolChange = task
        await task.value
    }

    func restoreRecommendation(_ id: String) async {
        await enqueueIgnoreChange(.restore(id))
    }

    func undoIgnoredRecommendationChange() async {
        await enqueueIgnoreChange(.undo)
    }

    private func enqueueIgnoreChange(_ change: IgnoreChange) async {
        let previous = pendingIgnoreChange
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.sensitiveContentVisible else { return }
            switch change {
            case .ignore(let id):
                var next = self.ignoredRecommendationKeys
                next.insert(id)
                await self.replaceIgnoredRecommendations(next)
            case .restore(let id):
                var next = self.ignoredRecommendationKeys
                next.remove(id)
                await self.replaceIgnoredRecommendations(next)
            case .undo:
                await self.applyIgnoreUndo()
            }
        }
        pendingIgnoreChange = task
        await task.value
    }

    private func applyIgnoreUndo() async {
        guard sensitiveContentVisible, let baseline = ignoreUndoBaseline, let saveIgnoredAction else { return }
        do {
            try await saveIgnoredAction(baseline)
            ignoredRecommendationKeys = baseline
            ignoreUndoBaseline = nil
            canUndoIgnoreChange = false
            if noticeKey == "phase2.preferenceSaveFailed" { noticeKey = nil }
        } catch {
            noticeKey = "phase2.preferenceSaveFailed"
        }
    }

    private func replaceIgnoredRecommendations(_ keys: Set<String>) async {
        guard sensitiveContentVisible, let saveIgnoredAction else {
            if sensitiveContentVisible { noticeKey = "phase2.preferenceSaveFailed" }
            return
        }
        let previous = ignoredRecommendationKeys
        do {
            try await saveIgnoredAction(keys)
            ignoreUndoBaseline = previous
            canUndoIgnoreChange = true
            ignoredRecommendationKeys = keys
            if noticeKey == "phase2.preferenceSaveFailed" { noticeKey = nil }
        } catch {
            ignoredRecommendationKeys = previous
            noticeKey = "phase2.preferenceSaveFailed"
        }
    }

    private func noteRecommendations(_ topIDs: [String], contentVisible: Bool? = nil) {
        let visible = contentVisible ?? sensitiveContentVisible
        let viewing = statisticsWindowOpen && statisticsSection != .settings && visible
        recommendationAttention.observe(topIDs: topIDs, contentVisible: visible, currentlyViewing: viewing)
    }

    var sensitiveContentVisible: Bool {
        flow.sensitiveContentVisible && (protectedGate.map { (try? $0.begin()) != nil } ?? true)
    }

    private func readPresentation<T>(_ generation: CaptureGeneration?, _ read: () -> T?) -> T? {
        guard flow.sensitiveContentVisible else { return nil }
        func observed() -> T? {
            #if DEBUG
            return ProtectedReadActivity.process.observe(.aggregate, read)
            #else
            return read()
            #endif
        }
        guard let protectedGate else { return observed() }
        guard let generation else { return nil }
        return try? protectedGate.use(generation, body: observed)
    }

    private func publishPresentation(_ publish: (CaptureGeneration?) -> Void) -> Bool {
        guard flow.sensitiveContentVisible else { return false }
        guard let protectedGate else { publish(nil); return true }
        do {
            let generation = try protectedGate.begin()
            try protectedGate.use(generation) { publish(generation) }
            return true
        } catch { return false }
    }

    func update(phase: LifecyclePhase, loginItemEnabled: Bool = false,
                       loginItemErrorKey: String? = nil) {
        state = PrimitiveState(phase: phase)
        awaitingConsent = phase == .unstarted || phase == .consent
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
        hasSavedPreferences = lifecycleState.preferences != nil
        layout = lifecycleState.preferences?.layout ?? LayoutPreference()
        let visible = SensitiveVisibility.isVisible(lifecycleState)
        if visible {
            ignoredRecommendationKeys = lifecycleState.preferences?.ignoredRecommendationKeys ?? []
            keyboardPoolConfirmed = lifecycleState.preferences?.keyboardPoolConfirmed ?? []
        } else {
            ignoredRecommendationKeys = []
            keyboardPoolConfirmed = []
            viaImport.clear()
            karabinerImport.clear()
            karabinerMappings.clear()
            ignoreUndoBaseline = nil
            canUndoIgnoreChange = false
            rawAnalysis = nil
        }
        let cycle = lifecycleState.preferences?.currentCycleID
        if let presentationCycleID, presentationCycleID != cycle {
            rawAnalysis = nil
            analysisGeneration = nil
        }
        presentationCycleID = cycle
        if !visible { noteRecommendations([], contentVisible: false) }
        state = PrimitiveState(phase: lifecycleState.phase)
        awaitingConsent = lifecycleState.phase == .unstarted || lifecycleState.phase == .consent
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
        karabinerDeployment.visibilityChanged(sensitiveContentVisible)
        if sensitiveContentVisible { karabinerDeployment.updateObservations() }
        if !sensitiveContentVisible { firmwareCopies.clear() }
        if !sensitiveContentVisible { rawAnalysis = nil; viaImport.clear(); karabinerImport.clear(); karabinerMappings.clear() }
        dialog = flow.dialog
        objectWillChange.send()
    }
}

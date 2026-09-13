#if DEBUG
import SwiftUI
import KeyRecordCore

@MainActor
private final class PreviewLifecycleDriver: LifecycleDriving {
    var state: LifecycleState
    var onRearmed: (() -> Void)?

    init(state: LifecycleState) { self.state = state }

    func returnToConsentRequired() async {
        state = .initial
        onRearmed?()
    }
}

@MainActor
private final class PreviewChoicesStore {
    private static let namesByBundle = [
        "com.example.editor": "preview.app.editor",
        "com.example.chat": "preview.app.chat",
    ]
    private(set) var items: [AppChoice]

    init(locale: String) {
        items = [
            AppChoice(bundleID: "com.example.editor",
                      name: PreviewChoicesStore.name("com.example.editor", locale: locale),
                      isExcluded: false, isForeground: true),
            AppChoice(bundleID: "com.example.chat",
                      name: PreviewChoicesStore.name("com.example.chat", locale: locale),
                      isExcluded: true, isForeground: false),
        ]
    }

    func apply(excluded: Set<String>) {
        items = items.map {
            AppChoice(bundleID: $0.bundleID, name: $0.name,
                      isExcluded: excluded.contains($0.bundleID), isForeground: $0.isForeground)
        }
    }

    func localize(_ locale: String) {
        items = items.map {
            AppChoice(bundleID: $0.bundleID,
                      name: PreviewChoicesStore.name($0.bundleID, locale: locale),
                      isExcluded: $0.isExcluded, isForeground: $0.isForeground)
        }
    }

    private static func name(_ bundleID: String, locale: String) -> String {
        NativeText(locale: locale)(namesByBundle[bundleID] ?? bundleID)
    }
}

private actor PreviewCycleReset: CycleResetting {
    func performCycleReset() async {}
}

private actor PreviewLocalDataEraser: LocalDataErasing {
    func eraseAllLocalData() async {}
}

@MainActor
final class FlowPreviewBox: ObservableObject {
    let flow: AppFlowObservable
    private let driver: PreviewLifecycleDriver
    private let choicesStore: PreviewChoicesStore

    init() {
        let driver = PreviewLifecycleDriver(state: FlowPreviewBox.collecting())
        self.driver = driver
        let store = PreviewChoicesStore(locale: "en")
        choicesStore = store
        let coreFlow = Phase1FlowModel(lifecycle: driver,
                                       cycleReset: PreviewCycleReset(),
                                       localDataEraser: PreviewLocalDataEraser())
        flow = AppFlowObservable(flow: coreFlow, actions: FlowActions(
            accept: { [weak driver] in driver?.state = FlowPreviewBox.collecting() },
            decline: { [weak driver] in driver?.state = .initial },
            start: { [weak driver] in driver?.state = FlowPreviewBox.collecting() },
            pause: { [weak driver] in driver?.state = LifecycleState(phase: .paused) },
            resume: { [weak driver] in driver?.state = FlowPreviewBox.collecting() },
            quit: { [weak driver] in driver?.state = LifecycleState(phase: .stopped) },
            setExclusions: { [weak store] excluded in store?.apply(excluded: excluded) },
            setLanguage: { [weak store] code in store?.localize(code) },
            loadChoices: { [weak store] in store?.items ?? [] }
        ))
        flow.refresh()
        flow.snapshot = FlowPreviewBox.makeSnapshot()
        driver.onRearmed = { [weak self] in self?.sync() }
    }

    func sync() { flow.update(phase: driver.state.phase) }

    func restart() {
        driver.state = .initial
        sync()
    }

    func setLocked(_ locked: Bool) {
        if locked {
            driver.state = LifecycleState.blockedForRetry(
                preferences: Preferences(currentCycleID: CycleID(rawValue: "preview-cycle")),
                reason: .sessionLocked)
        } else {
            driver.state = FlowPreviewBox.collecting()
        }
        sync()
    }

    func setLocale(_ locale: String) {
        choicesStore.localize(locale)
        flow.refresh()
    }

    static func collecting() -> LifecycleState {
        var gate = PrivacyGate()
        gate.update(GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
                               secureInput: .disabled,
                               foreground: .attributable(bundleID: "com.example.editor"),
                               exclusion: .included))
        return LifecycleState(phase: .collecting, gate: gate)
    }

    static func makeSnapshot() -> AggregateSnapshot {
        let cycle = CycleID(rawValue: "preview-cycle")
        let day = LocalDay("2026-09-13")
        let command = ModifierSet(command: .both, option: .none, control: .none, shift: .none, fn: .none)
        let shiftCommand = ModifierSet(command: .both, option: .none, control: .none, shift: .both, fn: .none)
        func bucket(_ code: Int, _ modifiers: ModifierSet) -> ChordBucket {
            ChordBucket(chord: Chord(keyCode: try! KeyCode(code), modifiers: modifiers),
                        appBucket: code == 48 ? .unknown : .bundleID("com.example.editor"))
        }
        func shortcut(_ code: Int, _ modifiers: ModifierSet, _ ordinary: Int64, _ suspected: Int64)
            -> DailyShortcutAggregate {
                DailyShortcutAggregate(cycleID: cycle, day: day, identity: bucket(code, modifiers),
                    classification: ChordRuleTable.v1.classify(bucket(code, modifiers).chord),
                    sourceCounts: try! SourceCounts(ordinary: Count(ordinary), suspectedInjection: Count(suspected)))
        }
        let shortcuts = [shortcut(48, command, 12, 0), shortcut(20, shiftCommand, 3, 0),
                         shortcut(8, command, 5, 2)]
        let bareKeys = [
            DailyBareKeyAggregate(cycleID: cycle, day: day, keyCode: try! KeyCode(99),
                                  sourceCounts: try! SourceCounts(ordinary: Count(7), suspectedInjection: Count(0))),
        ]
        return try! AggregateSnapshot(shortcuts: shortcuts, bareKeys: bareKeys)
    }
}

struct FlowPreviewGallery: View {
    @StateObject private var box = FlowPreviewBox()
    @State private var locale = "en"
    @State private var locked = false

    var body: some View {
        let text = NativeText(locale: locale)
        VStack(spacing: NativeLayout.group) {
            HStack(spacing: NativeLayout.group) {
                Text(text("flowpreview.title")).font(.title2)
                Spacer()
                Picker(text("harness.locale"), selection: Binding(
                    get: { locale },
                    set: { locale = $0; box.setLocale($0) }
                )) {
                    Text(text("locale.en")).tag("en")
                    Text(text("locale.zh-Hans")).tag("zh-Hans")
                }.accessibilityIdentifier("preview.locale")
                Toggle(text("preview.locked"), isOn: Binding(
                    get: { locked },
                    set: { locked = $0; box.setLocked($0) }
                )).accessibilityIdentifier("preview.locked.toggle")
                Button(text("preview.restart")) { box.restart() }
                    .accessibilityIdentifier("preview.restart")
            }
            TabView {
                ConsentFlowView(flow: box.flow, text: text)
                    .tabItem { Text(text("flowpreview.tab.consent")) }.tag(0)
                VStack(alignment: .leading, spacing: NativeLayout.group) {
                    MenuBarMenu(flow: box.flow, text: text)
                    Divider()
                    MenuBarMenuContent(flow: box.flow, text: text)
                }.tabItem { Text(text("flowpreview.tab.menu")) }.tag(1)
                AggregateFlowView(snapshot: box.flow.snapshot, text: text)
                    .tabItem { Text(text("flowpreview.tab.aggregates")) }.tag(2)
                SettingsFlowView(flow: box.flow, text: text)
                    .tabItem { Text(text("flowpreview.tab.settings")) }.tag(3)
            }
        }
        .padding(NativeLayout.page)
        .frame(width: NativeLayout.aggregateMinimum.width,
               height: NativeLayout.aggregateMinimum.height)
        .environment(\.locale, Locale(identifier: locale))
    }
}
#endif

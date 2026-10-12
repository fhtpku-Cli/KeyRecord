import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

// MARK: - Settings flow screen

struct SettingsFlowView: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Form {
            if flow.sensitiveContentVisible {
                Section {
                    AnalysisLayoutControls(layout: flow.layout, ask: flow.analysis?.shouldAskLayout == true && !flow.layout.hasAsked,
                                           text: text, noticeKey: flow.noticeKey == "phase2.preferenceSaveFailed" ? flow.noticeKey : nil,
                                           saveLayout: { await flow.saveLayout($0) })
                } header: {
                    Text(text("phase2.layout"))
                }
                FunctionKeyPoolSection(flow: flow, text: text)
                Section {
                    Picker(text("phase2.backendChoice"), selection: $flow.intendedBackend) {
                        Text("Karabiner").tag(RecommendationBackend.karabiner)
                        Text("VIA").tag(RecommendationBackend.via)
                        Text("Vial").tag(RecommendationBackend.vial)
                    }
                    Text(text("phase2.backendDisconnected"))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text("phase2.backendSession"))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(text("phase2.backend"))
                }
                if flow.intendedBackend == .karabiner {
                    KarabinerImportSection(model: flow.karabinerImport, text: text)
                    KarabinerDeploymentSection(model: flow.karabinerDeployment,
                        selectedProfile: flow.karabinerImport.selectedConfiguration?.profile, text: text)
                    KarabinerMappingSection(model: flow.karabinerMappings, text: text)
                } else { VIAImportSection(model: flow.viaImport, text: text) }
                FirmwareCopiesSection(model: flow.firmwareCopies, viaBytes: flow.viaImport.selectedOriginalBytes, text: text)
            }
            Section {
                Text(text("consent.disclosure")).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.consent")
            } header: {
                Text(text("settings.consent"))
            }
            ExcludedApplicationsSection(flow: flow, text: text)
            LoginItemSection(flow: flow, text: text)
            LanguageSection(flow: flow, text: text)
            DangerSection(flow: flow, text: text)
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("settings.form")
        .task { await flow.refresh() }
        .sheet(isPresented: dialogPresented) {
            FlowDialogView(flow: flow, text: text)
        }
        .nativeMotionPolicy()
    }

    private var dialogPresented: Binding<Bool> {
        Binding(get: { flow.dialog != .none },
                set: { presented in
                    guard !presented else { return }
                    Task { @MainActor in await flow.choose(.cancel) }
                })
    }
}

private struct FunctionKeyPoolSection: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Section {
            Text(text("phase2.keyPoolNotice"))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.keyPool.notice")
            Text(text("phase2.functionKeys"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), alignment: .leading)], alignment: .leading) {
                ForEach(Array(LogicalPreviews.functionKeyValues.enumerated()), id: \.element) { index, value in
                    if let key = try? KeyCode(value) {
                        Toggle("F\(index + 1)", isOn: Binding(
                            get: { flow.keyboardPoolConfirmed.contains(key) },
                            set: { confirmed in
                                Task { @MainActor in await flow.setFunctionKey(key, confirmed: confirmed) }
                            }))
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("settings.keyPool.\(value)")
                    }
                }
            }
        } header: {
            Text(text("phase2.keyPool"))
        }
    }
}

// MARK: - Excluded applications

private struct ExcludedApplicationsSection: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Section {
            if flow.choices.isEmpty {
                Text(text("settings.exclusions.none"))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.exclusions.empty")
            } else {
                ForEach(Array(flow.choices.enumerated()), id: \.element.id) { index, choice in
                    Toggle(isOn: Binding(
                        get: { choice.isExcluded },
                        set: { enabled in
                            Task { @MainActor in await flow.setExclusion(bundleID: choice.bundleID, enabled: enabled) }
                        }
                    )) {
                        HStack(spacing: NativeLayout.compact) {
                            Text(choice.name)
                            if choice.isForeground {
                                Label(text("exclusions.foreground"), systemImage: "eye")
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption)
                                    .accessibilityIdentifier("settings.exclusions.foreground")
                            }
                        }
                    }
                    .accessibilityLabel(Text(choice.isForeground
                        ? "\(choice.name), \(text("exclusions.foreground"))" : choice.name))
                    .accessibilitySortPriority(Double(flow.choices.count - index + 4))
                    .accessibilityIdentifier("settings.exclusions.\(choice.bundleID)")
                }
            }
        } header: {
            Text(text("settings.exclusions"))
        }
    }
}

// MARK: - Login item

private struct LoginItemSection: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { flow.loginItemEnabled },
                set: { enabled in Task { @MainActor in await flow.setLoginItem(enabled: enabled) } }
            )) {
                Text(text("settings.login"))
            }
            .accessibilityLabel(Text(text("settings.login")))
            .accessibilitySortPriority(4)
            .accessibilityIdentifier("settings.login")
            if let errorKey = flow.loginItemErrorKey {
                Label(text(errorKey), systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("settings.login.error")
            }
        } header: {
            Text(text("settings.login"))
        }
    }
}

// MARK: - Language

private struct LanguageSection: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Section {
            Picker(text("settings.language"), selection: Binding(
                get: { flow.language },
                set: { code in Task { @MainActor in await flow.setLanguage(code) } }
            )) {
                Text(text("locale.en")).tag("en")
                Text(text("locale.zh-Hans")).tag("zh-Hans")
            }
            .focusable()
            .accessibilitySortPriority(3)
            .accessibilityIdentifier("settings.language")
        } header: {
            Text(text("settings.language"))
        }
    }
}

// MARK: - Danger zone

private struct DangerSection: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Section {
            if let noticeKey = flow.noticeKey {
                Text(text(noticeKey)).font(.caption).foregroundStyle(.primary)
                    .accessibilityIdentifier("flow.notice")
            }
            SettingsRow(text: text, titleKey: "settings.reset",
                        rowIdentifier: "settings.reset") {
                flow.requestReset()
            }
            .accessibilitySortPriority(2)
            SettingsRow(text: text, titleKey: "settings.delete",
                        rowIdentifier: "settings.delete", role: .destructive) {
                flow.requestDeleteLocalData()
            }
            .accessibilitySortPriority(1)
        } header: {
            Label(text("settings.danger"), systemImage: "exclamationmark.triangle")
        }
    }
}

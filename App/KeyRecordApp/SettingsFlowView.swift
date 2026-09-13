import SwiftUI
import KeyRecordCore

// MARK: - Settings flow screen

struct SettingsFlowView: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Form {
            ExcludedApplicationsSection(flow: flow, text: text)
            LoginItemSection(flow: flow, text: text)
            LanguageSection(flow: flow, text: text)
            DangerSection(flow: flow, text: text)
        }
        .formStyle(.grouped)
        .frame(minWidth: NativeLayout.minimum.width,
               minHeight: NativeLayout.minimum.height)
        .accessibilityIdentifier("settings.form")
        .sheet(isPresented: dialogPresented) {
            FlowDialogView(flow: flow, text: text)
        }
    }

    private var dialogPresented: Binding<Bool> {
        Binding(get: { flow.dialog != .none },
                set: { presented in
                    guard !presented else { return }
                    Task { @MainActor in await flow.choose(.cancel) }
                })
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
                ForEach(flow.choices) { choice in
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
            .accessibilityIdentifier("settings.login")
            if let errorKey = flow.loginItemErrorKey {
                Label(text(errorKey), systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text(text(noticeKey)).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("flow.notice")
            }
            SettingsRow(text: text, titleKey: "settings.reset",
                        rowIdentifier: "settings.reset") {
                flow.requestReset()
            }
            SettingsRow(text: text, titleKey: "settings.delete",
                        rowIdentifier: "settings.delete", role: .destructive) {
                flow.requestDeleteLocalData()
            }
        } header: {
            Label(text("settings.danger"), systemImage: "exclamationmark.triangle")
        }
    }
}

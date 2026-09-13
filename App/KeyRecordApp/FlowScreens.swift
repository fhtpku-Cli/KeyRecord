import SwiftUI
import KeyRecordCore

// MARK: - Consent flow

struct ConsentFlowView: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        ConsentPanel(text: text, action: {})
            .environment(\.primitiveActionObserver) { identifier in
                switch identifier {
                case "consent.accept":
                    Task { @MainActor in await flow.accept() }
                case "consent.reject":
                    flow.decline()
                default:
                    break
                }
            }
    }
}

// MARK: - Reset / delete confirmation dialog

struct FlowDialogView: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        dialogContent
            .frame(minWidth: 420)
            .padding(NativeLayout.page)
    }

    @ViewBuilder private var dialogContent: some View {
        switch flow.dialog {
        case .none:
            EmptyView()
        case .resetConfirmation(let proposal):
            confirmation(proposal, systemImage: "arrow.counterclockwise.circle")
        case .deleteConfirmation(let proposal):
            confirmation(proposal, systemImage: "trash")
        }
    }

    private func confirmation(_ proposal: ResetProposal, systemImage: String) -> some View {
        DestructiveConfirmation(text: text, action: { Task { @MainActor in await flow.choose(.confirm) } },
                                titleKey: proposal.titleKey, messageKey: proposal.messageKey,
                                confirmKey: proposal.confirmKey, cancelKey: proposal.cancelKey,
                                panelIdentifier: "dialog.panel", messageIdentifier: "dialog.message",
                                confirmIdentifier: "dialog.confirm", cancelIdentifier: "dialog.cancel",
                                systemImage: systemImage,
                                onCancel: { Task { @MainActor in await flow.choose(.cancel) } })
    }

    private func confirmation(_ proposal: DeleteProposal, systemImage: String) -> some View {
        DestructiveConfirmation(text: text, action: { Task { @MainActor in await flow.choose(.confirm) } },
                                titleKey: proposal.titleKey, messageKey: proposal.messageKey,
                                confirmKey: proposal.confirmKey, cancelKey: proposal.cancelKey,
                                panelIdentifier: "dialog.panel", messageIdentifier: "dialog.message",
                                confirmIdentifier: "dialog.confirm", cancelIdentifier: "dialog.cancel",
                                systemImage: systemImage,
                                onCancel: { Task { @MainActor in await flow.choose(.cancel) } })
    }
}

// MARK: - Menu-bar menu

struct MenuBarMenuContent: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        let menu = flow.menuState
        CaptureStatus(state: menu.state, text: text)
        Button(text("action.start")) { Task { @MainActor in await flow.start() } }
            .disabled(!menu.canStart).accessibilityIdentifier("menu.start")
        Button(text("action.pause")) { Task { @MainActor in await flow.pause() } }
            .disabled(!menu.canPause).accessibilityIdentifier("menu.pause")
        Button(text("action.resume")) { Task { @MainActor in await flow.resume() } }
            .disabled(!menu.canResume).accessibilityIdentifier("menu.resume")
        Divider()
        Button(text("action.settings")) { flow.openSettings() }
            .keyboardShortcut(",", modifiers: .command).accessibilityIdentifier("menu.settings")
        Button(text("action.quit")) { Task { @MainActor in await flow.quit() } }
            .keyboardShortcut("q", modifiers: .command).accessibilityIdentifier("menu.quit")
    }
}

struct MenuBarMenu: View {
    @ObservedObject var flow: AppFlowObservable
    let text: NativeText

    var body: some View {
        Menu {
            MenuBarMenuContent(flow: flow, text: text)
        } label: {
            Image(systemName: "keyboard")
                .accessibilityLabel(text("app.name"))
                .accessibilityIdentifier("menu.open")
        }
    }
}

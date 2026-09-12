import SwiftUI

enum NativeLayout {
    static let compact: CGFloat = 8
    static let group: CGFloat = 16
    static let page: CGFloat = 24
    static let minimum = CGSize(width: 640, height: 480)
    static let aggregateMinimum = CGSize(width: 1000, height: 700)
}

struct ConsentPanel: View {
    let text: NativeText
    let action: () -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text(text("consent.disclosure")).fixedSize(horizontal: false, vertical: true)
                HStack {
                    NativeAction(title: text("consent.accept"), identifier: "consent.accept", action: action)
                    NativeAction(title: text("consent.reject"), identifier: "consent.reject", action: action)
                }
            }
        } label: { Text(text("consent.title")) }
        .accessibilityIdentifier("consent.panel")
    }
}

struct CaptureStatus: View {
    let state: PrimitiveState
    let text: NativeText
    var body: some View {
        HStack(spacing: NativeLayout.compact) {
            Image(systemName: state.symbol).accessibilityHidden(true)
            NativeLabel(title: text(state.statusKey), value: text(state.statusKey), identifier: "capture.status", textStyle: .headline)
        }.font(.headline)
    }
}

struct PrimaryAction: View {
    let state: PrimitiveState
    let text: NativeText
    let action: () -> Void
    var body: some View {
        NativeAction(title: text(state.actionKey), identifier: "capture.primary", keyEquivalent: "\r", action: action)
    }
}

struct AggregateRow: View {
    let name: String
    let text: NativeText
    var body: some View {
        NativeLabel(title: text.aggregateName(name), value: text("aggregate.value"),
                    identifier: "aggregates.row", showsValue: true)
    }
}

struct SettingsRow: View {
    let text: NativeText
    let action: () -> Void
    var body: some View {
        NativeAction(title: text("settings.exclusions"), identifier: "settings.exclusions", action: action)
    }
}

struct DestructiveConfirmation: View {
    let text: NativeText
    let action: () -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text(text("destructive.warning")).fixedSize(horizontal: false, vertical: true)
                HStack {
                    NativeAction(title: text("action.cancel"), identifier: "destructive.cancel", keyEquivalent: "\u{1b}", action: action)
                    NativeAction(title: text("destructive.confirm"), identifier: "destructive.confirm", action: action)
                }
            }
        } label: { Text(text("destructive.title")) }
        .accessibilityIdentifier("destructive.panel")
    }
}

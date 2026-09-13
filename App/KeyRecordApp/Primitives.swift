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
                    .accessibilityIdentifier("consent.disclosure")
                HStack {
                    NativeAction(title: text("consent.accept"), identifier: "consent.accept", action: action)
                    NativeAction(title: text("consent.reject"), identifier: "consent.reject", action: action)
                }
            }
        } label: { Text(text("consent.title")).accessibilityIdentifier("consent.panel") }
    }
}

struct CaptureStatus: View {
    let state: PrimitiveState
    let text: NativeText
    var body: some View {
        HStack(spacing: NativeLayout.compact) {
            Image(systemName: state.symbol)
                .accessibilityLabel(text(state.statusKey))
                .accessibilityIdentifier("capture.symbol")
            Text(text(state.statusKey))
                .accessibilityValue(text(state.statusKey))
                .accessibilityIdentifier("capture.status")
        }
        .font(.headline)
        .accessibilityElement(children: .contain)
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
    /// Real task-18 row detail (total, classification, source confidence). When nil the
    /// task-10 placeholder captions remain, preserving the primitive showcase contract.
    var detail: String? = nil
    var rowIdentifier = "aggregates.row"
    private var value: String { detail ?? text(name.isEmpty ? "aggregate.emptyValue" : "aggregate.value") }
    var body: some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            Text(text.aggregateName(name)).fixedSize(horizontal: false, vertical: true)
            Text(value).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text.aggregateName(name))
        .accessibilityValue(value)
        .accessibilityIdentifier(rowIdentifier)
    }
}

struct SettingsRow: View {
    let text: NativeText
    var titleKey = "settings.exclusions"
    var rowIdentifier = "settings.exclusions"
    var role: ButtonRole? = nil
    let action: () -> Void
    var body: some View {
        NativeAction(title: text(titleKey), identifier: rowIdentifier, role: role, action: action)
    }
}

struct DestructiveConfirmation: View {
    let text: NativeText
    let action: () -> Void
    // Task-10 defaults reproduce the original demonstration exactly; task-18 reset/delete
    // dialogs supply their own proposal keys, ids and symbol.
    var titleKey = "destructive.title"
    var messageKey = "destructive.warning"
    var confirmKey = "destructive.confirm"
    var cancelKey = "action.cancel"
    var panelIdentifier = "destructive.panel"
    var messageIdentifier = "destructive.warning"
    var confirmIdentifier = "destructive.confirm"
    var cancelIdentifier = "destructive.cancel"
    var systemImage: String? = nil
    var onCancel: (() -> Void)? = nil
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text(text(messageKey)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(messageIdentifier)
                HStack {
                    NativeAction(title: text(cancelKey), identifier: cancelIdentifier,
                                 keyEquivalent: "\u{1b}", action: onCancel ?? action)
                    NativeAction(title: text(confirmKey), identifier: confirmIdentifier,
                                 role: .destructive, action: action)
                }
            }
        } label: {
            if let systemImage {
                Label { Text(text(titleKey)) } icon: {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                .accessibilityIdentifier(panelIdentifier)
            } else {
                Text(text(titleKey)).accessibilityIdentifier(panelIdentifier)
            }
        }
    }
}

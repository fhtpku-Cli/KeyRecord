import SwiftUI

private struct NativeReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nativeReduceMotion: Bool {
        get { self[NativeReduceMotionKey.self] }
        set { self[NativeReduceMotionKey.self] = newValue }
    }
}

private struct NativeMotionPolicy: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.nativeReduceMotion) private var injectedReducedMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            NativeMotion.apply(to: &transaction, reducedMotion: systemReducedMotion || injectedReducedMotion)
        }
    }
}

extension View {
    func nativeMotionPolicy() -> some View { modifier(NativeMotionPolicy()) }
}

enum PrimitiveFocus {
    static let order = ["consent.accept", "consent.reject", "capture.primary",
                        "settings.exclusions", "destructive.cancel", "destructive.confirm"]
}

@MainActor
final class PrimitiveFocusContext {
    let binding: FocusState<String?>.Binding
    init(_ binding: FocusState<String?>.Binding) { self.binding = binding }
}

private struct PrimitiveFocusKey: EnvironmentKey {
    static let defaultValue: PrimitiveFocusContext? = nil
}

private struct PrimitiveActionObserverKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (String) -> Void)? = nil
}

extension EnvironmentValues {
    var primitiveActionObserver: (@MainActor @Sendable (String) -> Void)? {
        get { self[PrimitiveActionObserverKey.self] }
        set { self[PrimitiveActionObserverKey.self] = newValue }
    }
    var primitiveFocus: PrimitiveFocusContext? {
        get { self[PrimitiveFocusKey.self] }
        set { self[PrimitiveFocusKey.self] = newValue }
    }
}

struct NativeAction: View {
    @Environment(\.primitiveFocus) private var focus
    @Environment(\.primitiveActionObserver) private var observeAction
    let title: String
    let identifier: String
    var keyEquivalent = ""
    var role: ButtonRole? = nil
    let action: () -> Void

    private var resolvedRole: ButtonRole? {
        role ?? (identifier == "destructive.confirm" ? .destructive : nil)
    }

    private var button: some View {
        Button(role: resolvedRole) {
            observeAction?(identifier)
            action()
        } label: {
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .id(identifier)
    }

    @ViewBuilder private var shortcutButton: some View {
        switch keyEquivalent {
        case "\r": button.keyboardShortcut(.defaultAction)
        case "\u{1b}": button.keyboardShortcut(.cancelAction)
        default: button
        }
    }

    var body: some View {
        if let focus {
            shortcutButton.focusable().focused(focus.binding, equals: identifier)
                .onKeyPress(phases: .down) { press in
                    guard press.key == .tab else { return .ignored }
                    guard let index = PrimitiveFocus.order.firstIndex(of: identifier) else { return .ignored }
                    let step = press.modifiers.contains(.shift) ? -1 : 1
                    focus.binding.wrappedValue = PrimitiveFocus.order[(index + step + PrimitiveFocus.order.count) % PrimitiveFocus.order.count]
                    return .handled
                }
        } else {
            shortcutButton
        }
    }
}

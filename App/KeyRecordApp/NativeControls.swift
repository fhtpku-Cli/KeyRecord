import AppKit
import SwiftUI

private struct NativeLargeTextKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nativeLargeText: Bool {
        get { self[NativeLargeTextKey.self] }
        set { self[NativeLargeTextKey.self] = newValue }
    }
}

struct NativeAction: NSViewRepresentable {
    @Environment(\.nativeLargeText) private var largeText
    let title: String
    let identifier: String
    var keyEquivalent = ""
    let action: () -> Void

    final class KeyboardButton: NSButton {
        override var acceptsFirstResponder: Bool { isEnabled }
        override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = KeyboardButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .preferredFont(forTextStyle: .body)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.font = .preferredFont(forTextStyle: largeText ? .title2 : .body)
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = []
        button.hasDestructiveAction = identifier == "destructive.confirm"
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityLabel(title)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

struct NativeLabel: NSViewRepresentable {
    @Environment(\.nativeLargeText) private var largeText
    let title: String
    let value: String
    let identifier: String
    var showsValue = false
    var textStyle: NSFont.TextStyle = .body

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .labelColor
        field.isSelectable = false
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = showsValue ? title + "\n" + value : title
        field.font = .preferredFont(forTextStyle: largeText ? .title2 : textStyle)
        field.setAccessibilityIdentifier(identifier)
        field.setAccessibilityLabel(title)
        field.setAccessibilityValue(value)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? NativeLayout.minimum.width
        let size = nsView.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size?.height ?? nsView.intrinsicContentSize.height))
    }
}

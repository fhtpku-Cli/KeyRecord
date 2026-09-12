import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let locale = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        let text = NativeText(locale: locale)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: text("app.name"))
        item.button?.setAccessibilityIdentifier("menu.open")
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (id, key) in [("status", "status.unstarted"), ("start", "action.start"),
                          ("pause", "action.pause"), ("resume", "action.resume"),
                          ("settings", "action.settings"), ("quit", "action.quit")] {
            let entry = NSMenuItem(title: text(key), action: nil, keyEquivalent: "")
            entry.setAccessibilityIdentifier("menu.\(id)")
            entry.isEnabled = false
            if id == "settings" {
                entry.action = #selector(showHarness)
                entry.target = self
                entry.keyEquivalent = ","
                entry.isEnabled = true
            } else if id == "quit" {
                entry.action = #selector(NSApplication.terminate(_:))
                entry.target = NSApp
                entry.keyEquivalent = "q"
                entry.isEnabled = true
            }
            menu.addItem(entry)
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func showHarness() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(origin: .zero, size: NativeLayout.minimum),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let locale = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
            let selection = HarnessSelection(locale: locale) { [weak panel] title in panel?.title = title }
            panel.title = selection.windowTitle
            panel.minSize = NativeLayout.minimum
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: PrimitiveHarness(selection: selection))
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

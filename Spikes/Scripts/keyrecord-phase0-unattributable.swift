import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let label = NSTextField(labelWithString: """
        SP-2 窗口 2

        先点一下本窗口，再按任意字母键（如 a）
        """)
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.frame = NSRect(x: 24, y: 24, width: 472, height: 112)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
        content.addSubview(label)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyRecord SP-2 Window 2"
        window.contentView = content
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

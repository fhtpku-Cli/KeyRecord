import AppKit
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var product: ProductComposition?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if FlowTestComposition.environmentConfigured, let fixture = FlowTestComposition.make() {
            statusItem = FlowTestComposition.boot(fixture)
            return
        }
        #endif
        Task {
            do {
                let composition = try await ProductComposition.make()
                product = composition
                statusItem = composition.boot()
            } catch {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.title = "KeyRecord BLOCKED"
                let menu = NSMenu()
                menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
                item.menu = menu
                statusItem = item
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let product, product.lifecycle.phase != .stopped,
              product.lifecycle.phase != .unstarted, product.lifecycle.phase != .consent else { return .terminateNow }
        Task { sender.reply(toApplicationShouldTerminate: await product.prepareQuit()) }
        return .terminateLater
    }
}

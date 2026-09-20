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
                statusItem = await composition.boot()
            } catch {
                // Composition failed before any UI exists. Previously the error was
                // swallowed entirely: the menu bar said "blocked" with no cause anywhere,
                // which during live verification (2026-09-18) cost a full diagnosis cycle
                // to attribute — the real cause turned out to be a 0755 parent directory
                // rejected by preparePrivateRoot's 0700 requirement.
                //
                // The reason is now shown in the menu. It is a startup/plumbing error
                // (path, permissions, keyring availability), never captured input, so it
                // carries no user keystroke data.
                let text = NativeText(locale: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en")
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.title = "\(text("app.name")) \(text("status.blocked"))"
                let menu = NSMenu()
                let cause = NSMenuItem(title: "Startup failed: \(error)", action: nil, keyEquivalent: "")
                cause.isEnabled = false
                cause.setAccessibilityIdentifier("menu.startupFailure")
                menu.addItem(cause)
                menu.addItem(.separator())
                menu.addItem(withTitle: text("action.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        product?.writeDiagnosticSummaryOnTermination()
        #endif
    }
}

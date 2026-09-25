import AppKit
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

#if DEBUG
private struct DebugTrialRejection: Error {}
#endif

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
        if AnalysisPreview.configured {
            AnalysisPreview.boot()
            return
        }
        if FlowTestComposition.environmentConfigured, let fixture = FlowTestComposition.make() {
            statusItem = FlowTestComposition.boot(fixture)
            return
        }
        #endif
        Task {
            do {
                let composition: ProductComposition
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                let trial = DebugTrialIsolation.select(
                    store: environment["KEYRECORD_TRIAL_STORE"],
                    namespace: environment["KEYRECORD_TRIAL_NAMESPACE"],
                    realStoreRoot: try ProductComposition.productionStoreRoot())
                switch trial {
                case .production:
                    composition = try await ProductComposition.make()
                case .trial(let location):
                    composition = try await ProductComposition.makeTrial(
                        storeRoot: location.storeRoot, namespace: location.namespace)
                case .rejected:
                    throw DebugTrialRejection()
                }
                #else
                composition = try await ProductComposition.make()
                #endif
                #if DEBUG
                if let path = ProcessInfo.processInfo.environment["KEYRECORD_PRIVACY_INTERVAL_PATH"], !path.isEmpty {
                    composition.enablePrivacyIntervalJournal(path: path)
                }
                #endif
                product = composition
                statusItem = await composition.boot()
                #if DEBUG
                // Opt-in, bounded system-state witness for a separately approved trial.
                if let raw = ProcessInfo.processInfo.environment["KEYRECORD_SYSTEM_WITNESS_SECONDS"],
                   let seconds = Int(raw) {
                    composition.startSystemWitness(seconds: seconds)
                }
                #endif
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
        guard let product else { return .terminateNow }
        return product.terminationReply { sender.reply(toApplicationShouldTerminate: $0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        product?.writeDiagnosticSummaryOnTermination(
            to: ProcessInfo.processInfo.environment["KEYRECORD_DIAGNOSTIC_SUMMARY_PATH"])
        #endif
    }
}

import AppKit
import Darwin
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

#if DEBUG
private struct DebugTrialRejection: Error {}
private enum DebugReplayMode: String { case typing, idle }
private struct DebugReplayProgress: Encodable {
    let mode: String
    var outcome = "waitingForCollecting"
    let expectedTicks = FixedReplayController.windowTicks
    var ticks = 0
    var acceptedEvents: Int64 = 0
    var durableKeyDownTotal: Int64?
    var elapsedSeconds = 0.0
    var startedUptimeSeconds: Double?
    var endedUptimeSeconds: Double?
}
#endif

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var product: ProductComposition?
    #if DEBUG
    private var replayTask: Task<Void, Never>?
    private var replayProgress: DebugReplayProgress?
    private var replaySummaryURL: URL?
    private var replayStarted: ContinuousClock.Instant?
    #endif

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
                let requiresTrial = Bundle.main.object(forInfoDictionaryKey: "KeyRecordRequiresTrialIsolation") as? Bool == true
                let trial = DebugTrialIsolation.select(
                    store: environment["KEYRECORD_TRIAL_STORE"],
                    namespace: environment["KEYRECORD_TRIAL_NAMESPACE"],
                    realStoreRoot: try ProductComposition.productionStoreRoot(),
                    requiresTrial: requiresTrial)
                var replay: (controller: FixedReplayController, mode: DebugReplayMode)?
                switch trial {
                case .production:
                    guard environment["KEYRECORD_PERFORMANCE_REPLAY"] == nil else { throw DebugTrialRejection() }
                    composition = try await ProductComposition.make()
                case .trial(let location):
                    if let requested = environment["KEYRECORD_PERFORMANCE_REPLAY"] {
                        guard requiresTrial, environment["KEYRECORD_LOCAL_CAPTURE"] == "1",
                              let mode = DebugReplayMode(rawValue: requested) else { throw DebugTrialRejection() }
                        let controller = FixedReplayController()
                        composition = try await ProductComposition.makeTrialReplay(
                            storeRoot: location.storeRoot, namespace: location.namespace,
                            controller: controller)
                        replay = (controller, mode)
                        replaySummaryURL = location.storeRoot.deletingLastPathComponent()
                            .appendingPathComponent("performance-replay.json")
                        replayProgress = DebugReplayProgress(mode: mode.rawValue)
                    } else {
                        composition = try await ProductComposition.makeTrial(
                            storeRoot: location.storeRoot, namespace: location.namespace)
                    }
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
                if let replay {
                    replayTask = Task {
                        await driveReplay(composition: composition, controller: replay.controller,
                                          mode: replay.mode)
                    }
                }
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
        replayTask?.cancel()
        if replayProgress?.outcome == "running" || replayProgress?.outcome == "waitingForCollecting" {
            replayProgress?.outcome = "terminated"
        }
        writeReplayProgress()
        product?.writeDiagnosticSummaryOnTermination(
            to: ProcessInfo.processInfo.environment["KEYRECORD_DIAGNOSTIC_SUMMARY_PATH"])
        #endif
    }

    #if DEBUG
    private func driveReplay(composition: ProductComposition, controller: FixedReplayController,
                             mode: DebugReplayMode) async {
        let clock = ContinuousClock()
        let waitDeadline = clock.now.advanced(by: .seconds(120))
        while !Task.isCancelled {
            if composition.lifecycle.phase == .collecting,
               await composition.capture.hasLiveSession() {
                break
            }
            if clock.now >= waitDeadline {
                replayProgress?.outcome = "collectingNotReached"
                writeReplayProgress()
                return
            }
            do { try await clock.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        replayStarted = clock.now
        guard let startedUptime = replayUptime() else {
            replayProgress?.outcome = "clockUnavailable"
            writeReplayProgress()
            return
        }
        replayProgress?.startedUptimeSeconds = startedUptime
        replayProgress?.outcome = "running"
        guard writeReplayProgress() else { return }
        var nextTick = clock.now
        for tick in 0..<FixedReplayController.windowTicks {
            if Task.isCancelled { return }
            guard composition.lifecycle.phase == .collecting,
                  await composition.capture.hasLiveSession(),
                  clock.now <= nextTick.advanced(by: .milliseconds(500)) else {
                replayProgress?.outcome = "interrupted"
                writeReplayProgress()
                return
            }
            if mode == .typing && tick < FixedReplayController.activeTicks {
                let accepted = controller.emit(tick: tick)
                guard accepted == FixedReplayController.expectedEvents(tick: tick) else {
                    replayProgress?.outcome = "handoffIncomplete"
                    writeReplayProgress()
                    return
                }
                replayProgress?.acceptedEvents += Int64(accepted)
            }
            replayProgress?.ticks += 1
            nextTick = nextTick.advanced(by: .milliseconds(100))
            do { try await clock.sleep(until: nextTick) } catch { return }
        }
        guard composition.lifecycle.phase == .collecting,
              await composition.capture.hasLiveSession(),
              clock.now <= nextTick.advanced(by: .milliseconds(500)) else {
            replayProgress?.outcome = "interrupted"
            writeReplayProgress()
            return
        }
        replayProgress?.outcome = "verifyingDurability"
        writeReplayProgress()
        do {
            let durable = try await composition.replayDurableKeyDownTotal(
                expectedAcceptedEvents: replayProgress?.acceptedEvents ?? -1)
            let accepted = replayProgress?.acceptedEvents ?? -1
            replayProgress?.durableKeyDownTotal = durable
            replayProgress?.outcome = durable == accepted / 2
                ? "completed" : "durabilityMismatch"
        } catch {
            replayProgress?.outcome = "durabilityUnavailable"
        }
        writeReplayProgress()
    }

    @discardableResult
    private func writeReplayProgress() -> Bool {
        guard var progress = replayProgress, let replaySummaryURL else { return false }
        if progress.endedUptimeSeconds == nil {
            if let replayStarted {
                let elapsed = replayStarted.duration(to: ContinuousClock().now).components
                progress.elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            }
            if progress.outcome != "running" {
                progress.endedUptimeSeconds = replayUptime()
            }
        }
        replayProgress = progress
        do {
            try JSONEncoder().encode(progress).write(to: replaySummaryURL, options: .atomic)
            return true
        } catch {
            fputs("KeyRecord replay summary write failed\n", stderr)
            return false
        }
    }

    private func replayUptime() -> Double? {
        var value = timespec()
        guard clock_gettime(CLOCK_UPTIME_RAW, &value) == 0 else { return nil }
        return Double(value.tv_sec) + Double(value.tv_nsec) / 1e9
    }
    #endif
}

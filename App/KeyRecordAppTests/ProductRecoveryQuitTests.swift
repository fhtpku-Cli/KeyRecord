import Foundation
import XCTest
import AppKit
import KeyRecordCore
@testable import KeyRecordCapture
@testable import KeyRecordStore

// Hostless reproduction of Start/Resume/Quit around privacy closure. The composition,
// lifecycle, recovery fence, coordinator, reducer, scheduler and encrypted store are the
// production objects. Only host boundaries are replaced: keychain, event tap, lock /
// Secure Input / foreground providers, Input Monitoring, login item, lock notifications
// and NSApp termination. Nothing here reads a real store, keychain item or keystroke.

private actor MemoryKeychain: KeychainBackend {
    private var items: [KeychainItemID: Data] = [:]
    private var holdingDeletes = false
    private var failNextDelete = false
    private var heldDeletes: [CheckedContinuation<Void, Never>] = []
    private(set) var deleteAttempts = 0
    var itemCount: Int { items.count }
    /// Parks every delete until released, to pause erase in the middle of maintenance.
    func holdDeletes() { holdingDeletes = true }
    func failNextDeleteOnce() { failNextDelete = true }
    func releaseDeletes() {
        holdingDeletes = false
        heldDeletes.forEach { $0.resume() }
        heldDeletes.removeAll()
    }
    func read(_ id: KeychainItemID) async throws -> Data? { items[id] }
    func versions(in namespace: KeychainNamespace) async throws -> Set<KeyVersion> {
        Set(items.keys.filter { $0.namespace == namespace }.compactMap(\.version))
    }
    func add(_ item: KeychainItem) async throws {
        guard items[item.id] == nil else { throw KeyringError.duplicateItem }
        items[item.id] = item.material
    }
    func publish(_ update: KeychainMetadataUpdate) async throws {
        guard items[update.id] == update.expected else { throw KeyringError.metadataConflict }
        items[update.id] = update.replacement
    }
    func delete(_ id: KeychainItemID) async throws {
        deleteAttempts += 1
        if failNextDelete { failNextDelete = false; throw KeyringError.metadataConflict }
        if holdingDeletes { await withCheckedContinuation { heldDeletes.append($0) } }
        items[id] = nil
    }
}

private struct SilentLogin: LoginItemBackend {
    func register() async throws {}
    func unregister() async throws {}
}

@MainActor
private final class ManualLockNotifications: LockNotificationCentering {
    private var handlers: [Notification.Name: [@MainActor () -> Void]] = [:]
    func addObserver(for name: Notification.Name,
                     handler: @escaping @MainActor () -> Void) -> any NSObjectProtocol {
        handlers[name, default: []].append(handler)
        return NSObject()
    }
    func post(_ name: Notification.Name) { handlers[name]?.forEach { $0() } }
}

/// Provider state shared by the product's providers and the synthetic tap, as the real
/// system state is shared by `SystemTapBackend` and the product providers.
private final class SyntheticHost: FrontmostAppProvider, SecureInputProvider, SessionLockProvider,
                                   InputMonitoringPermission, @unchecked Sendable {
    private let mutex = NSLock()
    private var lock: SessionLockState = .unlocked
    private var scriptedLockReads: [SessionLockState] = []
    private var secure: SecureInputState = .disabled
    private var secureInputReadsToHold = 0
    private var heldSecureInputReads: [CheckedContinuation<SecureInputState, Never>] = []
    private var foreground: ForegroundState = .attributable(bundleID: "synthetic.editor")
    private var scriptedForegroundReads: [ForegroundState] = []
    private var permission: InputMonitoringStatus = .granted
    private(set) var lockReads = 0

    func setLock(_ state: SessionLockState) { mutex.withLock { lock = state } }
    /// Consumed one per lock read before falling back to the steady state.
    func scriptLockReads(_ states: [SessionLockState]) { mutex.withLock { scriptedLockReads = states } }
    func setSecureInput(_ state: SecureInputState) { mutex.withLock { secure = state } }
    /// Parks the next `count` Secure Input reads so a stale poller can finish after replacement
    /// without also blocking Start/Resume readiness reads.
    func holdNextSecureInputReads(_ count: Int) { mutex.withLock { secureInputReadsToHold = count } }
    var parkedSecureInputReads: Int { mutex.withLock { heldSecureInputReads.count } }
    func completeNextSecureInputRead(_ state: SecureInputState) {
        let continuation: CheckedContinuation<SecureInputState, Never>? = mutex.withLock {
            guard !heldSecureInputReads.isEmpty else { return nil }
            return heldSecureInputReads.removeFirst()
        }
        continuation?.resume(returning: state)
    }
    func releaseSecureInputReads() {
        let (held, current): ([CheckedContinuation<SecureInputState, Never>], SecureInputState) = mutex.withLock {
            secureInputReadsToHold = 0
            let held = heldSecureInputReads
            heldSecureInputReads.removeAll()
            return (held, secure)
        }
        held.forEach { $0.resume(returning: current) }
    }
    func setForeground(_ state: ForegroundState) { mutex.withLock { foreground = state } }
    /// Product-side foreground reads consumed before the steady state; the tap reads the steady state.
    func scriptForegroundReads(_ states: [ForegroundState]) { mutex.withLock { scriptedForegroundReads = states } }
    func setPermission(_ status: InputMonitoringStatus) { mutex.withLock { permission = status } }

    func sessionLockState() async -> SessionLockState {
        mutex.withLock {
            lockReads += 1
            return scriptedLockReads.isEmpty ? lock : scriptedLockReads.removeFirst()
        }
    }
    func secureInputState() async -> SecureInputState {
        await withCheckedContinuation { continuation in
            mutex.withLock {
                if secureInputReadsToHold > 0 {
                    secureInputReadsToHold -= 1
                    heldSecureInputReads.append(continuation)
                } else {
                    continuation.resume(returning: secure)
                }
            }
        }
    }
    func foregroundState() async -> ForegroundState {
        mutex.withLock { scriptedForegroundReads.isEmpty ? foreground : scriptedForegroundReads.removeFirst() }
    }
    func preflight() -> InputMonitoringStatus { mutex.withLock { permission } }
    func request() -> InputMonitoringStatus { mutex.withLock { permission } }

    /// What `CGSessionCopyCurrentDictionary` would report for this synthetic state.
    var sessionDictionary: NSDictionary {
        let locked = mutex.withLock { lock == .locked }
        return ["CGSSessionScreenIsLocked": NSNumber(value: locked ? 1 : 0), kCGSessionOnConsoleKey: true,
                kCGSessionUserIDKey: NSNumber(value: getuid())] as NSDictionary
    }

    fileprivate var providerSnapshot: CaptureProviderSnapshot {
        mutex.withLock {
            CaptureProviderSnapshot(GateInputs(sessionLock: lock, secureInput: secure, foreground: foreground))
        }
    }
}

private final class SyntheticTap: CaptureTapBackend, @unchecked Sendable {
    private let mutex = NSLock()
    private let host: SyntheticHost
    private let queue: CaptureQueue
    private var invalidate: (@Sendable (CaptureInvalidation) -> Void)?
    private var handoff: (@Sendable (ObservedKeyEvent) -> EventHandoffResult)?
    private var cached = CaptureProviderSnapshot.unknown

    init(host: SyntheticHost, queue: CaptureQueue) { self.host = host; self.queue = queue }

    func subscribe(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) async throws {
        mutex.withLock {
            self.invalidate = { [weak self] reason in
                self?.mutex.withLock { self?.cached = .unknown }
                invalidate(reason)
            }
        }
    }
    func readProviders() async -> CaptureProviderSnapshot {
        let current = host.providerSnapshot
        mutex.withLock { cached = current }
        return current
    }
    func cachedProviders() -> CaptureProviderSnapshot { mutex.withLock { cached } }
    func start(handoff: @escaping @Sendable (ObservedKeyEvent) -> EventHandoffResult) async throws {
        mutex.withLock { self.handoff = handoff }
    }
    func stop() async {
        queue.revoke()
        mutex.withLock { handoff = nil; invalidate = nil; cached = .unknown }
    }

    /// Delivers an invalidation the way the workspace fence does; false once the fence is gone.
    @discardableResult
    func report(_ reason: CaptureInvalidation) -> Bool {
        guard let invalidate = mutex.withLock({ invalidate }) else { return false }
        invalidate(reason)
        return true
    }

    /// One bare key press, delivered the way the tap callback delivers it.
    @discardableResult
    func press(_ key: Int = 0) throws -> EventHandoffResult {
        guard let handoff = mutex.withLock({ handoff }) else { return .closed }
        let code = try KeyCode(key)
        // What `decodeCaptureEvent` produces for a key with no modifier flag set.
        let modifiers = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        for kind in [KeyEventKind.keyDown, .keyUp] {
            let event = ObservedKeyEvent(keyCode: code, kind: kind, isAutoRepeat: false, modifiers: modifiers,
                                         source: .ordinaryObserved, generation: queue.generation)
            let result = handoff(event)
            if result != .accepted { return result }
        }
        return .accepted
    }
}

@MainActor
private final class SyntheticProduct {
    let host = SyntheticHost()
    let keychain: MemoryKeychain
    let notifications = ManualLockNotifications()
    let root: URL
    let journal: URL
    private(set) var tap: SyntheticTap?
    /// Replaces the synthetic host as the product's lock provider when set before boot.
    var lockProvider: (any SessionLockProvider)?
    private(set) var terminateRequests = 0
    /// What the delegate answered when AppKit asked from inside `terminate`.
    private(set) var nestedTerminationReplies: [NSApplication.TerminateReply] = []
    private(set) var composition: ProductComposition!

    init(root: URL, keychain: MemoryKeychain) {
        self.root = root
        self.keychain = keychain
        journal = root.appendingPathComponent("journal-\(UUID().uuidString).jsonl")
    }

    static func fresh() throws -> SyntheticProduct {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-synthetic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return SyntheticProduct(root: base, keychain: MemoryKeychain())
    }

    /// A later launch against the same synthetic store and keychain.
    func relaunch() -> SyntheticProduct { SyntheticProduct(root: root, keychain: keychain) }

    var storeRoot: URL { root.appendingPathComponent("app/store", isDirectory: true) }

    func boot(journal enabled: Bool = true) async throws {
        let host = self.host
        var boundaries = ProductHostBoundaries(
            storeRoot: storeRoot, namespace: try KeychainNamespace("com.keyrecord.synthetic"),
            backend: keychain, login: SilentLogin(),
            localCapture: LocalDevelopmentCapture(armed: true),
            eventSource: { [weak self] queue, qualification, _ in
                let tap = SyntheticTap(host: host, queue: queue)
                self?.tap = tap
                return ListenOnlyEventSource(queue: queue, qualification: qualification, backend: tap,
                                             permission: host)
            })
        boundaries.sessionLock = lockProvider ?? host
        boundaries.foreground = host
        boundaries.secureInput = host
        boundaries.lockNotifications = notifications
        // AppKit's `terminate` asks the delegate synchronously, inside the caller's main-actor job.
        boundaries.terminate = { [weak self] in
            guard let self else { return }
            self.terminateRequests += 1
            self.nestedTerminationReplies.append(self.composition.terminationReply { _ in })
        }
        composition = try await ProductComposition.makeSynthetic(boundaries)
        if enabled { composition.enablePrivacyIntervalJournal(path: journal.path) }
        await composition.restoreRuntime()
    }

    var phase: LifecyclePhase { composition.lifecycle.phase }
    var live: Bool { get async { await composition.capture.hasLiveSession() } }
    var aggregateDelta: Int64 { composition.diagnostics.runSummary.aggregateDelta }
    var keyGateOpen: Bool { (try? composition.gate.begin()) != nil }

    func press(_ count: Int) async throws {
        let before = aggregateDelta
        for _ in 0..<count { XCTAssertEqual(try tap?.press(), .accepted) }
        do {
            try await waitUntil("aggregate moved") { self.aggregateDelta >= before + Int64(count) }
        } catch {
            let run = composition.diagnostics.runSummary
            print("SYNTHETIC-COUNTERS handoff=\(run.handoffAccepted) closed=\(run.handoffClosed) "
                  + "normalized=\(run.normalizationOutput) aggregate=\(run.aggregateDelta) before=\(before)")
            throw error
        }
    }

    /// Explicit save used to prepare durable fixtures. Two separate dirty/pending reads can
    /// both be false while a pulse has just staged the count, so they are not a completion boundary.
    func waitDurable() async throws {
        try await composition.flush.flushWhileUnlocked()
    }

    /// Reads the encrypted store. This does not stage, tick, or flush.
    func diskBareTotal() async throws -> Int64 {
        let cycle = try XCTUnwrap(composition.lifecycle.state.preferences?.currentCycleID)
        let aggregate = try await AggregatePersistence.restore(
            cycleID: cycle, store: composition.store, gate: composition.gate)
        return try AggregateSnapshot(shortcuts: aggregate.shortcuts, bareKeys: aggregate.bareKeys).bareKeyTotal
    }

    /// Polls the store until the pulse has written `expected`, or the bound expires.
    /// A timeout fails with the last read; it does not flush or try again.
    func waitForPulseWrite(_ expected: Int64, bound: Duration = .seconds(8)) async throws -> Int64 {
        let deadline = ContinuousClock().now.advanced(by: bound)
        var last = Int64.min
        var lastError = "none"
        while ContinuousClock().now < deadline {
            do {
                last = try await diskBareTotal()
                lastError = "none"
                if last == expected { return last }
            } catch {
                lastError = String(describing: error)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let pending = await composition.scheduler.hasPendingChanges()
        let unflushed = composition.reduction.hasUnflushedChanges()
        XCTFail("pulse write bound expired: disk=\(last) expected=\(expected) pending=\(pending) "
            + "unflushed=\(unflushed) pulse=\(composition.activePulseCount) lastError=\(lastError)")
        return last
    }

    /// Stop background tasks, then wait out a write they already issued, before another
    /// store client resets or reopens the same files.
    func finishIssuedWrites() async throws {
        await composition.stopBackgroundMaintenanceForFixture()
        await composition.capture.stop()
        await composition.scheduler.waitForIssuedWrite()
        try await composition.flush.flushWhileUnlocked()
    }

    func lockScreen() async throws {
        host.setLock(.locked)
        notifications.post(ProductComposition.screenLockedNotification)
        try await waitUntil("closed after lock") {
            let live = await self.live
            // Blocked ignores conditionsChanged, so cached lifecycle conditions may still
            // read unlocked here; the closure is judged by gate, session and visibility.
            return !self.composition.flow.sensitiveContentVisible && !live && !self.keyGateOpen
                && [.blocked, .paused].contains(self.phase)
        }
    }

    func unlockScreen() async throws {
        host.setLock(.unlocked)
        notifications.post(ProductComposition.screenUnlockedNotification)
        try await Task.sleep(for: .milliseconds(100))
    }

    func marks() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: journal.path) else { return [] }
        return try String(contentsOf: journal, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    func actionEnds(_ name: String) throws -> [[String: Any]] {
        try marks().filter { $0["role"] as? String == "actionEnd" && $0["action"] as? String == name }
            .compactMap { $0["actionDetail"] as? [String: Any] }
    }

    func reset() async {
        composition.flow.requestReset()
        await composition.flow.choose(.confirm)
    }

    func erase() async {
        composition.flow.requestDeleteLocalData()
        await composition.flow.choose(.confirm)
    }

    /// Readiness calls made by anyone (lifecycle, coordinator, monitor-triggered recovery).
    var readinessCalls: Int { get async { await composition.capture.readinessObservation().sequence } }

    func dump() -> String {
        let state = composition.lifecycle.state
        let lines = (try? String(contentsOf: journal, encoding: .utf8)) ?? "<no journal>"
        return "phase=\(state.phase) reason=\(String(describing: state.blockedReason)) "
            + "failure=\(String(describing: state.failure)) notice=\(String(describing: state.notice)) "
            + "diagnosis=\(composition.diagnostics.snapshot.diagnosis)\n\(lines)"
    }

    func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeRoot.path)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func waitUntil(_ label: String, timeout: Duration = .seconds(8),
                       _ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    XCTFail("timed out waiting for \(label)")
    throw CancellationError()
}

@MainActor
final class ProductRecoveryQuitTests: XCTestCase {
    private var products: [SyntheticProduct] = []

    override func tearDown() async throws {
        for product in products { product.cleanUp() }
        products.removeAll()
    }

    private func collecting() async throws -> SyntheticProduct {
        let product = try SyntheticProduct.fresh()
        products.append(product)
        try await product.boot()
        // Fresh install: Start opens consent, then the consent screen's Accept starts capture.
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .consent)
        await product.composition.flow.accept()
        do {
            try await waitUntil("collecting after consent") {
                let live = await product.live
                return product.phase == .collecting && live
            }
        } catch {
            print("SYNTHETIC-DUMP \(product.dump())")
            throw error
        }
        return product
    }

    // MARK: - Recovery

    func testExplicitStartAfterLockAndUnlockReestablishesCollecting() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()

        try await product.lockScreen()
        XCTAssertEqual(product.phase, .blocked)
        XCTAssertEqual(product.composition.lifecycle.state.blockedReason, .sessionLocked)
        XCTAssertFalse(product.keyGateOpen)
        XCTAssertEqual(try product.tap?.press(), .closed, "no delivery while closed")

        try await product.unlockScreen()
        XCTAssertEqual(product.phase, .blocked, "unlock alone must not resume")
        let liveAfterUnlock = await product.live
        XCTAssertFalse(liveAfterUnlock)

        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        let liveAfterStart = await product.live
        XCTAssertTrue(liveAfterStart)
        XCTAssertTrue(product.composition.flow.sensitiveContentVisible)
        try await product.press(1)

        let start = try XCTUnwrap(product.actionEnds("start").last)
        XCTAssertEqual(start["prepareOutcome"] as? String, "ready")
        XCTAssertEqual(start["prepareLockRead"] as? String, "unlocked")
        XCTAssertEqual(start["lifecycleCommandRun"] as? Bool, true)
        XCTAssertEqual(start["phaseAfter"] as? String, "collecting")
        XCTAssertEqual(start["sessionLiveAfter"] as? Bool, true)
        XCTAssertEqual(start["readinessOutcome"] as? String,
                       "lock=unlocked,secure=disabled,foreground=attributable")
    }

    func testClosedIntervalBoundariesComeFromTheProductPath() async throws {
        let product = try await collecting()
        try await product.press(1)
        try await product.lockScreen()
        XCTAssertEqual(try product.tap?.press(), .closed)
        try await product.unlockScreen()
        try await Task.sleep(for: .milliseconds(1_200))
        await product.composition.startOrRetry()
        try await product.press(2)

        let marks = try product.marks()
        let begin = try XCTUnwrap(marks.last {
            $0["role"] as? String == "begin" && $0["boundaryCause"] as? String == "protectedStateClosed"
        })
        let beginSeq = try XCTUnwrap(begin["seq"] as? Int)
        let end = try XCTUnwrap(marks.first { $0["role"] as? String == "end" && ($0["seq"] as? Int ?? 0) > beginSeq })
        let endSeq = try XCTUnwrap(end["seq"] as? Int)
        XCTAssertEqual(begin["privacyTrigger"] as? String, "screenLockedNotification")
        XCTAssertEqual(begin["captureSessionLive"] as? Bool, false)
        XCTAssertEqual(end["boundaryCause"] as? String, "captureSessionStarting",
                       "the interval ends before the new session can accept input")
        let observes = marks.filter {
            $0["role"] as? String == "observe" && (beginSeq..<endSeq).contains($0["seq"] as? Int ?? -1)
        }
        XCTAssertFalse(observes.isEmpty)
        XCTAssertTrue(observes.allSatisfy { $0["lockReadStatus"] as? String != "notChecked" })
        for counter in ["aggregateDelta", "normalizationOutput", "handoffAccepted", "flushDurable"] {
            XCTAssertEqual(end[counter] as? Int, begin[counter] as? Int, "\(counter) moved while closed")
        }
        XCTAssertEqual(product.aggregateDelta, Int64(end["aggregateDelta"] as? Int ?? -1) + 2,
                       "input after reopening is outside the closed interval")
        XCTAssertEqual(try product.actionEnds("start").last?["phaseAfter"] as? String, "collecting")
    }

    func testStartWhileLockIsLockedOrUnknownRefusesEveryTime() async throws {
        let product = try await collecting()
        try await product.lockScreen()
        for state in [SessionLockState.locked, .locked, .unknown] {
            product.host.setLock(state)
            await product.composition.startOrRetry()
            XCTAssertEqual(product.phase, .blocked)
            XCTAssertFalse(product.keyGateOpen, "unknown must never be treated as unlocked")
            let live = await product.live
            XCTAssertFalse(live)
        }
        let begins = try product.marks().filter {
            $0["role"] as? String == "actionBegin" && $0["action"] as? String == "start"
        }
        let ends = try product.actionEnds("start")
        XCTAssertEqual(ends.suffix(3).map { $0["prepareOutcome"] as? String },
                       ["lockNotUnlocked", "lockNotUnlocked", "lockNotUnlocked"])
        XCTAssertEqual(ends.suffix(3).map { $0["prepareLockRead"] as? String }, ["locked", "locked", "unknown"])
        XCTAssertEqual(ends.suffix(3).map { $0["lifecycleCommandRun"] as? Bool }, [nil, nil, nil])
        XCTAssertEqual(ends.suffix(3).map { $0["abortRun"] as? Bool }, [true, true, true])
        XCTAssertEqual(Set(begins.suffix(3).compactMap { $0["actionSeq"] as? Int }).count, 3)
    }

    func testLockReturningDuringRecoveryKeepsCaptureClosed() async throws {
        let product = try await collecting()
        try await product.lockScreen()
        try await product.unlockScreen()
        // The explicit Start sees unlocked, then the lifecycle readiness check sees locked.
        product.host.scriptLockReads([.unlocked, .locked])
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .blocked)
        XCTAssertEqual(product.composition.lifecycle.state.blockedReason, .sessionLocked)
        XCTAssertFalse(product.keyGateOpen)
        let live = await product.live
        XCTAssertFalse(live)
        let start = try XCTUnwrap(product.actionEnds("start").last)
        XCTAssertEqual(start["prepareOutcome"] as? String, "ready")
        XCTAssertEqual(start["lifecycleCommandRun"] as? Bool, true)
        XCTAssertEqual(start["readinessOutcome"] as? String,
                       "lock=locked,secure=disabled,foreground=attributable")
    }

    func testStartWithoutInputMonitoringPermissionStaysClosed() async throws {
        let product = try await collecting()
        try await product.lockScreen()
        try await product.unlockScreen()
        product.host.setPermission(.denied)
        await product.composition.startOrRetry()
        XCTAssertNotEqual(product.phase, .collecting)
        let live = await product.live
        XCTAssertFalse(live)
        XCTAssertFalse(product.keyGateOpen)
        let start = try XCTUnwrap(product.actionEnds("start").last)
        XCTAssertEqual(start["permissionStatus"] as? String, "denied")
        XCTAssertEqual(start["phaseAfter"] as? String, "failed")
        XCTAssertEqual(start["failureAfter"] as? String,
                       "captureStartDenied(KeyRecordCore.LifecycleCaptureError.runtimeFailed)")

        // The same Quit path must still close cleanly.
        await product.composition.requestQuit()
        XCTAssertEqual(product.terminateRequests, 1)
    }

    func testPausedIntentSurvivesLockAndOnlyResumeReopens() async throws {
        let product = try await collecting()
        await product.composition.flow.pause()
        XCTAssertEqual(product.phase, .paused)
        try await product.lockScreen()
        try await product.unlockScreen()
        XCTAssertEqual(product.phase, .paused)
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .paused, "Start must not resume a user pause")
        var live = await product.live
        XCTAssertFalse(live)
        XCTAssertEqual(try product.actionEnds("start").last?["earlyReturn"] as? String, "not-blocked-or-failed")

        await product.composition.resume()
        XCTAssertEqual(product.phase, .collecting)
        live = await product.live
        XCTAssertTrue(live)
        try await product.press(1)
        XCTAssertEqual(try product.actionEnds("resume").last?["prepareOutcome"] as? String, "ready")
    }

    func testPreferenceSaveAfterProtectedSessionCloseReopensTheStore() async throws {
        let product = try await collecting()
        let preferences = try XCTUnwrap(product.composition.lifecycle.state.preferences)
        // Exactly what privacy closure does to the store, with the key gate still open.
        await product.composition.store.closeProtectedSession()
        XCTAssertTrue(product.keyGateOpen)
        do {
            try await product.composition.capture.persistence.save(preferences.updating(expectedCollecting: true))
        } catch {
            XCTFail("save after closeProtectedSession failed: \(error)")
        }
    }

    func testFailedResumeAfterPausedLockIsNotStuckForStart() async throws {
        let product = try await collecting()
        await product.composition.flow.pause()
        try await product.lockScreen()
        try await product.unlockScreen()
        await product.composition.resume()
        if product.phase == .failed {
            await product.composition.startOrRetry()
            XCTAssertNotEqual(product.phase, .failed, "Start retry replays the same failing save")
        }
        XCTAssertEqual(product.phase, .collecting)
    }

    func testStaleLockedNotificationKeepsStartRefusedUntilUnlockIsDelivered() async throws {
        final class Delivery: @unchecked Sendable { var send: ((SessionLockState) -> Void)? }
        let delivery = Delivery()
        let product = try SyntheticProduct.fresh()
        products.append(product)
        let host = product.host
        product.lockProvider = SystemSessionLockProvider(
            sessionDictionaryQuery: { host.sessionDictionary }, consoleLockQuery: { nil },
            notificationRegistrar: { delivery.send = $0 })
        try await product.boot()
        await product.composition.startOrRetry()
        await product.composition.flow.accept()
        try await waitUntil("collecting") {
            let live = await product.live
            return product.phase == .collecting && live
        }

        delivery.send?(.locked)
        try await product.lockScreen()
        // The session dictionary now says unlocked, but the provider never saw the unlock.
        host.setLock(.unlocked)
        product.notifications.post(ProductComposition.screenUnlockedNotification)
        try await Task.sleep(for: .milliseconds(1_200))
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .blocked)
        let refused = try XCTUnwrap(product.actionEnds("start").last)
        XCTAssertEqual(refused["prepareLockRead"] as? String, "locked")
        XCTAssertEqual(refused["prepareOutcome"] as? String, "lockNotUnlocked")
        let observe = try XCTUnwrap(product.marks().last { $0["role"] as? String == "observe" })
        XCTAssertEqual(observe["lockReadStatus"] as? String, "locked")
        XCTAssertEqual(observe["lockComponents"] as? String,
                       "session=unlocked,console=unknown,eligible=true,notification=locked")

        delivery.send?(.unlocked)
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        let live = await product.live
        XCTAssertTrue(live)
    }

    func testFailedAutomaticRecoveryLeavesAnActionableState() async throws {
        let product = try await collecting()
        try await product.press(1)
        // Foreground moves, and moves again while recovery is rebuilding the session.
        product.host.scriptForegroundReads(Array(repeating: .attributable(bundleID: "synthetic.browser"), count: 3))
        product.host.setForeground(.attributable(bundleID: "synthetic.editor2"))
        XCTAssertEqual(product.tap?.report(.foregroundChanged), true)
        try await waitUntil("failed recovery hands over to Start") { product.phase == .blocked }
        let live = await product.live
        XCTAssertFalse(live)
        XCTAssertEqual(product.composition.lifecycle.state.blockedReason, .keyUnavailable)
        XCTAssertFalse(product.composition.flow.sensitiveContentVisible)
        XCTAssertFalse(product.tap?.report(.foregroundChanged) ?? true, "no automatic trigger remains")
        XCTAssertFalse(product.composition.reduction.hasUnflushedChanges(), "retained count was saved")
        let pending = await product.composition.scheduler.hasPendingChanges()
        XCTAssertFalse(pending)

        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        let liveAfterStart = await product.live
        XCTAssertTrue(liveAfterStart)
        try await product.press(1)
        try await waitUntil("both counts published") { product.composition.flow.snapshot?.bareKeyTotal == 2 }

        await product.composition.requestQuit()
        XCTAssertEqual(product.terminateRequests, 1)
    }

    // MARK: - Quit

    func testMenuQuitWhileBlockedDoesNotWaitOnAReplyThatCannotRun() async throws {
        let product = try await collecting()
        try await product.lockScreen()
        try await product.unlockScreen()
        await product.composition.requestQuit()
        XCTAssertEqual(product.terminateRequests, 1)
        // `.terminateLater` here would spin AppKit's nested loop inside this main-actor job,
        // and its reply task could never start (observed live as a hung Quit).
        XCTAssertEqual(product.nestedTerminationReplies, [.terminateNow])
    }

    func testQuitWhileBlockedAfterLockTerminatesThroughBothAppKitPaths() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.lockScreen()
        try await product.unlockScreen()

        await product.composition.requestQuit()
        XCTAssertEqual(product.terminateRequests, 1, "menu Quit asks AppKit to terminate")
        // AppKit then asks the delegate; blocked is not stopped, so it replies later.
        var reply: Bool?
        let answer = product.composition.terminationReply { reply = $0 }
        XCTAssertEqual(answer, .terminateLater)
        try await waitUntil("termination reply") { reply != nil }
        XCTAssertEqual(reply, true)

        let quits = try product.actionEnds("quit")
        XCTAssertEqual(quits.map { $0["invocation"] as? String }, ["menu", "applicationShouldTerminate"])
        for quit in quits {
            XCTAssertEqual(quit["phaseBefore"] as? String, "blocked")
            XCTAssertEqual(quit["lifecycleFlushCalls"] as? Int, 0, "blocked quit runs no lifecycle flush")
            XCTAssertEqual(quit["lifecycleFlushOutcome"] as? String, "notInvoked")
            XCTAssertEqual(quit["reductionUnsavedBefore"] as? Bool, false)
            XCTAssertEqual(quit["schedulerUnsavedBefore"] as? Bool, false)
            XCTAssertEqual(quit["quitDecision"] as? String, "terminate")
        }
    }

    func testQuitFlushFailureCancelsVisiblyAndLaterQuitSucceeds() async throws {
        let product = try await collecting()
        try await product.press(1)
        try await product.waitDurable()
        try await product.press(1)
        // A real write failure: the private store root stops accepting new files.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: product.storeRoot.path)
        await product.composition.requestQuit()
        XCTAssertEqual(product.terminateRequests, 0, "unsaved data must not be abandoned")
        XCTAssertEqual(product.phase, .collecting)
        XCTAssertEqual(product.composition.flow.noticeKey, "flow.actionUnavailable")
        XCTAssertEqual(product.composition.lifecycle.state.notice, .quitFlushFailed(.failed))
        let failed = try XCTUnwrap(product.actionEnds("quit").last)
        XCTAssertEqual(failed["lifecycleFlushCalls"] as? Int, 1)
        XCTAssertEqual(failed["lifecycleFlushOutcome"] as? String, "flushError.failed")
        XCTAssertEqual(failed["quitDecision"] as? String, "cancel")
        XCTAssertEqual(failed["schedulerUnsavedAfter"] as? Bool, true)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: product.storeRoot.path)
        await product.composition.requestQuit()
        XCTAssertEqual(product.terminateRequests, 1)
        XCTAssertEqual(product.phase, .stopped)
        XCTAssertEqual(try product.actionEnds("quit").last?["lifecycleFlushOutcome"] as? String, "saved")

        let next = product.relaunch()
        products.append(next)
        try await next.boot()
        try await waitUntil("restart collecting and published") {
            let live = await next.live
            return next.phase == .collecting && live && next.composition.flow.snapshot != nil
        }
        XCTAssertEqual(next.composition.flow.snapshot?.bareKeyTotal, 2, "both presses were saved")
    }

    func testLockDiscardsUnsavedDeltaKeepsDurableCountsAndLeavesNoDirtyFlag() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        try await product.press(3)
        try await product.lockScreen()
        XCTAssertFalse(product.composition.reduction.hasUnflushedChanges())
        let schedulerPending = await product.composition.scheduler.hasPendingChanges()
        XCTAssertFalse(schedulerPending)

        await product.composition.requestQuit()
        XCTAssertEqual(product.terminateRequests, 1)

        let next = product.relaunch()
        products.append(next)
        try await next.boot()
        try await waitUntil("restart collecting and published") {
            let live = await next.live
            return next.phase == .collecting && live && next.composition.flow.snapshot != nil
        }
        XCTAssertEqual(next.composition.flow.snapshot?.bareKeyTotal, 2,
                       "durable counts survive; deltas since the last durable save are discarded")
    }

    // MARK: - Secure Input monitor

    func testSecureInputClosesTheLiveSessionAndClearingItResumesAutomatically() async throws {
        let product = try await collecting()
        try await product.press(2)
        product.host.setSecureInput(.enabled)
        try await waitUntil("closed for Secure Input") {
            let live = await product.live
            return !live
        }
        XCTAssertEqual(try product.tap?.press(), .closed)
        XCTAssertEqual(product.phase, .collecting, "Secure Input is not a user-visible block")
        XCTAssertFalse(product.composition.flow.sensitiveContentVisible)
        XCTAssertNil(product.composition.flow.snapshot, "no statistics are published without a live session")
        XCTAssertNil(product.composition.flow.analysis)
        let begin = try XCTUnwrap(product.marks().last {
            $0["role"] as? String == "begin" && $0["phase"] as? String == "collecting"
                && $0["captureSessionLive"] as? Bool == false
                && $0["sensitiveContentVisible"] as? Bool == false
        })
        let beginSeq = try XCTUnwrap(begin["seq"] as? Int)
        XCTAssertEqual(begin["captureSessionLive"] as? Bool, false)
        XCTAssertEqual(begin["sensitiveContentVisible"] as? Bool, false)
        XCTAssertEqual(begin["phase"] as? String, "collecting")
        try await waitUntil("closed interval observed") {
            ((try? product.marks()) ?? []).contains {
                $0["role"] as? String == "observe" && ($0["seq"] as? Int ?? 0) > beginSeq
            }
        }
        try await Task.sleep(for: .milliseconds(600))
        let stillClosed = await product.live
        XCTAssertFalse(stillClosed, "no reopen while Secure Input stays on")

        product.host.setSecureInput(.disabled)
        try await waitUntil("resumed after Secure Input") {
            let live = await product.live
            return live && product.phase == .collecting
                && product.composition.flow.sensitiveContentVisible
        }
        let end = try XCTUnwrap(product.marks().last {
            $0["role"] as? String == "end" && ($0["seq"] as? Int ?? 0) > beginSeq
        })
        XCTAssertEqual(end["captureSessionLive"] as? Bool, true)
        XCTAssertEqual(product.phase, .collecting)
        try await product.press(1)
        try await waitUntil("retained and new counts published") {
            product.composition.flow.snapshot?.bareKeyTotal == 3
        }
    }

    func testFailedRebuildDuringSecureInputWaitsForItToClear() async throws {
        let product = try await collecting()
        product.host.setSecureInput(.enabled)
        // A foreground switch lands before the monitor's next read, as when a password page closes.
        XCTAssertEqual(product.tap?.report(.foregroundChanged), true)
        try await waitUntil("closed") {
            let live = await product.live
            return !live
        }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(product.phase, .collecting, "a Secure Input failure must not demand a manual Start")
        product.host.setSecureInput(.disabled)
        try await waitUntil("resumed") {
            let live = await product.live
            return live
        }
        try await product.press(1)
    }

    func testUnknownSecureInputStaysClosed() async throws {
        let product = try await collecting()
        product.host.setSecureInput(.unknown)
        try await waitUntil("closed for unknown") {
            let live = await product.live
            return !live
        }
        try await Task.sleep(for: .milliseconds(800))
        let live = await product.live
        XCTAssertFalse(live, "unknown is never treated as disabled")
        XCTAssertEqual(try product.tap?.press(), .closed)
    }

    func testLockDuringSecureInputStillNeedsExplicitStart() async throws {
        let product = try await collecting()
        product.host.setSecureInput(.enabled)
        try await waitUntil("closed") {
            let live = await product.live
            return !live
        }
        try await product.lockScreen()
        product.host.setSecureInput(.disabled)
        try await product.unlockScreen()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(product.phase, .blocked)
        let live = await product.live
        XCTAssertFalse(live, "clearing Secure Input must not bypass the lock recovery rule")
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
    }

    // MARK: - Secure Input monitor lifecycle

    private func closesForSecureInput(_ product: SyntheticProduct, _ label: String) async throws {
        product.host.setSecureInput(.enabled)
        try await waitUntil("\(label): Secure Input closes the session", timeout: .seconds(3)) {
            let live = await product.live
            return !live
        }
        product.host.setSecureInput(.disabled)
        try await waitUntil("\(label): cleared Secure Input resumes", timeout: .seconds(3)) {
            let live = await product.live
            return live && product.phase == .collecting
        }
    }

    func testMonitorSurvivesPrivacyClosureThatSkipsTheUnlockSync() async throws {
        let product = try await collecting()
        // A non-recoverable invalidation closes through handlePrivacyInvalidation, which
        // syncs without reconciling runtime tasks; the old poller sees blocked and exits.
        XCTAssertEqual(product.tap?.report(.sessionChanged), true)
        try await waitUntil("blocked") { product.phase == .blocked }
        try await Task.sleep(for: .milliseconds(600))
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        try await closesForSecureInput(product, "after privacy closure")
    }

    func testMonitorSurvivesLockUnlockAndStart() async throws {
        let product = try await collecting()
        try await product.lockScreen()
        try await product.unlockScreen()
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        try await closesForSecureInput(product, "after lock")
    }

    func testMonitorRestartsExactlyOncePerCollectingEntryAcrossRepeatedClosures() async throws {
        let product = try await collecting()
        let firstStarts = product.composition.secureInputMonitorStarts
        for round in 1...2 {
            XCTAssertEqual(product.tap?.report(.sessionChanged), true)
            try await waitUntil("blocked \(round)") { product.phase == .blocked }
            try await Task.sleep(for: .milliseconds(400))
            await product.composition.startOrRetry()
            XCTAssertEqual(product.phase, .collecting)
            try await closesForSecureInput(product, "round \(round)")
        }
        XCTAssertEqual(product.composition.secureInputMonitorStarts, firstStarts + 2,
                       "one new poller per return to collecting, never a duplicate")
    }

    func testStaleMonitorCannotCloseOrReopenAfterReplacement() async throws {
        let product = try await collecting()
        product.host.holdNextSecureInputReads(1)
        try await waitUntil("old monitor parked") { product.host.parkedSecureInputReads >= 1 }

        XCTAssertEqual(product.tap?.report(.sessionChanged), true)
        try await waitUntil("blocked") { product.phase == .blocked }
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        var live = await product.live
        XCTAssertTrue(live)

        product.host.completeNextSecureInputRead(.enabled)
        try await Task.sleep(for: .milliseconds(400))
        live = await product.live
        XCTAssertTrue(live, "a stale enabled read must not close the replacement session")
        XCTAssertEqual(product.phase, .collecting)

        product.host.holdNextSecureInputReads(1)
        try await waitUntil("replacement monitor parked") { product.host.parkedSecureInputReads >= 1 }
        await product.composition.flow.pause()
        XCTAssertEqual(product.phase, .paused)
        product.host.completeNextSecureInputRead(.disabled)
        try await Task.sleep(for: .milliseconds(400))
        live = await product.live
        XCTAssertFalse(live, "a stale disabled read must not reopen over a pause")
        XCTAssertEqual(product.phase, .paused)

        product.host.releaseSecureInputReads()
        await product.composition.resume()
        try await closesForSecureInput(product, "after stale replacement")
    }

    func testPauseAndQuitStopTheMonitorAndClearingSecureInputCannotReopen() async throws {
        let product = try await collecting()
        await product.composition.flow.pause()
        XCTAssertEqual(product.phase, .paused)
        product.host.setSecureInput(.enabled)
        try await Task.sleep(for: .milliseconds(400))
        product.host.setSecureInput(.disabled)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(product.phase, .paused, "clearing Secure Input must not override a pause")
        var live = await product.live
        XCTAssertFalse(live)

        await product.composition.resume()
        try await closesForSecureInput(product, "after resume")

        await product.composition.requestQuit()
        XCTAssertEqual(product.phase, .stopped)
        product.host.setSecureInput(.enabled)
        try await Task.sleep(for: .milliseconds(400))
        product.host.setSecureInput(.disabled)
        try await Task.sleep(for: .milliseconds(600))
        live = await product.live
        XCTAssertFalse(live, "a stopped product never reopens capture")
        XCTAssertEqual(product.phase, .stopped)
    }

    func testMonitorDoesNotActWhileMaintenanceRuns() async throws {
        let product = try await collecting()
        try await product.press(1)
        try await product.waitDurable()
        await product.keychain.holdDeletes()
        let erase = Task { await product.erase() }
        try await waitUntil("erase reached keychain deletion") { await product.keychain.deleteAttempts > 0 }
        let phaseDuring = product.phase
        let readiness = await product.readinessCalls
        product.host.setSecureInput(.enabled)
        try await Task.sleep(for: .milliseconds(400))
        product.host.setSecureInput(.disabled)
        product.composition.menuWillOpen(NSMenu())
        try await Task.sleep(for: .milliseconds(700))
        let readinessDuring = await product.readinessCalls
        let liveDuring = await product.live
        XCTAssertEqual(product.phase, phaseDuring, "the monitor must not move the lifecycle mid-erase")
        XCTAssertEqual(readinessDuring, readiness, "no recovery attempt during maintenance")
        XCTAssertFalse(liveDuring)
        await product.keychain.releaseDeletes()
        await erase.value
        XCTAssertEqual(product.phase, .unstarted)
    }

    // MARK: - Maintenance after privacy closure

    func testResetAfterPrivacyCloseRequiresAnOpenGateThenClearsCounts() async throws {
        let pausedLocked = try await collecting()
        try await pausedLocked.press(2)
        try await pausedLocked.waitDurable()
        await pausedLocked.composition.flow.pause()
        try await pausedLocked.lockScreen()
        try await pausedLocked.unlockScreen()
        await pausedLocked.reset()
        XCTAssertEqual(pausedLocked.phase, .paused, "lock recovery still requires Resume before reset")
        XCTAssertEqual(pausedLocked.composition.flow.noticeKey, "flow.actionUnavailable")
        let pausedLockedKeys = await pausedLocked.keychain.itemCount
        XCTAssertEqual(pausedLockedKeys, 2)
        await pausedLocked.composition.resume()
        try await waitUntil("resume after refused reset") {
            let live = await pausedLocked.live
            return live && pausedLocked.phase == .collecting && pausedLocked.composition.flow.snapshot?.bareKeyTotal == 2
        }

        let afterResume = try await collecting()
        try await afterResume.press(2)
        try await afterResume.waitDurable()
        await afterResume.composition.flow.pause()
        try await afterResume.lockScreen()
        try await afterResume.unlockScreen()
        await afterResume.composition.resume()
        await afterResume.reset()
        try await waitUntil("reset after Resume") {
            let live = await afterResume.live
            return live && afterResume.phase == .collecting && afterResume.composition.flow.snapshot?.bareKeyTotal == 0
        }
        XCTAssertNil(afterResume.composition.flow.noticeKey)
        let afterResumeKeys = await afterResume.keychain.itemCount
        XCTAssertEqual(afterResumeKeys, 2)

        let afterStart = try await collecting()
        try await afterStart.press(2)
        try await afterStart.waitDurable()
        try await afterStart.lockScreen()
        try await afterStart.unlockScreen()
        await afterStart.composition.startOrRetry()
        await afterStart.reset()
        try await waitUntil("reset after Start") {
            let live = await afterStart.live
            return live && afterStart.phase == .collecting && afterStart.composition.flow.snapshot?.bareKeyTotal == 0
        }
        XCTAssertNil(afterStart.composition.flow.noticeKey)
    }

    func testEraseAfterPrivacyCloseRequiresAnOpenGateThenWipesLocalData() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        try await product.lockScreen()
        try await product.unlockScreen()
        await product.erase()
        XCTAssertEqual(product.phase, .blocked)
        XCTAssertEqual(product.composition.lifecycle.state.blockedReason, .sessionLocked)
        XCTAssertEqual(product.composition.flow.noticeKey, "flow.actionUnavailable")
        let keysBeforeStart = await product.keychain.itemCount
        XCTAssertEqual(keysBeforeStart, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: product.storeRoot.path))

        await product.composition.startOrRetry()
        try await waitUntil("Start after refused erase") {
            let live = await product.live
            return live && product.phase == .collecting
        }
        await product.erase()
        XCTAssertEqual(product.phase, .unstarted)
        let keysAfterErase = await product.keychain.itemCount
        XCTAssertEqual(keysAfterErase, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: product.storeRoot.path))
    }

    func testFailedResetKeepsUnsavedCountsAndReloadsTheSameTotal() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        try await product.press(1)
        XCTAssertEqual(try product.composition.reduction.snapshot()?.bareKeyTotal, 3)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: product.storeRoot.path)
        await product.reset()
        let pending = await product.composition.scheduler.hasPendingChanges()
        XCTAssertTrue(pending, "a failed flush must leave the unsaved count pending")
        XCTAssertNotEqual(product.phase, .collecting)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: product.storeRoot.path)
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        XCTAssertEqual(try product.composition.reduction.snapshot()?.bareKeyTotal, 3,
                       "Start must not replace the unsaved count with the older durable total")
        try await product.waitDurable()
        let reloaded = try await relaunchCollecting(product)
        XCTAssertEqual(reloaded.composition.flow.snapshot?.bareKeyTotal, 3)
        try await reloaded.press(1)
        try await reloaded.waitDurable()
        let afterNewInput = try await relaunchCollecting(reloaded)
        XCTAssertEqual(afterNewInput.composition.flow.snapshot?.bareKeyTotal, 4,
                       "the recovered count is saved once, then a new count is added once")
    }

    func testFailedResetAfterWriterSuspendCanSaveNewCounts() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        let pendingBefore = await product.composition.scheduler.hasPendingChanges()
        XCTAssertFalse(pendingBefore)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: product.storeRoot.path)
        await product.reset()
        XCTAssertEqual(product.composition.flow.noticeKey, "flow.actionUnavailable")
        XCTAssertNotEqual(product.phase, .collecting)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: product.storeRoot.path)
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        try await product.press(1)
        do {
            try await product.composition.flush.flushWhileUnlocked()
        } catch {
            XCTFail("collecting after a failed reset must be able to finish a write: \(error)")
            return
        }
        let pending = await product.composition.scheduler.hasPendingChanges()
        XCTAssertFalse(pending, "collecting after a failed reset must be able to finish a write")
        let reloaded = try await relaunchCollecting(product)
        XCTAssertEqual(reloaded.composition.flow.snapshot?.bareKeyTotal, 3)
    }

    func testMenuOpenDoesNotRestartPulseWhileEraseIsHeld() async throws {
        let product = try await collecting()
        try await product.press(1)
        try await product.waitDurable()
        await product.keychain.holdDeletes()
        let erase = Task { await product.erase() }
        try await waitUntil("erase reached keychain deletion") { await product.keychain.deleteAttempts > 0 }
        XCTAssertEqual(product.composition.activePulseCount, 0)
        product.composition.menuWillOpen(NSMenu())
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(product.composition.activePulseCount, 0,
                       "opening the menu during maintenance must not start the pulse")
        XCTAssertEqual(product.phase, .collecting)
        await product.keychain.releaseDeletes()
        await erase.value
        XCTAssertEqual(product.phase, .unstarted)
        XCTAssertEqual(product.composition.activePulseCount, 0)
    }

    private func relaunchCollecting(_ product: SyntheticProduct) async throws -> SyntheticProduct {
        try await product.finishIssuedWrites()
        let next = product.relaunch()
        products.append(next)
        try await next.boot()
        try await waitUntil("reloaded collecting") {
            let live = await next.live
            return next.phase == .collecting && live && next.composition.flow.snapshot != nil
        }
        return next
    }

    func testUnfinishedResetUsesTheJournalOperationAcrossCancelAndRelaunch() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        let originalCycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        try await requireInterruptedReset(product)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: product.storeRoot.path)
        await product.reset()
        XCTAssertEqual(product.phase, .blocked)
        XCTAssertNotEqual(product.composition.flow.dialog, .none, "a failed confirm leaves the dialog reachable")
        await product.composition.flow.choose(.cancel)
        XCTAssertEqual(product.composition.flow.dialog, .none)
        product.composition.flow.requestReset()
        XCTAssertEqual(product.composition.flow.dialog, .none, "blocked no longer offers reset; Start is the recovery entry")
        await product.composition.startOrRetry()
        let liveWhileUnwritable = await product.live
        XCTAssertFalse(liveWhileUnwritable)
        XCTAssertNotEqual(product.phase, .collecting)
        let journalWhileBlocked = await product.composition.store.hasUnfinishedCycleReset()
        XCTAssertTrue(journalWhileBlocked)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: product.storeRoot.path)
        await product.composition.startOrRetry()
        let journalAfterStart = await product.composition.store.hasUnfinishedCycleReset()
        XCTAssertFalse(journalAfterStart)
        let recoveredCycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        XCTAssertNotEqual(recoveredCycle, originalCycle)
        let summary = try await recoveredSummary(product, cycle: originalCycle)
        XCTAssertEqual(summary.perBareKeyTotals.values.map(\.value).reduce(0, +), 2)
        await product.composition.startOrRetry()
        XCTAssertEqual(product.composition.lifecycle.state.preferences?.currentCycleID, recoveredCycle,
                       "a second recovery must not open another cycle")
        let summaryAgain = try await recoveredSummary(product, cycle: originalCycle)
        XCTAssertEqual(summaryAgain, summary)

        let reloaded = try await relaunchCollecting(product)
        XCTAssertEqual(reloaded.composition.lifecycle.state.preferences?.currentCycleID, recoveredCycle)
        XCTAssertEqual(reloaded.composition.flow.snapshot?.bareKeyTotal, 0)
        let journalAfterRelaunch = await reloaded.composition.store.hasUnfinishedCycleReset()
        XCTAssertFalse(journalAfterRelaunch)
        try await reloaded.press(1)
        try await reloaded.waitDurable()
        let afterInput = try await relaunchCollecting(reloaded)
        XCTAssertEqual(afterInput.composition.flow.snapshot?.bareKeyTotal, 1)
        let summaryAfterInput = try await recoveredSummary(afterInput, cycle: originalCycle)
        XCTAssertEqual(summaryAfterInput, summary)
    }

    func testRelaunchContinuesTheDurableResetBeforeCollecting() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        let originalCycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        try await requireInterruptedReset(product)
        let next = product.relaunch()
        products.append(next)
        try await next.boot()
        let live = await next.live
        let journal = await next.composition.store.hasUnfinishedCycleReset()
        XCTAssertFalse(journal)
        XCTAssertTrue(live)
        XCTAssertEqual(next.phase, .collecting)
        let recoveredCycle = try XCTUnwrap(next.composition.lifecycle.state.preferences?.currentCycleID)
        XCTAssertNotEqual(recoveredCycle, originalCycle)
        try await waitUntil("recovered cycle published") { next.composition.flow.snapshot != nil }
        XCTAssertEqual(next.composition.flow.snapshot?.bareKeyTotal, 0)
        let summary = try await recoveredSummary(next, cycle: originalCycle)
        XCTAssertEqual(summary.perBareKeyTotals.values.map(\.value).reduce(0, +), 2)
        let again = next.relaunch()
        products.append(again)
        try await again.boot()
        XCTAssertEqual(again.composition.lifecycle.state.preferences?.currentCycleID, recoveredCycle)
        try await waitUntil("second launch published") { again.composition.flow.snapshot != nil }
        XCTAssertEqual(again.composition.flow.snapshot?.bareKeyTotal, 0)
        let summaryAgain = try await recoveredSummary(again, cycle: originalCycle)
        XCTAssertEqual(summaryAgain, summary)
    }

    func testUnreadableResetJournalDoesNotReportRecoverySuccess() async throws {
        let product = try await collecting()
        try await product.press(1)
        try await product.waitDurable()
        let originalCycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        try await requireInterruptedReset(product)
        try await corruptUnindexedStoreFiles(product)
        let next = product.relaunch()
        products.append(next)
        try await next.boot()
        let live = await next.live
        XCTAssertFalse(live)
        XCTAssertNotEqual(next.phase, .collecting)
        let stillPending = await next.composition.store.hasUnfinishedCycleReset()
        XCTAssertTrue(stillPending, "an unreadable journal must stay on disk")
        if let cycle = next.composition.lifecycle.state.preferences?.currentCycleID {
            XCTAssertEqual(cycle, originalCycle)
        }
    }

    func testPartialEraseRetryClearsTheBlockAndAcceptsFreshConsent() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        await product.keychain.failNextDeleteOnce()
        await product.erase()
        XCTAssertEqual(product.phase, .blocked)
        let remaining = await product.keychain.itemCount
        XCTAssertEqual(remaining, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: product.storeRoot.path))
        await product.composition.startOrRetry()
        let liveWhilePartial = await product.live
        XCTAssertFalse(liveWhilePartial)
        XCTAssertNotEqual(product.phase, .collecting)

        await product.erase()
        XCTAssertEqual(product.phase, .unstarted)
        let keys = await product.keychain.itemCount
        XCTAssertEqual(keys, 0)
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .consent)
        await product.composition.flow.accept()
        try await waitUntil("fresh consent collects") {
            let live = await product.live
            return product.phase == .collecting && live
        }
        try await product.press(1)
        try await product.waitDurable()
        let reloaded = try await relaunchCollecting(product)
        XCTAssertEqual(reloaded.composition.flow.snapshot?.bareKeyTotal, 1)
    }

    private func requireInterruptedReset(_ product: SyntheticProduct) async throws {
        try await product.finishIssuedWrites()
        do {
            _ = try await product.composition.store.resetCycle(
                operationID: UUID(), day: ProductClock().day,
                injection: CycleResetInjection(summaryWrite: DurabilityInjection(failPhase: .data, failAt: .afterWrite)))
            XCTFail("injected summary write must fail after the journal is durable")
        } catch {
            let text = String(describing: error)
            guard text.contains("injected-data-afterWrite") else {
                XCTFail("fixture stopped before the summary write: \(text)")
                throw error
            }
        }
        let pending = await product.composition.store.hasUnfinishedCycleReset()
        XCTAssertTrue(pending, "the injected failure must leave the reset journal")
    }

    func testSplitDurabilitySampleCanPassWhileTheCountIsStillPending() async throws {
        let product = try await collecting()
        await product.composition.stopBackgroundMaintenanceForFixture()
        try await product.press(1)
        let sampledPending = await product.composition.scheduler.hasPendingChanges()
        XCTAssertFalse(sampledPending)
        try await product.composition.flush.stage()
        let sampledDirty = product.composition.reduction.hasUnflushedChanges()
        let oldPredicate = !sampledDirty && !sampledPending
        let actualPending = await product.composition.scheduler.hasPendingChanges()
        let cycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        let before = try await AggregatePersistence.restore(cycleID: cycle,
            store: product.composition.store, gate: product.composition.gate)
        let beforeTotal = try AggregateSnapshot(shortcuts: before.shortcuts, bareKeys: before.bareKeys).bareKeyTotal
        XCTAssertTrue(oldPredicate, "separate dirty and pending reads can both look saved")
        XCTAssertTrue(actualPending)
        XCTAssertEqual(beforeTotal, 0)
        try await product.waitDurable()
        let after = try await AggregatePersistence.restore(cycleID: cycle,
            store: product.composition.store, gate: product.composition.gate)
        let afterTotal = try AggregateSnapshot(shortcuts: after.shortcuts, bareKeys: after.bareKeys).bareKeyTotal
        XCTAssertEqual(afterTotal, 1)
        let pending = await product.composition.scheduler.hasPendingChanges()
        XCTAssertFalse(pending)
    }

    func testSameSessionResetRecoveryPersistsNewInputBeforeRelaunch() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        try await requireInterruptedReset(product)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: product.storeRoot.path)
        await product.reset()
        await product.composition.flow.choose(.cancel)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: product.storeRoot.path)
        await product.composition.startOrRetry()
        XCTAssertEqual(product.phase, .collecting)
        let live = await product.live
        XCTAssertTrue(live)
        try await product.press(1)
        do {
            try await product.composition.flush.flushWhileUnlocked()
        } catch {
            XCTFail("same-session recovery must persist the new count: \(error)")
            return
        }
        let pending = await product.composition.scheduler.hasPendingChanges()
        XCTAssertFalse(pending)
        XCTAssertEqual(try product.composition.reduction.snapshot()?.bareKeyTotal, 1)
        let reloaded = try await relaunchCollecting(product)
        XCTAssertEqual(reloaded.composition.flow.snapshot?.bareKeyTotal, 1)
    }

    func testNewResetAfterRecoveryStartsADistinctCycle() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        let originalCycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        try await requireInterruptedReset(product)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: product.storeRoot.path)
        await product.reset()
        await product.composition.flow.choose(.cancel)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: product.storeRoot.path)
        await product.composition.startOrRetry()
        let recoveredCycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        XCTAssertNotEqual(recoveredCycle, originalCycle)
        try await product.press(1)
        try await product.waitDurable()
        await product.reset()
        try await waitUntil("new reset collects") {
            let live = await product.live
            return live && product.phase == .collecting
                && product.composition.lifecycle.state.preferences?.currentCycleID != recoveredCycle
        }
        let newerCycle = try XCTUnwrap(product.composition.lifecycle.state.preferences?.currentCycleID)
        XCTAssertNotEqual(newerCycle, recoveredCycle)
        let summary = try await recoveredSummary(product, cycle: recoveredCycle)
        XCTAssertEqual(summary.perBareKeyTotals.values.map(\.value).reduce(0, +), 1)
        XCTAssertEqual(try product.composition.reduction.snapshot()?.bareKeyTotal, 0)
    }

    private func recoveredSummary(_ product: SyntheticProduct, cycle: CycleID) async throws -> CycleSummary {
        let data = try await product.composition.store.read(CycleResetObjects.summary(cycle))
        return try JSONDecoder().decode(CycleSummary.self, from: data)
    }

    private func corruptUnindexedStoreFiles(_ product: SyntheticProduct) async throws {
        let indexed = Set(try await product.composition.store.entries().map(\.locator.fileName))
        let names = try FileManager.default.contentsOfDirectory(atPath: product.storeRoot.path)
        var corrupted = 0
        for name in names where name.hasSuffix(".krenc") && name != ManifestDiscovery.fileName && !indexed.contains(name) {
            let url = product.storeRoot.appendingPathComponent(name)
            var data = try Data(contentsOf: url)
            if data.isEmpty { data = Data([1]) } else { data[0] ^= 0xFF }
            try data.write(to: url)
            corrupted += 1
        }
        XCTAssertGreaterThan(corrupted, 0)
    }

    func testFailedResetLeavesAnExplicitStartPath() async throws {
        let product = try await collecting()
        try await product.press(2)
        try await product.waitDurable()
        try await product.press(1)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: product.storeRoot.path)
        await product.reset()
        XCTAssertEqual(product.composition.flow.noticeKey, "flow.actionUnavailable")
        XCTAssertEqual(product.composition.lifecycle.state.preferences?.expectedCollecting, true)
        let liveDuringFailure = await product.live
        XCTAssertFalse(liveDuringFailure)
        XCTAssertNotEqual(product.phase, .collecting, "a dead collecting session must not remain after failed reset")

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: product.storeRoot.path)
        await product.composition.startOrRetry()
        try await waitUntil("Start after failed reset") {
            let live = await product.live
            return live && product.phase == .collecting
        }
        XCTAssertEqual(product.composition.lifecycle.state.preferences?.expectedCollecting, true)
    }

    func testBackgroundPulsePersistsCountsWithoutAnExplicitFlush() async throws {
        let product = try await collecting()
        XCTAssertEqual(product.composition.activePulseCount, 1)
        try await product.press(2)
        let first = try await product.waitForPulseWrite(2)
        XCTAssertEqual(first, 2)
        try await product.press(1)
        let total = try await product.waitForPulseWrite(3)
        XCTAssertEqual(total, 3)
        XCTAssertEqual(product.composition.activePulseCount, 1)
    }

    func testDiskReadDoesNotSaveWhenThePulseIsStopped() async throws {
        let product = try await collecting()
        await product.composition.stopBackgroundMaintenanceForFixture()
        XCTAssertEqual(product.composition.activePulseCount, 0)
        try await product.press(2)
        let deadline = ContinuousClock().now.advanced(by: .seconds(8))
        var last = Int64.min
        while ContinuousClock().now < deadline {
            last = try await product.diskBareTotal()
            if last != 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(last, 0, "stopping the pulse must leave the same disk read at zero")
        XCTAssertEqual(product.composition.reduction.hasUnflushedChanges(), true)
    }

    // MARK: - System-state witness

    func testWitnessReportsSecureInputWhileCollectingWithoutRelyingOnClosure() async throws {
        let product = try await collecting()
        XCTAssertTrue(product.composition.startSystemWitness(seconds: 1, interval: .milliseconds(100)))
        XCTAssertFalse(product.composition.startSystemWitness(seconds: 1), "one bounded window per launch")
        try await Task.sleep(for: .milliseconds(250))
        product.host.setSecureInput(.enabled)
        try await waitUntil("product closed for Secure Input") {
            let live = await product.live
            return !live
        }
        try await Task.sleep(for: .milliseconds(250))
        product.host.setSecureInput(.unknown)
        try await Task.sleep(for: .milliseconds(250))
        product.composition.stopSystemWitness()

        let witness = try product.marks().filter { $0["role"] as? String == "witness" }
        let reads = witness.compactMap { $0["secureInputReadStatus"] as? String }
        XCTAssertTrue(reads.contains("disabled"))
        XCTAssertTrue(reads.contains("enabled"))
        XCTAssertTrue(reads.contains("unknown"))
        XCTAssertTrue(witness.contains { $0["cachedSecureInputState"] as? String == "enabled" },
                      "the monitor publishes the provider read into the lifecycle")
        // The witness reads independently; the product's own monitor closes the session.
        XCTAssertTrue(witness.contains {
            $0["secureInputReadStatus"] as? String == "enabled" && $0["captureSessionLive"] as? Bool == false
        })
        XCTAssertTrue(witness.allSatisfy { $0["protectedSnapshotAttempts"] != nil })
    }

    func testWitnessRequiresJournalAndABoundedWindow() async throws {
        let product = try SyntheticProduct.fresh()
        products.append(product)
        try await product.boot()
        XCTAssertFalse(product.composition.startSystemWitness(seconds: 0))
        XCTAssertFalse(product.composition.startSystemWitness(
            seconds: ProductComposition.systemWitnessLimitSeconds + 1))
        func witnessLines() throws -> Int { try product.marks().filter { $0["role"] as? String == "witness" }.count }
        XCTAssertEqual(try witnessLines(), 0)
        XCTAssertTrue(product.composition.startSystemWitness(seconds: 1, interval: .milliseconds(100)))
        try await Task.sleep(for: .milliseconds(1_400))
        let after = try witnessLines()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertGreaterThan(after, 3)
        XCTAssertEqual(try witnessLines(), after, "the witness stops at its deadline")
    }

    func testWitnessDoesNothingWithoutJournal() async throws {
        let product = try SyntheticProduct.fresh()
        products.append(product)
        try await product.boot(journal: false)
        XCTAssertFalse(product.composition.startSystemWitness(seconds: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: product.journal.path))
    }
}

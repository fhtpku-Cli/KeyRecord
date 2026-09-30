#if DEBUG
import Foundation
import Security
import XCTest
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore
import LifecyclePreflight

private enum CompositionTrialError: Error {
    case timeout(String), unexpectedState, cleanupIncomplete
}

private final class CompositionSignals: FrontmostAppProvider, SecureInputProvider,
    SessionLockProvider, InputMonitoringPermission, @unchecked Sendable {
    private let mutex = NSLock()
    private var locked = false
    func setLocked(_ value: Bool) { mutex.withLock { locked = value } }
    func sessionLockState() async -> SessionLockState { mutex.withLock { locked ? .locked : .unlocked } }
    func secureInputState() async -> SecureInputState { .disabled }
    func foregroundState() async -> ForegroundState { .attributable(bundleID: "synthetic.editor") }
    func preflight() -> InputMonitoringStatus { .granted }
    func request() -> InputMonitoringStatus { .granted }
}

private struct CompositionLogin: LoginItemBackend {
    func register() async throws {}
    func unregister() async throws {}
}

@MainActor
private final class CompositionNotifications: LockNotificationCentering {
    private var handlers: [Notification.Name: [@Sendable () -> Void]] = [:]
    func addObserver(for name: Notification.Name,
                     handler: @escaping @Sendable () -> Void) -> any NSObjectProtocol {
        handlers[name, default: []].append(handler)
        return NSObject()
    }
    func post(_ name: Notification.Name) { handlers[name]?.forEach { $0() } }
}

// Track successful creates at the Security client boundary, including metadata adds.
// A failed product start must still clean up items created before that failure.
private final class CompositionOwnedClient: LocalKeychainClient, @unchecked Sendable {
    private let client: AuthorizedProductKeychainClient
    private let mutex = NSLock()
    private var created: [String] = []
    private var firstFailure: String?
    init(_ client: AuthorizedProductKeychainClient) { self.client = client }
    var ownedAccounts: [String] { mutex.withLock { created } }
    var failureSummary: String { mutex.withLock { firstFailure ?? "none" } }
    private func operation<T>(_ name: String, _ body: () throws -> (T, OSStatus)) throws -> T {
        do {
            let (value, status) = try body()
            let allowedAbsence = status == errSecItemNotFound && (name == "read" || name == "delete")
            if status != errSecSuccess && !allowedAbsence {
                mutex.withLock { if firstFailure == nil { firstFailure = "\(name):status=\(status)" } }
            }
            return value
        } catch {
            let cause = (error as? PreflightBlock).map { String(describing: $0) } ?? "clientError"
            mutex.withLock { if firstFailure == nil { firstFailure = "\(name):\(cause)" } }
            throw error
        }
    }
    func copyMatching(_ query: [String: Any]) throws -> LocalKeychainMatch {
        try operation("read") { let result = try client.copyMatching(query); return (result, result.status) }
    }
    func add(_ attributes: [String: Any]) throws -> OSStatus {
        let status = try operation("add") { let status = try client.add(attributes); return (status, status) }
        if status == errSecSuccess, let account = attributes[kSecAttrAccount as String] as? String {
            mutex.withLock { if !created.contains(account) { created.append(account) } }
        }
        return status
    }
    func update(_ query: [String: Any], attributes: [String: Any]) throws -> OSStatus {
        try operation("update") { let status = try client.update(query, attributes: attributes); return (status, status) }
    }
    func delete(_ query: [String: Any]) throws -> OSStatus {
        try operation("delete") { let status = try client.delete(query); return (status, status) }
    }

    func cleanup() throws {
        var firstFailure: (any Error)?
        for account in ownedAccounts.reversed() {
            do {
                let identity = LocalKeychainQueries.productIdentity(service: client.namespace.service, account: account)
                let status = try client.delete(identity)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw CompositionTrialError.cleanupIncomplete
                }
                let result = try client.copyMatching(LocalKeychainQueries.queryForReadingData(identity: identity))
                guard result.status == errSecItemNotFound else { throw CompositionTrialError.cleanupIncomplete }
            } catch { if firstFailure == nil { firstFailure = error } }
        }
        if let firstFailure { throw firstFailure }
    }
}

@MainActor
private final class CompositionFixture {
    let signals = CompositionSignals()
    let notifications = CompositionNotifications()
    let replay = FixedReplayController()
    let product: ProductComposition

    init(root: URL, namespace: KeychainNamespace, backend: LocalKeychainBackend) async throws {
        let signals = signals, replay = replay
        var boundaries = ProductHostBoundaries(storeRoot: root, namespace: namespace,
            backend: backend, login: CompositionLogin(), localCapture: LocalDevelopmentCapture(armed: true),
            eventSource: { queue, qualification, _ in
                ListenOnlyEventSource.fixedReplay(queue: queue, qualification: qualification,
                    providers: CaptureProviderSet(foreground: signals, secureInput: signals, sessionLock: signals),
                    controller: replay, permission: signals)
            })
        boundaries.sessionLock = signals
        boundaries.foreground = signals
        boundaries.secureInput = signals
        boundaries.lockNotifications = notifications
        boundaries.terminate = {}
        product = try await ProductComposition.makeSynthetic(boundaries)
        await product.restoreRuntime()
    }

    func start(fresh: Bool) async throws {
        await product.startOrRetry()
        if fresh {
            guard product.lifecycle.phase == .consent else { throw CompositionTrialError.unexpectedState }
            await product.flow.accept()
        }
        try await wait("start") { self.product.lifecycle.phase == .collecting && self.product.captureSessionLive }
    }

    func emitOne() async throws {
        let before = product.diagnostics.runSummary.aggregateDelta
        guard replay.emit(tick: 1) == 2 else { throw CompositionTrialError.unexpectedState }
        try await wait("input") { self.product.diagnostics.runSummary.aggregateDelta == before + 1 }
        try await product.flush.flushWhileUnlocked()
    }

    func total() async throws -> Int64 {
        guard let cycle = product.lifecycle.state.preferences?.currentCycleID else {
            throw CompositionTrialError.unexpectedState
        }
        let aggregate = try await AggregatePersistence.restore(cycleID: cycle, store: product.store, gate: product.gate)
        return try AggregateSnapshot(shortcuts: aggregate.shortcuts, bareKeys: aggregate.bareKeys).bareKeyTotal
    }

    func closeForSimulatedLock() async throws {
        signals.setLocked(true)
        notifications.post(ProductComposition.screenLockedNotification)
        try await wait("simulated-lock") {
            let state = self.product.diagnostics.runSummary
            return self.product.lifecycle.phase == .blocked && state.captureQueueOpen == false
                && state.keyGateOpen == false && !state.captureSessionLive && !state.sensitiveContentVisible
        }
    }

    func stop() async {
        await product.stopBackgroundMaintenanceForFixture()
        await product.requestQuit()
        await product.capture.stop()
        await product.scheduler.waitForIssuedWrite()
    }

    private func wait(_ step: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let state = product.lifecycle.state
        throw CompositionTrialError.timeout("step=\(step) phase=\(state.phase) "
            + "reason=\(String(describing: state.blockedReason)) failure=\(String(describing: state.failure)) "
            + "load=\(String(describing: ProductPersistence.lastLoadFailure))")
    }
}

final class HostedProductCompositionTests: XCTestCase {
    func testFullCompositionWithSlowAuthorization() async throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(namespace: fixture.namespace,
            accounts: ["metadata", "master-v1", "master-v2"], client: memory, evidence: {
                Thread.sleep(forTimeInterval: 0.1)
                return evidence
            }))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-composition-slow-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try await run(root: root, namespace: fixture.namespace, client: client)
    }

    func testFullCompositionWithGuardedMemoryKeychain() async throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(namespace: fixture.namespace,
            accounts: ["metadata", "master-v1", "master-v2"], client: memory, evidence: { evidence }))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-composition-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try await run(root: root, namespace: fixture.namespace, client: client)
        XCTAssertEqual(Set(client.ownedAccounts), ["metadata", "master-v1"])
        XCTAssertFalse(memory.queries.isEmpty)
    }

    func testCleanupDoesNotDeletePreexistingOrRejectedItems() throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(namespace: fixture.namespace,
            accounts: ["metadata", "master-v1"], client: memory, evidence: { evidence }))
        let identity = LocalKeychainQueries.productIdentity(service: fixture.namespace.service, account: "metadata")
        let attributes = LocalKeychainQueries.attributesForAdd(identity: identity, data: Data([1]),
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        XCTAssertEqual(memory.add(attributes), errSecSuccess)
        XCTAssertEqual(try client.add(attributes), errSecDuplicateItem)
        XCTAssertTrue(client.ownedAccounts.isEmpty)
        try client.cleanup()
        XCTAssertEqual(memory.copyMatching(LocalKeychainQueries.queryForReadingData(identity: identity)).status,
                       errSecSuccess)
    }

    func testAuthorizedProductCompositionWithRealKeychainAndSimulatedInput() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KEYRECORD_HOSTED_PRODUCT_COMPOSITION_TRIAL"] == "1" else {
            throw XCTSkip("No authorized full product composition trial requested")
        }
        let path = try XCTUnwrap(environment["PHASE1_QA_ATTEMPT"])
        guard path.hasPrefix("/") else { throw PreflightBlock.scratchRootMismatch }
        let attempt = URL(fileURLWithPath: path).standardizedFileURL
        let namespace = ProbeNamespace(attempt: attempt.lastPathComponent, seed: UUID())
        let evidence = SignedCandidateBackend.evidence(attempt: attempt)
        guard case .ready = SignedEffectGate.authorizeKeychain(namespace: namespace, evidence: evidence,
                                                               expectedNamespace: namespace),
              case .success(let manifest) = evidence.manifest, manifest.operations == [.keychain] else {
            throw PreflightBlock.operationAllowlistMismatch
        }
        let record = attempt.appendingPathComponent("product-composition-service.txt")
        guard !FileManager.default.fileExists(atPath: record.path),
              FileManager.default.createFile(atPath: record.path, contents: Data(namespace.service.utf8),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let root = attempt.appendingPathComponent("product-composition-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(attempt: attempt,
            namespace: namespace, accounts: ["metadata", "master-v1", "master-v2"]))
        try await run(root: root, namespace: namespace, client: client)
    }

    private func run(root: URL, namespace: ProbeNamespace, client: CompositionOwnedClient) async throws {
        var failure: (any Error)?
        do {
            let backend = LocalKeychainBackend(client: client)
            let productNamespace = try KeychainNamespace(namespace.service)
            for id in [KeychainItemID.metadata(productNamespace), .key(productNamespace, .init(rawValue: 1)),
                       .key(productNamespace, .init(rawValue: 2))] {
                guard try await backend.read(id) == nil else { throw KeyringError.duplicateItem }
            }
            try await Self.exercise(root: root.appendingPathComponent("store"), namespace: productNamespace, backend: backend)
        } catch {
            print("COMPOSITION failure=\(error) ownedItemCount=\(client.ownedAccounts.count) client=\(client.failureSummary)")
            failure = error
        }
        do {
            try client.cleanup()
            print("COMPOSITION cleanupVerified=\(client.ownedAccounts.count)")
        }
        catch {
            XCTFail("Full product test-item cleanup blocked; inspect the retained service record")
            if failure == nil { failure = error }
        }
        if let failure { throw failure }
    }

    @MainActor
    private static func exercise(root: URL, namespace: KeychainNamespace, backend: LocalKeychainBackend) async throws {
        var products: [CompositionFixture] = []
        var failure: (any Error)?
        do {
            let first = try await CompositionFixture(root: root, namespace: namespace, backend: backend)
            products.append(first)
            try await first.start(fresh: true)
            try await first.emitOne()
            try await first.emitOne()
            let saved = try await first.total()
            XCTAssertEqual(saved, 2)
            try await first.closeForSimulatedLock()
            XCTAssertEqual(first.replay.emit(tick: 1), 0)
            let observer = try XCTUnwrap(CounterWindowProductObserver(recorder: first.product.diagnostics, interval: 0.05))
            var simulatedAuthority = SessionLockQualification(supported: true)
            let locked = try simulatedAuthority.advance(.init(challenge: simulatedAuthority.challenge, unlocked: false),
                                                        expectedUnlocked: false).get()
            let closed = await Task.detached { observer.observe(step: .lockBackground, transition: locked) }.value
            assertClosed(closed)
            first.signals.setLocked(false)
            first.notifications.post(ProductComposition.screenUnlockedNotification)
            let unlocked = try simulatedAuthority.advance(.init(challenge: simulatedAuthority.challenge, unlocked: true),
                                                          expectedUnlocked: true).get()
            let waiting = await Task.detached { observer.observe(step: .unlockRevalidate, transition: unlocked) }.value
            assertClosed(waiting)
            try await first.start(fresh: false)
            let recovered = try await first.total()
            XCTAssertEqual(recovered, 2)
            await first.stop()

            let reopened = try await CompositionFixture(root: root, namespace: namespace, backend: backend)
            products.append(reopened)
            try await reopened.start(fresh: false)
            let reloaded = try await reopened.total()
            XCTAssertEqual(reloaded, 2)
            try await reopened.emitOne()
            let final = try await reopened.total()
            XCTAssertEqual(final, 3)
        } catch { failure = error }
        for product in products.reversed() { await product.stop() }
        if let failure { throw failure }
    }

    private static func assertClosed(_ observation: HostedProductObservation?) {
        XCTAssertEqual(observation?.captureClosed, true)
        XCTAssertEqual(observation?.protectedReadDelta, 0)
        XCTAssertEqual(observation?.publishDelta, 0)
        XCTAssertEqual(observation?.aggregateDelta, 0)
    }
}
#endif

#if DEBUG
import Foundation
import Security
import XCTest
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore
import LifecyclePreflight

private enum CompositionTrialError: Error {
    case timeout(String), unexpectedState, stateMismatch(String), cleanupIncomplete
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
    private var attemptedOperations = 0
    private let recordOwnership: @Sendable ([String]) throws -> Void
    init(_ client: AuthorizedProductKeychainClient, adopting accounts: [String] = [],
         recordOwnership: @escaping @Sendable ([String]) throws -> Void = { _ in }) {
        self.client = client
        self.created = accounts
        self.recordOwnership = recordOwnership
    }
    var ownedAccounts: [String] { mutex.withLock { created } }
    var failureSummary: String { mutex.withLock { firstFailure ?? "none" } }
    var operationCount: Int { mutex.withLock { attemptedOperations } }
    private func operation<T>(_ name: String, _ body: () throws -> (T, OSStatus)) throws -> T {
        mutex.withLock { attemptedOperations += 1 }
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
            try recordOwnership(ownedAccounts)
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

private struct CompositionRestartRecord: Codable, Sendable {
    let attempt: String
    let seed: UUID
    let seedPID: Int32
    var accounts: [String] = []
    var savedTotal: Int64?

    static let name = "product-restart.json"
    static func read(at root: URL, currentPID: Int32) throws -> Self {
        let url = root.appendingPathComponent(name)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) < 4096 else {
            throw CompositionTrialError.stateMismatch("restart-record-file")
        }
        let record = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard record.attempt == root.lastPathComponent, record.seedPID > 0,
              record.seedPID != currentPID, record.savedTotal == 2,
              record.accounts.count == 2, Set(record.accounts) == ["metadata", "master-v1"] else {
            throw CompositionTrialError.stateMismatch("restart-record-content")
        }
        return record
    }

    func write(at root: URL, initial: Bool = false) throws {
        let url = root.appendingPathComponent(Self.name)
        let data = try JSONEncoder().encode(self)
        if initial {
            try data.write(to: url, options: .withoutOverwriting)
        } else {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw CompositionTrialError.stateMismatch("restart-record-file")
            }
            try data.write(to: url, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor
private final class CompositionFixture {
    let signals = CompositionSignals()
    let notifications = CompositionNotifications()
    let replay = FixedReplayController()
    let product: ProductComposition

    init(root: URL, namespace: KeychainNamespace, backend: LocalKeychainBackend,
         lockProvider: (any SessionLockProvider)? = nil,
         lockNotifications: (any LockNotificationCentering)? = nil) async throws {
        let signals = signals, replay = replay
        var boundaries = ProductHostBoundaries(storeRoot: root, namespace: namespace,
            backend: backend, login: CompositionLogin(), localCapture: LocalDevelopmentCapture(armed: true),
            eventSource: { queue, qualification, sessionLock in
                ListenOnlyEventSource.fixedReplay(queue: queue, qualification: qualification,
                    providers: CaptureProviderSet(foreground: signals, secureInput: signals, sessionLock: sessionLock),
                    controller: replay, permission: signals)
            })
        boundaries.sessionLock = lockProvider ?? signals
        boundaries.foreground = signals
        boundaries.secureInput = signals
        boundaries.lockNotifications = lockNotifications ?? notifications
        boundaries.terminate = {}
        product = try await ProductComposition.makeSynthetic(boundaries)
        await product.restoreRuntime()
    }

    func start(fresh: Bool) async throws {
        await product.startOrRetry()
        if fresh {
            guard product.lifecycle.phase == .consent else {
                throw CompositionTrialError.stateMismatch("fresh-consent phase=\(product.lifecycle.phase) "
                    + "reason=\(String(describing: product.lifecycle.state.blockedReason)) "
                    + "failure=\(String(describing: product.lifecycle.state.failure))")
            }
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
        try await waitForClosed()
        try await wait("simulated-lock") { self.product.lifecycle.phase == .blocked }
    }

    func waitForClosed() async throws {
        try await wait("closed") {
            let state = self.product.diagnostics.runSummary
            return self.product.lifecycle.phase != .collecting && state.captureQueueOpen == false
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
        let (root, namespace, client) = try authorizedResources(
            optIn: "KEYRECORD_HOSTED_PRODUCT_COMPOSITION_TRIAL",
            recordName: "product-composition-service.txt", operations: [.keychain])
        try await run(root: root, namespace: namespace, client: client)
    }

    @MainActor
    func testLockedStartupWithGuardedMemoryKeychain() async throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(namespace: fixture.namespace,
            accounts: ["metadata", "master-v1", "master-v2"], client: memory, evidence: { evidence }))
        let signals = CompositionSignals()
        signals.setLocked(true)
        let notifications = CompositionNotifications()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-locked-startup-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.runLockedStartup(root: root, namespace: fixture.namespace, client: client,
            provider: { signals }, notifications: { notifications }, unlock: {
                signals.setLocked(false)
                notifications.post(ProductComposition.screenUnlockedNotification)
            })
    }

    func testAuthorizedProductStartupWhileLocked() async throws {
        let (root, namespace, client) = try authorizedResources(
            optIn: "KEYRECORD_HOSTED_LOCKED_STARTUP_TRIAL",
            recordName: "product-locked-startup-service.txt", operations: [.keychain, .screen])
        try await Self.runLockedStartup(root: root, namespace: namespace, client: client,
            provider: { SystemSessionLockProvider() }, notifications: { DistributedLockNotifications() },
            unlock: {
                print("LOCKED_STARTUP readyForUnlock")
                let observer = SystemSessionLockProvider()
                let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                while ContinuousClock.now < deadline {
                    if await observer.sessionLockState() == .unlocked { return }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw CompositionTrialError.timeout("waiting-for-owner-unlock")
            })
    }

    func testAuthorizedProductRestartSeed() async throws {
        let root = try restartAttempt()
        let record = CompositionRestartRecord(attempt: root.lastPathComponent, seed: UUID(), seedPID: getpid())
        let namespace = ProbeNamespace(attempt: record.attempt, seed: record.seed)
        try authorizeRestart(at: root, namespace: namespace)
        guard await SystemSessionLockProvider().sessionLockState() == .unlocked else {
            throw CompositionTrialError.stateMismatch("seed-requires-unlocked")
        }
        let store = root.appendingPathComponent("restart-store")
        guard !FileManager.default.fileExists(atPath: store.path) else {
            throw CompositionTrialError.stateMismatch("restart-store-already-exists")
        }
        try record.write(at: root, initial: true)
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(attempt: root,
            namespace: namespace, accounts: ["metadata", "master-v1", "master-v2"]), recordOwnership: { accounts in
                var updated = record
                updated.accounts = accounts
                try updated.write(at: root)
            })
        do {
            let backend = LocalKeychainBackend(client: client)
            let productNamespace = try KeychainNamespace(namespace.service)
            for id in [KeychainItemID.metadata(productNamespace), .key(productNamespace, .init(rawValue: 1)),
                       .key(productNamespace, .init(rawValue: 2))] {
                guard try await backend.read(id) == nil else { throw KeyringError.duplicateItem }
            }
            try await Self.seedRestart(root: store, namespace: productNamespace, backend: backend,
                provider: SystemSessionLockProvider(), notifications: DistributedLockNotifications())
            guard Set(client.ownedAccounts) == ["metadata", "master-v1"], client.ownedAccounts.count == 2 else {
                throw CompositionTrialError.stateMismatch("seed-ownership")
            }
            var completed = record
            completed.accounts = client.ownedAccounts
            completed.savedTotal = 2
            try completed.write(at: root)
            print("LOCKED_RESTART seeded=2 pid=\(getpid()) retainedItems=2")
        } catch {
            var retained = record
            retained.accounts = client.ownedAccounts
            do { try retained.write(at: root) }
            catch { print("LOCKED_RESTART ownershipRecordWriteFailed=true") }
            print("LOCKED_RESTART seedFailed service=\(namespace.service) ownedAccounts=\(client.ownedAccounts.joined(separator: ","))")
            if await SystemSessionLockProvider().sessionLockState() == .unlocked {
                try client.cleanup()
                print("LOCKED_RESTART seedFailureCleanupVerified=\(client.ownedAccounts.count)")
            } else {
                print("LOCKED_RESTART cleanupDeferred=true")
            }
            throw error
        }
    }

    @MainActor
    func testExistingStoreLockedReconstructionWithMemoryKeychain() async throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let authorized = AuthorizedProductKeychainClient(namespace: fixture.namespace,
            accounts: ["metadata", "master-v1", "master-v2"], client: memory, evidence: { evidence })
        let seedClient = CompositionOwnedClient(authorized)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-restart-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let signals = CompositionSignals()
        let notifications = CompositionNotifications()
        try await Self.seedRestart(root: root, namespace: KeychainNamespace(fixture.namespace.service),
            backend: LocalKeychainBackend(client: seedClient), provider: signals, notifications: notifications)
        let restartedClient = CompositionOwnedClient(authorized, adopting: seedClient.ownedAccounts)
        signals.setLocked(true)
        try await Self.restoreRestart(root: root, namespace: fixture.namespace, client: restartedClient,
            provider: signals, notifications: notifications, unlock: {
                signals.setLocked(false)
                notifications.post(ProductComposition.screenUnlockedNotification)
            })
        XCTAssertEqual(Set(restartedClient.ownedAccounts), ["metadata", "master-v1"])
        try restartedClient.cleanup()
    }

    func testRestartRecordRejectsIncompleteWrongProcessAndUnownedAccounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-record-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        var record = CompositionRestartRecord(attempt: root.lastPathComponent, seed: UUID(), seedPID: 123)
        try record.write(at: root, initial: true)
        XCTAssertThrowsError(try record.write(at: root, initial: true))
        XCTAssertThrowsError(try CompositionRestartRecord.read(at: root, currentPID: 124))
        record.accounts = ["metadata", "master-v1"]
        record.savedTotal = 2
        try record.write(at: root)
        XCTAssertThrowsError(try CompositionRestartRecord.read(at: root, currentPID: 123))
        XCTAssertEqual(try CompositionRestartRecord.read(at: root, currentPID: 124).seed, record.seed)
        record.accounts = ["metadata", "unowned"]
        try record.write(at: root)
        XCTAssertThrowsError(try CompositionRestartRecord.read(at: root, currentPID: 124))
        record.accounts = ["metadata", "master-v1"]
        try record.write(at: root)
        let recordURL = root.appendingPathComponent(CompositionRestartRecord.name)
        let moved = root.appendingPathComponent("moved.json")
        try FileManager.default.moveItem(at: recordURL, to: moved)
        try FileManager.default.createSymbolicLink(at: recordURL, withDestinationURL: moved)
        XCTAssertThrowsError(try CompositionRestartRecord.read(at: root, currentPID: 124))
    }

    func testOwnershipJournalFailureStillCleansOnlySuccessfulAdds() throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(namespace: fixture.namespace,
            accounts: ["metadata"], client: memory, evidence: { evidence }), recordOwnership: { _ in
                throw CocoaError(.fileWriteUnknown)
            })
        let identity = LocalKeychainQueries.productIdentity(service: fixture.namespace.service, account: "metadata")
        let attributes = LocalKeychainQueries.attributesForAdd(identity: identity, data: Data([1]),
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        XCTAssertThrowsError(try client.add(attributes))
        XCTAssertEqual(client.ownedAccounts, ["metadata"])
        try client.cleanup()
        XCTAssertEqual(memory.copyMatching(LocalKeychainQueries.queryForReadingData(identity: identity)).status,
                       errSecItemNotFound)
    }

    func testAuthorizedProductRestartWhileLocked() async throws {
        let root = try restartAttempt()
        let record = try CompositionRestartRecord.read(at: root, currentPID: getpid())
        let namespace = ProbeNamespace(attempt: record.attempt, seed: record.seed)
        try authorizeRestart(at: root, namespace: namespace)
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(attempt: root,
            namespace: namespace, accounts: ["metadata", "master-v1", "master-v2"]), adopting: record.accounts)
        var failure: (any Error)?
        do {
            try await Self.restoreRestart(root: root.appendingPathComponent("restart-store"), namespace: namespace,
                client: client, provider: SystemSessionLockProvider(), notifications: DistributedLockNotifications(),
                unlock: {
                    print("LOCKED_RESTART readyForUnlock")
                    let observer = SystemSessionLockProvider()
                    let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                    while ContinuousClock.now < deadline {
                        if await observer.sessionLockState() == .unlocked { return }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    throw CompositionTrialError.timeout("restart-waiting-for-unlock")
                })
        } catch { failure = error }
        guard await SystemSessionLockProvider().sessionLockState() == .unlocked else {
            throw failure ?? CompositionTrialError.stateMismatch("cleanup-retained-until-unlocked")
        }
        try client.cleanup()
        print("LOCKED_RESTART cleanupVerified=2 seedPID=\(record.seedPID) restartPID=\(getpid())")
        if let failure { throw failure }
    }

    private func restartAttempt() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KEYRECORD_HOSTED_LOCKED_RESTART_TRIAL"] == "1" else {
            throw XCTSkip("No authorized separate-process restart trial requested")
        }
        let path = try XCTUnwrap(environment["PHASE1_QA_ATTEMPT"])
        guard path.hasPrefix("/") else { throw PreflightBlock.scratchRootMismatch }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    func testAuthorizedProductRestartCleanup() async throws {
        let root = try restartAttempt()
        let record = try CompositionRestartRecord.read(at: root, currentPID: getpid())
        let namespace = ProbeNamespace(attempt: record.attempt, seed: record.seed)
        try authorizeRestart(at: root, namespace: namespace)
        guard await SystemSessionLockProvider().sessionLockState() == .unlocked else {
            throw CompositionTrialError.stateMismatch("cleanup-retained-until-unlocked")
        }
        let client = CompositionOwnedClient(AuthorizedProductKeychainClient(attempt: root,
            namespace: namespace, accounts: Set(record.accounts)), adopting: record.accounts)
        try client.cleanup()
        print("LOCKED_RESTART cleanupOnlyVerified=2")
    }

    private func authorizeRestart(at root: URL, namespace: ProbeNamespace) throws {
        let evidence = SignedCandidateBackend.evidence(attempt: root)
        guard case .ready = SignedEffectGate.authorizeKeychain(namespace: namespace, evidence: evidence,
                                                               expectedNamespace: namespace),
              case .success(let manifest) = evidence.manifest,
              Set(manifest.operations) == [.keychain, .screen, .restart], manifest.operations.count == 3 else {
            throw PreflightBlock.operationAllowlistMismatch
        }
    }

    @MainActor
    private static func seedRestart(root: URL, namespace: KeychainNamespace, backend: LocalKeychainBackend,
        provider: any SessionLockProvider, notifications: any LockNotificationCentering) async throws {
        let product = try await CompositionFixture(root: root, namespace: namespace, backend: backend,
            lockProvider: provider, lockNotifications: notifications)
        var failure: (any Error)?
        do {
            try await product.start(fresh: true)
            try await product.emitOne()
            try await product.emitOne()
            guard try await product.total() == 2 else { throw CompositionTrialError.stateMismatch("seed-total") }
        } catch { failure = error }
        await product.stop()
        if let failure { throw failure }
    }

    @MainActor
    private static func restoreRestart(root: URL, namespace: ProbeNamespace, client: CompositionOwnedClient,
        provider: any SessionLockProvider, notifications: any LockNotificationCentering,
        unlock: () async throws -> Void) async throws {
        guard await provider.sessionLockState() == .locked, client.operationCount == 0 else {
            throw CompositionTrialError.stateMismatch("restart-requires-locked")
        }
        let product = try await CompositionFixture(root: root, namespace: KeychainNamespace(namespace.service),
            backend: LocalKeychainBackend(client: client), lockProvider: provider, lockNotifications: notifications)
        var failure: (any Error)?
        do {
            try await product.waitForClosed()
            XCTAssertEqual(product.replay.emit(tick: 1), 0)
            let observer = try XCTUnwrap(CounterWindowProductObserver(recorder: product.product.diagnostics, interval: 0.05))
            var window = SessionLockQualification(supported: true)
            let transition = try window.advance(.init(challenge: window.challenge, unlocked: false),
                                                expectedUnlocked: false).get()
            let closed = await Task.detached { observer.observe(step: .lockBackground, transition: transition) }.value
            assertClosed(closed)
            guard await provider.sessionLockState() == .locked, client.operationCount == 0 else {
                throw CompositionTrialError.stateMismatch("restart-locked-keychain-attempt")
            }
            print("LOCKED_RESTART closed keychainAttempts=0")
            try await unlock()
            guard await provider.sessionLockState() == .unlocked, client.operationCount == 0 else {
                throw CompositionTrialError.stateMismatch("restart-unlock-keychain-attempt")
            }
            try await product.start(fresh: false)
            guard try await product.total() == 2 else { throw CompositionTrialError.stateMismatch("restart-restored-total") }
            try await product.emitOne()
            guard try await product.total() == 3 else { throw CompositionTrialError.stateMismatch("restart-final-total") }
            print("LOCKED_RESTART restored=2 final=3")
        } catch { failure = error }
        await product.stop()
        if let failure { throw failure }
    }

    private func authorizedResources(optIn: String, recordName: String,
                                     operations: Set<HostOperation>) throws
        -> (URL, ProbeNamespace, CompositionOwnedClient) {
        let environment = ProcessInfo.processInfo.environment
        guard environment[optIn] == "1" else {
            throw XCTSkip("No authorized full product composition trial requested")
        }
        let path = try XCTUnwrap(environment["PHASE1_QA_ATTEMPT"])
        guard path.hasPrefix("/") else { throw PreflightBlock.scratchRootMismatch }
        let attempt = URL(fileURLWithPath: path).standardizedFileURL
        let namespace = ProbeNamespace(attempt: attempt.lastPathComponent, seed: UUID())
        let evidence = SignedCandidateBackend.evidence(attempt: attempt)
        guard case .ready = SignedEffectGate.authorizeKeychain(namespace: namespace, evidence: evidence,
                                                               expectedNamespace: namespace),
              case .success(let manifest) = evidence.manifest,
              Set(manifest.operations) == operations, manifest.operations.count == operations.count else {
            throw PreflightBlock.operationAllowlistMismatch
        }
        let record = attempt.appendingPathComponent(recordName)
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
        return (root, namespace, client)
    }

    @MainActor
    private static func runLockedStartup(root: URL, namespace: ProbeNamespace,
        client: CompositionOwnedClient, provider: () -> any SessionLockProvider,
        notifications: () -> any LockNotificationCentering,
        unlock: () async throws -> Void) async throws {
        var products: [CompositionFixture] = []
        var failure: (any Error)?
        do {
            let lock = provider()
            guard await lock.sessionLockState() == .locked, client.operationCount == 0 else {
                throw CompositionTrialError.unexpectedState
            }
            let backend = LocalKeychainBackend(client: client)
            let productNamespace = try KeychainNamespace(namespace.service)
            let storeRoot = root.appendingPathComponent("store")
            let first = try await CompositionFixture(root: storeRoot, namespace: productNamespace,
                backend: backend, lockProvider: lock, lockNotifications: notifications())
            products.append(first)
            try await first.waitForClosed()
            XCTAssertEqual(first.replay.emit(tick: 1), 0)
            let observer = try XCTUnwrap(CounterWindowProductObserver(recorder: first.product.diagnostics, interval: 0.05))
            var window = SessionLockQualification(supported: true)
            let transition = try window.advance(.init(challenge: window.challenge, unlocked: false),
                                                expectedUnlocked: false).get()
            let closed = await Task.detached { observer.observe(step: .lockBackground, transition: transition) }.value
            assertClosed(closed)
            guard await lock.sessionLockState() == .locked, client.operationCount == 0 else {
                throw CompositionTrialError.unexpectedState
            }
            print("LOCKED_STARTUP closed keychainAttempts=0")
            try await unlock()
            guard await lock.sessionLockState() == .unlocked, client.operationCount == 0 else {
                throw CompositionTrialError.stateMismatch("unlock keychainAttempts=\(client.operationCount)")
            }
            // Namespace absence is checked only after unlock, outside the zero-read window.
            for id in [KeychainItemID.metadata(productNamespace), .key(productNamespace, .init(rawValue: 1)),
                       .key(productNamespace, .init(rawValue: 2))] {
                guard try await backend.read(id) == nil else { throw KeyringError.duplicateItem }
            }
            await first.product.startOrRetry()
            guard first.product.lifecycle.phase == .unstarted,
                  first.product.lifecycle.state.preferences == nil,
                  first.product.lifecycle.state.failure == nil,
                  ProductPersistence.lastLoadFailure == .freshInstall,
                  client.ownedAccounts.isEmpty else {
                throw CompositionTrialError.stateMismatch("retry-did-not-restore-fresh-install")
            }
            try await first.start(fresh: true)
            try await first.emitOne()
            try await first.emitOne()
            let saved = try await first.total()
            XCTAssertEqual(saved, 2)
            await first.stop()
            let reopened = try await CompositionFixture(root: storeRoot, namespace: productNamespace,
                backend: backend, lockProvider: provider(), lockNotifications: notifications())
            products.append(reopened)
            try await reopened.start(fresh: false)
            let restored = try await reopened.total()
            XCTAssertEqual(restored, 2)
            try await reopened.emitOne()
            let final = try await reopened.total()
            XCTAssertEqual(final, 3)
            print("LOCKED_STARTUP recovered saved=2 restored=2 final=3")
        } catch { failure = error }
        for product in products.reversed() { await product.stop() }
        do {
            try await Task.detached { try client.cleanup() }.value
            print("LOCKED_STARTUP cleanupVerified=\(client.ownedAccounts.count)")
        } catch {
            XCTFail("Locked-startup cleanup blocked; inspect retained service record")
            if failure == nil { failure = error }
        }
        if let failure { throw failure }
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

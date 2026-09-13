import Foundation
import KeyRecordCore
import KeyRecordStore

struct ProductClock: LocalClock, KeyringClock {
    var calendar: Calendar { Calendar.current }
    var timeZone: TimeZone { TimeZone.current }
    func now() -> Date { Date() }
    var day: LocalDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: now())
        return LocalDay(String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
    }
}

struct ProductCycleIDs: CycleIDGenerator {
    func nextCycleID() -> CycleID { CycleID(rawValue: UUID().uuidString) }
}

actor ProductConsent: KeyringCreationAuthorizing {
    private var accepted = false
    private var fresh = false
    func authorize(fresh: Bool) { accepted = true; self.fresh = fresh }
    func creationState() -> KeyringCreationState {
        KeyringCreationState(consent: accepted, store: fresh ? .fresh : .existing)
    }
}

struct ProductKeySource: ObjectStoreKeySource {
    let backend: any KeychainBackend
    let namespace: KeychainNamespace
    let gate: KeyAvailabilityGate
    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        let generation = try gate.begin()
        return try await gate.run(generation) { try await backend.versions(in: namespace) }
    }
    func material(for version: KeyVersion) async throws -> Data {
        let generation = try gate.begin()
        return try await gate.run(generation) {
            guard let data = try await backend.read(.key(namespace, version)) else {
                throw KeyringError.missingKey(version)
            }
            return data
        }
    }
}

actor ProductPersistence: LifecycleKeyProviding, PreferencesPersisting {
    let store: ObjectStore
    let keyring: KeychainKeyring
    let consent: ProductConsent
    let gate: KeyAvailabilityGate
    let writer: SerialObjectWriter
    let ownedRoot: URL

    init(store: ObjectStore, keyring: KeychainKeyring, consent: ProductConsent, gate: KeyAvailabilityGate,
         writer: SerialObjectWriter, ownedRoot: URL) {
        self.store = store; self.keyring = keyring; self.consent = consent; self.gate = gate
        self.writer = writer; self.ownedRoot = ownedRoot
    }

    func provisionAfterConsent() async throws {
        _ = try gate.begin()
        try AtomicFileSystem().preparePrivateRoot(at: ownedRoot.deletingLastPathComponent())
        let state = try await store.bootstrap()
        await consent.authorize(fresh: state == .freshInstall)
        if state == .freshInstall {
            _ = try await keyring.bootstrap()
            try await store.initializeFreshInstallation()
        } else { _ = try await keyring.open() }
        try await writer.resume()
    }

    func load() async throws -> Preferences? {
        _ = try gate.begin()
        if try await store.bootstrap() == .freshInstall { return nil }
        return try JSONDecoder().decode(Preferences.self,
            from: await store.readProtected(CycleResetObjects.preferences, gate: gate))
    }

    func save(_ preferences: Preferences) async throws {
        let generation = try gate.begin()
        var objects = [FlushObject(identity: CycleResetObjects.preferences,
                                   payload: try JSONEncoder().encode(preferences))]
        let entries = try await store.entries()
        if !entries.contains(where: { $0.identity == CycleResetObjects.currentCycle }) {
            let cycle = CycleRecord(cycleID: preferences.currentCycleID, index: try Count(1),
                                    createdDay: ProductClock().day, closedDay: nil, isCurrent: true)
            objects.append(FlushObject(identity: CycleResetObjects.currentCycle, payload: try JSONEncoder().encode(cycle)))
        }
        try await writer.write(objects, generation: generation)
    }
}

struct ProductDeletionLogin: DeletionLoginItems {
    let login: any LoginItemBackend
    func unregisterProductLoginItem() async throws -> DeletionOutcome {
        try await login.unregister()
        return .succeeded
    }
}

actor ProductDestruction: CycleResetting, LocalDataErasing {
    let store: ObjectStore
    let gate: KeyAvailabilityGate
    let flush: any LifecycleFlushing
    let capture: any LifecycleCaptureControlling
    let deletion: LocalDeletionCoordinator
    let clear: @Sendable () -> Void
    let scheduler: FlushScheduler
    let writer: SerialObjectWriter
    let beforeMaintenance: @MainActor @Sendable () -> Void
    let afterReset: @MainActor @Sendable () async -> Void
    private var busy = false
    private var resetOperation: UUID?
    init(store: ObjectStore, gate: KeyAvailabilityGate, flush: any LifecycleFlushing,
         capture: any LifecycleCaptureControlling, deletion: LocalDeletionCoordinator,
         scheduler: FlushScheduler, writer: SerialObjectWriter,
         beforeMaintenance: @escaping @MainActor @Sendable () -> Void,
         afterReset: @escaping @MainActor @Sendable () async -> Void,
         clear: @escaping @Sendable () -> Void) {
        self.store = store; self.gate = gate; self.flush = flush
        self.capture = capture; self.deletion = deletion; self.clear = clear
        self.scheduler = scheduler; self.writer = writer
        self.beforeMaintenance = beforeMaintenance; self.afterReset = afterReset
    }
    func performCycleReset() async throws {
        guard !busy else { throw LifecycleFlushError.failed }
        busy = true
        defer { busy = false }
        await beforeMaintenance()
        await capture.stop()
        if resetOperation == nil { try await flush.flushWhileUnlocked() }
        try await quiesce()
        let operation = resetOperation ?? UUID()
        resetOperation = operation
        _ = try await store.resetCycle(operationID: operation, day: ProductClock().day)
        clear()
        resetOperation = nil
        try await writer.resume()
        await afterReset()
    }
    func eraseAllLocalData() async throws {
        guard !busy else { throw LifecycleFlushError.failed }
        busy = true
        defer { busy = false }
        await beforeMaintenance()
        await capture.stop()
        try await quiesce()
        clear()
        await store.closeProtectedSession()
        let report = try await deletion.deleteEverything()
        guard report.succeeded else { throw LifecycleStoreError.filesystemFailure }
    }

    private func quiesce() async throws {
        _ = try gate.renewOpenGeneration()
        await scheduler.suspend()
        switch await writer.suspendAndDrain() {
        case .saved: return
        case .failed: throw LifecycleFlushError.failed
        case .timedOut: throw LifecycleFlushError.timedOut
        case .locked: throw LifecycleFlushError.locked
        }
    }
}

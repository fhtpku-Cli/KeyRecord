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
        let versions = try await gate.run(generation) { try await backend.versions(in: namespace) }
        #if DEBUG
        // Records what bootstrap actually matched the envelope version against.
        ProductPersistence.lastEnumeratedVersionCount = versions.count
        #endif
        return versions
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

    #if DEBUG
    /// Records the last underlying failure so diagnostics can name it.
    ///
    /// `LifecycleOrchestrator.reload` funnels every non-`PreferencesRepositoryError` into
    /// `.protectedDataUnavailable`, which during live verification reported a real,
    /// specific store error as a generic "protected data unavailable" and hid which step
    /// actually failed. The typed error stays internal; only its case description is kept.
    nonisolated(unsafe) static var lastLoadFailure: CaptureDiagnostics.LoadFailureKind?
    /// Gate openness sampled at the instant load() failed.
    nonisolated(unsafe) static var lastLoadGateOpen: Bool?
    /// Number of key versions enumeration produced at the moment load() failed.
    nonisolated(unsafe) static var lastEnumeratedVersionCount: Int?

    /// Maps a thrown store/keyring error onto the closed diagnostic enum. Deliberately
    /// lossy: the classification is what a diagnosis needs, and it cannot carry a path.
    /// Preserves the specific corruption cause. Collapsing all twelve into one value
    /// would hide which remedy applies.
    static func classify(_ cause: StoreCorruption) -> CaptureDiagnostics.LoadFailureKind {
        switch cause {
        case .rootReplacedBySymlink: return .rootReplacedBySymlink
        case .rootNotDirectory: return .rootNotDirectory
        case .insecureRoot: return .insecureRoot
        case .manifestMissing: return .manifestMissing
        case .manifestUnreadable: return .manifestUnreadable
        case .unknownManifestSchemaVersion: return .unknownManifestSchemaVersion
        case .unexpectedEntry: return .unexpectedEntry
        case .symlinkEncountered: return .symlinkEncountered
        case .referencedObjectMissing: return .referencedObjectMissing
        case .envelopeKeyMissing: return .envelopeKeyMissing
        case .unindexedDataWithNamespaceKey: return .unindexedDataWithNamespaceKey
        case .resetJournalUnreadable: return .resetJournalUnreadable
        default: return .otherCorruption
        }
    }

    static func classify(_ error: any Error) -> CaptureDiagnostics.LoadFailureKind {
        if error is DecodingError { return .decodeFailed }
        switch error {
        case let storeError as ObjectStoreError:
            switch storeError {
            case .storeNotInitialized: return .storeNotInitialized
            case .corruption(let cause): return classify(cause)
            case .envelope, .locator: return .envelopeOrLocator
            default: return .other
            }
        case is KeyringError: return .keyGateLocked
        default: return .other
        }
    }

    #endif

    func load() async throws -> Preferences? {
        do {
            _ = try gate.begin()
            if try await store.bootstrap() == .freshInstall {
                #if DEBUG
                Self.lastLoadFailure = .freshInstall
                #endif
                return nil
            }
            let data = try await store.readProtected(CycleResetObjects.preferences, gate: gate)
            #if DEBUG
            Self.lastLoadFailure = nil
            #endif
            return try JSONDecoder().decode(Preferences.self, from: data)
        } catch {
            #if DEBUG
            Self.lastLoadFailure = Self.classify(error)
            Self.lastLoadGateOpen = (try? gate.begin()) != nil
            // Re-run enumeration to see what bootstrap actually had to match against.
            // Count recorded by ProductKeySource on its own enumeration path; widening
            // KeychainKeyring.inventory to public just for a diagnostic is not warranted.
            #endif
            throw error
        }
    }

    func save(_ preferences: Preferences) async throws {
        let generation = try gate.begin()
        // Privacy closure closes the protected store session; reopen it as `load()` does.
        _ = try await store.bootstrap()
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

import Foundation
import KeyRecordCore
import KeyRecordStore

struct ProbeFailure: Error { let message: String }

final class SequenceEntropy: MasterMaterialGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var nextByte: UInt8 = 7
    func generate() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let value = nextByte
        nextByte += 1
        return Data(repeating: value, count: 32)
    }
}

final class FixedClock: KeyringClock {
    func now() -> Date { Date(timeIntervalSince1970: 100) }
}

actor FreshAuthorizer: KeyringCreationAuthorizing {
    func creationState() -> KeyringCreationState {
        KeyringCreationState(consent: true, store: .fresh)
    }
}

actor ProbeBackend: KeychainBackend {
    var items: [KeychainItemID: Data] = [:]

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

    func delete(_ id: KeychainItemID) async throws { items[id] = nil }
}

actor BackedKeySource: ObjectStoreKeySource {
    private let backend: ProbeBackend
    private let namespace: KeychainNamespace

    init(backend: ProbeBackend, namespace: KeychainNamespace) {
        self.backend = backend; self.namespace = namespace
    }

    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        try await backend.versions(in: namespace)
    }

    func material(for version: KeyVersion) async throws -> Data {
        guard let bytes = try await backend.read(.key(namespace, version)) else {
            throw ObjectStoreError.corruption(.envelopeKeyMissing)
        }
        return bytes
    }
}

actor DeterministicResetKeys: ObjectStoreKeySource {
    private var initialized: Bool

    init(manifestPresent: Bool) { initialized = manifestPresent }

    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        initialized ? [KeyVersion(rawValue: 1)] : []
    }

    func material(for version: KeyVersion) async throws -> Data {
        guard version.rawValue == 1 else { throw ObjectStoreError.corruption(.envelopeKeyMissing) }
        initialized = true
        return Data(repeating: 7, count: 32)
    }
}

let probeResetOperation = UUID(uuidString: "D178B166-9866-4361-AD90-996941ED4101")!
let probeOldCycle = CycleID(rawValue: "old-cycle")

func seedResetFixture(_ store: ObjectStore) async throws {
    let encoder = JSONEncoder()
    _ = try await store.put(
        identity: CycleResetObjects.preferences,
        payload: try encoder.encode(Preferences(currentCycleID: probeOldCycle, expectedCollecting: true)))
    _ = try await store.put(
        identity: CycleResetObjects.currentCycle,
        payload: try encoder.encode(CycleRecord(cycleID: probeOldCycle, index: try Count(1),
            createdDay: LocalDay("2026-09-11"), closedDay: nil, isCurrent: true)))
    let chord = try ChordBucket(chord: Chord(keyCode: try KeyCode(12), modifiers: ModifierSet()), appBucket: .unknown)
    for day in ["2026-09-11", "2026-09-12"] {
        let counts = try SourceCounts(ordinary: try Count(2), suspectedInjection: try Count(1))
        let shortcuts = [DailyShortcutAggregate(cycleID: probeOldCycle, day: LocalDay(day), identity: chord,
            classification: ShortcutClassification(kind: .discrete, scope: .normal), sourceCounts: counts)]
        let keys = try [DailyBareKeyAggregate(cycleID: probeOldCycle, day: LocalDay(day),
            keyCode: try KeyCode(0), sourceCounts: counts)]
        _ = try await store.put(
            identity: .shard(cycleID: probeOldCycle.rawValue, dayKey: day, aggregateType: "shortcut"),
            payload: try encoder.encode(shortcuts))
        _ = try await store.put(
            identity: .shard(cycleID: probeOldCycle.rawValue, dayKey: day, aggregateType: "bareKey"),
            payload: try encoder.encode(keys))
    }
    for kind in ["mapping", "backup", "preferences", "ignored"] {
        _ = try await store.put(
            identity: CanonicalLogicalIdentity(objectType: "com.keyrecord.\(kind)", schemaVersion: 1,
                                               logicalIDText: "opaque-fixture"),
            payload: Data([0xff, 0, 0x80, 42]))
    }
}

func parseBoundary(_ spec: String) throws -> (DurabilityPhase, DurabilityBoundary) {
    let parts = spec.split(separator: "-", maxSplits: 1).map(String.init)
    guard parts.count == 2,
          let phase = DurabilityPhase(rawValue: parts[0]),
          let boundary = DurabilityBoundary(rawValue: parts[1])
    else { throw ProbeFailure(message: "bad boundary \(spec)") }
    return (phase, boundary)
}

func injection() throws -> DurabilityInjection {
    guard boundarySpec != "none" else { return .none }
    let (phase, boundary) = try parseBoundary(boundarySpec)
    return DurabilityInjection(killPhase: phase, killAt: boundary)
}

func resetInjection(_ spec: String) throws -> CycleResetInjection {
    guard spec != "none" else { return .none }
    if spec.hasPrefix("stage-") {
        let point = String(spec.dropFirst("stage-".count))
        guard let kill = ResetKillPoint(rawValue: point) else { throw ProbeFailure(message: "bad stage \(spec)") }
        return CycleResetInjection(killAfter: kill)
    }
    let parts = spec.split(separator: "-", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { throw ProbeFailure(message: "bad reset spec \(spec)") }
    let (slot, boundarySpec) = (parts[0], parts[1])
    let (phase, boundary) = try parseBoundary(boundarySpec)
    let file = DurabilityInjection(killPhase: phase, killAt: boundary)
    switch slot {
    case "journal": return CycleResetInjection(journalWrite: file)
    case "summary": return CycleResetInjection(summaryWrite: file)
    case "details": return CycleResetInjection(detailDelete: file)
    case "cycle": return CycleResetInjection(cycleWrite: file)
    case "clear": return CycleResetInjection(journalClear: file)
    default: throw ProbeFailure(message: "bad reset slot \(spec)")
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { throw ProbeFailure(message: "usage: probe <root> <put|rotate|reset> [boundary]") }
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let operation = arguments[2]
let boundarySpec = arguments.count >= 4 ? arguments[3] : "none"

let namespace = try KeychainNamespace("com.keyrecord.tests.crashprobe")
let backend = ProbeBackend()
let keySource = BackedKeySource(backend: backend, namespace: namespace)
let gate = KeyAvailabilityGate()
gate.update(.unlocked)
let entropy = SequenceEntropy()
let store: ObjectStore
switch operation {
case "put":
    store = ObjectStore(root: root, keySource: keySource)
case "rotate":
    let (phase, boundary) = boundarySpec == "none"
        ? (DurabilityPhase.manifest, DurabilityBoundary.afterDirectoryFsync)
        : try parseBoundary(boundarySpec)
    let migration: MigrationInjection
    switch phase {
    case .data: migration = MigrationInjection(data: DurabilityInjection(killPhase: .data, killAt: boundary))
    case .manifest: migration = MigrationInjection(manifest: DurabilityInjection(killPhase: .manifest, killAt: boundary))
    case .cleanup: migration = MigrationInjection(cleanup: DurabilityInjection(killPhase: .cleanup, killAt: boundary))
    }
    store = ObjectStore(root: root, keySource: keySource, migrationInjection: migration)
case "reset":
    let manifestPresent = FileManager.default.fileExists(
        atPath: root.appendingPathComponent(ManifestDiscovery.fileName).path)
    store = ObjectStore(root: root, keySource: DeterministicResetKeys(manifestPresent: manifestPresent),
                        resetInjection: try resetInjection(boundarySpec))
default:
    throw ProbeFailure(message: "unknown operation \(operation)")
}

let ring = KeychainKeyring(
    configuration: KeyringConfiguration(namespace: namespace),
    ports: KeyringPorts(backend: backend, entropy: entropy, creation: FreshAuthorizer(),
                        references: store, clock: FixedClock()),
    gate: gate)

switch operation {
case "put":
    let state = try await store.bootstrap()
    guard state == .freshInstall else { throw ProbeFailure(message: "expected fresh store") }
    _ = try await ring.bootstrap()
    try await store.initializeFreshInstallation()
    _ = try await store.put(
        identity: CanonicalLogicalIdentity(objectType: "com.keyrecord.crash",
                                           schemaVersion: 1, logicalIDText: "crash-object"),
        payload: Data("crash-object-payload".utf8), injection: injection())
case "rotate":
    let state = try await store.bootstrap()
    guard state == .freshInstall else { throw ProbeFailure(message: "rotate requires a fresh root") }
    _ = try await ring.bootstrap()
    try await store.initializeFreshInstallation()
    _ = try await store.put(
        identity: CanonicalLogicalIdentity(objectType: "com.keyrecord.crash",
                                           schemaVersion: 1, logicalIDText: "rotate-object"),
        payload: Data("rotate-object-payload".utf8))
    try await ring.rotate(to: KeyVersion(rawValue: 2))
case "reset":
    switch try await store.bootstrap() {
    case .freshInstall:
        try await store.initializeFreshInstallation()
        try await seedResetFixture(store)
    case .opened:
        break
    }
    _ = try await store.resetCycle(operationID: probeResetOperation, day: LocalDay("2026-09-13"))
default:
    break
}

if await store.bootstrapState() == nil {
    throw ProbeFailure(message: "uninitialized")
}

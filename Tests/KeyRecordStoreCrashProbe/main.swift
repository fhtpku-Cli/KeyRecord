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

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { throw ProbeFailure(message: "usage: probe <root> <put|rotate> [boundary]") }
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
default:
    break
}

if await store.bootstrapState() == nil {
    throw ProbeFailure(message: "uninitialized")
}

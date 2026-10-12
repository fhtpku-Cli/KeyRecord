import Foundation
import Darwin
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore
import KeyRecordMappings

actor FixtureKeys: ObjectStoreKeySource {
    var present: Bool
    init(present: Bool) { self.present = present }
    func namespaceKeyVersions() -> Set<KeyVersion> { present ? [KeyVersion(rawValue: 1)] : [] }
    func material(for version: KeyVersion) throws -> Data {
        guard present, version.rawValue == 1 else { throw KarabinerMappingError.unavailable }
        return Data(repeating: 0xa7, count: 32)
    }
    func seed() { present = true }
}

@main
struct MappingProbe {
    static let namespace = UUID(uuidString: "AAA00000-0000-0000-0000-000000000003")!
    static func main() async {
        do { try await run() } catch { fputs("offline mapping probe failed: \(error)\n", stderr); exit(2) }
    }
    static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] {
            print("Usage: KeyRecordMappingCrashProbe --offline-run | --crash <owned-temporary-directory> <afterWrite|afterFileFsync|afterRename|afterDirectoryFsync>")
            return
        }
        let root: URL
        let boundary: DurabilityBoundary?
        let cleanup: Bool
        if arguments == ["--offline-run"] {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-mapping-probe-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            boundary = nil; cleanup = true
        } else if arguments.count == 3, arguments[0] == "--crash", let requested = DurabilityBoundary(rawValue: arguments[2]) {
            root = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            guard root.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path + "/keyrecord-mapping-crash-")
                    || root.path.hasPrefix("/private/tmp/keyrecord-mapping-crash-") else { throw KarabinerMappingError.unavailable }
            boundary = requested; cleanup = false
        } else { throw KarabinerMappingError.invalidDraft }
        defer { if cleanup { try? FileManager.default.removeItem(at: root) } }
        let configuration = root.appendingPathComponent("configuration.json")
        let base = Data(#"{"profiles":[{"name":"Probe","complex_modifications":{"rules":[]}}]}"#.utf8)
        try base.write(to: configuration)
        let objectRoot = root.appendingPathComponent("objects")
        let keys = FixtureKeys(present: false)
        let store = ObjectStore(root: objectRoot, keySource: keys)
        guard try await store.bootstrap() == .freshInstall else { throw KarabinerMappingError.unavailable }
        await keys.seed(); try await store.initializeFreshInstallation(version: KeyVersion(rawValue: 1))
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let context = KarabinerRuntimeContext(version: "offline-fixture", authority: .temporaryConfiguration,
            capabilities: BackendCapabilityCatalog.reference(.karabiner), observations: [])
        let port = try KarabinerFilePort(target: configuration, gate: gate, runtime: { context },
            injection: DurabilityInjection(killPhase: boundary == nil ? nil : .data, killAt: boundary))
        let persistence = try EncryptedKarabinerTransactionStore(store: store, namespace: namespace)
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: persistence)
        let trigger = Chord(keyCode: try KeyCode(111), modifiers: ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none))
        let output = Chord(keyCode: try KeyCode(8), modifiers: ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none))
        let draft = KarabinerMappingDraft(name: "Offline fixture", profile: "Probe", trigger: trigger, output: output)
        let plan = try await coordinator.prepare(profile: "Probe", drafts: [draft])
        let applied = try await coordinator.apply(plan)
        guard applied.batches.last?.state == .pendingVerification else { throw KarabinerMappingError.unavailable }
        _ = try await coordinator.verifyConfiguration()
        _ = try await coordinator.setDisabled(true)
        _ = try await coordinator.setDisabled(false)
        let unchanged = try port.read()
        try (unchanged + Data(" ".utf8)).write(to: configuration, options: .atomic)
        do { _ = try await coordinator.rollbackLatest(); throw KarabinerMappingError.invalidDraft }
        catch KarabinerMappingError.externalChange {}
        _ = try await coordinator.resolveExternal(.adopt)
        let removed = try await coordinator.removeManagedRules()
        guard removed.batches.last?.state == .unmanaged else { throw KarabinerMappingError.unavailable }
        print("offline=true apply=pendingVerification verify=configurationReadback disable=passed restore=passed externalRollback=refused uninstallRules=removed encryptedBackups=passed")
    }
}

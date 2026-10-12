import SwiftUI
import AppKit
import Darwin
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordMappings
import KeyRecordStore

struct KarabinerDeploymentDependencies: Sendable {
    static let supportedProfilesByVersion: [String: Set<String>] = [:]
    var version: @Sendable () throws -> String? = {
        let url = URL(fileURLWithPath: "/Applications/Karabiner-Elements.app/Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 65536,
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "org.pqrs.Karabiner-Elements.Settings" else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
    var authority: @Sendable (String?, String) -> KarabinerWriteAuthority = { version, profile in
        guard let version, let profiles = supportedProfilesByVersion[version], profiles.contains(profile) else { return .readOnly }
        return .qualifiedAdapter(version: version, testedProfiles: profiles)
    }
}

private final class DeploymentRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var observations: [ChordBucket]?
    private let dependencies: KarabinerDeploymentDependencies
    private let profile: String
    init(dependencies: KarabinerDeploymentDependencies, profile: String, observations: [ChordBucket]?) {
        self.dependencies = dependencies; self.profile = profile; self.observations = observations
    }
    func revoke() { lock.withLock { active = false; observations = nil } }
    func update(_ observations: [ChordBucket]?) { lock.withLock { self.observations = observations } }
    func context() throws -> KarabinerRuntimeContext {
        try lock.withLock {
            guard active else { throw KarabinerMappingError.unavailable }
            let version = try dependencies.version()
            return KarabinerRuntimeContext(version: version, authority: dependencies.authority(version, profile),
                capabilities: BackendCapabilityCatalog.reference(.karabiner), observations: observations)
        }
    }
}

@MainActor
final class KarabinerDeploymentModel: ObservableObject {
    @Published private(set) var profile: String?
    @Published private(set) var version: String?
    @Published private(set) var issueKey: String?
    @Published private(set) var working = false
    @Published private(set) var connected = false
    var canRead: @MainActor () -> Bool = { false }
    var observations: @MainActor () -> [ChordBucket]? = { nil }
    var onChange: @MainActor () -> Void = {}
    var selectTarget: @MainActor () -> URL? = {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    private let mappings: KarabinerMappingModel
    private var store: ObjectStore?
    private var gate: KeyAvailabilityGate?
    private var dependencies = KarabinerDeploymentDependencies()
    private var runtime: DeploymentRuntime?
    private var port: KarabinerFilePort?
    private var target: URL?
    private var scoped = false
    private var monitor: DispatchSourceFileSystemObject?
    private var session = UUID()
    private var visible = false
    private var resumeTask: Task<Void, Never>?

    init(mappings: KarabinerMappingModel) { self.mappings = mappings }
    func configure(store: ObjectStore, gate: KeyAvailabilityGate,
                   dependencies: KarabinerDeploymentDependencies = KarabinerDeploymentDependencies()) {
        self.store = store; self.gate = gate; self.dependencies = dependencies
    }
    var selectedConfiguration: (bytes: Data, profile: String)? {
        guard canRead(), let port, let profile else { return nil }
        updateObservations()
        guard let bytes = try? port.read() else { return nil }
        return (bytes, profile)
    }
    func visibilityChanged(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if !value { close() }
        else if store != nil { resumeTask = Task { await reopen() } }
    }
    func updateObservations() { runtime?.update(observations()) }
    func close() {
        session = UUID(); resumeTask?.cancel(); resumeTask = nil
        runtime?.revoke(); runtime = nil; port = nil
        monitor?.cancel(); monitor = nil
        if scoped, let target { target.stopAccessingSecurityScopedResource() }
        target = nil; scoped = false
        profile = nil; version = nil; issueKey = nil; working = false; connected = false
        mappings.clear(); onChange()
    }
    func requestApplication(profile: String?) async {
        guard canRead(), !mappings.maintenance, !working, let profile else { issueKey = "phase3.selectProfile"; return }
        let ticket = session
        guard let url = selectTarget(), ticket == session, canRead() else { return }
        await bind(url: url, profile: profile)
    }
    func bind(url: URL, profile: String) async {
        guard canRead(), !mappings.maintenance, !working, let store else { return }
        working = true
        let ticket = session
        var replacingConnection = false
        do {
            let targets = try EncryptedKarabinerTargetStore(store: store)
            let previous = try await targets.load()
            guard ticket == session, canRead() else { return }
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let same = previous?.profile == profile && previous?.location == location(url)
            if let previous, !same {
                let ledger = try await EncryptedKarabinerTransactionStore(store: store, namespace: previous.namespace).load()
                guard ledger.managedProfile == nil, ledger.pending == nil else { throw KarabinerMappingError.busy }
            }
            guard ticket == session, canRead() else { return }
            let reference = KarabinerTargetReference(namespace: same ? previous?.namespace ?? UUID() : UUID(), bookmark: bookmark, location: location(url), profile: profile)
            replacingConnection = true
            try await openTarget(url: url, reference: reference, ticket: ticket)
            guard ticket == session, canRead() else { return }
            try await targets.save(reference)
            guard ticket == session, canRead() else { return }
            connected = true
        } catch {
            guard ticket == session, canRead() else { return }
            if replacingConnection { disconnect() }
            issueKey = error as? KarabinerMappingError == .busy ? "phase3.rebindBlocked" : "phase3.bindingFailed"
        }
        if ticket == session { working = false; onChange() }
    }
    func reopen() async {
        guard canRead(), !working, !connected, let store else { return }
        working = true
        let ticket = session
        do {
            if let reference = try await EncryptedKarabinerTargetStore(store: store).load() {
                guard ticket == session, canRead() else { return }
                try await openTarget(url: resolve(reference), reference: reference, ticket: ticket)
                guard ticket == session, canRead() else { return }
                connected = true
            }
        } catch {
            if ticket == session, canRead() { disconnect(); issueKey = "phase3.bindingFailed" }
        }
        if ticket == session { working = false; onChange() }
    }
    private func resolve(_ reference: KarabinerTargetReference) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: reference.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard location(url) == reference.location else { throw KarabinerMappingError.unavailable }
        return url
    }
    func removeForUninstall() async throws {
        guard canRead(), let store else { throw KarabinerMappingError.unavailable }
        guard let reference = try await EncryptedKarabinerTargetStore(store: store).load() else { return }
        let ledger = try await EncryptedKarabinerTransactionStore(store: store, namespace: reference.namespace).load()
        guard ledger.pending == nil else { throw KarabinerMappingError.busy }
        if ledger.managedProfile != nil {
            guard connected else { throw KarabinerMappingError.unavailable }
            try await mappings.removeForUninstall()
        }
    }
    private func location(_ url: URL) -> String {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
    }
    private func openTarget(url: URL, reference: KarabinerTargetReference, ticket: UUID) async throws {
        guard let store, let gate else { throw KarabinerMappingError.unavailable }
        disconnect()
        target = url; scoped = url.startAccessingSecurityScopedResource()
        let runtime = DeploymentRuntime(dependencies: dependencies, profile: reference.profile, observations: observations())
        self.runtime = runtime
        let port = try KarabinerFilePort(target: url, gate: gate, runtime: { try runtime.context() })
        let bytes = try port.read()
        _ = try KarabinerProfilePlanner.plan(bytes, profile: reference.profile, drafts: [])
        guard ticket == session, canRead() else { runtime.revoke(); throw KarabinerMappingError.unavailable }
        self.port = port; profile = reference.profile; version = try runtime.context().version
        let coordinator = KarabinerTransactionCoordinator(configuration: port,
            store: try EncryptedKarabinerTransactionStore(store: store, namespace: reference.namespace))
        try await mappings.attachReconciled(coordinator)
        guard ticket == session, canRead(), self.runtime === runtime else { throw KarabinerMappingError.unavailable }
        try watch(url.deletingLastPathComponent(), ticket: ticket)
        issueKey = try runtime.context().authority == .readOnly ? "phase3.readOnlyVersion" : nil
    }
    private func disconnect() {
        runtime?.revoke(); runtime = nil; port = nil
        monitor?.cancel(); monitor = nil
        if scoped, let target { target.stopAccessingSecurityScopedResource() }
        target = nil; scoped = false; profile = nil; version = nil; connected = false
        mappings.detach()
    }
    private func watch(_ directory: URL, ticket: UUID) throws {
        let descriptor = Darwin.open(directory.path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw KarabinerMappingError.unavailable }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke], queue: .global(qos: .utility))
        source.setCancelHandler { @Sendable in Darwin.close(descriptor) }
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in
                guard let self, self.session == ticket, self.canRead() else { return }
                self.mappings.invalidate()
                await self.mappings.refresh()
                self.version = try? self.runtime?.context().version
                self.onChange()
            }
        }
        monitor = source; source.resume()
    }
}

struct KarabinerDeploymentSection: View {
    @ObservedObject var model: KarabinerDeploymentModel
    let selectedProfile: String?
    let text: NativeText
    var body: some View {
        Section {
            Text(text("phase3.targetExplanation")).fixedSize(horizontal: false, vertical: true)
            Button(text("phase3.prepareApplication")) { Task { await model.requestApplication(profile: selectedProfile) } }
                .disabled(model.working || selectedProfile == nil).accessibilityIdentifier("phase3.prepareApplication")
            if model.connected {
                Text(model.profile ?? "")
                Text(model.version ?? text("phase3.versionUnknown"))
            }
            if let key = model.issueKey { Text(text(key)).accessibilityIdentifier("phase3.deploymentIssue") }
        } header: { Text(text("phase3.deploymentTitle")) }
    }
}

import SwiftUI
import UniformTypeIdentifiers
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordMappings
import KeyRecordStore

private struct MappingDraftActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor (Chord, Chord, RecommendationScope) -> Void)? = nil
}
extension EnvironmentValues {
    var createMappingDraft: (@MainActor (Chord, Chord, RecommendationScope) -> Void)? {
        get { self[MappingDraftActionKey.self] }
        set { self[MappingDraftActionKey.self] = newValue }
    }
}

@MainActor
final class KarabinerMappingModel: ObservableObject {
    @Published private(set) var drafts: [KarabinerMappingDraft] = []
    @Published private(set) var prepared: KarabinerPreparedOperation?
    @Published private(set) var lastLedger: KarabinerLedger?
    @Published private(set) var issueKey: String?
    @Published private(set) var working = false
    @Published var riskConfirmed = false
    var canRead: @MainActor () -> Bool = { false }
    var configuration: @MainActor () -> (bytes: Data, profile: String)? = { nil }
    var observations: @MainActor () -> [ChordBucket]? = { nil }
    var onChange: @MainActor () -> Void = {}
    var protectedGate: KeyAvailabilityGate?
    var defaultName: @MainActor (Chord, RecommendationScope) -> String = { _, _ in "KeyRecord mapping" }
    private var coordinator: KarabinerTransactionCoordinator?
    private var session = UUID()
    private var revision = UUID()
    private var exports: [MappingExportPermission] = []
    private var refreshPending = false
    var maintenance = false { didSet { invalidate() } }

    var canApply: Bool {
        guard canRead(), !maintenance, !working, let coordinator, let prepared, !prepared.hasBlockingConflict,
              (try? coordinator.currentContext()) == prepared.context,
              !prepared.requiresRiskConfirmation || riskConfirmed else { return false }
        if let profile = lastLedger?.managedProfile, profile != prepared.plan.diff.profile { return false }
        switch prepared.context.authority { case .readOnly: return false; default: return true }
    }
    var canManage: Bool {
        guard canRead(), !maintenance, !working, let coordinator, let profile = lastLedger?.managedProfile else { return false }
        do { try coordinator.currentContext().requireWrite(profile: profile); return true } catch { return false }
    }
    var canInspect: Bool { canRead() && !working && coordinator != nil && lastLedger?.managedProfile != nil }
    func detach() { coordinator = nil; lastLedger = nil; refreshPending = false; invalidate() }
    func removeForUninstall() async throws {
        guard canRead(), !working, let coordinator else { throw KarabinerMappingError.unavailable }
        working = true; defer { working = false; onChange() }
        let ticket = session
        let result = try await coordinator.removeManagedRules()
        guard canRead(), ticket == session, result.managedProfile == nil else { throw KarabinerMappingError.unavailable }
        lastLedger = result; invalidate()
    }
    func connect(_ coordinator: KarabinerTransactionCoordinator) async throws {
        let ticket = session
        let ledger = try await coordinator.reconcile()
        guard canRead(), ticket == session else { throw KarabinerMappingError.unavailable }
        self.coordinator = coordinator; lastLedger = ledger; invalidate()
    }
    func attach(_ coordinator: KarabinerTransactionCoordinator) async {
        self.coordinator = coordinator; invalidate(); await refresh()
    }
    func stage(output: Chord, trigger: Chord, scope: RecommendationScope) {
        guard canRead(), !maintenance, !working, let selection = configuration() else { issueKey = "phase3.selectProfile"; return }
        let selectedScope: MappingScope = if case .application(let id) = scope { .application(id) } else { .global }
        let draft = KarabinerMappingDraft(name: defaultName(output, scope), profile: selection.profile,
            trigger: trigger, output: output, scope: selectedScope)
        do { _ = try draft.rule(); drafts.append(draft); invalidate() }
        catch { issueKey = "phase3.invalidDraft" }
        onChange()
    }
    func update(_ draft: KarabinerMappingDraft) {
        guard canRead(), !maintenance, !working, let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft; invalidate(); onChange()
    }
    func remove(_ id: UUID) { guard canRead(), !maintenance, !working else { return }; drafts.removeAll { $0.id == id }; invalidate(); onChange() }
    func invalidate() {
        exports.forEach { $0.invalidate() }; exports = []
        revision = UUID(); prepared = nil; riskConfirmed = false; issueKey = nil; onChange()
    }
    func clear() {
        session = UUID(); coordinator = nil; drafts = []; prepared = nil; lastLedger = nil
        exports.forEach { $0.invalidate() }; exports = []
        issueKey = nil; working = false; riskConfirmed = false; refreshPending = false; onChange()
    }
    func check() async {
        guard canRead(), !maintenance, !working, let selection = configuration() else { issueKey = "phase3.selectProfile"; return }
        let currentSession = session
        let currentRevision = revision
        working = true; riskConfirmed = false; issueKey = nil
        let selectedDrafts = drafts.filter { $0.profile == selection.profile }
        do {
            let result: KarabinerPreparedOperation
            if let coordinator { result = try await coordinator.prepare(profile: selection.profile, drafts: selectedDrafts) }
            else {
                let port = KarabinerCopyPort(bytes: selection.bytes, observations: observations())
                result = try await KarabinerTransactionCoordinator(configuration: port, store: ReadOnlyMappingStore())
                    .prepare(profile: selection.profile, drafts: selectedDrafts)
            }
            guard canRead(), currentSession == session else { return }
            if currentRevision == revision { prepared = result }
        } catch { if canRead(), currentSession == session { issueKey = "phase3.checkFailed" } }
        guard currentSession == session else { return }
        working = false; onChange()
    }
    func apply() async {
        guard canApply, let coordinator, let prepared else { return }
        await run { try await coordinator.apply(prepared, riskConfirmed: self.riskConfirmed) }
    }
    func refresh() async {
        guard let coordinator, canRead() else { return }
        if working { refreshPending = true; return }
        await run { try await coordinator.reconcile() }
    }
    func verify() async { guard let coordinator, canInspect else { return }; await run { try await coordinator.verifyConfiguration() } }
    func disable() async {
        guard let coordinator, canManage else { return }
        await run { try await coordinator.setDisabled(true) }
    }
    func restore() async {
        guard let coordinator, canManage else { return }
        await run { try await coordinator.setDisabled(false, confirmation: self.riskConfirmed ? self.prepared : nil) }
    }
    func rollback() async { guard let coordinator, canManage else { return }; await run { try await coordinator.rollbackLatest() } }
    func resolve(_ choice: KarabinerExternalChoice) async {
        guard let coordinator, canInspect else { return }
        await run { try await coordinator.resolveExternal(choice, confirmation: self.riskConfirmed ? self.prepared : nil) }
    }
    func removeManaged() async { guard let coordinator, canManage else { return }; await run { try await coordinator.removeManagedRules() } }
    private func run(_ operation: () async throws -> KarabinerLedger) async {
        guard canRead(), !working else { return }
        let currentSession = session
        working = true
        do {
            let result = try await operation()
            guard canRead(), currentSession == session else { return }
            lastLedger = result; prepared = nil; riskConfirmed = false; issueKey = nil
        } catch {
            if canRead(), currentSession == session {
                issueKey = error as? KarabinerMappingError == .externalChange ? "phase3.externalChange" : "phase3.operationFailed"
                if let coordinator {
                    let result = try? await coordinator.ledger()
                    if canRead(), currentSession == session { lastLedger = result }
                    if error as? KarabinerMappingError == .riskConfirmationRequired {
                        let check = try? await coordinator.prepareRestore()
                        if canRead(), currentSession == session {
                            prepared = check; riskConfirmed = false; issueKey = "phase3.confirmRisk"
                        }
                    }
                }
            }
        }
        guard currentSession == session else { return }
        working = false; onChange()
        if refreshPending { refreshPending = false; await refresh() }
    }
    func exportRules() throws -> Data {
        guard canRead(), let prepared, !prepared.hasBlockingConflict else { throw KarabinerMappingError.unavailable }
        let rules = try prepared.plan.drafts.map { try JSONSerialization.jsonObject(with: $0.rule()) }
        return try JSONSerialization.data(withJSONObject: ["title": "KeyRecord mappings", "rules": rules], options: [.prettyPrinted, .sortedKeys])
    }
    func exportDocument() throws -> KarabinerRulesDocument {
        let permission = try MappingExportPermission(gate: protectedGate)
        exports.append(permission)
        return KarabinerRulesDocument(bytes: try exportRules(), permission: permission)
    }
}

final class MappingExportPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private let gate: KeyAvailabilityGate?
    private let generation: CaptureGeneration?
    init(gate: KeyAvailabilityGate?) throws { self.gate = gate; generation = try gate?.begin() }
    func invalidate() { lock.withLock { active = false } }
    func use<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            guard active else { throw KarabinerMappingError.unavailable }
            if let gate, let generation { return try gate.use(generation, body: body) }
            return try body()
        }
    }
}

private struct KarabinerCopyPort: KarabinerConfigurationPort {
    let bytes: Data
    let observations: [ChordBucket]?
    func context() -> KarabinerRuntimeContext { KarabinerRuntimeContext(version: nil, observations: observations) }
    func read() -> Data { bytes }
    func replace(expected: Data, with bytes: Data, context: KarabinerRuntimeContext) throws { throw KarabinerMappingError.readOnlyVersion }
}
private struct ReadOnlyMappingStore: KarabinerTransactionStore {
    func load() -> KarabinerLedger { KarabinerLedger() }
    func save(_ ledger: KarabinerLedger) throws { throw KarabinerMappingError.readOnlyVersion }
    func putBackup(_ backup: KarabinerBackup) throws { throw KarabinerMappingError.readOnlyVersion }
    func backup(_ id: UUID) throws -> KarabinerBackup { throw KarabinerMappingError.readOnlyVersion }
    func removeBackup(_ id: UUID) throws { throw KarabinerMappingError.readOnlyVersion }
    func discardUnreferencedBackups(retaining ids: Set<UUID>) throws { throw KarabinerMappingError.readOnlyVersion }
}

struct KarabinerRulesDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var bytes: Data
    var permission: MappingExportPermission?
    init(bytes: Data, permission: MappingExportPermission? = nil) { self.bytes = bytes; self.permission = permission }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let permission { return try permission.use { FileWrapper(regularFileWithContents: bytes) } }
        return FileWrapper(regularFileWithContents: bytes)
    }
}

struct KarabinerMappingSection: View {
    @ObservedObject var model: KarabinerMappingModel
    let text: NativeText
    @State private var exporting = false
    @State private var document: KarabinerRulesDocument?
    var body: some View {
        Section {
            Text(text("phase3.readOnly")).fixedSize(horizontal: false, vertical: true)
            ForEach(model.drafts) { draft in
                KarabinerDraftRow(draft: draft, text: text, update: model.update, remove: { model.remove(draft.id) })
            }
            Button(text("phase3.check")) { Task { await model.check() } }
                .disabled(model.working || model.drafts.isEmpty).accessibilityIdentifier("phase3.check")
            if let prepared = model.prepared {
                if prepared.hasChainedMapping { Text(text("phase3.chainBlocking")) }
                Text(String(format: text("phase3.diff"), prepared.plan.diff.profile, prepared.plan.diff.previousRuleCount, prepared.plan.diff.ruleCount))
                    .accessibilityIdentifier("phase3.diff")
                ForEach(Array(prepared.reports.enumerated()), id: \.offset) { _, report in
                    AnalysisConflictView(input: report.check.input, text: text)
                }
                if prepared.requiresRiskConfirmation {
                    Toggle(text("phase3.confirmRisk"), isOn: $model.riskConfirmed).toggleStyle(.checkbox)
                }
                Text(text("phase3.exportWarning")).font(.caption)
                Button(text("phase3.export")) {
                    if let selected = try? model.exportDocument() { document = selected; exporting = true }
                }.disabled(prepared.hasBlockingConflict)
                Button(text("phase3.apply")) { Task { await model.apply() } }
                    .disabled(!model.canApply).accessibilityIdentifier("phase3.apply")
            }
            if let batch = model.lastLedger?.batches.last {
                Text(text("phase3.state.\(batch.state.rawValue)"))
                ForEach(model.lastLedger?.mappingRecords ?? []) { record in
                    Text(record.draft.name + ": " + text("phase3.state.\(record.state.rawValue)"))
                    if let date = record.verifiedAt { Text(date, style: .time) }
                }
                if let verified = batch.verifiedAt { Text(verified, style: .date); Text(text("phase3.configurationOnly")) }
                HStack {
                    Button(text("phase3.verify")) { Task { await model.verify() } }.accessibilityIdentifier("phase3.verify")
                    Button(text("phase3.disable")) { Task { await model.disable() } }.disabled(!model.canManage).accessibilityIdentifier("phase3.disable")
                    Button(text("phase3.restore")) { Task { await model.restore() } }.disabled(!model.canManage).accessibilityIdentifier("phase3.restore")
                    Button(text("phase3.rollback")) { Task { await model.rollback() } }.disabled(!model.canManage)
                }.disabled(!model.canInspect)
                if batch.state == .externallyChanged {
                    Button(text("phase3.adopt")) { Task { await model.resolve(.adopt) } }.accessibilityIdentifier("phase3.adopt")
                    Button(text("phase3.reapply")) { Task { await model.resolve(.reapply) } }.disabled(!model.canManage).accessibilityIdentifier("phase3.reapply")
                    Button(text("phase3.stopManaging")) { Task { await model.resolve(.stopManaging) } }.accessibilityIdentifier("phase3.stopManaging")
                }
                Button(text("phase3.removeManaged")) { Task { await model.removeManaged() } }.disabled(!model.canManage)
            }
            if let issue = model.issueKey { Text(text(issue)).accessibilityIdentifier("phase3.issue") }
        } header: { Text(text("phase3.title")) }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "KeyRecord-rules") { _ in document = nil }
        .onChange(of: model.prepared) { _, _ in exporting = false; document = nil }
        .onDisappear { exporting = false; document = nil }
    }
}

private struct KarabinerDraftRow: View {
    let draft: KarabinerMappingDraft
    let text: NativeText
    let update: (KarabinerMappingDraft) -> Void
    let remove: () -> Void
    @State private var vendor = ""
    @State private var product = ""
    @State private var application = ""
    var body: some View {
        VStack(alignment: .leading) {
            Text(draft.profile)
            Text(text("phase3.state.draft"))
            TextField(text("phase3.name"), text: Binding(get: { draft.name }, set: { var next = draft; next.name = $0; update(next) }))
            if case .application(let app) = draft.scope { Text(app) } else { Text(text("phase2.global")) }
            TextField(text("phase3.application"), text: $application)
            HStack {
                Button(text("phase3.applicationScope")) { var next = draft; next.scope = .application(application); update(next) }.disabled(application.isEmpty)
                Button(text("phase2.global")) { var next = draft; next.scope = .global; update(next) }
            }
            Text(draft.devices.map { $0.sorted { $0.identity < $1.identity }.map(\.identity).joined(separator: ", ") } ?? text("phase3.allDevices"))
            HStack {
                TextField(text("phase3.vendor"), text: $vendor)
                TextField(text("phase3.product"), text: $product)
                Button(text("phase3.limitDevice")) {
                    if let a = UInt16(vendor), let b = UInt16(product) { var next = draft; next.devices = [MappingDevice(vendorID: a, productID: b)]; update(next) }
                }.disabled(UInt16(vendor) == nil || UInt16(product) == nil)
                Button(text("phase3.allDevices")) { var next = draft; next.devices = nil; update(next) }
            }
            Text(AnalysisLabels.chord(draft.trigger, text: text) + " → " + AnalysisLabels.chord(draft.output, text: text))
            Button(text("phase3.removeDraft"), action: remove)
        }
    }
}

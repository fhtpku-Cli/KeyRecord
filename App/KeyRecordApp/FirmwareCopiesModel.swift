import SwiftUI
import AppKit
import KeyRecordCore
import KeyRecordMappings
import KeyRecordStore

@MainActor
final class FirmwareCopiesModel: ObservableObject {
    @Published private(set) var records: [FirmwareBatchRecord] = []
    @Published private(set) var issueKey: String?
    @Published private(set) var working = false
    @Published private(set) var uninstallReady = false
    @Published var recoveryChoice = 0
    @Published var deleteLocalData = false
    @Published var discardConfirmed = false
    var canRead: @MainActor () -> Bool = { false }
    var selectedOriginal: @MainActor () -> Data? = { nil }
    var onChange: @MainActor () -> Void = {}
    var selectVial: @MainActor () -> URL? = {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    var selectExport: @MainActor (FirmwareBatchRecord) -> URL? = { record in
        let panel = NSSavePanel(); panel.nameFieldStringValue = record.id.uuidString + (record.backend == .via ? ".json" : ".vil")
        return panel.runModal() == .OK ? panel.url : nil
    }
    private var store: ObjectStore?
    private var gate: KeyAvailabilityGate?
    private var firmware: FirmwareOperationCoordinator?
    private var session = UUID()
    private var readRequest = UUID()
    private var support = FirmwareSupportDirectory()
    private var versionAxes: @MainActor (FirmwareBackend) -> FirmwareVersionAxes? = { _ in nil }
    private var uninstall: UninstallActions?
    struct UninstallActions {
        let removeRules: @MainActor () async throws -> Void
        let removeLogin: @MainActor () async throws -> Void
        let eraseData: @MainActor () async throws -> Void
        let editing: @MainActor (Bool) -> Void
        var ready: @MainActor () -> Bool = { true }
    }
    func configure(store: ObjectStore, gate: KeyAvailabilityGate, support: FirmwareSupportDirectory = FirmwareSupportDirectory(),
                   versionAxes: @escaping @MainActor (FirmwareBackend) -> FirmwareVersionAxes? = { _ in nil }) {
        self.store = store; self.gate = gate; self.support = support; self.versionAxes = versionAxes; firmware = nil
    }
    func configureUninstall(_ actions: UninstallActions) { uninstall = actions }
    var canPrepareUninstall: Bool {
        canRead() && !working && uninstall?.ready() == true && (recoveryChoice != 2 || records.isEmpty || discardConfirmed)
    }
    private func coordinator() throws -> FirmwareOperationCoordinator {
        guard let store, let gate else { throw FirmwareError.unavailable }
        if let firmware { return firmware }
        let coordinator = try FirmwareOperationCoordinator(store: store, support: support,
            resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        firmware = coordinator; return coordinator
    }
    func clear() {
        session = UUID(); records = []; firmware = nil; issueKey = nil; working = false
        recoveryChoice = 0; deleteLocalData = false; discardConfirmed = false
    }
    func refresh() async {
        guard canRead(), !working, store != nil else { return }
        let ticket = session
        let request = UUID(); readRequest = request
        do {
            let ledger = try await coordinator().reconcile()
            if canRead(), ticket == session, request == readRequest { records = ledger.records; onChange() }
        } catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed"; onChange() } }
    }
    func selectionTicket() -> UUID? { canRead() && !working ? session : nil }
    func retainVIA(_ bytes: Data?, ticket: UUID) async {
        guard ticket == session, bytes == selectedOriginal() else { return }
        await retain(bytes, backend: .via)
    }
    func retainVial(ticket: UUID) async {
        guard canRead(), ticket == session, !working, let gate else { return }
        guard let url = selectVial(), canRead(), ticket == session else { return }
        do {
            let generation = try gate.begin()
            let selected = try await Task.detached {
                try VIAFileReader.readConfiguration(url: url,
                    access: VIAFileReadAccess(gate: gate, generation: generation), notify: {}) { bytes in
                        _ = try FirmwareDocument(bytes: bytes, backend: .vial)
                        return bytes
                    }
            }.value
            defer { selected.monitor.cancel() }
            try gate.check(generation)
            guard canRead(), ticket == session, !selected.monitor.hasChanged else { return }
            await retain(selected.reference, backend: .vial)
        } catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed"; onChange() } }
    }
    private func retain(_ bytes: Data?, backend: FirmwareBackend) async {
        guard canRead(), !working, let bytes else { return }
        let ticket = session; readRequest = UUID(); working = true
        do {
            let axes = versionAxes(backend) ?? FirmwareVersionAxes(definitionSchema: nil, deviceProtocol: nil, layoutFormat: nil, keycodeDialect: nil, importer: nil)
            _ = try await coordinator().retainOriginal(bytes, backend: backend, axes: axes, confirmedAt: Date())
            guard canRead(), ticket == session else { return }
            working = false; await refresh()
        } catch { if canRead(), ticket == session { working = false; issueKey = "phase4.operationFailed" } }
        if ticket == session { onChange() }
    }
    func exportOriginal(_ record: FirmwareBatchRecord, ticket: UUID) async {
        guard canRead(), ticket == session, !working, records.contains(where: { $0.id == record.id }), let gate else { return }
        guard let url = selectExport(record), canRead(), ticket == session else { return }
        working = true
        do { try await coordinator().exportOriginal(record.id, destination: FirmwareFileDestination(target: url, gate: gate)) }
        catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed" } }
        if ticket == session { working = false; onChange() }
    }
    func deleteOriginal(_ record: FirmwareBatchRecord, ticket: UUID) async {
        guard canRead(), ticket == session, !working,
              records.contains(record), record.state == .draft || record.state == .rolledBack else { return }
        working = true; issueKey = nil
        do { try await coordinator().deleteOriginal(record.id) }
        catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed" } }
        if canRead(), ticket == session { working = false; await refresh(); onChange() }
    }
    func canGenerate(_ record: FirmwareBatchRecord) -> Bool {
        canRead() && !working && record.state == .draft &&
            records.last(where: { $0.backend == record.backend && $0.device == record.device })?.id == record.id &&
            isCompatible(record)
    }
    func isCompatible(_ record: FirmwareBatchRecord) -> Bool { support.supports(backend: record.backend, device: record.device, axes: record.axes) }
    func exportChanges(_ record: FirmwareBatchRecord, changes: [FirmwareSlotChange], ticket: UUID) async {
        guard ticket == session, records.contains(record), canGenerate(record), !changes.isEmpty, let gate else { return }
        working = true; issueKey = nil
        defer { if ticket == session { working = false; onChange() } }
        do {
            let operations = try coordinator()
            _ = try await operations.prepare(record.id, changes: changes)
            guard canRead(), ticket == session, let url = selectExport(record), canRead(), ticket == session else { return }
            let ledger = try await operations.export(record.id, changes: changes, destination: FirmwareFileDestination(target: url, gate: gate))
            if canRead(), ticket == session { records = ledger.records }
        } catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed" } }
    }
    enum RecordAction { case claimImport, abandon, rollback, viaPassed, viaFailed }
    func perform(_ action: RecordAction, record: FirmwareBatchRecord, ticket: UUID) async {
        guard canRead(), ticket == session, !working, records.contains(record) else { return }
        working = true; issueKey = nil
        defer { if ticket == session { working = false; onChange() } }
        do {
            let operations = try coordinator()
            let ledger: FirmwareLedger
            switch action {
            case .claimImport: ledger = try await operations.claimImport(record.id, at: Date())
            case .abandon: ledger = try await operations.abandon(record.id)
            case .rollback: ledger = try await operations.confirmGuidedRollback(record.id)
            case .viaPassed: ledger = try await operations.confirmVIABehavior(record.id, passed: true, at: Date())
            case .viaFailed: ledger = try await operations.confirmVIABehavior(record.id, passed: false, at: Date())
            }
            if canRead(), ticket == session { records = ledger.records }
        } catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed" } }
    }
    func prepareUninstall(ticket: UUID, choice: Int, deleteData: Bool, discard: Bool) async {
        guard canRead(), ticket == session, !working, let actions = uninstall, actions.ready(), let store, let gate,
              (0...2).contains(choice) else { return }
        working = true; issueKey = nil; uninstallReady = false; actions.editing(true)
        onChange()
        defer { actions.editing(false); if ticket == session { working = false; onChange() } }
        do {
            let firmware = try coordinator()
            let originals = try await firmware.reconcile().records
            guard canRead(), ticket == session else { throw FirmwareError.unavailable }
            var choices: [UUID: FirmwareRecoveryChoice] = [:]
            for original in originals {
                guard canRead(), ticket == session else { throw FirmwareError.unavailable }
                switch choice {
                case 0:
                    guard let url = selectExport(original) else { return }
                    guard canRead(), ticket == session else { throw FirmwareError.unavailable }
                    choices[original.id] = .export(try FirmwareFileDestination(target: url, gate: gate))
                case 1: choices[original.id] = .heldElsewhere
                default:
                    guard discard else { throw FirmwareError.unavailable }
                    choices[original.id] = .discardConfirmed
                }
            }
            let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
                removeRules: actions.removeRules, removeLogin: actions.removeLogin, eraseData: actions.eraseData,
                authorize: { [weak self] in
                    guard let self, self.canRead(), self.session == ticket else { throw FirmwareError.unavailable }
                })
            let result = try await preparation.prepare(choices: choices, deleteLocalData: deleteData)
            if result.stage == .completed || (ticket == session && canRead()) { uninstallReady = true }
        } catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed" } }
    }
}

struct FirmwareCopiesSection: View {
    @ObservedObject var model: FirmwareCopiesModel
    let viaBytes: Data?
    let text: NativeText
    @State private var deletion: (FirmwareBatchRecord, UUID)?
    @State private var preparation: (UUID, Int, Bool, Bool)?
    var body: some View {
        Section {
            if model.records.isEmpty { Text(text("phase4.compatibilityUnknown")).fixedSize(horizontal: false, vertical: true) }
            Button(text("phase4.retainVIA")) {
                if let ticket = model.selectionTicket() { Task { await model.retainVIA(viaBytes, ticket: ticket) } }
            }
                .disabled(model.working || viaBytes == nil).accessibilityIdentifier("phase4.retainVIA")
            Button(text("phase4.retainVial")) {
                if let ticket = model.selectionTicket() { Task { await model.retainVial(ticket: ticket) } }
            }.disabled(model.working).accessibilityIdentifier("phase4.retainVial")
            ForEach(model.records) { record in
                Text(record.device + ": " + text("phase4.state.\(record.state.rawValue)"))
                if !model.isCompatible(record) { Text(text("phase4.compatibilityUnknown")) }
                if let date = record.exportedAt { HStack { Text(text("phase4.exportedAt")); Text(date, style: .date) } }
                if let date = record.importClaimedAt { HStack { Text(text("phase4.importClaimedAt")); Text(date, style: .date) } }
                if let date = record.verifiedAt { HStack { Text(text("phase4.evidenceAt")); Text(date, style: .date) } }
                Text(text("phase4.importNotVerification"))
                Text(text("phase4.exportWarning"))
                FirmwareOperationRow(model: model, record: record, text: text)
                Button(text("phase4.exportOriginal")) {
                    if let ticket = model.selectionTicket() { Task { await model.exportOriginal(record, ticket: ticket) } }
                }.disabled(model.working)
                    .accessibilityIdentifier(record.id.uuidString)
                if record.state == .draft || record.state == .rolledBack {
                    Button(text("phase4.deleteOriginal"), role: .destructive) {
                        if let ticket = model.selectionTicket() { deletion = (record, ticket) }
                    }.disabled(model.working).accessibilityIdentifier("delete-" + record.id.uuidString)
                }
            }
            Text(text("phase4.restoreInstructions")).fixedSize(horizontal: false, vertical: true)
            if let issue = model.issueKey { Text(text(issue)) }
        } header: { Text(text("phase4.copiesTitle")) }
        .task { await model.refresh() }
        if let (record, ticket) = deletion {
            Section {
                Text(text("phase4.deleteOriginalConfirm"))
                Button(text("phase4.deleteOriginal"), role: .destructive) {
                    Task { await model.deleteOriginal(record, ticket: ticket) }
                    deletion = nil
                }.accessibilityIdentifier("phase4.confirmDeleteOriginal")
                Button(text("action.cancel")) { deletion = nil }
            }
        }
        Section {
            Text(text("phase4.uninstallExplanation"))
            Picker(text("phase4.recoveryChoice"), selection: $model.recoveryChoice) {
                Text(text("phase4.recoveryExport")).tag(0)
                Text(text("phase4.recoveryHeld")).tag(1)
                Text(text("phase4.recoveryDiscard")).tag(2)
            }.disabled(model.working || preparation != nil)
            if model.recoveryChoice == 2 {
                Toggle(text("phase4.discardConfirmation"), isOn: $model.discardConfirmed).disabled(model.working || preparation != nil)
            }
            Toggle(text("phase4.deleteLocalData"), isOn: $model.deleteLocalData).disabled(model.working || preparation != nil)
            Button(text("phase4.prepareUninstall"), role: .destructive) {
                if let ticket = model.selectionTicket() {
                    preparation = (ticket, model.recoveryChoice, model.deleteLocalData, model.discardConfirmed)
                }
            }.disabled(!model.canPrepareUninstall || preparation != nil).accessibilityIdentifier("phase4.prepareUninstall")
            if model.uninstallReady { Text(text("phase4.uninstallReady")) }
        } header: { Text(text("phase4.uninstallTitle")) }
        if let (ticket, choice, deleteData, discard) = preparation {
            Section {
                Text(text("phase4.uninstallConfirm"))
                Button(text("phase4.prepareUninstall"), role: .destructive) {
                    Task { await model.prepareUninstall(ticket: ticket, choice: choice, deleteData: deleteData, discard: discard) }
                    preparation = nil
                }.accessibilityIdentifier("phase4.confirmUninstall")
                Button(text("action.cancel")) { preparation = nil }
            }
        }
    }
}

private struct FirmwareOperationRow: View {
    @ObservedObject var model: FirmwareCopiesModel
    let record: FirmwareBatchRecord
    let text: NativeText
    @State private var layer = 0
    @State private var row = 0
    @State private var column = 0
    @State private var output = "KC_C"
    @State private var pending: (FirmwareCopiesModel.RecordAction, UUID, String)?
    private func request(_ action: FirmwareCopiesModel.RecordAction, key: String) {
        if let ticket = model.selectionTicket() { pending = (action, ticket, key) }
    }
    var body: some View {
        if record.state == .draft {
            if model.canGenerate(record) {
                Stepper(text("phase4.layer") + ": \(layer)", value: $layer, in: 0...255)
                if record.backend == .vial { Stepper(text("phase4.row") + ": \(row)", value: $row, in: 0...255) }
                Stepper(text("phase4.column") + ": \(column)", value: $column, in: 0...255)
                TextField(text("phase4.outputKeycode"), text: $output)
                Button(text("phase4.exportChanges")) {
                    let changes = [FirmwareSlotChange(slot: FirmwareSlot(layer: layer, row: row, column: column), output: output, automatic: false)]
                    if let ticket = model.selectionTicket() { Task { await model.exportChanges(record, changes: changes, ticket: ticket) } }
                }.accessibilityIdentifier("patch-" + record.id.uuidString)
            }
        }
        if record.state == .awaitingUserImport {
            Button(text("phase4.claimImport")) { request(.claimImport, key: "phase4.claimImportConfirm") }
                .disabled(model.working || pending != nil).accessibilityIdentifier("claim-" + record.id.uuidString)
            Button(text("phase4.abandonExport")) { request(.abandon, key: "phase4.abandonConfirm") }
                .disabled(model.working || pending != nil)
        }
        if [.importClaimed, .verified, .failed].contains(record.state) {
            if record.backend == .via {
                Button(text("phase4.behaviorPassed")) { request(.viaPassed, key: "phase4.behaviorConfirm") }
                    .disabled(model.working || pending != nil).accessibilityIdentifier("passed-" + record.id.uuidString)
                Button(text("phase4.behaviorFailed")) { request(.viaFailed, key: "phase4.behaviorConfirm") }
                    .disabled(model.working || pending != nil)
            } else { Text(text("phase4.vialReadbackUnavailable")) }
        }
        if [.importClaimed, .verified, .failed, .externallyChanged].contains(record.state) {
            Button(text("phase4.guidedRollback")) { request(.rollback, key: "phase4.rollbackConfirm") }
                .disabled(model.working || pending != nil)
        }
        if let (action, ticket, key) = pending {
            Text(text(key))
            Button(text("phase4.confirmOperation")) {
                Task { await model.perform(action, record: record, ticket: ticket) }
                pending = nil
            }.disabled(model.working).accessibilityIdentifier("firmware-confirm-" + record.id.uuidString)
            Button(text("action.cancel")) { pending = nil }
        }
    }
}

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
    @Published private(set) var uninstallStage: UninstallPreparationStage?
    @Published private(set) var previousPreparation: UninstallPreparationRecord?
    @Published var recoverySelections: [UUID: RecoverySelection] = [:]
    @Published var deleteLocalData = false
    enum RecoveryOption: Int { case export, heldElsewhere, discard }
    struct RecoverySelection: Equatable {
        var option: RecoveryOption = .export
        var discardConfirmed = false
        var isConfirmed: Bool { option != .discard || discardConfirmed }
    }
    struct UninstallRequest {
        let records: [FirmwareBatchRecord]
        let selections: [UUID: RecoverySelection]
        let deleteLocalData: Bool
    }
    func recoverySelection(for record: FirmwareBatchRecord) -> RecoverySelection {
        recoverySelections[record.id] ?? RecoverySelection()
    }
    func uninstallRequest() -> UninstallRequest {
        UninstallRequest(records: records, selections: Dictionary(uniqueKeysWithValues: records.map {
            ($0.id, recoverySelection(for: $0))
        }), deleteLocalData: deleteLocalData)
    }
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
    private var vialReadback: (@Sendable (FirmwareBatchRecord) async throws -> VialKeymapObservation)?
    private var uninstall: UninstallActions?
    struct UninstallActions {
        let stopCapture: @MainActor () async throws -> Void
        let removeRules: @MainActor () async throws -> Void
        let removeLogin: @MainActor () async throws -> Void
        let eraseData: @MainActor () async throws -> Void
        let editing: @MainActor (Bool) -> Void
        var ready: @MainActor () -> Bool = { true }
    }
    func configure(store: ObjectStore, gate: KeyAvailabilityGate, support: FirmwareSupportDirectory = FirmwareSupportDirectory(),
                   versionAxes: @escaping @MainActor (FirmwareBackend) -> FirmwareVersionAxes? = { _ in nil },
                   vialReadback: (@Sendable (FirmwareBatchRecord) async throws -> VialKeymapObservation)? = nil) {
        self.store = store; self.gate = gate; self.support = support; self.versionAxes = versionAxes; firmware = nil
        self.vialReadback = vialReadback
    }
    func configureUninstall(_ actions: UninstallActions) { uninstall = actions }
    var canPrepareUninstall: Bool {
        canRead() && !working && uninstall?.ready() == true && records.allSatisfy { recoverySelection(for: $0).isConfirmed }
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
        recoverySelections = [:]; deleteLocalData = false
        uninstallStage = nil; previousPreparation = nil; uninstallReady = false
    }
    func refresh() async {
        guard canRead(), !working, store != nil else { return }
        let ticket = session
        let request = UUID(); readRequest = request
        do {
            let ledger = try await coordinator().reconcile()
            guard let store else { return }
            let previous = try await UninstallPreparationCoordinator.previousPreparation(store: store)
            if canRead(), ticket == session, request == readRequest {
                records = ledger.records; previousPreparation = previous
                recoverySelections = recoverySelections.filter { id, _ in records.contains(where: { $0.id == id }) }
                onChange()
            }
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
    func canVerifyVial(_ record: FirmwareBatchRecord) -> Bool {
        canRead() && !working && hasVialReadback(record)
    }
    func hasVialReadback(_ record: FirmwareBatchRecord) -> Bool {
        record.backend == .vial && vialReadback != nil && isCompatible(record) &&
            [.importClaimed, .verified, .failed, .externallyChanged].contains(record.state)
    }
    func verifyVial(_ record: FirmwareBatchRecord, ticket: UUID) async {
        guard ticket == session, records.contains(record), canVerifyVial(record), let gate, let vialReadback else { return }
        working = true; issueKey = nil
        defer { if ticket == session { working = false; onChange() } }
        do {
            let generation = try gate.begin()
            let observation = try await vialReadback(record)
            try gate.check(generation)
            guard canRead(), ticket == session else { return }
            let ledger = try await coordinator().confirmVialReadback(record.id, observation: observation)
            if canRead(), ticket == session { records = ledger.records }
        } catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed" } }
    }
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
    func prepareUninstall(ticket: UUID, request: UninstallRequest) async {
        guard canRead(), ticket == session, !working, let actions = uninstall, actions.ready(), let store, let gate else { return }
        guard request.records == records, Set(request.selections.keys) == Set(records.map(\.id)),
              request.selections.values.allSatisfy(\.isConfirmed) else {
            issueKey = "phase4.recoveryChanged"; onChange(); return
        }
        working = true; readRequest = UUID(); issueKey = nil; uninstallReady = false; actions.editing(true)
        uninstallStage = nil
        onChange()
        defer { actions.editing(false); if ticket == session { working = false; onChange() } }
        do {
            let firmware = try coordinator()
            let originals = try await firmware.reconcile().records
            guard canRead(), ticket == session else { throw FirmwareError.unavailable }
            guard originals == request.records else { throw FirmwareError.externalChange }
            var choices: [UUID: FirmwareRecoveryChoice] = [:]
            for original in originals {
                guard canRead(), ticket == session else { throw FirmwareError.unavailable }
                guard let selection = request.selections[original.id] else { throw FirmwareError.unavailable }
                switch selection.option {
                case .export:
                    guard let url = selectExport(original) else { return }
                    guard canRead(), ticket == session else { throw FirmwareError.unavailable }
                    choices[original.id] = .export(try FirmwareFileDestination(target: url, gate: gate))
                case .heldElsewhere: choices[original.id] = .heldElsewhere
                case .discard:
                    guard selection.discardConfirmed else { throw FirmwareError.unavailable }
                    choices[original.id] = .discardConfirmed
                }
            }
            let preparation = try UninstallPreparationCoordinator(store: store, firmware: firmware, gate: gate,
                stopCapture: actions.stopCapture,
                removeRules: actions.removeRules, removeLogin: actions.removeLogin, eraseData: actions.eraseData,
                authorize: { [weak self] in
                    guard let self, self.canRead(), self.session == ticket else { throw FirmwareError.unavailable }
                }, onProgress: { [weak self] stage in
                    guard let self, self.canRead(), self.session == ticket else { return }
                    self.uninstallStage = stage; self.onChange()
                })
            let result = try await preparation.prepare(choices: choices, deleteLocalData: request.deleteLocalData)
            if result.stage == .completed || (ticket == session && canRead()) { uninstallReady = true }
        } catch { if canRead(), ticket == session { issueKey = "phase4.operationFailed" } }
    }
}

struct FirmwareCopiesSection: View {
    @ObservedObject var model: FirmwareCopiesModel
    let viaBytes: Data?
    let text: NativeText
    @State private var deletion: (FirmwareBatchRecord, UUID)?
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
        FirmwareUninstallSection(model: model, text: text)
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
        if [.importClaimed, .verified, .failed, .externallyChanged].contains(record.state) {
            if record.backend == .via && record.state != .externallyChanged {
                Button(text("phase4.behaviorPassed")) { request(.viaPassed, key: "phase4.behaviorConfirm") }
                    .disabled(model.working || pending != nil).accessibilityIdentifier("passed-" + record.id.uuidString)
                Button(text("phase4.behaviorFailed")) { request(.viaFailed, key: "phase4.behaviorConfirm") }
                    .disabled(model.working || pending != nil)
            } else if model.hasVialReadback(record) {
                Button(text("phase4.verifyVialReadback")) {
                    if let ticket = model.selectionTicket() { Task { await model.verifyVial(record, ticket: ticket) } }
                }.disabled(!model.canVerifyVial(record)).accessibilityIdentifier("readback-" + record.id.uuidString)
            } else if record.backend == .vial { Text(text("phase4.vialReadbackUnavailable")) }
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

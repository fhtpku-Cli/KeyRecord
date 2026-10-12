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
    var canRead: @MainActor () -> Bool = { false }
    var selectedOriginal: @MainActor () -> Data? = { nil }
    var onChange: @MainActor () -> Void = {}
    var selectExport: @MainActor (FirmwareBatchRecord) -> URL? = { record in
        let panel = NSSavePanel(); panel.nameFieldStringValue = record.id.uuidString + (record.backend == .via ? ".json" : ".vil")
        return panel.runModal() == .OK ? panel.url : nil
    }
    private var store: ObjectStore?
    private var gate: KeyAvailabilityGate?
    private var firmware: FirmwareOperationCoordinator?
    private var session = UUID()
    private var readRequest = UUID()
    func configure(store: ObjectStore, gate: KeyAvailabilityGate) { self.store = store; self.gate = gate }
    private func coordinator() throws -> FirmwareOperationCoordinator {
        guard let store, let gate else { throw FirmwareError.unavailable }
        if let firmware { return firmware }
        let coordinator = try FirmwareOperationCoordinator(store: store, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        firmware = coordinator; return coordinator
    }
    func clear() { session = UUID(); records = []; firmware = nil; issueKey = nil; working = false }
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
    private func retain(_ bytes: Data?, backend: FirmwareBackend) async {
        guard canRead(), !working, let bytes else { return }
        let ticket = session; readRequest = UUID(); working = true
        do {
            let axes = FirmwareVersionAxes(definitionSchema: nil, deviceProtocol: nil, layoutFormat: nil, keycodeDialect: nil, importer: nil)
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
}

struct FirmwareCopiesSection: View {
    @ObservedObject var model: FirmwareCopiesModel
    let viaBytes: Data?
    let text: NativeText
    var body: some View {
        Section {
            Text(text("phase4.compatibilityUnknown")).fixedSize(horizontal: false, vertical: true)
            Button(text("phase4.retainVIA")) {
                if let ticket = model.selectionTicket() { Task { await model.retainVIA(viaBytes, ticket: ticket) } }
            }
                .disabled(model.working || viaBytes == nil).accessibilityIdentifier("phase4.retainVIA")
            ForEach(model.records) { record in
                Text(record.device + ": " + text("phase4.state.\(record.state.rawValue)"))
                if let date = record.exportedAt { Text(date, style: .date) }
                if let date = record.importClaimedAt { Text(date, style: .date) }
                if let date = record.verifiedAt { Text(date, style: .date) }
                Text(text("phase4.importNotVerification"))
                Text(text("phase4.exportWarning"))
                Button(text("phase4.exportOriginal")) {
                    if let ticket = model.selectionTicket() { Task { await model.exportOriginal(record, ticket: ticket) } }
                }.disabled(model.working)
                    .accessibilityIdentifier(record.id.uuidString)
            }
            Text(text("phase4.restoreInstructions")).fixedSize(horizontal: false, vertical: true)
            if let issue = model.issueKey { Text(text(issue)) }
        } header: { Text(text("phase4.copiesTitle")) }
        .task { await model.refresh() }
    }
}

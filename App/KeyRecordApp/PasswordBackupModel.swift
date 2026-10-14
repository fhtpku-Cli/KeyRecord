import AppKit
import SwiftUI
import KeyRecordCore
import KeyRecordStore

actor PasswordBackupWorker {
    func export(_ objects: [BackupObject], password: String) throws -> Data {
        try PasswordBackup.seal(objects, password: password)
    }
    func decrypt(_ url: URL, password: String) throws -> [BackupObject] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try PasswordBackup.open(PasswordBackupFile.read(url), password: password)
    }
}

@MainActor
final class PasswordBackupModel: ObservableObject {
    @Published var password = ""
    @Published var confirmation = ""
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    var canExport: () -> Bool = { false }
    var canRestore: () -> Bool = { false }
    var snapshot: (() async throws -> [BackupObject])?
    var restore: (([BackupObject]) async throws -> Void)?
    var gate: KeyAvailabilityGate?
    var selectExport: () -> URL? = {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KeyRecord-\(UUID().uuidString.prefix(8)).krbackup"
        return panel.runModal() == .OK ? panel.url : nil
    }
    var selectImport: () -> URL? = {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    private let worker = PasswordBackupWorker()
    private var session = UUID()

    func clear() {
        session = UUID(); password = ""; confirmation = ""; message = nil
    }

    func export() async {
        guard !busy, canExport(), let snapshot, let gate else { return }
        guard !password.isEmpty, password == confirmation else { message = "backup.passwordMismatch"; return }
        guard let url = selectExport() else { return }
        let password = self.password
        self.password = ""; confirmation = ""
        let ticket = session
        busy = true; message = nil
        defer { busy = false }
        do {
            let generation = try gate.begin()
            let objects = try await snapshot()
            try gate.check(generation)
            let archive = try await worker.export(objects, password: password)
            guard ticket == session, canExport() else { throw CancellationError() }
            try gate.check(generation)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try PasswordBackupFile.writeNew(archive, to: url)
            message = "backup.exported"
        } catch {
            if ticket == session { message = (error as? PasswordBackupError) == .destinationNotEmpty
                ? "backup.chooseNewFile" : "backup.failed" }
        }
    }

    func importBackup() async {
        guard !busy, canRestore(), let restore, !password.isEmpty else { return }
        guard let url = selectImport() else { return }
        let password = self.password
        self.password = ""; confirmation = ""
        let ticket = session
        busy = true; message = nil
        defer { busy = false }
        do {
            var objects = try await worker.decrypt(url, password: password)
            guard ticket == session, canRestore() else { throw CancellationError() }
            guard let index = objects.firstIndex(where: { $0.identity == CycleResetObjects.preferences }),
                  let current = objects.first(where: { $0.identity == CycleResetObjects.currentCycle })
            else { throw PasswordBackupError.invalidArchive }
            let preferences = try JSONDecoder().decode(Preferences.self, from: objects[index].payload)
            let cycle = try JSONDecoder().decode(CycleRecord.self, from: current.payload)
            guard preferences.currentCycleID == cycle.cycleID, cycle.isCurrent else { throw PasswordBackupError.invalidArchive }
            objects[index] = BackupObject(identity: objects[index].identity,
                payload: try JSONEncoder().encode(preferences.updating(expectedCollecting: false, loginItemEnabled: false)))
            try await restore(objects)
            message = "backup.restored"
        } catch {
            if ticket == session { message = "backup.restoreFailed" }
        }
    }
}

struct PasswordBackupSection: View {
    @ObservedObject var model: PasswordBackupModel
    let restoring: Bool
    let text: NativeText
    var body: some View {
        Section {
            Text(text(restoring ? "backup.restoreDisclosure" : "backup.disclosure"))
                .fixedSize(horizontal: false, vertical: true)
            SecureField(text("backup.password"), text: $model.password)
                .accessibilityIdentifier("backup.password")
            if !restoring {
                SecureField(text("backup.confirmPassword"), text: $model.confirmation)
                    .accessibilityIdentifier("backup.confirmPassword")
            }
            Button(text(restoring ? "backup.restore" : "backup.export")) {
                Task { if restoring { await model.importBackup() } else { await model.export() } }
            }
            .disabled(model.busy || model.password.isEmpty)
            .accessibilityIdentifier(restoring ? "backup.restore" : "backup.export")
            if model.busy { ProgressView() }
            if let message = model.message { Text(text(message)).accessibilityIdentifier("backup.message") }
        } header: { Text(text("backup.title")) }
        .disabled(model.busy)
        .onDisappear { model.clear() }
    }
}

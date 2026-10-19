import AppKit
import SwiftUI
import KeyRecordStore
import KeyRecordMappings

@MainActor
final class ConfigurationExportModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    var canExport: () -> Bool = { false }
    var snapshot: (() async throws -> ConfigurationExport)?
    var gate: KeyAvailabilityGate?
    var selectDestination: () -> URL? = {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KeyRecord-settings.json"
        return panel.runModal() == .OK ? panel.url : nil
    }
    private var session = UUID()
    func clear() { session = UUID(); message = nil }

    func export() async {
        guard canExport(), !busy, let snapshot, let gate else { return }
        busy = true; message = nil
        defer { busy = false }
        let ticket = session
        guard let url = selectDestination(), ticket == session, canExport() else { return }
        do {
            let generation = try gate.begin()
            let value = try await snapshot()
            guard ticket == session, canExport() else { throw CancellationError() }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try gate.use(generation) { try PasswordBackupFile.writeNew(value.encoded(), to: url) }
            message = "settings.exported"
        } catch {
            if ticket == session { message = error as? PasswordBackupError == .destinationNotEmpty
                ? "backup.chooseNewFile" : "backup.failed" }
        }
    }
}

struct ConfigurationExportSection: View {
    @ObservedObject var model: ConfigurationExportModel
    let text: NativeText
    var body: some View {
        Section {
            Text(text("settings.exportWarning")).fixedSize(horizontal: false, vertical: true)
            Button(text("settings.export")) { Task { await model.export() } }
                .disabled(model.busy).accessibilityIdentifier("settings.export")
            if let message = model.message { Text(text(message)) }
        } header: { Text(text("settings.exportTitle")) }
    }
}

import SwiftUI
import KeyRecordMappings

struct FirmwareUninstallSection: View {
    @ObservedObject var model: FirmwareCopiesModel
    let text: NativeText
    @State private var preparation: (UUID, FirmwareCopiesModel.UninstallRequest)?
    var body: some View {
        Section {
            Text(text("phase4.uninstallExplanation"))
            ForEach(Array(model.records.enumerated()), id: \.element.id) { index, record in
                VStack(alignment: .leading) {
                    Text(copyLabel(record, index: index))
                    HStack {
                        Text(text("phase4.originalConfirmedAt"))
                        Text(record.originalExportConfirmedAt, style: .date)
                        Text(record.originalExportConfirmedAt, style: .time)
                    }
                    Picker(text("phase4.recoveryChoice"), selection: option(for: record)) {
                        Text(text("phase4.recoveryExport")).tag(FirmwareCopiesModel.RecoveryOption.export)
                        Text(text("phase4.recoveryHeld")).tag(FirmwareCopiesModel.RecoveryOption.heldElsewhere)
                        Text(text("phase4.recoveryDiscard")).tag(FirmwareCopiesModel.RecoveryOption.discard)
                    }.accessibilityIdentifier("recovery-choice-" + record.id.uuidString)
                    if model.recoverySelection(for: record).option == .discard {
                        Toggle(text("phase4.discardConfirmation"), isOn: discard(for: record))
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("recovery-discard-" + record.id.uuidString)
                    }
                }.disabled(model.working || preparation != nil)
            }
            Toggle(text("phase4.deleteLocalData"), isOn: $model.deleteLocalData).disabled(model.working || preparation != nil)
            Button(text("phase4.prepareUninstall"), role: .destructive) {
                if let ticket = model.selectionTicket() { preparation = (ticket, model.uninstallRequest()) }
            }.disabled(!model.canPrepareUninstall || preparation != nil).accessibilityIdentifier("phase4.prepareUninstall")
            if model.uninstallReady { Text(text("phase4.uninstallReady")) }
            if let stage = model.uninstallStage {
                Text(text("phase4.uninstallStage.\(stage.rawValue)"))
                    .accessibilityIdentifier("phase4.uninstallProgress")
            } else if let previous = model.previousPreparation {
                Text(text("phase4.previousUninstallAttempt"))
                Text(text("phase4.uninstallStage.\(previous.stage.rawValue)"))
                    .accessibilityIdentifier("phase4.previousUninstallProgress")
                Text(text("phase4.previousUninstallReview"))
            }
        } header: { Text(text("phase4.uninstallTitle")) }
        if let (ticket, request) = preparation {
            Section {
                Text(text("phase4.uninstallConfirm"))
                ForEach(Array(request.records.enumerated()), id: \.element.id) { index, record in
                    Text(copyLabel(record, index: index) + ": " + choiceText(request.selections[record.id]?.option ?? .export))
                }
                Text(text(request.deleteLocalData ? "phase4.confirmDataErasure" : "phase4.confirmDataRetained"))
                Button(text("phase4.prepareUninstall"), role: .destructive) {
                    Task { await model.prepareUninstall(ticket: ticket, request: request) }
                    preparation = nil
                }.accessibilityIdentifier("phase4.confirmUninstall")
                Button(text("action.cancel")) { preparation = nil }
            }
        }
    }
    private func copyLabel(_ record: FirmwareBatchRecord, index: Int) -> String {
        String(format: text("phase4.numberedCopy"), index + 1) + ": " + record.device
    }
    private func choiceText(_ option: FirmwareCopiesModel.RecoveryOption) -> String {
        switch option {
        case .export: text("phase4.recoveryExport")
        case .heldElsewhere: text("phase4.recoveryHeld")
        case .discard: text("phase4.recoveryDiscard")
        }
    }
    private func option(for record: FirmwareBatchRecord) -> Binding<FirmwareCopiesModel.RecoveryOption> {
        Binding(get: { model.recoverySelection(for: record).option }, set: { value in
            model.recoverySelections[record.id] = .init(option: value)
        })
    }
    private func discard(for record: FirmwareBatchRecord) -> Binding<Bool> {
        Binding(get: { model.recoverySelection(for: record).discardConfirmed }, set: { value in
            var selection = model.recoverySelection(for: record)
            selection.discardConfirmed = value; model.recoverySelections[record.id] = selection
        })
    }
}

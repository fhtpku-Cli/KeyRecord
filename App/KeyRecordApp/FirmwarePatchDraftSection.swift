import SwiftUI
import KeyRecordMappings

struct FirmwarePatchDraftSection: View {
    @ObservedObject var model: FirmwareCopiesModel
    let record: FirmwareBatchRecord
    let text: NativeText
    @State private var layer = 0
    @State private var row = 0
    @State private var column = 0
    @State private var output = "KC_C"
    var body: some View {
        Stepper(text("phase4.layer") + ": \(layer)", value: $layer, in: 0...255).disabled(model.working)
        if record.backend == .vial {
            Stepper(text("phase4.row") + ": \(row)", value: $row, in: 0...255).disabled(model.working)
        }
        Stepper(text("phase4.column") + ": \(column)", value: $column, in: 0...255).disabled(model.working)
        TextField(text("phase4.outputKeycode"), text: $output).disabled(model.working)
        Button(text("phase4.stagePatchChange")) {
            if let ticket = model.selectionTicket() {
                model.stagePatchChange(.init(slot: .init(layer: layer, row: record.backend == .via ? 0 : row, column: column),
                    output: output, automatic: false), record: record, ticket: ticket)
            }
        }.disabled(!model.canGenerate(record)).accessibilityIdentifier("stage-" + record.id.uuidString)
        let changes = model.patchDrafts[record.id] ?? []
        ForEach(changes.map { (id: "draft-" + slotID($0.slot), change: $0) }, id: \.id) { entry in
            let change = entry.change
            HStack {
                Text(slotText(change.slot) + ": " + change.output)
                Button(text("phase4.removePatchChange")) {
                    if let ticket = model.selectionTicket() { model.removePatchChange(slot: change.slot, record: record, ticket: ticket) }
                }.disabled(model.working).accessibilityIdentifier("remove-patch-" + record.id.uuidString + "-" + slotID(change.slot))
            }
        }
        Button(text("phase4.previewPatch")) {
            if let ticket = model.selectionTicket() { Task { await model.previewPatch(record, ticket: ticket) } }
        }.disabled(!model.canGenerate(record) || changes.isEmpty).accessibilityIdentifier("preview-" + record.id.uuidString)
        if let preview = model.patchPreviews[record.id] {
            Text(text("phase4.patchPreviewTitle"))
            ForEach(preview.differences.map { (id: "difference-" + slotID($0.change.slot), difference: $0) }, id: \.id) { entry in
                let difference = entry.difference
                let summary = slotText(difference.change.slot) + ": " + difference.before + " \u{2192} " + difference.change.output
                HStack { Text(summary) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(summary)
                    .accessibilityIdentifier("patch-diff-" + record.id.uuidString + "-" + slotID(difference.change.slot))
            }
            Text(text("phase4.patchPreviewExplanation"))
            Text(text("phase4.exportWarning"))
        }
        Button(text("phase4.exportChanges")) {
            if let ticket = model.selectionTicket() { Task { await model.exportPreview(record, ticket: ticket) } }
        }.disabled(!model.canExportPreview(record)).accessibilityIdentifier("patch-" + record.id.uuidString)
    }
    private func slotID(_ slot: FirmwareSlot) -> String { "\(slot.layer)-\(slot.row)-\(slot.column)" }
    private func slotText(_ slot: FirmwareSlot) -> String {
        if record.backend == .vial { return String(format: text("phase4.vialSlot"), slot.layer, slot.row, slot.column) }
        return String(format: text("phase4.viaSlot"), slot.layer, slot.column)
    }
}

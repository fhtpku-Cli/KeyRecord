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
        if record.compatibilityBasis == .viaFile {
            VIAFilePatchControls(model: model, record: record, text: text)
                .disabled(model.working)
                .task(id: record.id) {
                    if model.viaFileSlots[record.id] == nil, let ticket = model.selectionTicket() {
                        await model.loadVIAFileSlots(record, ticket: ticket)
                    }
                }
        } else {
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
        }
        let changes = model.patchDrafts[record.id] ?? []
        ForEach(changes.map { (id: "draft-" + slotID($0.slot), change: $0) }, id: \.id) { entry in
            let change = entry.change
            HStack {
                Text(slotText(change.slot) + ": " + keyName(change.output))
                Button(text("phase4.removePatchChange")) {
                    if let ticket = model.selectionTicket() { model.removePatchChange(slot: change.slot, record: record, ticket: ticket) }
                }.disabled(model.working).accessibilityIdentifier("remove-patch-" + record.id.uuidString + "-" + slotID(change.slot))
            }
        }
        Button(text("phase4.previewPatch")) {
            if let ticket = model.selectionTicket() { Task { await model.previewPatch(record, ticket: ticket) } }
        }.disabled(!model.canGenerate(record) || changes.isEmpty).accessibilityIdentifier("preview-" + record.id.uuidString)
        if let issue = model.patchIssueKeys[record.id] {
            Text(text(issue)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("patch-issue-" + record.id.uuidString)
        }
        if let preview = model.patchPreviews[record.id] {
            Text(text("phase4.patchPreviewTitle"))
            ForEach(preview.differences.map { (id: "difference-" + slotID($0.change.slot), difference: $0) }, id: \.id) { entry in
                let difference = entry.difference
                let summary = slotText(difference.change.slot) + ": " + keyName(difference.before) + " \u{2192} " + keyName(difference.change.output)
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
    private func keyName(_ key: String) -> String {
        record.compatibilityBasis == .viaFile ? VIAFileKeyLabels.name(key, text: text) : key
    }
    private func slotText(_ slot: FirmwareSlot) -> String {
        if record.backend == .vial { return String(format: text("phase4.vialSlot"), slot.layer, slot.row, slot.column) }
        return String(format: text("phase4.viaSlot"), slot.layer, slot.column)
    }
}

private struct VIAFilePatchControls: View {
    @ObservedObject var model: FirmwareCopiesModel
    let record: FirmwareBatchRecord
    let text: NativeText
    @State private var layer = 0
    @State private var selected: FirmwareSlot?
    @State private var output: String?
    @State private var search = ""
    @FocusState private var focusedChoice: String?
    private var slots: [VIAFileSlot] { model.viaFileSlots[record.id] ?? [] }
    private var current: VIAFileSlot? { slots.first { $0.slot == selected } }
    private var outputs: [String] {
        VIAFileCompatibility.outputs.sorted().filter { search.isEmpty ||
            VIAFileKeyLabels.name($0, text: text).localizedCaseInsensitiveContains(search) ||
            $0.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        Text(text("phase4.fileEditingTitle")).font(.headline)
        Text(text("phase4.fileSteps")).fixedSize(horizontal: false, vertical: true)
        if model.viaFileSlots[record.id] == nil {
            Button(text("phase4.loadPositions")) {
                if let ticket = model.selectionTicket() { Task { await model.loadVIAFileSlots(record, ticket: ticket) } }
            }.disabled(model.working).accessibilityIdentifier("load-slots-" + record.id.uuidString)
        } else {
            positionChoices
            originalValue
            outputChoices
            Text(text("phase4.basicOutputNotice")).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button(text("phase4.stagePatchChange")) {
                if let current, current.restriction == nil, let output, let ticket = model.selectionTicket() {
                    model.stagePatchChange(.init(slot: current.slot, output: output, automatic: false), record: record, ticket: ticket)
                }
            }.disabled(!model.canGenerate(record) || current == nil || current?.restriction != nil || output == nil || current?.original == output)
                .accessibilityIdentifier("stage-" + record.id.uuidString)
        }
    }
    @ViewBuilder private var positionChoices: some View {
        Picker(text("phase4.layer"), selection: $layer) {
            ForEach(Array(Set(slots.map { $0.slot.layer })).sorted(), id: \.self) { layer in
                Text(String(layer)).tag(layer)
            }
        }.accessibilityIdentifier("via-layer-" + record.id.uuidString)
            .onChange(of: layer) { _, _ in selected = nil }
        Text(text("phase4.selectPosition"))
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(slots.filter { $0.slot.layer == layer }, id: \.slot) { entry in positionButton(entry) }
            }.padding(4)
        }.frame(height: 150)
        Text(text("phase4.filePositionNotice")).font(.caption).fixedSize(horizontal: false, vertical: true)
    }
    private func positionButton(_ entry: VIAFileSlot) -> some View {
        let title = String(format: text("phase4.filePosition"), entry.slot.column) + ": " + VIAFileKeyLabels.name(entry.original, text: text)
        return Button { selected = entry.slot } label: {
            HStack {
                Text(title).lineLimit(1)
                if entry.restriction != nil { Image(systemName: "lock") }
                if selected == entry.slot { Image(systemName: "checkmark") }
            }
        }
        .focusable()
        .focused($focusedChoice, equals: "slot-\(entry.slot.layer)-\(entry.slot.column)")
        .onKeyPress(keys: [.space, .return]) { _ in
            guard !model.working else { return .ignored }
            selected = entry.slot
            return .handled
        }
        .accessibilityLabel(title + (entry.restriction == nil ? "" : ", " + text("phase4.readOnlyPosition")))
        .accessibilityIdentifier("via-slot-\(record.id)-\(entry.slot.layer)-\(entry.slot.column)")
    }
    @ViewBuilder private var originalValue: some View {
        if let current {
            Text(text("phase4.originalKey") + ": " + VIAFileKeyLabels.name(current.original, text: text))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("via-original-" + record.id.uuidString)
            if let restriction = current.restriction {
                Text(text(restriction == .protectedEntry ? "phase4.patchIssue.protected" :
                    restriction == .unreachableLayer ? "phase4.patchIssue.layer" : "phase4.readOnlyAction"))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("via-restriction-" + record.id.uuidString)
            }
        }
    }
    @ViewBuilder private var outputChoices: some View {
        TextField(text("phase4.searchOutput"), text: $search)
            .accessibilityIdentifier("via-output-search-" + record.id.uuidString)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading) {
                ForEach(outputs, id: \.self) { key in outputButton(key) }
            }.padding(4)
        }.frame(height: 140)
        if outputs.isEmpty { Text(text("phase4.noOutputMatches")) }
        if let output { Text(text("phase4.newKey") + ": " + VIAFileKeyLabels.name(output, text: text)) }
    }
    private func outputButton(_ key: String) -> some View {
        Button { output = key } label: {
            HStack {
                Text(VIAFileKeyLabels.name(key, text: text))
                if output == key { Image(systemName: "checkmark") }
            }
        }.focusable()
            .focused($focusedChoice, equals: "output-" + key)
            .onKeyPress(keys: [.space, .return]) { _ in
                guard !model.working else { return .ignored }
                output = key
                return .handled
            }
            .accessibilityIdentifier("via-output-\(record.id)-\(key)")
    }
}

enum VIAFileKeyLabels {
    static func name(_ token: String, text: NativeText) -> String {
        let translated = text("phase4.key." + token)
        if translated != "phase4.key." + token { return translated }
        if VIAFileCompatibility.outputs.contains(token) { return String(token.dropFirst(3)) }
        return token
    }
}

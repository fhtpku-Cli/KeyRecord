import SwiftUI
import UniformTypeIdentifiers
import KeyRecordAnalysis

struct VIAImportSection: View {
    @ObservedObject var model: VIAImportModel
    let text: NativeText
    @State private var choosingFile = false
    @State private var kind: VIAImportFileKind = .layout
    @State private var ticket: UUID?

    var body: some View {
        Section {
            Text(text("phase2.via.notice")).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(text("phase2.via.chooseLayout")) { choose(.layout) }
                    .disabled(model.loading.contains(.layout))
                    .accessibilityIdentifier("phase2.via.chooseLayout")
                Button(text("phase2.via.chooseDefinition")) { choose(.definition) }
                    .disabled(model.loading.contains(.definition))
                    .accessibilityIdentifier("phase2.via.chooseDefinition")
            }
            if let name = model.layoutFilename { Text(String(format: text("phase2.via.layoutSelected"), name)).lineLimit(2) }
            if let name = model.definitionFilename { Text(String(format: text("phase2.via.definitionSelected"), name)).lineLimit(2) }
            if !model.loading.isEmpty { Text(text("phase2.via.loading")) }
            if let issue = model.issue { Text(text(VIAImportLabels.issueKey(issue))).accessibilityIdentifier("phase2.via.issue") }
            if let configuration = model.configuration {
                VIAReferenceSummary(configuration: configuration, text: text)
            } else if model.issue == nil && model.loading.isEmpty {
                Text(text("phase2.via.needPair"))
            }
            Button(text("phase2.via.clear")) { model.clear() }
                .accessibilityIdentifier("phase2.via.clear")
        } header: { Text(text("phase2.via.title")) }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let selection = kind
                let authorization = ticket
                Task { @MainActor in await model.load(kind: selection, url: url, ticket: authorization) }
            }
        }
        .onDisappear { choosingFile = false }
    }

    private func choose(_ selection: VIAImportFileKind) {
        guard let current = model.selectionTicket() else { return }
        ticket = current
        kind = selection
        choosingFile = true
    }
}

struct VIAReferenceSummary: View {
    let configuration: VIAImportedConfiguration
    let text: NativeText
    var body: some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            Text(String(format: text("phase2.via.summary"), configuration.name, configuration.layerCount,
                configuration.geometry?.positions.count ?? 0, configuration.standardKeyCount, configuration.unsupportedKeyCount))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("phase2.via.summary")
            ForEach(configuration.limitations.sorted { $0.rawValue < $1.rawValue }, id: \.self) { reason in
                Text(text(VIAImportLabels.limitationKey(reason))).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum VIAImportLabels {
    static func limitationKey(_ reason: VIAReferenceLimitation) -> String {
        switch reason {
        case .deploymentUnknown: return "phase2.via.deploymentUnknown"
        case .transformsUnknown: return "phase2.via.transformsUnknown"
        case .additionalLayers: return "phase2.via.additionalLayers"
        case .unsupportedKeycodes: return "phase2.via.unsupportedKeycodes"
        case .layoutOptions: return "phase2.via.layoutOptions"
        case .complexGeometry: return "phase2.via.complexGeometry"
        case .dynamicFeatures: return "phase2.via.dynamicFeatures"
        }
    }
    static func issueKey(_ issue: VIAImportIssue) -> String {
        switch issue {
        case .changed: return "phase2.via.changed"
        case .readFailed: return "phase2.via.readFailed"
        case .notRegularFile: return "phase2.via.notRegularFile"
        case .parser(let error):
            switch error {
            case .jsonProtection: return "phase2.via.jsonProtection"
            case .keyboardMismatch: return "phase2.via.keyboardMismatch"
            case .layerShapeMismatch: return "phase2.via.layerShapeMismatch"
            case .unsupportedSchema: return "phase2.via.unsupportedSchema"
            case .invalidGeometry: return "phase2.via.invalidGeometry"
            case .malformedDocument, .invalidIdentity, .invalidMatrix, .invalidLayers: return "phase2.via.invalidDocument"
            }
        }
    }
}

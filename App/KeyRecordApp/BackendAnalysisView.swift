import SwiftUI
import UniformTypeIdentifiers
import KeyRecordCore
import KeyRecordStore
import KeyRecordAnalysis

struct SelectedKarabinerFile: Sendable {
    let reference: KarabinerReference
    let monitor: VIAFileMonitor
}

@MainActor
final class KarabinerImportModel: ObservableObject {
    @Published private var rawReference: KarabinerReference?
    @Published var profile: String? { didSet { onChange() } }
    @Published private(set) var filename: String?
    @Published private(set) var loading = false
    @Published private(set) var issueKey: String?
    var canRead: @MainActor () -> Bool = { false }
    var protectedGate: KeyAvailabilityGate?
    var onChange: @MainActor () -> Void = {}
    var readFile: @Sendable (URL, VIAFileReadAccess, @escaping @Sendable () -> Void) throws -> SelectedKarabinerFile = {
        let file = try VIAFileReader.readConfiguration(url: $0, access: $1, notify: $2, parse: KarabinerReferenceParser.parse)
        return SelectedKarabinerFile(reference: file.reference, monitor: file.monitor)
    }
    private var request: UUID?
    private var job: Task<SelectedKarabinerFile, any Error>?
    private var monitor: VIAFileMonitor?
    private var session = UUID()
    private var sessionActive = false

    var reference: KarabinerReference? { canRead() && monitor?.hasChanged != true ? rawReference : nil }
    var evidence: BackendRuleEvidence? { reference?.profiles.first { $0.id == profile }?.evidence }

    func selectionTicket() -> UUID? {
        guard canRead() else { return nil }
        sessionActive = true
        return session
    }

    func load(url: URL, ticket: UUID) async {
        guard canRead(), ticket == session else { return }
        let generation: CaptureGeneration?
        do { generation = try protectedGate?.begin() }
        catch { clear(); return }
        withdraw()
        let current = UUID()
        request = current
        filename = String(url.lastPathComponent.prefix(256))
        loading = true
        issueKey = nil
        onChange()
        let access = VIAFileReadAccess(gate: protectedGate, generation: generation)
        let read = readFile
        let task = Task.detached(priority: .userInitiated) {
            try read(url, access) { [weak self] in
                Task { @MainActor in self?.changed(current) }
            }
        }
        job = task
        do {
            let selected = try await task.value
            guard canRead(), request == current else { selected.monitor.cancel(); return }
            try access.use {}
            guard !selected.monitor.hasChanged else { selected.monitor.cancel(); throw VIAFileReadError.changed }
            rawReference = selected.reference
            profile = selected.reference.selectedProfile
            monitor = selected.monitor
            loading = false
            job = nil
            onChange()
        } catch {
            guard canRead(), request == current else { return }
            withdraw()
            issueKey = error is KarabinerReferenceError ? "phase2.karabiner.invalid" : "phase2.karabiner.readFailed"
            onChange()
        }
    }

    func clear() {
        guard sessionActive || request != nil || rawReference != nil || filename != nil || issueKey != nil else { return }
        session = UUID()
        sessionActive = false
        withdraw()
        filename = nil
        issueKey = nil
        onChange()
    }

    private func withdraw() {
        request = nil
        job?.cancel(); job = nil
        monitor?.cancel(); monitor = nil
        rawReference = nil
        profile = nil
        loading = false
    }

    private func changed(_ current: UUID) {
        guard request == current else { return }
        withdraw()
        issueKey = canRead() ? "phase2.karabiner.changed" : nil
        onChange()
    }
}

struct KarabinerImportSection: View {
    @ObservedObject var model: KarabinerImportModel
    let text: NativeText
    @State private var choosing = false
    @State private var ticket: UUID?

    var body: some View {
        Section {
            Text(text("phase2.karabiner.notice")).fixedSize(horizontal: false, vertical: true)
            Button(text("phase2.karabiner.choose")) {
                ticket = model.selectionTicket()
                choosing = ticket != nil
            }.disabled(model.loading).accessibilityIdentifier("phase2.karabiner.choose")
            if let filename = model.filename { Text(filename).lineLimit(2) }
            if let reference = model.reference {
                Picker(text("phase2.karabiner.profile"), selection: $model.profile) {
                    Text(text("phase2.karabiner.selectProfile")).tag(nil as String?)
                    ForEach(reference.profiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
                }.accessibilityIdentifier("phase2.karabiner.profile")
                if let evidence = model.evidence {
                    Text(String(format: text("phase2.karabiner.summary"), evidence.rules.count, evidence.unsupportedRuleCount))
                }
            }
            if model.loading { Text(text("phase2.via.loading")) }
            if let issue = model.issueKey { Text(text(issue)) }
            Button(text("phase2.karabiner.clear")) { model.clear() }
        } header: { Text(text("phase2.karabiner.title")) }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result, let ticket {
                Task { @MainActor in await model.load(url: url, ticket: ticket) }
            }
        }
        .onDisappear { choosing = false }
    }
}

struct AnalysisConflictView: View {
    let input: CandidateCheckInput
    let text: NativeText

    var body: some View {
        let report = CandidateConflictDetector.evaluate(input)
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            Text(AnalysisReadinessText.label(report.readiness, text: text))
            Text(text("phase2.conflict.partial")).font(.caption)
            if let capabilities = BackendCapabilityCatalog.reference(input.backend.kind) {
                let referenceInput = CandidateCheckInput(source: input.source, trigger: input.trigger, scope: input.scope,
                    backend: .connected(capabilities))
                if case .unsupported(let reason) = CandidateConstraints.assess(referenceInput) {
                    Text(AnalysisReadinessText.label(.unsupported(reason), text: text))
                } else { Text(text("phase2.conflict.referenceSupported")) }
            }
            ForEach(report.findings, id: \.kind) { finding in
                Text(text("phase2.conflict.\(finding.kind.rawValue)"))
                Text(text(finding.severity == .blocking ? "phase2.conflict.blocking" : "phase2.conflict.warning")).font(.caption)
            }
            ForEach(report.check.evidenceKinds.sorted(), id: \.self) { kind in
                Text(text("phase2.evidence.\(kind)")).font(.caption)
            }
            ForEach(report.limitations.sorted { $0.rawValue < $1.rawValue }, id: \.self) { limitation in
                Text(text("phase2.conflict.limit.\(limitation.rawValue)")).font(.caption)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("phase2.conflict.report")
    }
}

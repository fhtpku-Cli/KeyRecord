import Foundation
import Combine
import KeyRecordCore
import KeyRecordStore
import KeyRecordAnalysis

enum VIAImportIssue: Equatable {
    case parser(VIAImportError), readFailed, notRegularFile, changed
}

@MainActor
final class VIAImportModel: ObservableObject {
    @Published private var rawConfiguration: VIAImportedConfiguration?
    @Published private(set) var layoutFilename: String?
    @Published private(set) var definitionFilename: String?
    @Published private(set) var loading: Set<VIAImportFileKind> = []
    @Published private(set) var issue: VIAImportIssue?
    var canRead: @MainActor () -> Bool = { false }
    var protectedGate: KeyAvailabilityGate?
    var onChange: @MainActor () -> Void = {}
    var readFile: @Sendable (URL, VIAImportFileKind, VIAFileReadAccess, @escaping @Sendable () -> Void) throws -> SelectedVIAFile = {
        try VIAFileReader.read(url: $0, kind: $1, access: $2, notify: $3)
    }
    private var layout: VIALayoutReference?
    private var definition: VIADefinitionReference?
    private var layoutBytes: Data?
    var selectedOriginalBytes: Data? { canRead() && monitors[.layout]?.hasChanged == false ? layoutBytes : nil }
    var layoutReference: VIALayoutReference? { selectedOriginalBytes != nil ? layout : nil }
    private var requests: [VIAImportFileKind: UUID] = [:]
    private var jobs: [VIAImportFileKind: Task<SelectedVIAFile, any Error>] = [:]
    private var monitors: [VIAImportFileKind: VIAFileMonitor] = [:]
    private(set) var selectionSession = UUID()
    private var sessionActive = false

    var configuration: VIAImportedConfiguration? {
        canRead() && !monitors.values.contains(where: { $0.hasChanged }) ? rawConfiguration : nil
    }

    func selectionTicket() -> UUID? {
        guard canRead() else { return nil }
        sessionActive = true
        return selectionSession
    }

    func load(kind: VIAImportFileKind, url: URL, ticket: UUID? = nil) async {
        guard canRead(), ticket == nil || ticket == selectionSession else { return }
        sessionActive = true
        let generation: CaptureGeneration?
        do { generation = try protectedGate?.begin() }
        catch { clear(); return }
        let request = UUID()
        requests[kind] = request
        jobs[kind]?.cancel()
        monitors.removeValue(forKey: kind)?.cancel()
        withdraw(kind)
        if kind == .layout { layoutFilename = String(url.lastPathComponent.prefix(256)) }
        else { definitionFilename = String(url.lastPathComponent.prefix(256)) }
        loading.insert(kind)
        issue = nil
        rawConfiguration = nil
        onChange()
        let read = readFile
        let access = VIAFileReadAccess(gate: protectedGate, generation: generation)
        let notify: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.fileChanged(kind, request: request) }
        }
        let job = Task.detached(priority: .userInitiated) { try read(url, kind, access, notify) }
        jobs[kind] = job
        do {
            let selected = try await job.value
            guard requests[kind] == request, canRead() else { selected.monitor.cancel(); return }
            try access.use {}
            guard !selected.monitor.hasChanged else { selected.monitor.cancel(); throw VIAFileReadError.changed }
            switch (kind, selected.reference) {
            case (.layout, .layout(let parsed)): layout = parsed; layoutBytes = selected.bytes
            case (.definition, .definition(let parsed)): definition = parsed
            default: selected.monitor.cancel(); throw VIAImportError.malformedDocument
            }
            monitors[kind] = selected.monitor
            loading.remove(kind)
            jobs[kind] = nil
            recompute()
        } catch {
            guard requests[kind] == request, canRead() else { return }
            loading.remove(kind)
            jobs[kind] = nil
            withdraw(kind)
            rawConfiguration = nil
            if let parse = error as? VIAImportError { issue = .parser(parse) }
            else if let file = error as? VIAFileReadError {
                switch file {
                case .notRegularFile: issue = .notRegularFile
                case .tooLarge: issue = .parser(.jsonProtection)
                case .changed: issue = .changed
                }
            } else { issue = .readFailed }
            onChange()
        }
    }

    func clear() {
        guard sessionActive || !requests.isEmpty || rawConfiguration != nil || issue != nil else { return }
        selectionSession = UUID()
        sessionActive = false
        requests.removeAll()
        jobs.values.forEach { $0.cancel() }
        jobs.removeAll()
        monitors.values.forEach { $0.cancel() }
        monitors.removeAll()
        layout = nil
        layoutBytes = nil
        definition = nil
        layoutFilename = nil
        definitionFilename = nil
        loading = []
        rawConfiguration = nil
        issue = nil
        onChange()
    }

    private func fileChanged(_ kind: VIAImportFileKind, request: UUID) {
        guard requests[kind] == request else { return }
        requests[kind] = nil
        jobs.removeValue(forKey: kind)?.cancel()
        monitors.removeValue(forKey: kind)?.cancel()
        loading.remove(kind)
        withdraw(kind)
        rawConfiguration = nil
        issue = canRead() ? .changed : nil
        onChange()
    }

    private func withdraw(_ kind: VIAImportFileKind) {
        if kind == .layout { layout = nil; layoutBytes = nil } else { definition = nil }
    }

    private func recompute() {
        rawConfiguration = nil
        if let layout, let definition, loading.isEmpty {
            do { rawConfiguration = try VIAReferenceParser.match(layout: layout, definition: definition); issue = nil }
            catch let error as VIAImportError { issue = .parser(error) }
            catch { issue = .parser(.malformedDocument) }
        }
        onChange()
    }
}

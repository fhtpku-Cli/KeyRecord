import Foundation
import Combine
import KeyRecordAnalysis
import KeyRecordStore
import AppKit
import IOKit
import IOKit.hidsystem

private final class NativePhysicalSystemPort: PhysicalSystemReading {
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private func services() throws -> [UInt64: IOHIDServiceClient] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { throw PhysicalSourceReadError.unavailable }
        var result: [UInt64: IOHIDServiceClient] = [:]
        for service in services where IOHIDServiceClientConformsTo(service, 1, 6) != 0 {
            guard let id = IOHIDServiceClientGetRegistryID(service) as? NSNumber,
                  result[id.uint64Value] == nil, result.count < 256 else { throw PhysicalSourceReadError.malformed }
            result[id.uint64Value] = service
        }
        return result
    }
    func keyboardServiceIDs() throws -> [UInt64] { Array(try services().keys) }
    func userKeyMapping(for registryID: UInt64) throws -> Any? {
        guard let service = try services()[registryID] else { throw PhysicalSourceReadError.unavailable }
        return IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString)
    }
    func keyboardProperties(for registryID: UInt64) throws -> [String: Any] {
        guard let service = try services()[registryID] else { throw PhysicalSourceReadError.unavailable }
        var result: [String: Any] = [:]
        for key in ["VendorID", "ProductID", "Transport", "VendorIDSource"] {
            result[key] = IOHIDServiceClientCopyProperty(service, key as CFString)
        }
        return result
    }
}

@MainActor
struct PhysicalSourceObservation {
    let input: PhysicalSourceInput
    let evidence: PhysicalEvidence
    let isCurrent: @MainActor () -> Bool
    var sources: [PhysicalSourceSummary]? = nil
    var system: PhysicalSystemSnapshot? = nil
    var deviceLayout: PhysicalDeviceLayoutResolution? = nil
}

struct PhysicalHostSourcePorts: Sendable {
    var system: @Sendable () throws -> PhysicalSystemSnapshot = { try PhysicalSystemSource.read(from: NativePhysicalSystemPort()) }
    var softwareURL: @Sendable () -> URL = {
        let configured = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let root = configured.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return root.appendingPathComponent("karabiner/karabiner.json")
    }
    var version: @Sendable () throws -> String? = KarabinerDeploymentDependencies().version
}

private struct CollectedPhysicalHostSources: Sendable {
    let system: PhysicalSystemSnapshot?
    let software: PhysicalSoftwareReference?
    let file: VIAFileMonitor?
}

@MainActor
final class PhysicalHostSourceAdapter {
    private let ports: PhysicalHostSourcePorts
    private let gate: KeyAvailabilityGate?
    private let canRead: @MainActor () -> Bool
    private var changed: (@MainActor () -> Void)?
    init(ports: PhysicalHostSourcePorts, gate: KeyAvailabilityGate? = nil, canRead: @escaping @MainActor () -> Bool) {
        self.ports = ports; self.gate = gate; self.canRead = canRead
    }
    var dependencies: PhysicalSourceDependencies {
        PhysicalSourceDependencies(observe: { input in try await self.read(input) }, observeChanges: { [self] callback in
            self.changed = callback
            let center = NSWorkspace.shared.notificationCenter
            let tokens = [NSWorkspace.didWakeNotification, NSWorkspace.didActivateApplicationNotification].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.changed?() }
                }
            }
            return { self.changed = nil; tokens.forEach(center.removeObserver) }
        })
    }
    func read(_ input: PhysicalSourceInput) async throws -> PhysicalSourceObservation? {
        guard canRead() else { throw PhysicalSourceReadError.unavailable }
        let generation = try gate?.begin(), ports = ports, gate = gate
        let access = VIAFileReadAccess(gate: gate, generation: generation)
        let notify: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.changed?() } }
        let job = Task.detached {
            let system = try access.use { try? ports.system() }
            let software: (reference: PhysicalSoftwareReference, monitor: VIAFileMonitor)?
            if input.software != nil {
                let version = try access.use { try? ports.version() }
                software = try? VIAFileReader.readConfiguration(url: ports.softwareURL(), access: access, notify: notify) {
                    try PhysicalActiveSoftwareSource.parse($0, version: version)
                }
            } else { software = nil }
            try access.use {}
            return CollectedPhysicalHostSources(system: system, software: software?.reference, file: software?.monitor)
        }
        let raw = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        try Task.checkCancellation()
        if let gate, let generation { try gate.check(generation) }
        guard canRead() else { throw PhysicalSourceReadError.unavailable }
        let reference = PhysicalSourceReport.references(input)
        let matches = raw.software.map { active in
            active.bytes == input.software?.bytes && active.profile == input.software?.profile &&
                (input.software?.version == nil || active.version == input.software?.version)
        } ?? false
        let rows = reference.sources.map { row -> PhysicalSourceSummary in
            switch row.id {
            case .device: return .init(.device, raw.system?.services.isEmpty == false ? .collected : .missing)
            case .software:
                guard input.software != nil else { return row }
                return .init(.software, raw.software == nil ? .reference : matches ? .collected : .unsupported)
            case .macOS:
                let available = raw.system?.services.isEmpty == false && raw.system?.services.allSatisfy { $0.mappings != nil } == true
                return .init(.macOS, available ? .collected : .missing)
            default: return row
            }
        }
        return PhysicalSourceObservation(input: input, evidence: reference.evidence, isCurrent: { [weak self] in
            guard let self, self.canRead(), !Task.isCancelled else { return false }
            if let gate, let generation, (try? gate.check(generation)) == nil { return false }
            guard raw.file?.hasChanged != true, (try? ports.system()) == raw.system else { return false }
            if let software = raw.software, (try? ports.version()) != software.version { return false }
            return true
        }, sources: rows, system: raw.system, deviceLayout: .resolve(input: input, system: raw.system))
    }
}

@MainActor
struct PhysicalSourceDependencies {
    var observe: @MainActor (PhysicalSourceInput) async throws -> PhysicalSourceObservation? = { _ in nil }
    var observeChanges: @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void) = { _ in {} }
}

@MainActor
final class PhysicalSourcesModel: ObservableObject {
    var input: @MainActor (RecommendationScope) -> PhysicalSourceInput? = { _ in nil }
    var onChange: @MainActor () -> Void = {}
    var dependencies = PhysicalSourceDependencies() { didSet { invalidate() } }
    private var session = UUID()
    private var entries: [String: PhysicalSourceObservation] = [:]
    private var pending: [String: UUID] = [:]
    private var jobs: [String: Task<PhysicalSourceObservation?, Never>] = [:]
    private var references: [String: (PhysicalSourceInput, PhysicalSourceReport)] = [:]
    private var pendingInputs: [String: PhysicalSourceInput] = [:]
    private var withdrawnFirmwareID: UUID?
    private var changed = false
    private var stopObserving: (@MainActor () -> Void)?

    deinit {
        jobs.values.forEach { $0.cancel() }
        let stop = stopObserving
        Task { @MainActor in stop?() }
    }

    func invalidate() {
        withdrawnFirmwareID = entries.values.compactMap(\.input.firmware?.id).first
            ?? pendingInputs.values.compactMap(\.firmware?.id).first
            ?? references.values.compactMap { $0.0.firmware?.id }.first ?? withdrawnFirmwareID
        changed = changed || !entries.isEmpty || !pending.isEmpty
        session = UUID(); entries.removeAll(); pending.removeAll(); references.removeAll()
        pendingInputs.removeAll()
        jobs.values.forEach { $0.cancel() }; jobs.removeAll()
        let stop = stopObserving; stopObserving = nil; stop?()
        objectWillChange.send(); onChange()
    }
    func isLoading(_ scope: RecommendationScope) -> Bool { pending[key(scope)] != nil }
    func report(_ scope: RecommendationScope) -> PhysicalSourceReport? {
        guard var current = currentInput(scope) else { return nil }
        if let observation = entries[key(scope)] {
            let ticket = session
            if observation.input == current, observation.evidence.scope == scope, observation.isCurrent(), ticket == session {
                return PhysicalSourceReport(evidence: observation.evidence,
                    sources: observation.sources ?? PhysicalSourceReport.observed(observation.evidence).sources,
                    deviceLayout: observation.deviceLayout)
            }
            withdrawnFirmwareID = observation.input.firmware?.id ?? withdrawnFirmwareID
            entries[key(scope)] = nil; references.removeAll(); changed = true
            guard let refreshed = currentInput(scope) else { return nil }
            current = refreshed
        }
        if let cached = references[key(scope)], cached.0 == current { return cached.1 }
        let report = PhysicalSourceReport.references(current, changed: changed)
        references[key(scope)] = (current, report)
        return report
    }
    func refresh(_ scope: RecommendationScope) async {
        guard !isLoading(scope) else { return }
        _ = report(scope)
        guard let current = currentInput(scope), !isLoading(scope) else { return }
        let ticket = session, request = UUID(), id = key(scope)
        entries[id] = nil; pending[id] = request; references.removeAll(); changed = false
        pendingInputs[id] = current
        objectWillChange.send(); onChange()
        if stopObserving == nil {
            let stop = dependencies.observeChanges { [weak self] in self?.invalidate() }
            guard ticket == session else { stop(); return }
            stopObserving = stop
        }
        let read = dependencies.observe
        let job = Task { try? await read(current) }
        jobs[id] = job
        let observed = await job.value
        guard ticket == session, pending[id] == request else { return }
        let latest = currentInput(scope)
        let valid = observed?.isCurrent() == true
        guard ticket == session, pending[id] == request else { return }
        pending[id] = nil; jobs[id] = nil; pendingInputs[id] = nil
        if latest == current, let observed, observed.input == current,
           observed.evidence.scope == scope, valid {
            entries[id] = observed
        } else if observed != nil || current.firmware != nil {
            withdrawnFirmwareID = current.firmware?.id ?? withdrawnFirmwareID
            references.removeAll(); changed = true
        }
        objectWillChange.send(); onChange()
    }
    private func currentInput(_ scope: RecommendationScope) -> PhysicalSourceInput? {
        guard let current = input(scope) else { return nil }
        guard let firmware = current.firmware, firmware.id == withdrawnFirmwareID else { return current }
        return .init(backend: current.backend, scope: current.scope, via: current.via, software: current.software)
    }
    private func key(_ scope: RecommendationScope) -> String {
        if case .application(let id) = scope { return "app:" + id }
        return "global"
    }
}

import Foundation
import KeyRecordStore

public enum FirmwareMappingState: String, Codable, Sendable {
    case draft, awaitingUserImport, importClaimed, verified, failed, externallyChanged, rolledBack
}
public enum FirmwareJournalPhase: String, Codable, Sendable {
    case artifactReady, exportRequested, externalExported, claimRecorded, evidenceRecorded, abandonRequested
}
public struct FirmwareExportReference: Codable, Equatable, Sendable {
    public let bookmark: Data
    public let location: String
    public init(bookmark: Data, location: String) { self.bookmark = bookmark; self.location = location }
}
public struct FirmwareBatchRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let backend: FirmwareBackend
    public let device: String
    public let axes: FirmwareVersionAxes
    public let baselineSHA256: String
    public let originalExportConfirmedAt: Date
    public var state: FirmwareMappingState = .draft
    public var artifactSHA256: String?
    public var exportedAt: Date?
    public var importClaimedAt: Date?
    public var verifiedAt: Date?
    public var verificationSource: String?
    public var changes: [FirmwareSlotChange] = []
}
public struct FirmwarePendingOperation: Codable, Equatable, Sendable {
    public let batch: UUID
    public var phase: FirmwareJournalPhase
    public var target: FirmwareExportReference?
    public var recordedAt: Date?
    public var verificationPassed: Bool?
    public var previousState: FirmwareMappingState = .draft
    public var verificationState: FirmwareMappingState?
    public var verificationSource: String?
}
public struct FirmwareLedger: Codable, Equatable, Sendable {
    public var records: [FirmwareBatchRecord] = []
    public var pending: FirmwarePendingOperation?
    public init() {}
}
public protocol FirmwareExportDestination: Sendable {
    var reference: FirmwareExportReference { get }
    func read() throws -> Data?
    func write(_ bytes: Data) throws
}
public actor FirmwareOperationCoordinator {
    private let store: ObjectStore
    private let support: FirmwareSupportDirectory
    private let injection: @Sendable (FirmwareJournalPhase) throws -> Void
    private let resolve: @Sendable (FirmwareExportReference) throws -> any FirmwareExportDestination
    private var busy = false
    private let ledgerIdentity: CanonicalLogicalIdentity
    public init(store: ObjectStore, support: FirmwareSupportDirectory = FirmwareSupportDirectory(),
                resolve: @escaping @Sendable (FirmwareExportReference) throws -> any FirmwareExportDestination,
                injection: @escaping @Sendable (FirmwareJournalPhase) throws -> Void = { _ in }) throws {
        self.store = store; self.support = support; self.resolve = resolve; self.injection = injection
        ledgerIdentity = try CanonicalLogicalIdentity(objectType: "com.keyrecord.firmware-journal", schemaVersion: 1, logicalIDText: "firmware")
    }
    private func begin() throws { guard !busy else { throw FirmwareError.busy }; busy = true }
    public func withRecoveryPreparation<T: Sendable>(_ work: @MainActor @Sendable () async throws -> T) async throws -> T {
        try begin(); defer { busy = false }
        return try await work()
    }
    private func identity(_ batch: UUID, original: Bool) throws -> CanonicalLogicalIdentity {
        try CanonicalLogicalIdentity(objectType: original ? "com.keyrecord.firmware-baseline" : "com.keyrecord.firmware-artifact",
            schemaVersion: 1, logicalIDText: batch.uuidString)
    }
    public func ledger() async throws -> FirmwareLedger {
        guard try await store.entries().contains(where: { $0.identity == ledgerIdentity }) else { return FirmwareLedger() }
        return try JSONDecoder().decode(FirmwareLedger.self, from: await store.read(ledgerIdentity))
    }
    private func save(_ ledger: FirmwareLedger) async throws {
        _ = try await store.put(identity: ledgerIdentity, payload: JSONEncoder().encode(ledger))
    }
    private func checkpoint(_ phase: FirmwareJournalPhase, ledger: inout FirmwareLedger) async throws {
        ledger.pending?.phase = phase
        try await save(ledger); try injection(phase)
    }
    public func retainOriginal(_ bytes: Data, backend: FirmwareBackend, axes: FirmwareVersionAxes,
                               confirmedAt: Date) async throws -> FirmwareBatchRecord {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil else { throw FirmwareError.busy }
        let document = try FirmwareDocument(bytes: bytes, backend: backend)
        let record = FirmwareBatchRecord(id: UUID(), backend: backend, device: document.device, axes: axes,
            baselineSHA256: KarabinerTransactionCoordinator.fileDigest(bytes), originalExportConfirmedAt: confirmedAt)
        _ = try await store.put(identity: identity(record.id, original: true), payload: bytes)
        ledger.records.append(record)
        try await save(ledger)
        return record
    }
    public func original(_ batch: UUID) async throws -> Data {
        let ledger = try await ledger()
        guard let record = ledger.records.first(where: { $0.id == batch }) else { throw FirmwareError.unavailable }
        let bytes = try await store.read(identity(batch, original: true))
        guard KarabinerTransactionCoordinator.fileDigest(bytes) == record.baselineSHA256 else { throw FirmwareError.unavailable }
        return bytes
    }
    private func draftDocument(_ batch: UUID) async throws -> (FirmwareBatchRecord, FirmwareDocument) {
        let ledger = try await ledger()
        guard ledger.pending == nil, let record = ledger.records.first(where: { $0.id == batch }), record.state == .draft else { throw FirmwareError.invalidState }
        guard ledger.records.last(where: { $0.backend == record.backend && $0.device == record.device })?.id == batch else { throw FirmwareError.staleBaseline }
        let document = try FirmwareDocument(bytes: await original(batch), backend: record.backend)
        return (record, document)
    }
    public func prepare(_ batch: UUID, changes: [FirmwareSlotChange]) async throws -> Data {
        let (record, document) = try await draftDocument(batch)
        return try document.patch(changes, expectedDevice: record.device, axes: record.axes, support: support)
    }
    public func preview(_ batch: UUID, changes: [FirmwareSlotChange]) async throws -> FirmwarePatchPreview {
        let (record, document) = try await draftDocument(batch)
        _ = try document.patch(changes, expectedDevice: record.device, axes: record.axes, support: support)
        return try FirmwarePatchPreview(batch: batch, differences: changes.map {
            FirmwareSlotDifference(change: $0, before: try document.value(at: $0.slot))
        })
    }
    public func export(_ batch: UUID, changes: [FirmwareSlotChange], destination: any FirmwareExportDestination) async throws -> FirmwareLedger {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil, let index = ledger.records.firstIndex(where: { $0.id == batch }) else { throw FirmwareError.busy }
        let bytes: Data
        if ledger.records[index].state == .draft { bytes = try await prepare(batch, changes: changes) }
        else if ledger.records[index].state == .awaitingUserImport, ledger.records[index].changes == changes {
            bytes = try await store.read(identity(batch, original: false))
            guard KarabinerTransactionCoordinator.fileDigest(bytes) == ledger.records[index].artifactSHA256 else { throw FirmwareError.unavailable }
        } else { throw FirmwareError.invalidState }
        _ = try await store.put(identity: identity(batch, original: false), payload: bytes)
        ledger.records[index].artifactSHA256 = KarabinerTransactionCoordinator.fileDigest(bytes)
        ledger.records[index].changes = changes
        ledger.pending = FirmwarePendingOperation(batch: batch, phase: .artifactReady, previousState: ledger.records[index].state)
        try await checkpoint(.artifactReady, ledger: &ledger)
        ledger.pending?.target = destination.reference
        try await checkpoint(.exportRequested, ledger: &ledger)
        try destination.write(bytes)
        guard try destination.read() == bytes else { throw FirmwareError.externalChange }
        ledger.pending?.recordedAt = Date()
        try await checkpoint(.externalExported, ledger: &ledger)
        ledger.records[index].state = .awaitingUserImport
        ledger.records[index].exportedAt = ledger.pending?.recordedAt
        ledger.pending = nil; try await save(ledger)
        return ledger
    }
    public func claimImport(_ batch: UUID, at date: Date) async throws -> FirmwareLedger {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil, let index = ledger.records.firstIndex(where: { $0.id == batch }),
              ledger.records[index].state == .awaitingUserImport else { throw FirmwareError.invalidState }
        ledger.pending = FirmwarePendingOperation(batch: batch, phase: .claimRecorded, recordedAt: date)
        try await checkpoint(.claimRecorded, ledger: &ledger)
        ledger.records[index].state = .importClaimed; ledger.records[index].importClaimedAt = date
        ledger.pending = nil; try await save(ledger); return ledger
    }
    public func confirmVIABehavior(_ batch: UUID, passed: Bool, at date: Date) async throws -> FirmwareLedger {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil, let index = ledger.records.firstIndex(where: { $0.id == batch }),
              ledger.records[index].backend == .via,
              [.importClaimed, .verified, .failed].contains(ledger.records[index].state) else { throw FirmwareError.invalidState }
        ledger.pending = FirmwarePendingOperation(batch: batch, phase: .evidenceRecorded, recordedAt: date, verificationPassed: passed)
        try await checkpoint(.evidenceRecorded, ledger: &ledger)
        ledger.records[index].state = passed ? .verified : .failed
        ledger.records[index].verifiedAt = date; ledger.records[index].verificationSource = "userBehaviorTestConfirmation"
        ledger.pending = nil; try await save(ledger); return ledger
    }
    public func abandon(_ batch: UUID) async throws -> FirmwareLedger {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil, let index = ledger.records.firstIndex(where: { $0.id == batch }),
              ledger.records[index].state == .awaitingUserImport else { throw FirmwareError.invalidState }
        ledger.pending = FirmwarePendingOperation(batch: batch, phase: .abandonRequested)
        try await checkpoint(.abandonRequested, ledger: &ledger)
        try await deleteArtifact(batch)
        ledger.records[index].state = .draft; ledger.records[index].artifactSHA256 = nil; ledger.records[index].exportedAt = nil
        ledger.pending = nil; try await save(ledger); return ledger
    }
    public func confirmVialReadback(_ batch: UUID, observation: VialKeymapObservation) async throws -> FirmwareLedger {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil, let index = ledger.records.firstIndex(where: { $0.id == batch }),
              ledger.records[index].backend == .vial,
              [.importClaimed, .verified, .failed, .externallyChanged].contains(ledger.records[index].state) else {
            throw FirmwareError.invalidState
        }
        let record = ledger.records[index]
        guard observation.device == record.device else { throw FirmwareError.identityMismatch }
        guard observation.axes == record.axes,
              support.supports(backend: .vial, device: record.device, axes: observation.axes) else { throw FirmwareError.unknownCompatibility }
        guard let claim = record.importClaimedAt, observation.observedAt >= claim,
              observation.observedAt >= (record.verifiedAt ?? claim) else { throw FirmwareError.unavailable }
        let bytes = try await store.read(identity(batch, original: false))
        guard KarabinerTransactionCoordinator.fileDigest(bytes) == record.artifactSHA256 else { throw FirmwareError.unavailable }
        let expected = try FirmwareDocument(bytes: bytes, backend: .vial).slotValues()
        let baseline = try FirmwareDocument(bytes: await original(batch), backend: .vial).slotValues()
        guard Set(observation.values.keys) == Set(expected.keys) else { throw FirmwareError.invalidDocument }
        let result: FirmwareMappingState = observation.values == expected ? .verified
            : observation.values == baseline ? .failed : .externallyChanged
        let pending = FirmwarePendingOperation(batch: batch, phase: .evidenceRecorded, recordedAt: observation.observedAt,
            verificationState: result, verificationSource: "vialKeymapReadback")
        ledger.pending = pending
        try await checkpoint(.evidenceRecorded, ledger: &ledger)
        try applyEvidence(pending, to: &ledger.records[index])
        ledger.pending = nil; try await save(ledger); return ledger
    }
    private func applyEvidence(_ pending: FirmwarePendingOperation, to record: inout FirmwareBatchRecord) throws {
        guard let date = pending.recordedAt else { throw FirmwareError.unavailable }
        if let state = pending.verificationState {
            guard record.backend == .vial, [.verified, .failed, .externallyChanged].contains(state),
                  pending.verificationSource == "vialKeymapReadback" else { throw FirmwareError.unavailable }
            record.state = state; record.verificationSource = pending.verificationSource
        } else {
            guard record.backend == .via, let passed = pending.verificationPassed else { throw FirmwareError.unavailable }
            record.state = passed ? .verified : .failed; record.verificationSource = "userBehaviorTestConfirmation"
        }
        record.verifiedAt = date
    }
    public func confirmGuidedRollback(_ batch: UUID) async throws -> FirmwareLedger {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil, let index = ledger.records.firstIndex(where: { $0.id == batch }),
              [.importClaimed, .verified, .failed, .externallyChanged].contains(ledger.records[index].state) else { throw FirmwareError.invalidState }
        ledger.records[index].state = .rolledBack
        ledger.records[index].verifiedAt = nil; ledger.records[index].verificationSource = nil
        try await save(ledger); return ledger
    }
    public func reconcile() async throws -> FirmwareLedger {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        if let pending = ledger.pending {
            guard let index = ledger.records.firstIndex(where: { $0.id == pending.batch }) else { throw FirmwareError.unavailable }
            switch pending.phase {
            case .artifactReady:
                ledger.records[index].state = pending.previousState
            case .exportRequested, .externalExported:
                if let target = pending.target, let bytes = try? resolve(target).read(),
                   KarabinerTransactionCoordinator.fileDigest(bytes) == ledger.records[index].artifactSHA256 {
                    ledger.records[index].state = .awaitingUserImport
                    ledger.records[index].exportedAt = pending.recordedAt ?? Date()
                } else { ledger.records[index].state = pending.previousState }
            case .claimRecorded:
                guard let date = pending.recordedAt else { throw FirmwareError.unavailable }
                ledger.records[index].state = .importClaimed; ledger.records[index].importClaimedAt = date
            case .evidenceRecorded:
                try applyEvidence(pending, to: &ledger.records[index])
            case .abandonRequested:
                try await deleteArtifact(pending.batch)
                ledger.records[index].state = .draft; ledger.records[index].artifactSHA256 = nil; ledger.records[index].exportedAt = nil
            }
            ledger.pending = nil; try await save(ledger)
        }
        for entry in try await store.entries() where ["com.keyrecord.firmware-baseline", "com.keyrecord.firmware-artifact"].contains(entry.identity.objectType) {
            let retained = Set(ledger.records.filter { entry.identity.objectType == "com.keyrecord.firmware-baseline" || $0.artifactSHA256 != nil }.map { $0.id.uuidString })
            if let id = entry.identity.logicalIDText, !retained.contains(id) { try await store.delete(entry.identity) }
        }
        return ledger
    }
    public func exportOriginal(_ batch: UUID, destination: any FirmwareExportDestination) async throws {
        let bytes = try await original(batch)
        try destination.write(bytes)
        guard try destination.read() == bytes else { throw FirmwareError.externalChange }
    }
    public func deleteOriginal(_ batch: UUID) async throws {
        try begin(); defer { busy = false }
        var ledger = try await ledger()
        guard ledger.pending == nil, let index = ledger.records.firstIndex(where: { $0.id == batch }),
              [.draft, .rolledBack].contains(ledger.records[index].state) else { throw FirmwareError.invalidState }
        ledger.records.remove(at: index); try await save(ledger)
        try await deleteArtifact(batch)
        let original = try identity(batch, original: true)
        if try await store.entries().contains(where: { $0.identity == original }) { try await store.delete(original) }
    }
    private func deleteArtifact(_ batch: UUID) async throws {
        let identity = try identity(batch, original: false)
        if try await store.entries().contains(where: { $0.identity == identity }) { try await store.delete(identity) }
    }
}

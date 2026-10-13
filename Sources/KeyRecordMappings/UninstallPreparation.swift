import Foundation
import KeyRecordCore
import KeyRecordStore

public enum FirmwareRecoveryChoice: Sendable {
    case export(any FirmwareExportDestination)
    case heldElsewhere
    case discardConfirmed
}
public enum FirmwareRecoveryDisposition: String, Codable, Sendable { case exported, heldElsewhere, discarded }
public enum UninstallPreparationStage: String, Codable, Sendable { case captureStopped, recoverySecured, rulesRemoved, loginRemoved, ready, erasing, completed }
public struct UninstallPreparationRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let choices: [String: FirmwareRecoveryDisposition]
    public let deleteLocalData: Bool
    public var stage: UninstallPreparationStage
}
@MainActor
public final class UninstallPreparationCoordinator {
    private let store: ObjectStore
    private let firmware: FirmwareOperationCoordinator
    private let stopCapture: @MainActor () async throws -> Void
    private let removeRules: @MainActor () async throws -> Void
    private let removeLogin: @MainActor () async throws -> Void
    private let eraseData: @MainActor () async throws -> Void
    private let authorize: @MainActor () throws -> Void
    private let gate: KeyAvailabilityGate
    private let generation: CaptureGeneration
    private let onProgress: @MainActor (UninstallPreparationStage) -> Void
    private var busy = false
    private let identity: CanonicalLogicalIdentity
    public init(store: ObjectStore, firmware: FirmwareOperationCoordinator, gate: KeyAvailabilityGate,
                stopCapture: @escaping @MainActor () async throws -> Void,
                removeRules: @escaping @MainActor () async throws -> Void,
                removeLogin: @escaping @MainActor () async throws -> Void,
                eraseData: @escaping @MainActor () async throws -> Void,
                authorize: @escaping @MainActor () throws -> Void = {},
                onProgress: @escaping @MainActor (UninstallPreparationStage) -> Void = { _ in }) throws {
        self.store = store; self.firmware = firmware; self.removeRules = removeRules
        self.removeLogin = removeLogin; self.eraseData = eraseData
        self.authorize = authorize
        self.stopCapture = stopCapture; self.onProgress = onProgress
        self.gate = gate; self.generation = try gate.begin()
        identity = try CanonicalLogicalIdentity(objectType: "com.keyrecord.uninstall-preparation", schemaVersion: 1, logicalIDText: "preparation")
    }
    private func checkAccess() throws { try gate.use(generation) { try authorize() } }
    private func save(_ record: UninstallPreparationRecord) async throws {
        _ = try await store.put(identity: identity, payload: JSONEncoder().encode(record))
        onProgress(record.stage)
    }
    public func prepare(choices: [UUID: FirmwareRecoveryChoice], deleteLocalData: Bool) async throws -> UninstallPreparationRecord {
        guard !busy else { throw FirmwareError.busy }
        busy = true; defer { busy = false }
        try checkAccess()
        try await stopCapture()
        try checkAccess(); onProgress(.captureStopped)
        _ = try await firmware.reconcile()
        return try await firmware.withRecoveryPreparation { [self] in
            try await prepareReserved(choices: choices, deleteLocalData: deleteLocalData)
        }
    }
    private func prepareReserved(choices: [UUID: FirmwareRecoveryChoice], deleteLocalData: Bool) async throws -> UninstallPreparationRecord {
        try checkAccess()
        let snapshot = try await firmware.ledger().records
        guard Set(choices.keys) == Set(snapshot.map(\.id)) else { throw FirmwareError.unavailable }
        var dispositions: [String: FirmwareRecoveryDisposition] = [:]
        for original in snapshot {
            try checkAccess()
            guard let choice = choices[original.id] else { throw FirmwareError.unavailable }
            switch choice {
            case .export(let destination):
                try await firmware.exportOriginal(original.id, destination: destination)
                dispositions[original.id.uuidString] = .exported
            case .heldElsewhere: dispositions[original.id.uuidString] = .heldElsewhere
            case .discardConfirmed: dispositions[original.id.uuidString] = .discarded
            }
        }
        guard try await firmware.ledger().records == snapshot else { throw FirmwareError.externalChange }
        var record = UninstallPreparationRecord(id: UUID(), choices: dispositions, deleteLocalData: deleteLocalData, stage: .recoverySecured)
        try await save(record)
        try checkAccess(); try await removeRules(); record.stage = .rulesRemoved; try await save(record)
        try checkAccess(); try await removeLogin(); record.stage = .loginRemoved; try await save(record)
        record.stage = .ready; try await save(record)
        if deleteLocalData {
            guard try await firmware.ledger().records == snapshot else { throw FirmwareError.externalChange }
            for original in snapshot {
                if case .export(let destination) = choices[original.id] {
                    let bytes = try await firmware.original(original.id)
                    guard try destination.read() == bytes else { throw FirmwareError.externalChange }
                }
            }
            record.stage = .erasing; try await save(record)
            try checkAccess(); try await eraseData()
            record.stage = .completed
            onProgress(.completed)
        }
        return record
    }
}

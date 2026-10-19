import Foundation
import KeyRecordCore
import KeyRecordStore

public struct ExportedPreferences: Codable, Equatable, Sendable {
    public let excludedBundleIDs: [String]
    public let ignoredRecommendationKeys: [String]
    public let layout: LayoutPreference
    public let loginItemEnabled: Bool
    public let locale: ProductLocale
    public let keyboardPoolConfirmed: [KeyCode]
    public let showDockIcon: Bool

    init(_ value: Preferences) {
        excludedBundleIDs = value.excludedBundleIDs.sorted()
        ignoredRecommendationKeys = value.ignoredRecommendationKeys.sorted()
        layout = value.layout; loginItemEnabled = value.loginItemEnabled; locale = value.locale
        keyboardPoolConfirmed = value.keyboardPoolConfirmed.sorted { $0.value < $1.value }
        showDockIcon = value.showDockIcon
    }
}

public struct ExportedKarabinerProfile: Codable, Sendable {
    public let reference: String
    public let disabled: Bool
    public let mappings: [KarabinerMappingDraft]
}

public struct ExportedFirmwareMapping: Codable, Sendable {
    public let id: UUID
    public let backend: FirmwareBackend
    public let name: String?
    public let device: String
    public let state: FirmwareMappingState
    public let changes: [FirmwareSlotChange]
}

public struct ExportedFirmwareDraft: Codable, Sendable {
    public let batch: UUID
    public let changes: [FirmwareSlotChange]
}

public struct ConfigurationExport: Codable, Sendable {
    public let schemaVersion: Int
    public let preferences: ExportedPreferences
    public let karabiner: [ExportedKarabinerProfile]
    public let firmware: [ExportedFirmwareMapping]
    public let karabinerDrafts: [KarabinerMappingDraft]
    public let firmwareDrafts: [ExportedFirmwareDraft]

    public static func load(store: ObjectStore, gate: KeyAvailabilityGate,
                            karabinerDrafts: [KarabinerMappingDraft] = [],
                            firmwareDrafts: [UUID: [FirmwareSlotChange]] = [:]) async throws -> Self {
        let generation = try gate.begin()
        let objects = try await store.backupSnapshot(gate: gate, objectTypes: [
            "com.keyrecord.preferences", "com.keyrecord.mapping-journal", "com.keyrecord.firmware-journal"])
        var preferences: Preferences?
        var profiles: [ExportedKarabinerProfile] = []
        var firmware: [ExportedFirmwareMapping] = []
        for entry in objects {
            guard entry.identity.schemaVersion == 1 else { throw FirmwareError.unavailable }
            let bytes = entry.payload
            try gate.use(generation) {
                switch entry.identity.objectType {
                case "com.keyrecord.preferences":
                    guard entry.identity == CycleResetObjects.preferences else { throw FirmwareError.unavailable }
                    preferences = try JSONDecoder().decode(Preferences.self, from: bytes)
                case "com.keyrecord.mapping-journal":
                    let ledger = try JSONDecoder().decode(KarabinerLedger.self, from: bytes)
                    guard ledger.pending == nil else { throw FirmwareError.busy }
                    profiles.append(.init(reference: entry.identity.logicalIDText ?? "", disabled: ledger.disabled,
                                          mappings: ledger.desired.filter { !$0.temporary }))
                case "com.keyrecord.firmware-journal":
                    let ledger = try JSONDecoder().decode(FirmwareLedger.self, from: bytes)
                    guard ledger.pending == nil else { throw FirmwareError.busy }
                    firmware += ledger.records.map { .init(id: $0.id, backend: $0.backend, name: $0.name,
                        device: $0.device, state: $0.state, changes: $0.changes) }
                default: throw FirmwareError.unavailable
                }
            }
        }
        guard let preferences else { throw FirmwareError.unavailable }
        return try gate.use(generation) {
            .init(schemaVersion: 1, preferences: ExportedPreferences(preferences),
                  karabiner: profiles.sorted { $0.reference < $1.reference },
                  firmware: firmware.sorted { $0.id.uuidString < $1.id.uuidString },
                  karabinerDrafts: karabinerDrafts.filter { !$0.temporary },
                  firmwareDrafts: firmwareDrafts.keys.sorted { $0.uuidString < $1.uuidString }.map {
                      .init(batch: $0, changes: firmwareDrafts[$0] ?? [])
                  })
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

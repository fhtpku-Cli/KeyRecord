import Foundation
import KeyRecordConfigurationRead
import KeyRecordAnalysis

public enum FirmwareBackend: String, Codable, Sendable { case via, vial }
public struct FirmwareVersionAxes: Codable, Equatable, Sendable {
    public let definitionSchema: String?
    public let deviceProtocol: String?
    public let layoutFormat: String?
    public let keycodeDialect: String?
    public let importer: String?
    public init(definitionSchema: String?, deviceProtocol: String?, layoutFormat: String?, keycodeDialect: String?, importer: String?) {
        self.definitionSchema = definitionSchema; self.deviceProtocol = deviceProtocol; self.layoutFormat = layoutFormat
        self.keycodeDialect = keycodeDialect; self.importer = importer
    }
    public var complete: Bool {
        [definitionSchema, deviceProtocol, layoutFormat, keycodeDialect, importer].allSatisfy { $0?.isEmpty == false }
    }
}
public struct FirmwareCompatibility: Equatable, Sendable {
    public let backend: FirmwareBackend
    public let device: String
    public let axes: FirmwareVersionAxes
    public let supportedOutputs: Set<String>
    public init(backend: FirmwareBackend, device: String, axes: FirmwareVersionAxes, supportedOutputs: Set<String>) {
        self.backend = backend; self.device = device; self.axes = axes; self.supportedOutputs = supportedOutputs
    }
}
public struct FirmwareSupportDirectory: Sendable {
    private let entries: [FirmwareCompatibility]
    public init(entries: [FirmwareCompatibility] = []) { self.entries = entries }
    public func supports(backend: FirmwareBackend, device: String, axes: FirmwareVersionAxes) -> Bool {
        axes.complete && entries.contains { $0.backend == backend && $0.device == device && $0.axes == axes }
    }
    func outputs(backend: FirmwareBackend, device: String, axes: FirmwareVersionAxes) throws -> Set<String> {
        guard axes.complete, let entry = entries.first(where: { $0.backend == backend && $0.device == device && $0.axes == axes }) else {
            throw FirmwareError.unknownCompatibility
        }
        return entry.supportedOutputs
    }
}
public enum FirmwareError: Error, Equatable, Sendable {
    case invalidDocument, identityMismatch, unknownCompatibility, staleBaseline, invalidSlot, unsupportedOutput
    case protectedEntry, occupiedAutomaticSlot, unreachableLayer, busy, unavailable, externalChange, invalidState
}
public struct FirmwareSlot: Codable, Hashable, Sendable {
    public let layer: Int
    public let row: Int
    public let column: Int
    public init(layer: Int, row: Int = 0, column: Int) { self.layer = layer; self.row = row; self.column = column }
}
public enum FirmwareEncoderDirection: Int, Hashable, Sendable { case clockwise = 0, counterclockwise = 1 }
public struct FirmwareEncoderSlot: Hashable, Sendable {
    public let layer: Int
    public let index: Int
    public let direction: FirmwareEncoderDirection
    public init(layer: Int, index: Int, direction: FirmwareEncoderDirection) {
        self.layer = layer; self.index = index; self.direction = direction
    }
}
public struct FirmwareSlotChange: Codable, Equatable, Sendable {
    public let slot: FirmwareSlot
    public let output: String
    public let automatic: Bool
    public init(slot: FirmwareSlot, output: String, automatic: Bool) { self.slot = slot; self.output = output; self.automatic = automatic }
}
public struct FirmwareSlotDifference: Equatable, Sendable {
    public let change: FirmwareSlotChange
    public let before: String
}
public struct FirmwarePatchPreview: Equatable, Sendable {
    public let batch: UUID
    public let differences: [FirmwareSlotDifference]
}
public struct VialDefinitionObservation: Sendable {
    public let device: String
    public let bytes: Data
    public init(device: String, bytes: Data) { self.device = device; self.bytes = bytes }
}
public struct VialKeymapObservation: Sendable {
    public let device: String
    public let axes: FirmwareVersionAxes
    public let values: [FirmwareSlot: String]
    public let encoderValues: [FirmwareEncoderSlot: String]
    public let dynamicEntries: [VialDynamicSection: [[UInt8]]]
    public let configurationValues: [VialConfigurationSection: Data]
    public let observedAt: Date
    public let definition: VialDefinitionObservation?
    public init(device: String, axes: FirmwareVersionAxes, values: [FirmwareSlot: String],
                encoderValues: [FirmwareEncoderSlot: String] = [:],
                dynamicEntries: [VialDynamicSection: [[UInt8]]] = [:],
                configurationValues: [VialConfigurationSection: Data] = [:], observedAt: Date,
                definition: VialDefinitionObservation? = nil) {
        self.device = device; self.axes = axes; self.values = values; self.encoderValues = encoderValues; self.observedAt = observedAt
        self.dynamicEntries = dynamicEntries
        self.configurationValues = configurationValues
        self.definition = definition
    }
}
public struct FirmwareDocument: Sendable {
    public let backend: FirmwareBackend
    public let device: String
    public let bytes: Data
    public let matrixDimensions: (layers: Int, rows: Int, columns: Int)?
    public let encoderCount: Int
    private let slots: [FirmwareSlot: JSONDocumentRanges.Node]
    private let encoders: [FirmwareEncoderSlot: JSONDocumentRanges.Node]
    public init(bytes: Data, backend: FirmwareBackend) throws {
        let root = try JSONDocumentRanges(bytes).root
        var slots: [FirmwareSlot: JSONDocumentRanges.Node] = [:]
        var encoders: [FirmwareEncoderSlot: JSONDocumentRanges.Node] = [:]
        var encoderCount = 0
        var dimensions: (layers: Int, rows: Int, columns: Int)?
        switch backend {
        case .via:
            guard let identity = root.members["vendorProductId"], let id = UInt32(String(decoding: bytes[identity.range], as: UTF8.self)),
                  let layers = root.members["layers"]?.elements, !layers.isEmpty else { throw FirmwareError.invalidDocument }
            device = String(id)
            var count: Int?
            for (layer, array) in layers.enumerated() {
                guard let entries = array.elements, !entries.isEmpty, count == nil || count == entries.count else { throw FirmwareError.invalidDocument }
                count = entries.count
                for (column, node) in entries.enumerated() { slots[FirmwareSlot(layer: layer, column: column)] = node }
            }
        case .vial:
            guard let identity = root.members["uid"], let version = root.members["version"],
                  String(decoding: bytes[version.range], as: UTF8.self) == "1",
                  let layers = root.members["layout"]?.elements, !layers.isEmpty else { throw FirmwareError.invalidDocument }
            let raw = Data(bytes[identity.range])
            if raw.first == 34 { device = try JSONDecoder().decode(String.self, from: raw) }
            else {
                let text = String(decoding: raw, as: UTF8.self)
                guard UInt64(text) != nil else { throw FirmwareError.invalidDocument }
                device = text
            }
            guard !device.isEmpty else { throw FirmwareError.invalidDocument }
            var shape: [Int]?
            for (layer, array) in layers.enumerated() {
                guard let rows = array.elements, !rows.isEmpty else { throw FirmwareError.invalidDocument }
                var current: [Int] = []
                for (row, array) in rows.enumerated() {
                    guard let entries = array.elements, !entries.isEmpty else { throw FirmwareError.invalidDocument }
                    current.append(entries.count)
                    for (column, node) in entries.enumerated() {
                        // Vial's official saver uses -1 for matrix positions absent from the definition.
                        if String(decoding: bytes[node.range], as: UTF8.self) != "-1" {
                            slots[FirmwareSlot(layer: layer, row: row, column: column)] = node
                        }
                    }
                }
                guard shape == nil || shape == current else { throw FirmwareError.invalidDocument }
                shape = current
            }
            if let shape, let columns = shape.first, shape.allSatisfy({ $0 == columns }) {
                dimensions = (layers.count, shape.count, columns)
            }
            if let node = root.members["encoder_layout"] {
                guard let encoderLayers = node.elements, encoderLayers.count == layers.count else { throw FirmwareError.invalidDocument }
                var count: Int?
                for (layer, node) in encoderLayers.enumerated() {
                    guard let entries = node.elements, entries.count <= 256,
                          count == nil || count == entries.count else { throw FirmwareError.invalidDocument }
                    count = entries.count
                    for (index, node) in entries.enumerated() {
                        guard let pair = node.elements, pair.count == 2 else { throw FirmwareError.invalidDocument }
                        let absent = pair.map { String(decoding: bytes[$0.range], as: UTF8.self) == "-1" }
                        guard absent[0] == absent[1] else { throw FirmwareError.invalidDocument }
                        if absent[0] { continue }
                        encoders[.init(layer: layer, index: index, direction: .clockwise)] = pair[0]
                        encoders[.init(layer: layer, index: index, direction: .counterclockwise)] = pair[1]
                    }
                }
                encoderCount = count ?? 0
            }
        }
        for node in slots.values { _ = try JSONDecoder().decode(String.self, from: Data(bytes[node.range])) }
        for node in encoders.values { _ = try JSONDecoder().decode(String.self, from: Data(bytes[node.range])) }
        self.backend = backend; self.bytes = bytes; self.slots = slots; self.matrixDimensions = dimensions
        self.encoders = encoders; self.encoderCount = encoderCount
    }
    public func value(at slot: FirmwareSlot) throws -> String {
        guard let node = slots[slot] else { throw FirmwareError.invalidSlot }
        return try JSONDecoder().decode(String.self, from: Data(bytes[node.range]))
    }
    public func slotValues() throws -> [FirmwareSlot: String] {
        try Dictionary(uniqueKeysWithValues: slots.keys.map { ($0, try value(at: $0)) })
    }
    public func encoderValues() throws -> [FirmwareEncoderSlot: String] {
        try encoders.mapValues { try JSONDecoder().decode(String.self, from: Data(bytes[$0.range])) }
    }
    public func patch(_ changes: [FirmwareSlotChange], expectedDevice: String, axes: FirmwareVersionAxes,
                      support: FirmwareSupportDirectory) throws -> Data {
        guard device == expectedDevice else { throw FirmwareError.identityMismatch }
        let outputs = try support.outputs(backend: backend, device: device, axes: axes)
        let vial6 = backend == .vial && axes.keycodeDialect == VialKeycodeDialect.name
        return try patch(changes, outputs: outputs, vial6: vial6, viaFile: false)
    }
    public func patchVIAFile(_ changes: [FirmwareSlotChange], expectedDevice: String) throws -> Data {
        guard backend == .via else { throw FirmwareError.unknownCompatibility }
        guard device == expectedDevice else { throw FirmwareError.identityMismatch }
        try VIAFileCompatibility.validate(bytes)
        return try patch(changes, outputs: VIAFileCompatibility.outputs, vial6: false, viaFile: true)
    }
    public func viaFileSlots() throws -> [VIAFileSlot] {
        guard backend == .via else { throw FirmwareError.unknownCompatibility }
        try VIAFileCompatibility.validate(bytes)
        let layers = try reachable(automatic: false, vial6: false, viaFile: true)
        return try slots.keys.sorted { ($0.layer, $0.column) < ($1.layer, $1.column) }.map { slot in
            let old = try value(at: slot)
            var restriction: FirmwareError?
            do {
                try Self.validateReplacementSource(old, automatic: false, vial6: false, viaFile: true)
                guard layers.contains(slot.layer) else { throw FirmwareError.unreachableLayer }
            } catch let error as FirmwareError { restriction = error }
            return VIAFileSlot(slot: slot, original: old, restriction: restriction)
        }
    }
    private func patch(_ changes: [FirmwareSlotChange], outputs: Set<String>, vial6: Bool, viaFile: Bool) throws -> Data {
        guard !changes.isEmpty, Set(changes.map(\.slot)).count == changes.count else { throw FirmwareError.invalidSlot }
        var edits: [(Range<Int>, Data)] = []
        for change in changes {
            guard outputs.contains(change.output), VIAReferenceParser.isStandardFirmwareOutput(change.output), !Self.protected(change.output) else { throw FirmwareError.unsupportedOutput }
            guard let node = slots[change.slot] else { throw FirmwareError.invalidSlot }
            let old = try value(at: change.slot)
            try Self.validateReplacementSource(old, automatic: change.automatic, vial6: vial6, viaFile: viaFile)
            guard try reachable(automatic: change.automatic, vial6: vial6, viaFile: viaFile).contains(change.slot.layer) else { throw FirmwareError.unreachableLayer }
            edits.append((node.range, try JSONEncoder().encode(change.output)))
        }
        var result = bytes
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { result.replaceSubrange(range, with: replacement) }
        let parsed = try FirmwareDocument(bytes: result, backend: backend)
        guard parsed.device == device, Set(parsed.slots.keys) == Set(slots.keys) else { throw FirmwareError.invalidDocument }
        if viaFile { try VIAFileCompatibility.validate(result) }
        return result
    }
    private static func validateReplacementSource(_ old: String, automatic: Bool, vial6: Bool, viaFile: Bool) throws {
        let protectedToken = vial6 ? old.trimmingCharacters(in: .whitespacesAndNewlines) : old
        guard !Self.protected(protectedToken), !(vial6 && VialKeycodeDialect.protectedEntry(old)) else { throw FirmwareError.protectedEntry }
        if viaFile, old != "KC_NO", old != "KC_TRNS", !VIAFileCompatibility.outputs.contains(old) {
            throw FirmwareError.unsupportedOutput
        }
        if automatic, old != "KC_NO", !(vial6 && (try? VialKeycodeDialect.rawValue(old)) == 0) {
            throw FirmwareError.occupiedAutomaticSlot
        }
    }
    private static func protected(_ token: String) -> Bool {
        ["MO(", "LT(", "LM(", "TG(", "TO(", "TT(", "DF(", "OSL("].contains { token.hasPrefix($0) }
            || ["QK_BOOT", "QK_REBOOT", "QK_CLEAR_EEPROM", "RESET", "EE_CLR", "FN_MO13", "FN_MO23"].contains(token)
    }
    private func reachable(automatic: Bool, vial6: Bool, viaFile: Bool) throws -> Set<Int> {
        let availableLayers = Set(slots.keys.map(\.layer))
        var reachable: Set<Int> = [0]
        var frontier: Set<Int> = [0]
        while !frontier.isEmpty {
            var next: Set<Int> = []
            for (slot, _) in slots where frontier.contains(slot.layer) {
                let old = try value(at: slot)
                let token = vial6 ? VialKeycodeDialect.layerEntry(old) : viaFile ? VIAFileCompatibility.layerEntry(old) : old
                let prefixes = automatic ? ["MO(", "LT("] : ["MO(", "LT(", "TG(", "TO(", "TT(", "DF(", "OSL("]
                guard let prefix = prefixes.first(where: { token.hasPrefix($0) }), token.hasSuffix(")") else { continue }
                let remainder = token.dropFirst(prefix.count).dropLast()
                guard let layer = Int(remainder.split(separator: ",").first ?? ""), availableLayers.contains(layer) else { continue }
                if !reachable.contains(layer) { next.insert(layer) }
            }
            reachable.formUnion(next)
            if automatic { break }
            frontier = next
        }
        return reachable
    }
}

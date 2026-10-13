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
public struct FirmwareSlotChange: Codable, Equatable, Sendable {
    public let slot: FirmwareSlot
    public let output: String
    public let automatic: Bool
    public init(slot: FirmwareSlot, output: String, automatic: Bool) { self.slot = slot; self.output = output; self.automatic = automatic }
}
public struct FirmwareDocument: Sendable {
    public let backend: FirmwareBackend
    public let device: String
    public let bytes: Data
    private let slots: [FirmwareSlot: JSONDocumentRanges.Node]
    public init(bytes: Data, backend: FirmwareBackend) throws {
        let root = try JSONDocumentRanges(bytes).root
        var slots: [FirmwareSlot: JSONDocumentRanges.Node] = [:]
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
                    for (column, node) in entries.enumerated() { slots[FirmwareSlot(layer: layer, row: row, column: column)] = node }
                }
                guard shape == nil || shape == current else { throw FirmwareError.invalidDocument }
                shape = current
            }
        }
        for node in slots.values { _ = try JSONDecoder().decode(String.self, from: Data(bytes[node.range])) }
        self.backend = backend; self.bytes = bytes; self.slots = slots
    }
    public func value(at slot: FirmwareSlot) throws -> String {
        guard let node = slots[slot] else { throw FirmwareError.invalidSlot }
        return try JSONDecoder().decode(String.self, from: Data(bytes[node.range]))
    }
    public func patch(_ changes: [FirmwareSlotChange], expectedDevice: String, axes: FirmwareVersionAxes,
                      support: FirmwareSupportDirectory) throws -> Data {
        guard device == expectedDevice else { throw FirmwareError.identityMismatch }
        let outputs = try support.outputs(backend: backend, device: device, axes: axes)
        guard !changes.isEmpty, Set(changes.map(\.slot)).count == changes.count else { throw FirmwareError.invalidSlot }
        var edits: [(Range<Int>, Data)] = []
        for change in changes {
            guard outputs.contains(change.output), VIAReferenceParser.isStandardFirmwareOutput(change.output), !Self.protected(change.output) else { throw FirmwareError.unsupportedOutput }
            guard let node = slots[change.slot] else { throw FirmwareError.invalidSlot }
            let old = try value(at: change.slot)
            guard !Self.protected(old) else { throw FirmwareError.protectedEntry }
            if change.automatic, old != "KC_NO" { throw FirmwareError.occupiedAutomaticSlot }
            guard try reachable(automatic: change.automatic).contains(change.slot.layer) else { throw FirmwareError.unreachableLayer }
            edits.append((node.range, try JSONEncoder().encode(change.output)))
        }
        var result = bytes
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { result.replaceSubrange(range, with: replacement) }
        let parsed = try FirmwareDocument(bytes: result, backend: backend)
        guard parsed.device == device, Set(parsed.slots.keys) == Set(slots.keys) else { throw FirmwareError.invalidDocument }
        return result
    }
    private static func protected(_ token: String) -> Bool {
        ["MO(", "LT(", "TG(", "TO(", "TT(", "DF(", "OSL("].contains { token.hasPrefix($0) }
            || ["QK_BOOT", "QK_REBOOT", "QK_CLEAR_EEPROM", "RESET", "EE_CLR"].contains(token)
    }
    private func reachable(automatic: Bool) throws -> Set<Int> {
        var reachable: Set<Int> = [0]
        var frontier: Set<Int> = [0]
        while !frontier.isEmpty {
            var next: Set<Int> = []
            for (slot, _) in slots where frontier.contains(slot.layer) {
                let token = try value(at: slot)
                let prefixes = automatic ? ["MO(", "LT("] : ["MO(", "LT(", "TG(", "TO(", "TT(", "DF(", "OSL("]
                guard let prefix = prefixes.first(where: { token.hasPrefix($0) }), token.hasSuffix(")") else { continue }
                let remainder = token.dropFirst(prefix.count).dropLast()
                guard let layer = Int(remainder.split(separator: ",").first ?? ""), slots.keys.contains(where: { $0.layer == layer }) else { continue }
                if !reachable.contains(layer) { next.insert(layer) }
            }
            reachable.formUnion(next)
            if automatic { break }
            frontier = next
        }
        return reachable
    }
}

import Foundation

public enum ViaLayoutError: String, Error, Equatable, Codable, Sendable {
    case inputTooLarge, depthExceeded, collectionElementsExceeded, scalarTooLarge
    case malformedJSON, duplicateKey, missingName, invalidKeyboardID, invalidLayers, nonStringSlot, invalidMacros
    case keyboardIDMismatch, layerShapeMismatch, slotShapeMismatch, macroShapeMismatch
    case protocolMismatch, keycodeDialectMismatch, unsupportedKeycode, invalidSelectedSlot, unsupportedMutation
}

public struct ViaLayoutCompatibility: Equatable, Sendable {
    public let vendorProductID: Int
    public let layerSlotCounts: [Int]
    public let macroCount: Int
    public let viaProtocol: Int
    public let keycodeDialect: String
    public let supportedKeycodes: Set<String>

    public init(
        vendorProductID: Int, layerSlotCounts: [Int], macroCount: Int, viaProtocol: Int,
        keycodeDialect: String, supportedKeycodes: Set<String>
    ) {
        self.vendorProductID = vendorProductID
        self.layerSlotCounts = layerSlotCounts
        self.macroCount = macroCount
        self.viaProtocol = viaProtocol
        self.keycodeDialect = keycodeDialect
        self.supportedKeycodes = supportedKeycodes
    }
}

public enum ViaLayoutMutation: Equatable, Sendable {
    case replaceSlot(layer: Int, slot: Int, value: String)
    case replaceMacro(index: Int, value: String)
}

public struct ViaLayoutPatchPlan: Equatable, Sendable {
    public let bytes: Data
    public let originalRange: Range<Int>
    public let bytesOutsideSelectedSlotIdentical: Bool
}

public struct ViaLayoutDocument: Sendable {
    public let name: String
    public let vendorProductID: Int
    public let layerSlotCounts: [Int]
    public let macroCount: Int
    private let bytes: Data
    private let members: [String: ViaLayoutJSONNode]
    private let layers: [[ViaLayoutJSONNode]]

    fileprivate init(
        name: String, vendorProductID: Int, macroCount: Int, bytes: Data,
        members: [String: ViaLayoutJSONNode], layers: [[ViaLayoutJSONNode]]
    ) {
        self.name = name
        self.vendorProductID = vendorProductID
        self.layerSlotCounts = layers.map(\.count)
        self.macroCount = macroCount
        self.bytes = bytes
        self.members = members
        self.layers = layers
    }

    public func rawSlice(named name: String) -> Data? {
        members[name].map { bytes.subdata(in: $0.range) }
    }

    public func slotValue(layer: Int, slot: Int) -> String? {
        guard layer >= 0, layer < layers.count, slot >= 0, slot < layers[layer].count else { return nil }
        return layers[layer][slot].stringValue
    }

    public func patchSelectedSlot(
        layer: Int, slot: Int, replacement: String, compatibility: ViaLayoutCompatibility,
        observedProtocol: Int, observedKeycodeDialect: String
    ) throws -> ViaLayoutPatchPlan {
        try patch(
            .replaceSlot(layer: layer, slot: slot, value: replacement), compatibility: compatibility,
            observedProtocol: observedProtocol, observedKeycodeDialect: observedKeycodeDialect
        )
    }

    public func patch(
        _ mutation: ViaLayoutMutation, compatibility: ViaLayoutCompatibility,
        observedProtocol: Int, observedKeycodeDialect: String
    ) throws -> ViaLayoutPatchPlan {
        guard vendorProductID == compatibility.vendorProductID else { throw ViaLayoutError.keyboardIDMismatch }
        guard layerSlotCounts.count == compatibility.layerSlotCounts.count else { throw ViaLayoutError.layerShapeMismatch }
        guard layerSlotCounts == compatibility.layerSlotCounts else { throw ViaLayoutError.slotShapeMismatch }
        guard macroCount == compatibility.macroCount else { throw ViaLayoutError.macroShapeMismatch }
        guard observedProtocol == compatibility.viaProtocol else { throw ViaLayoutError.protocolMismatch }
        guard observedKeycodeDialect == compatibility.keycodeDialect else { throw ViaLayoutError.keycodeDialectMismatch }
        guard case let .replaceSlot(layer, slot, replacement) = mutation else { throw ViaLayoutError.unsupportedMutation }
        guard compatibility.supportedKeycodes.contains(replacement) else { throw ViaLayoutError.unsupportedKeycode }
        guard let node = node(layer: layer, slot: slot) else { throw ViaLayoutError.invalidSelectedSlot }
        let encoded = try JSONEncoder().encode(replacement)
        guard encoded.count >= 2, encoded.count - 2 <= ViaDefinitionLimits.maximumScalarBytes else {
            throw ViaLayoutError.scalarTooLarge
        }
        var candidate = Data()
        candidate.reserveCapacity(bytes.count - node.range.count + encoded.count)
        candidate.append(bytes[..<node.range.lowerBound])
        candidate.append(encoded)
        candidate.append(bytes[node.range.upperBound...])
        guard candidate.count <= ViaDefinitionLimits.maximumInputBytes else { throw ViaLayoutError.inputTooLarge }
        let reparsed = try ViaLayoutParser.parse(candidate)
        guard reparsed.vendorProductID == vendorProductID, reparsed.layerSlotCounts == layerSlotCounts,
              reparsed.macroCount == macroCount else { throw ViaLayoutError.malformedJSON }
        let candidateEnd = node.range.lowerBound + encoded.count
        let unchanged = bytes[..<node.range.lowerBound] == candidate[..<node.range.lowerBound]
            && bytes[node.range.upperBound...] == candidate[candidateEnd...]
        return ViaLayoutPatchPlan(bytes: candidate, originalRange: node.range, bytesOutsideSelectedSlotIdentical: unchanged)
    }

    private func node(layer: Int, slot: Int) -> ViaLayoutJSONNode? {
        guard layer >= 0, layer < layers.count, slot >= 0, slot < layers[layer].count else { return nil }
        return layers[layer][slot]
    }
}

public enum ViaLayoutParser {
    public static func parse(_ data: Data) throws -> ViaLayoutDocument {
        guard data.count <= ViaDefinitionLimits.maximumInputBytes else { throw ViaLayoutError.inputTooLarge }
        var scanner = ViaLayoutJSONScanner(data)
        let root = try scanner.parseRootObject()
        guard let nameNode = root["name"], nameNode.kind == .string, let name = nameNode.stringValue, !name.isEmpty else {
            throw ViaLayoutError.missingName
        }
        guard let idNode = root["vendorProductId"], idNode.kind == .number,
              let id = Int(String(decoding: data[idNode.range], as: UTF8.self)), id >= 0 else {
            throw ViaLayoutError.invalidKeyboardID
        }
        guard let layersNode = root["layers"], layersNode.kind == .array else { throw ViaLayoutError.invalidLayers }
        let layers = try layersNode.children.map { layer -> [ViaLayoutJSONNode] in
            guard layer.kind == .array else { throw ViaLayoutError.invalidLayers }
            return try layer.children.map { slot in
                guard slot.kind == .string else { throw ViaLayoutError.nonStringSlot }
                return slot
            }
        }
        let macroCount: Int
        if let macros = root["macros"] {
            guard macros.kind == .array, macros.children.allSatisfy({ $0.kind == .string }) else { throw ViaLayoutError.invalidMacros }
            macroCount = macros.children.count
        } else {
            macroCount = 0
        }
        return ViaLayoutDocument(name: name, vendorProductID: id, macroCount: macroCount, bytes: data, members: root, layers: layers)
    }
}

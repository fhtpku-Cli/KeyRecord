import Foundation
import KeyRecordCore
import KeyRecordConfigurationRead

public enum VIAImportError: Error, Equatable, Sendable {
    case jsonProtection, malformedDocument, unsupportedSchema, invalidIdentity, invalidMatrix
    case invalidLayers, keyboardMismatch, layerShapeMismatch, invalidGeometry
}

public enum VIAImportFileKind: String, Hashable, Sendable { case layout, definition }
public enum VIAReferenceLimitation: String, CaseIterable, Hashable, Sendable {
    case deploymentUnknown, transformsUnknown, additionalLayers, unsupportedKeycodes
    case layoutOptions, complexGeometry, dynamicFeatures
}

public enum VIAKeyBinding: Equatable, Sendable {
    case standard(keyCode: KeyCode, hidUsage: UInt16)
    case noAction
    case unsupported
}

public struct VIALayoutReference: Equatable, Sendable {
    public let name: String
    public let vendorProductID: UInt32
    public let layers: [[VIAKeyBinding]]
    public let hasDynamicFeatures: Bool
}

public struct VIADefinitionReference: Equatable, Sendable {
    public let name: String
    public let vendorProductID: UInt32
    public let rows: Int
    public let columns: Int
    public let geometry: CanonicalGeometry?
    public let limitations: Set<VIAReferenceLimitation>
}

public struct VIAImportedConfiguration: Equatable, Sendable {
    public let name: String
    public let vendorProductID: UInt32
    public let layerCount: Int
    public let bindings: [String: VIAKeyBinding]
    public let geometry: CanonicalGeometry?
    public let limitations: Set<VIAReferenceLimitation>
    public let standardKeyCount: Int
    public let unsupportedKeyCount: Int
    private let positionCounts: [KeyCode: Int]
    public let physicalEvidence: PhysicalEvidence

    public func positionCount(for key: KeyCode) -> Int {
        positionCounts[key] ?? 0
    }

    fileprivate init(name: String, vendorProductID: UInt32, layerCount: Int, bindings: [String: VIAKeyBinding],
                     geometry: CanonicalGeometry?, limitations: Set<VIAReferenceLimitation>) {
        self.name = name
        self.vendorProductID = vendorProductID
        self.layerCount = layerCount
        self.bindings = bindings
        self.geometry = geometry
        self.limitations = limitations
        standardKeyCount = bindings.values.filter { if case .standard = $0 { return true }; return false }.count
        unsupportedKeyCount = bindings.values.filter { $0 == .unsupported }.count
        var counts: [KeyCode: Int] = [:]
        for (id, binding) in bindings {
            if geometry?.positions[id] != nil, case .standard(let code, _) = binding { counts[code, default: 0] += 1 }
        }
        positionCounts = counts
        let entries = bindings.sorted { $0.key < $1.key }.compactMap { id, binding -> CanonicalTransform.Mapping? in
            guard case .standard(_, let usage) = binding else { return nil }
            return .init(input: [.position(id)], output: [.hidUsage(usage)])
        }
        physicalEvidence = PhysicalEvidence(geometry: geometry, chain: [
            TransformEvidence(link: .firmware, status: .absent, reference: "via-file-reference",
                mapping: CanonicalTransform(mappings: entries, completeInverseFor: [])),
            TransformEvidence(link: .software, status: .absent, reference: "unobserved-software", mapping: nil),
            TransformEvidence(link: .macOS, status: .absent, reference: "unobserved-system", mapping: nil)],
            device: .unknown, scope: .global)
    }
}

public enum VIAReferenceParser {
    public static func standardKeyCode(hidUsage: UInt16) -> KeyCode? {
        guard let entry = VIAStandardKeyCodes.values.values.first(where: { $0.1 == hidUsage }) else { return nil }
        return try? KeyCode(entry.0)
    }
    public static func standardHIDUsage(_ key: KeyCode) -> UInt16? {
        VIAStandardKeyCodes.values.values.first(where: { $0.0 == key.value })?.1
    }
    public static func standardKeyCode(_ token: String) -> KeyCode? {
        if case .standard(let key, _) = VIAStandardKeyCodes.binding(token) { return key }
        return nil
    }
    public static func isStandardFirmwareOutput(_ token: String) -> Bool {
        if case .standard = VIAStandardKeyCodes.binding(token) { return true }
        let wrappers = ["LCTL(", "LSFT(", "LALT(", "LGUI(", "RCTL(", "RSFT(", "RALT(", "RGUI("]
        var remaining = token
        var count = 0
        while let wrapper = wrappers.first(where: { remaining.hasPrefix($0) }), remaining.hasSuffix(")"), count < 4 {
            remaining = String(remaining.dropFirst(wrapper.count).dropLast()); count += 1
        }
        if case .standard = VIAStandardKeyCodes.binding(remaining) { return count > 0 }
        return false
    }
    public static let maximumInputBytes = ConfigurationReadLimits.maximumInputBytes
    public static func layout(_ data: Data) throws -> VIALayoutReference {
        let root = try object(data)
        guard let name = root["name"]?.string, !name.isEmpty,
              let id = root["vendorProductId"]?.unsigned,
              let arrays = root["layers"]?.array, !arrays.isEmpty else { throw VIAImportError.malformedDocument }
        let layers = try arrays.map { value -> [VIAKeyBinding] in
            guard let slots = value.array, !slots.isEmpty else { throw VIAImportError.invalidLayers }
            return try slots.map { slot in
                guard let code = slot.string else { throw VIAImportError.invalidLayers }
                return VIAStandardKeyCodes.binding(code)
            }
        }
        let macros = try strings(root["macros"])
        return VIALayoutReference(name: String(name.prefix(256)), vendorProductID: id, layers: layers,
            hasDynamicFeatures: macros.contains { !$0.isEmpty } || !(root["encoders"]?.array ?? []).isEmpty)
    }

    public static func definition(_ data: Data) throws -> VIADefinitionReference {
        let root = try object(data)
        let hasLegacy = root["vendorProductId"] != nil
        let hasV3 = root["vendorId"] != nil || root["productId"] != nil
        guard hasLegacy != hasV3 else { throw VIAImportError.unsupportedSchema }
        let id: UInt32
        if hasLegacy {
            guard let parsed = root["vendorProductId"]?.unsigned else { throw VIAImportError.invalidIdentity }
            id = parsed
        } else {
            guard let vendor = hex(root["vendorId"]), let product = hex(root["productId"]) else { throw VIAImportError.invalidIdentity }
            id = UInt32(vendor) << 16 | UInt32(product)
        }
        guard let name = root["name"]?.string, !name.isEmpty,
              let matrix = root["matrix"]?.object,
              let rows = matrix["rows"]?.integer, let cols = matrix["cols"]?.integer,
              rows > 0, cols > 0 else { throw VIAImportError.invalidMatrix }
        let (slots, overflow) = rows.multipliedReportingOverflow(by: cols)
        guard !overflow, slots <= ConfigurationReadLimits.maximumCollectionElements else { throw VIAImportError.invalidMatrix }
        guard let layouts = root["layouts"]?.object,
              (layouts["keymap"] != nil) != (layouts["keys"] != nil) else { throw VIAImportError.invalidGeometry }
        var limitations: Set<VIAReferenceLimitation> = []
        let geometry: CanonicalGeometry?
        let options: [VIAJSONValue]
        if let value = layouts["labels"] {
            guard let array = value.array, array.allSatisfy({ label in
                if label.string != nil { return true }
                return label.array?.allSatisfy({ $0.string != nil }) == true
            }) else { throw VIAImportError.invalidGeometry }
            options = array
        } else { options = [] }
        if layouts["keys"] != nil {
            guard hasLegacy else { throw VIAImportError.unsupportedSchema }
            let result = try geometryFromCompiled(layouts, rows: rows, cols: cols, hasOptions: !options.isEmpty)
            geometry = result.geometry
            limitations.formUnion(result.limitations)
        } else {
            guard let keymap = layouts["keymap"]?.array, !keymap.isEmpty,
                  keymap.allSatisfy({ $0.array != nil }), layouts["optionKeys"] == nil else { throw VIAImportError.invalidGeometry }
            if !Set(layouts.keys).isSubset(of: ["keymap", "labels"]) {
                limitations.insert(.complexGeometry)
            }
            if !options.isEmpty {
                limitations.insert(.layoutOptions)
                geometry = nil
            } else {
                let result = try geometryFromKLE(keymap, rows: rows, cols: cols)
                geometry = limitations.contains(.complexGeometry) ? nil : result.geometry
                limitations.formUnion(result.limitations)
            }
        }
        return VIADefinitionReference(name: String(name.prefix(256)), vendorProductID: id, rows: rows,
            columns: cols, geometry: geometry, limitations: limitations)
    }

    public static func match(layout: VIALayoutReference, definition: VIADefinitionReference) throws -> VIAImportedConfiguration {
        guard layout.vendorProductID == definition.vendorProductID else { throw VIAImportError.keyboardMismatch }
        let count = definition.rows * definition.columns
        guard layout.layers.allSatisfy({ $0.count == count }), let first = layout.layers.first else { throw VIAImportError.layerShapeMismatch }
        let bindings = Dictionary(uniqueKeysWithValues: first.enumerated().map { index, binding in
            ("\(index / definition.columns),\(index % definition.columns)", binding)
        })
        var limitations = definition.limitations.union([.deploymentUnknown, .transformsUnknown])
        if layout.layers.count > 1 { limitations.insert(.additionalLayers) }
        if first.contains(.unsupported) { limitations.insert(.unsupportedKeycodes) }
        if layout.hasDynamicFeatures { limitations.insert(.dynamicFeatures) }
        return VIAImportedConfiguration(name: definition.name, vendorProductID: definition.vendorProductID,
            layerCount: layout.layers.count, bindings: bindings, geometry: definition.geometry, limitations: limitations)
    }

    private static func object(_ data: Data) throws -> [String: VIAJSONValue] {
        do { try BoundedJSONPreflight.rejectDuplicateKeys(data) }
        catch { throw VIAImportError.jsonProtection }
        do {
            guard let root = try JSONDecoder().decode(VIAJSONValue.self, from: data).object else { throw VIAImportError.malformedDocument }
            return root
        } catch { throw VIAImportError.malformedDocument }
    }

    private static func hex(_ value: VIAJSONValue?) -> UInt16? {
        guard let string = value?.string, string.hasPrefix("0x"), string.count > 2 else { return nil }
        return UInt16(string.dropFirst(2), radix: 16)
    }

    private static func strings(_ value: VIAJSONValue?) throws -> [String] {
        guard let value else { return [] }
        guard let array = value.array else { throw VIAImportError.malformedDocument }
        return try array.map { entry in
            guard let text = entry.string else { throw VIAImportError.malformedDocument }
            return text
        }
    }

    private static func geometryFromKLE(_ keymap: [VIAJSONValue], rows: Int, cols: Int)
        throws -> (geometry: CanonicalGeometry?, limitations: Set<VIAReferenceLimitation>) {
        var y = 0.0
        var positions: [PhysicalPosition] = []
        let decorative: Set<String> = ["c", "t", "a", "f", "f2", "fa", "p", "sm", "sb", "st", "n", "g"]
        for row in keymap {
            guard let keys = row.array else { throw VIAImportError.invalidGeometry }
            var x = 0.0
            var width = 1.0, height = 1.0
            for key in keys {
                if let properties = key.object {
                    guard Set(properties.keys).isSubset(of: decorative.union(["x", "y", "w", "h"])) else {
                        return (nil, [.complexGeometry])
                    }
                    if let alignment = properties["a"] {
                        guard let value = alignment.integer, value == 0 || value == 4 else { return (nil, [.complexGeometry]) }
                    }
                    if properties["g"] == .bool(true) { return (nil, [.complexGeometry]) }
                    for field in ["x", "y", "w", "h"] where properties[field] != nil {
                        guard let number = properties[field]?.number, number.isFinite else { throw VIAImportError.invalidGeometry }
                        switch field {
                        case "x": x += number
                        case "y": y += number
                        case "w": width = number
                        case "h": height = number
                        default: break
                        }
                    }
                } else if let label = key.string {
                    if label.contains("\n") { return (nil, [.layoutOptions]) }
                    let parts = label.split(separator: ",", omittingEmptySubsequences: false)
                    guard parts.count == 2, let r = Int(parts[0]), let c = Int(parts[1]),
                          r >= 0, c >= 0, r < rows, c < cols, width > 0, height > 0,
                          x.isFinite, y.isFinite else { throw VIAImportError.invalidGeometry }
                    let centerX = x + width / 2, centerY = y + height / 2
                    guard centerX.isFinite, centerY.isFinite else { throw VIAImportError.invalidGeometry }
                    positions.append(try PhysicalPosition(id: "\(r),\(c)", centerX: centerX,
                        centerY: centerY, coordinateFrame: "via-definition-reference"))
                    x += width
                    width = 1
                    height = 1
                } else { throw VIAImportError.invalidGeometry }
            }
            y += 1
        }
        guard !positions.isEmpty else { throw VIAImportError.invalidGeometry }
        do { return (try CanonicalGeometry(positions: positions), []) }
        catch { throw VIAImportError.invalidGeometry }
    }

    private static func geometryFromCompiled(_ layouts: [String: VIAJSONValue], rows: Int, cols: Int, hasOptions: Bool)
        throws -> (geometry: CanonicalGeometry?, limitations: Set<VIAReferenceLimitation>) {
        guard let keys = layouts["keys"]?.array, let options = layouts["optionKeys"]?.object,
              let width = layouts["width"]?.number, let height = layouts["height"]?.number,
              width.isFinite, height.isFinite, width > 0, height > 0 else { throw VIAImportError.invalidGeometry }
        var limitations: Set<VIAReferenceLimitation> = []
        if hasOptions || !options.isEmpty { limitations.insert(.layoutOptions) }
        if !Set(layouts.keys).isSubset(of: ["keys", "optionKeys", "width", "height", "labels"]) {
            limitations.insert(.complexGeometry)
        }
        var alternatives: [VIAJSONValue] = []
        for group in options.values {
            guard let choices = group.object else { throw VIAImportError.invalidGeometry }
            for choice in choices.values {
                guard let entries = choice.array else { throw VIAImportError.invalidGeometry }
                alternatives += entries
            }
        }
        guard !keys.isEmpty || !alternatives.isEmpty else { throw VIAImportError.invalidGeometry }
        var positions: [PhysicalPosition] = []
        for value in keys + alternatives {
            guard let key = value.object,
                  let row = key["row"]?.integer, let col = key["col"]?.integer,
                  (0..<rows).contains(row), (0..<cols).contains(col),
                  let x = key["x"]?.number, let y = key["y"]?.number,
                  let w = key["w"]?.number, let h = key["h"]?.number,
                  let r = key["r"]?.number, let rx = key["rx"]?.number, let ry = key["ry"]?.number,
                  [x, y, w, h, r, rx, ry].allSatisfy(\.isFinite), w > 0, h > 0,
                  let decal = key["d"], decal == .bool(false) || decal == .bool(true),
                  key["color"]?.string != nil else { throw VIAImportError.invalidGeometry }
            let understood: Set<String> = ["row", "col", "x", "y", "w", "h", "r", "rx", "ry", "d", "color"]
            if !Set(key.keys).isSubset(of: understood) || r != 0 || decal == .bool(true) {
                limitations.insert(.complexGeometry)
            }
            let centerX = x + w / 2, centerY = y + h / 2
            guard centerX.isFinite, centerY.isFinite else { throw VIAImportError.invalidGeometry }
            positions.append(try PhysicalPosition(id: "\(row),\(col)", centerX: centerX, centerY: centerY,
                coordinateFrame: "via-definition-reference"))
        }
        guard limitations.isEmpty else { return (nil, limitations) }
        do { return (try CanonicalGeometry(positions: positions), []) }
        catch { throw VIAImportError.invalidGeometry }
    }
}

private enum VIAJSONValue: Decodable, Equatable {
    case object([String: VIAJSONValue]), array([VIAJSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode([VIAJSONValue].self) { self = .array(decoded) }
        else { self = .object(try value.decode([String: VIAJSONValue].self)) }
    }
    var object: [String: VIAJSONValue]? { if case .object(let value) = self { return value }; return nil }
    var array: [VIAJSONValue]? { if case .array(let value) = self { return value }; return nil }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var unsigned: UInt32? { number.flatMap { UInt32(exactly: $0) } }
    var integer: Int? { number.flatMap { Int(exactly: $0) } }
}

private enum VIAStandardKeyCodes {
    static func binding(_ token: String) -> VIAKeyBinding {
        if token == "KC_NO" { return .noAction }
        guard let pair = values[token], let key = try? KeyCode(pair.0) else { return .unsupported }
        return .standard(keyCode: key, hidUsage: pair.1)
    }

    static let values: [String: (Int, UInt16)] = {
        var map: [String: (Int, UInt16)] = [:]
        let letterCodes = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { map["KC_\(letter)"] = (letterCodes[index], UInt16(0x04 + index)) }
        for (index, code) in [18,19,20,21,23,22,26,28,25,29].enumerated() { map["KC_\((index + 1) % 10)"] = (code, UInt16(0x1e + index)) }
        for (index, code) in LogicalPreviews.functionKeyValues.enumerated() {
            map["KC_F\(index + 1)"] = (code, UInt16(index < 12 ? 0x3a + index : 0x68 + index - 12))
        }
        let special: [(String, Int, UInt16)] = [
            ("KC_ENTER",36,0x28),("KC_ESC",53,0x29),("KC_BSPC",51,0x2a),("KC_TAB",48,0x2b),("KC_SPACE",49,0x2c),
            ("KC_MINS",27,0x2d),("KC_EQL",24,0x2e),("KC_LBRC",33,0x2f),("KC_RBRC",30,0x30),("KC_BSLS",42,0x31),
            ("KC_SCLN",41,0x33),("KC_QUOT",39,0x34),("KC_GRV",50,0x35),("KC_COMM",43,0x36),("KC_DOT",47,0x37),("KC_SLSH",44,0x38),
            ("KC_CAPS",57,0x39),("KC_HOME",115,0x4a),("KC_PGUP",116,0x4b),("KC_DEL",117,0x4c),("KC_END",119,0x4d),
            ("KC_PGDN",121,0x4e),("KC_RIGHT",124,0x4f),("KC_LEFT",123,0x50),("KC_DOWN",125,0x51),("KC_UP",126,0x52),
            ("KC_LCTL",59,0xe0),("KC_LSFT",56,0xe1),("KC_LALT",58,0xe2),("KC_LGUI",55,0xe3),
            ("KC_RCTL",62,0xe4),("KC_RSFT",60,0xe5),("KC_RALT",61,0xe6),("KC_RGUI",54,0xe7)]
        for (name, code, usage) in special { map[name] = (code, usage) }
        let aliases = ["KC_ENT":"KC_ENTER", "KC_SPC":"KC_SPACE", "KC_RGHT":"KC_RIGHT", "KC_BSPACE":"KC_BSPC",
            "KC_LCTRL":"KC_LCTL", "KC_RCTRL":"KC_RCTL", "KC_LSHIFT":"KC_LSFT", "KC_RSHIFT":"KC_RSFT"]
        for (alias, canonical) in aliases { map[alias] = map[canonical] }
        return map
    }()
}

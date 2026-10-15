import Foundation
import KeyRecordConfigurationRead

public enum VialConfigurationSection: String, CaseIterable, Sendable {
    case macro, layoutOptions = "layout_options", settings
}

enum VialSettingsSchema {
    static func width(_ id: UInt16) -> Int? {
        guard (1...27).contains(id) else { return nil }
        if [1, 3, 5, 8, 20, 22, 23, 24, 26].contains(id) { return 1 }
        return id == 21 ? 4 : 2
    }
    static func encode(_ values: [UInt16: [UInt8]]) -> Data {
        Data(values.keys.sorted().flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] + values[$0]! })
    }
}

extension FirmwareDocument {
    func configurationValue(_ section: VialConfigurationSection) throws -> Data? {
        guard let node = try JSONDocumentRanges(bytes).root.members[section.rawValue] else { return nil }
        func text(_ node: JSONDocumentRanges.Node) throws -> String {
            try JSONDecoder().decode(String.self, from: Data(bytes[node.range]))
        }
        func number(_ node: JSONDocumentRanges.Node) throws -> UInt32 {
            guard let value = UInt32(String(decoding: bytes[node.range], as: UTF8.self)) else { throw FirmwareError.invalidDocument }
            return value
        }
        do {
            switch section {
            case .layoutOptions:
                if String(decoding: bytes[node.range], as: UTF8.self) == "-1" { return Data([0]) }
                let value = try number(node)
                return Data([1] + (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
            case .settings:
                guard bytes[node.range.lowerBound] == 123 else { return nil }
                var values: [UInt16: [UInt8]] = [:]
                for (key, field) in node.members {
                    guard let id = UInt16(key), String(id) == key, let width = VialSettingsSchema.width(id) else { return nil }
                    let value = try number(field)
                    guard value <= UInt32.max >> ((4 - width) * 8) else { return nil }
                    values[id] = (0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
                }
                return VialSettingsSchema.encode(values)
            case .macro:
                guard let macros = node.elements, macros.count <= 255 else { return nil }
                var result = [UInt8(macros.count)]
                for macro in macros {
                    guard let actions = macro.elements else { return nil }
                    for action in actions {
                        guard let fields = action.elements, let first = fields.first else { return nil }
                        switch try text(first) {
                        case "text":
                            guard fields.count == 2 else { return nil }
                            let value = try text(fields[1])
                            guard value.utf8.allSatisfy({ $0 > 1 }) else { return nil }
                            result += value.utf8
                        case "delay":
                            guard fields.count == 2 else { return nil }
                            let delay = try number(fields[1])
                            guard delay <= 65_024 else { return nil }
                            result += [1, 4, UInt8(delay % 255 + 1), UInt8(delay / 255 + 1)]
                        case "tap", "down", "up":
                            let tag = try text(first)
                            let code: UInt8 = tag == "tap" ? 1 : (tag == "down" ? 2 : 3)
                            for key in fields.dropFirst() {
                                let value = try VialKeycodeDialect.rawValue(text(key))
                                guard value > 0, value < 0xff00 else { return nil }
                                if value < 256 { result += [1, code, UInt8(value)] }
                                else {
                                    let escaped = value & 255 == 0 ? 0xff00 | value >> 8 : value
                                    result += [1, code + 4, UInt8(escaped & 255), UInt8(escaped >> 8)]
                                }
                            }
                        default: return nil
                        }
                        guard result.count <= 65_536 else { return nil }
                    }
                    result.append(0)
                }
                guard result.count <= 65_536 else { return nil }
                return Data(result)
            }
        } catch { return nil }
    }
}

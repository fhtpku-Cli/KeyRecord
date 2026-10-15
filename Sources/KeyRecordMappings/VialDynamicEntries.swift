import Foundation
import KeyRecordConfigurationRead

public enum VialDynamicSection: String, CaseIterable, Sendable {
    case tapDance = "tap_dance", combo, keyOverride = "key_override", alternateRepeat = "alt_repeat_key"
    var command: UInt8 {
        switch self { case .tapDance: 1; case .combo: 3; case .keyOverride: 5; case .alternateRepeat: 7 }
    }
    var countIndex: Int { Int(command / 2) }
    var byteCount: Int { self == .alternateRepeat ? 6 : 10 }
}

extension FirmwareDocument {
    // Encode only understood save-file entries. Unrecognized shapes/names remain
    // unverified, including future fields that an older reader cannot compare.
    func dynamicEntries(_ section: VialDynamicSection) throws -> [[UInt8]]? {
        let root = try JSONDocumentRanges(bytes).root
        guard let node = root.members[section.rawValue], let entries = node.elements,
              entries.count <= 255 else { return nil }
        func integer(_ node: JSONDocumentRanges.Node?, max: UInt16 = .max) throws -> UInt16 {
            guard let node, let value = UInt16(String(decoding: bytes[node.range], as: UTF8.self)), value <= max else {
                throw FirmwareError.invalidDocument
            }
            return value
        }
        func key(_ node: JSONDocumentRanges.Node?) throws -> UInt16 {
            guard let node else { throw FirmwareError.invalidDocument }
            return try VialKeycodeDialect.rawValue(JSONDecoder().decode(String.self, from: Data(bytes[node.range])))
        }
        func little(_ value: UInt16) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
        do {
            return try entries.map { entry in
                switch section {
                case .tapDance, .combo:
                    guard let parts = entry.elements, parts.count == 5 else { throw FirmwareError.invalidDocument }
                    return try parts.enumerated().flatMap { index, node in
                        little(try section == .tapDance && index == 4 ? integer(node) : key(node))
                    }
                case .keyOverride:
                    let m = entry.members
                    guard Set(m.keys) == ["trigger", "replacement", "layers", "trigger_mods", "negative_mod_mask", "suppressed_mods", "options"] else {
                        throw FirmwareError.invalidDocument
                    }
                    let words = try [key(m["trigger"]), key(m["replacement"]), integer(m["layers"])].flatMap(little)
                    let tail = try ["trigger_mods", "negative_mod_mask", "suppressed_mods", "options"].map { UInt8(try integer(m[$0], max: 255)) }
                    guard tail[3] & 0x40 == 0 else { throw FirmwareError.invalidDocument }
                    return words + tail
                case .alternateRepeat:
                    let m = entry.members
                    guard Set(m.keys) == ["keycode", "alt_keycode", "allowed_mods", "options"] else { throw FirmwareError.invalidDocument }
                    return try [key(m["keycode"]), key(m["alt_keycode"])].flatMap(little)
                        + [UInt8(integer(m["allowed_mods"], max: 255)), UInt8(integer(m["options"], max: 15))]
                }
            }
        } catch { return nil }
    }
}

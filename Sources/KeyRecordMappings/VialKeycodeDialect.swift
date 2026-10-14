import Foundation

// A deliberately limited Vial 6 dialect. Unknown named/custom actions fail closed;
// official hexadecimal serialization can represent every raw 16-bit keycode.
public enum VialKeycodeDialect {
    public static let name = "vial-qmk-6"
    public static func rawValue(_ token: String) throws -> UInt16 {
        try rawValue(token, depth: 0)
    }
    private static func rawValue(_ token: String, depth: Int) throws -> UInt16 {
        guard depth <= 4 else { throw FirmwareError.unsupportedOutput }
        if let value = basic[token] { return value }
        if token.hasPrefix("0x"), let value = UInt16(token.dropFirst(2), radix: 16) { return value }
        for (prefix, base) in layerCodes where token.hasPrefix(prefix + "(") && token.hasSuffix(")") {
            guard let layer = UInt16(token.dropFirst(prefix.count + 1).dropLast()), layer < (prefix == "TO" ? 16 : 32) else {
                throw FirmwareError.unsupportedOutput
            }
            return base + layer
        }
        if token.hasPrefix("LT("), token.hasSuffix(")") {
            let fields = token.dropFirst(3).dropLast().split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 2, let layer = UInt16(fields[0]), layer < 16,
                  let key = basic[String(fields[1]).trimmingCharacters(in: .whitespaces)], key <= 255 else {
                throw FirmwareError.unsupportedOutput
            }
            return 0x4000 | layer << 8 | key
        }
        for (prefix, modifier) in modifiers where token.hasPrefix(prefix + "(") && token.hasSuffix(")") {
            let key = try rawValue(String(token.dropFirst(prefix.count + 1).dropLast()), depth: depth + 1)
            guard key < 0x2000, key & 0xFF > 1,
                  key < 0x100 || (key & 0x1000) == (modifier & 0x1000) else { throw FirmwareError.unsupportedOutput }
            return key | modifier
        }
        throw FirmwareError.unsupportedOutput
    }
    public static func token(_ raw: UInt16) -> String { String(format: "0x%04x", raw) }
    static func normalized<Slot: Hashable>(_ values: [Slot: String]) throws -> [Slot: String] {
        try values.mapValues { token(try rawValue($0)) }
    }
    static func protectedEntry(_ token: String) -> Bool {
        guard let raw = try? rawValue(token) else { return false }
        return (0x4000...0x4fff).contains(raw) || (0x5200...0x529f).contains(raw)
            || (0x52c0...0x52ff).contains(raw) || [0x7c00, 0x7c01, 0x7c03].contains(raw)
    }
    static func layerEntry(_ token: String) -> String {
        guard let raw = try? rawValue(token) else { return token }
        for (prefix, base) in layerCodes where (base...(base + (prefix == "TO" ? 15 : 31))).contains(raw) {
            return "\(prefix)(\(raw - base))"
        }
        if (0x4000...0x4fff).contains(raw) { return "LT(\((raw >> 8) & 15),KC_NO)" }
        return token
    }
    private static let layerCodes: [(String, UInt16)] = [
        ("TO", 0x5210), ("MO", 0x5220), ("DF", 0x5240), ("TG", 0x5260), ("OSL", 0x5280), ("TT", 0x52c0)]
    private static let modifiers: [(String, UInt16)] = [
        ("LCTL", 0x0100), ("LSFT", 0x0200), ("LALT", 0x0400), ("LGUI", 0x0800),
        ("RCTL", 0x1100), ("RSFT", 0x1200), ("RALT", 0x1400), ("RGUI", 0x1800),
        ("C_S", 0x0300), ("LCA", 0x0500), ("LSA", 0x0600), ("MEH", 0x0700),
        ("LCG", 0x0900), ("SGUI", 0x0a00), ("LAG", 0x0c00), ("LCAG", 0x0d00),
        ("HYPR", 0x0f00), ("RCG", 0x1900), ("LSG", 0x0a00), ("SCMD", 0x0a00), ("SWIN", 0x0a00),
        ("C", 0x0100), ("S", 0x0200), ("A", 0x0400), ("G", 0x0800),
        ("LOPT", 0x0400), ("LCMD", 0x0800), ("LWIN", 0x0800),
        ("ALGR", 0x1400), ("ROPT", 0x1400), ("RCMD", 0x1800), ("RWIN", 0x1800)]
    private static let basic: [String: UInt16] = {
        var result: [String: UInt16] = ["KC_NO": 0, "KC_TRNS": 1,
            "KC_ENTER": 0x28, "KC_ENT": 0x28, "KC_ESC": 0x29, "KC_BSPC": 0x2a, "KC_BSPACE": 0x2a,
            "KC_TAB": 0x2b, "KC_SPACE": 0x2c, "KC_SPC": 0x2c, "KC_MINS": 0x2d, "KC_EQL": 0x2e,
            "KC_LBRC": 0x2f, "KC_RBRC": 0x30, "KC_BSLS": 0x31, "KC_SCLN": 0x33, "KC_QUOT": 0x34,
            "KC_GRV": 0x35, "KC_COMM": 0x36, "KC_DOT": 0x37, "KC_SLSH": 0x38, "KC_CAPS": 0x39,
            "KC_HOME": 0x4a, "KC_PGUP": 0x4b, "KC_DEL": 0x4c, "KC_END": 0x4d, "KC_PGDN": 0x4e,
            "KC_RIGHT": 0x4f, "KC_LEFT": 0x50, "KC_DOWN": 0x51, "KC_UP": 0x52,
            "KC_LCTL": 0xe0, "KC_LCTRL": 0xe0, "KC_LSFT": 0xe1, "KC_LSHIFT": 0xe1,
            "KC_LALT": 0xe2, "KC_LGUI": 0xe3, "KC_RCTL": 0xe4, "KC_RCTRL": 0xe4,
            "KC_RSFT": 0xe5, "KC_RSHIFT": 0xe5, "KC_RALT": 0xe6, "KC_RGUI": 0xe7,
            "QK_BOOT": 0x7c00, "RESET": 0x7c00, "QK_REBOOT": 0x7c01, "QK_CLEAR_EEPROM": 0x7c03, "EE_CLR": 0x7c03]
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { result["KC_\(letter)"] = UInt16(4 + index) }
        for index in 0..<10 { result["KC_\((index + 1) % 10)"] = UInt16(0x1e + index) }
        for index in 0..<24 { result["KC_F\(index + 1)"] = UInt16(index < 12 ? 0x3a + index : 0x68 + index - 12) }
        let names: [(UInt16, [String])] = [
            (1, ["KC_TRANSPARENT"]), (0x29, ["KC_ESCAPE"]),
            (0x2d, ["KC_MINUS"]), (0x2e, ["KC_EQUAL"]),
            (0x2f, ["KC_LBRACKET"]), (0x30, ["KC_RBRACKET"]),
            (0x31, ["KC_BSLASH"]), (0x33, ["KC_SCOLON"]), (0x34, ["KC_QUOTE"]),
            (0x35, ["KC_GRAVE", "KC_ZKHK"]), (0x36, ["KC_COMMA"]), (0x38, ["KC_SLASH"]),
            (0x39, ["KC_CAPSLOCK", "KC_CLCK"]),
            (0x46, ["KC_PSCREEN", "KC_PSCR"]), (0x47, ["KC_SCROLLLOCK", "KC_SLCK", "KC_BRMD"]),
            (0x48, ["KC_PAUSE", "KC_PAUS", "KC_BRK", "KC_BRMU"]), (0x49, ["KC_INSERT", "KC_INS"]),
            (0x4c, ["KC_DELETE"]), (0x4e, ["KC_PGDOWN"]), (0x4f, ["KC_RGHT"]),
            (0x53, ["KC_NUMLOCK", "KC_NLCK"]), (0x54, ["KC_KP_SLASH", "KC_PSLS"]),
            (0x55, ["KC_KP_ASTERISK", "KC_PAST"]), (0x56, ["KC_KP_MINUS", "KC_PMNS"]),
            (0x57, ["KC_KP_PLUS", "KC_PPLS"]), (0x58, ["KC_KP_ENTER", "KC_PENT"]),
            (0x63, ["KC_KP_DOT", "KC_PDOT"]), (0x67, ["KC_KP_EQUAL", "KC_PEQL"]),
            (0x85, ["KC_KP_COMMA", "KC_PCMM"]), (0x65, ["KC_APPLICATION", "KC_APP"]),
            (0xe2, ["KC_LOPT"]), (0xe3, ["KC_LCMD", "KC_LWIN"]),
            (0xe6, ["KC_ALGR", "KC_ROPT"]), (0xe7, ["KC_RCMD", "KC_RWIN"]),
            (0x32, ["KC_NONUS_HASH", "KC_NUHS"]), (0x64, ["KC_NONUS_BSLASH", "KC_NUBS"]),
            (0x87, ["KC_RO", "KC_INT1"]), (0x88, ["KC_KANA", "KC_INT2"]),
            (0x89, ["KC_JYEN", "KC_INT3"]), (0x8a, ["KC_HENK", "KC_INT4"]),
            (0x8b, ["KC_MHEN", "KC_INT5"]), (0x90, ["KC_LANG1", "KC_HAEN"]),
            (0x91, ["KC_LANG2", "KC_HANJ"])]
        for (raw, aliases) in names { for alias in aliases { result[alias] = raw } }
        for index in 0..<10 {
            let digit = (index + 1) % 10, raw = UInt16(0x59 + index)
            result["KC_KP_\(digit)"] = raw; result["KC_P\(digit)"] = raw
        }
        return result
    }()
}

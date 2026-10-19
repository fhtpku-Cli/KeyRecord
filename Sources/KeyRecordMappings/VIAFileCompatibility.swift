import Foundation
import KeyRecordAnalysis
import KeyRecordConfigurationRead

/// Compatibility of a local file edit, not qualification of a device or importer.
public enum FirmwareCompatibilityBasis: String, Codable, Sendable {
    case viaFile
}

public struct VIAFileSlot: Equatable, Sendable {
    public let slot: FirmwareSlot
    public let original: String
    public let restriction: FirmwareError?
}

public enum VIAFileCompatibility {
    public static let outputs: Set<String> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { "KC_\($0)" }
        + (0...9).map { "KC_\($0)" }
        + (1...20).map { "KC_F\($0)" }
        + ["KC_ENT", "KC_ESC", "KC_BSPC", "KC_TAB", "KC_SPC", "KC_MINS", "KC_EQL",
           "KC_LBRC", "KC_RBRC", "KC_BSLS", "KC_SCLN", "KC_QUOT", "KC_GRV", "KC_COMM",
           "KC_DOT", "KC_SLSH", "KC_CAPS", "KC_HOME", "KC_PGUP", "KC_DEL", "KC_END",
           "KC_PGDN", "KC_RGHT", "KC_LEFT", "KC_DOWN", "KC_UP", "KC_LCTL", "KC_LSFT",
           "KC_LALT", "KC_LGUI", "KC_RCTL", "KC_RSFT", "KC_RALT", "KC_RGUI"])

    public static func validate(_ bytes: Data) throws {
        do {
            _ = try VIAReferenceParser.layout(bytes)
            let document = try FirmwareDocument(bytes: bytes, backend: .via)
            guard document.device != "0" else { throw FirmwareError.invalidDocument }
            let root = try JSONDocumentRanges(bytes).root
            guard let layers = root.members["layers"]?.elements, layers.count <= 32 else { throw FirmwareError.invalidDocument }
            if let encoders = root.members["encoders"] {
                guard let entries = encoders.elements else { throw FirmwareError.invalidDocument }
                for entry in entries {
                    guard let values = entry.elements, values.count == layers.count else { throw FirmwareError.invalidDocument }
                    for value in values {
                        guard let pair = value.elements, pair.count == 2 else { throw FirmwareError.invalidDocument }
                        for token in pair { _ = try JSONDecoder().decode(String.self, from: Data(bytes[token.range])) }
                    }
                }
            }
        } catch { throw FirmwareError.invalidDocument }
    }

    static func layerEntry(_ token: String) -> String {
        let pattern = #"^(MO|TG|TO|TT|DF|OSL)\(([0-9]|[12][0-9]|3[01])\)$"#
        if token.range(of: pattern, options: .regularExpression) != nil { return token }
        if token.hasPrefix("LT("), token.hasSuffix(")") {
            let parts = token.dropFirst(3).dropLast().split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, let layer = Int(parts[0]), (0...15).contains(layer),
               String(layer) == parts[0], outputs.contains(String(parts[1])) { return token }
        }
        return ""
    }
}

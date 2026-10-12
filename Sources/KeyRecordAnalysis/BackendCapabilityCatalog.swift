import Foundation
import KeyRecordCore

public enum BackendCapabilityCatalog {
    public static func reference(_ backend: RecommendationBackend) -> BackendCapabilities? {
        switch backend {
        case .karabiner, .via:
            return BackendCapabilities(backend: backend, keyCodes: Set(KarabinerKeyCodes.values.values),
                applicationScope: backend == .karabiner, fnModifier: backend == .karabiner)
        case .vial: return nil
        }
    }
}

enum KarabinerKeyCodes {
    static let values: [String: KeyCode] = {
        var values: [String: Int] = [:]
        for (letter, code) in zip("abcdefghijklmnopqrstuvwxyz", [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]) {
            values[String(letter)] = code
        }
        for (index, code) in [18,19,20,21,23,22,26,28,25,29].enumerated() { values[String((index + 1) % 10)] = code }
        for (index, code) in LogicalPreviews.functionKeyValues.enumerated() { values["f\(index + 1)"] = code }
        let named = ["return_or_enter":36, "escape":53, "delete_or_backspace":51, "tab":48, "spacebar":49,
            "hyphen":27, "equal_sign":24, "open_bracket":33, "close_bracket":30, "backslash":42,
            "semicolon":41, "quote":39, "grave_accent_and_tilde":50, "comma":43, "period":47, "slash":44,
            "caps_lock":57, "home":115, "page_up":116, "delete_forward":117, "end":119, "page_down":121,
            "right_arrow":124, "left_arrow":123, "down_arrow":125, "up_arrow":126,
            "left_control":59, "left_shift":56, "left_option":58, "left_command":55,
            "right_control":62, "right_shift":60, "right_option":61, "right_command":54]
        values.merge(named) { _, value in value }
        return values.compactMapValues { try? KeyCode($0) }
    }()
}

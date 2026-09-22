import AppKit
import KeyRecordCore
import KeyRecordAnalysis

/// Display names never alter the stored key code, sided chord, or application identity.
enum AnalysisLabels {
    static func key(_ code: KeyCode, text: NativeText) -> String {
        let names: [Int: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            71: "Clear", 76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete",
            119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let functions: [Int: Int] = [122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6,
            98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12, 105: 13, 107: 14, 113: 15,
            106: 16, 64: 17, 79: 18, 80: 19, 90: 20]
        if let function = functions[code.value] { return "F\(function)" }
        if let name = names[code.value] { return text("phase2.key.\(name)") }
        let ansi: [Int: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 41: ";", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"]
        if let position = ansi[code.value] { return String(format: text("phase2.ansiPosition"), position, code.value) }
        return String(format: text("aggregate.keyToken"), code.value)
    }

    static func chord(_ chord: Chord, text: NativeText) -> String {
        let modifiers = chord.modifiers
        var parts: [String] = []
        for (name, side) in [("modifier.command", modifiers.command), ("modifier.option", modifiers.option),
                              ("modifier.control", modifiers.control), ("modifier.shift", modifiers.shift)] where side != .none {
            parts.append(side == .activeSideUnknown
                ? String(format: text("modifier.side.unknown"), text(name)) : text(name))
        }
        if modifiers.fn != .none { parts.append(text(modifiers.fn == .unknown ? "modifier.fn.unknown" : "modifier.fn")) }
        parts.append(key(chord.keyCode, text: text))
        return parts.joined(separator: " + ")
    }

    static func app(_ bucket: AppBucket, text: NativeText) -> String {
        switch bucket {
        case .unknown: return text("aggregate.appUnknown")
        case .bundleID(let identifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                  let name = Bundle(url: url)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? Bundle(url: url)?.localizedInfoDictionary?["CFBundleName"] as? String
                    ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                  !name.isEmpty else { return identifier }
            return "\(name) (\(identifier))"
        }
    }

    static func exactChord(_ chord: Chord, text: NativeText) -> String {
        var parts: [String] = []
        for (key, side) in [("modifier.command", chord.modifiers.command),
                            ("modifier.option", chord.modifiers.option),
                            ("modifier.control", chord.modifiers.control),
                            ("modifier.shift", chord.modifiers.shift)] {
            let suffix: String
            switch side {
            case .none: continue
            case .left: suffix = "left"
            case .right: suffix = "right"
            case .both: suffix = "both"
            case .activeSideUnknown: suffix = "unknown"
            }
            parts.append(String(format: text("modifier.side.\(suffix)"), text(key)))
        }
        if chord.modifiers.fn != .none {
            parts.append(text(chord.modifiers.fn == .unknown ? "modifier.fn.unknown" : "modifier.fn"))
        }
        parts.append(String(format: text("aggregate.keyToken"), chord.keyCode.value))
        return parts.joined(separator: " + ")
    }

    static func layout(_ preset: LayoutPreset, text: NativeText) -> String {
        text("phase2.layout.\(preset.rawValue)")
    }
}

extension AnalysisLabels {
    static func sources(_ counts: SourceCounts, text: NativeText) -> String {
        String(format: text("phase2.sources"), counts.total.value, counts.ordinary.value, counts.suspectedInjection.value)
    }
}

/// Family grouping is presentation only; all sided variants remain inspectable.
struct AnalysisStatisticGroup: Identifiable {
    let id: String
    let representative: Chord
    var variants: [ShortcutStatistic]
    var total: Int64
    var ordinary: Int64
    var suspected: Int64
    var weightedFrequency: Double

    static func make(_ snapshot: AnalysisSnapshot) -> [AnalysisStatisticGroup] {
        let frequencies = Dictionary(uniqueKeysWithValues: snapshot.candidates.map { ($0.chord, $0.factors.weightedFrequency) })
        var groups: [String: AnalysisStatisticGroup] = [:]
        for row in snapshot.shortcutStatistics {
            let m = row.chord.modifiers
            let family = [m.command, m.option, m.control, m.shift].map { side in
                switch side {
                case .none: return "0"
                case .left, .right, .both: return "1"
                case .activeSideUnknown: return "?"
                }
            }.joined()
            let id = "\(row.chord.keyCode.value):\(family):\(m.fn.rawValue)"
            var group = groups[id] ?? AnalysisStatisticGroup(id: id, representative: row.chord, variants: [], total: 0, ordinary: 0, suspected: 0, weightedFrequency: 0)
            group.variants.append(row)
            group.total += row.sourceCounts.total.value
            group.ordinary += row.sourceCounts.ordinary.value
            group.suspected += row.sourceCounts.suspectedInjection.value
            group.weightedFrequency += frequencies[row.chord] ?? 0
            groups[id] = group
        }
        return groups.values.sorted { $0.total == $1.total ? $0.id < $1.id : $0.total > $1.total }
    }
}

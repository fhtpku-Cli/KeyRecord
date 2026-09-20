import Foundation
import KeyRecordCore

// MARK: - Task 22 bilingual catalog audit (pure functions; no UI)

enum LocalizationAudit {
    // Exact reviewed AX IDs, SF Symbols, bundle IDs and fixture filenames, never catalog-derived.
    static let nonLocalizationLiterals: Set<String> = [
        "aggregates.bare", "aggregates.bareTotal", "aggregates.empty", "aggregates.list",
        "aggregates.locked", "aggregates.panel", "aggregates.row", "aggregates.shortcutTotal",
        "arrow.counterclockwise.circle", "capture.primary", "capture.status", "capture.symbol",
        "com.apple.screenIsLocked", "com.apple.screenIsUnlocked",
        "com.example.chat", "com.example.editor", "com.keyrecord.app", "consent.panel",
        "debug.localCaptureEnabled",
        "destructive.cancel", "destructive.panel", "dialog.cancel", "dialog.confirm", "dialog.message",
        "dialog.panel", "exclamationmark.triangle", "flow.notice", "harness.appearance", "lock.circle",
        "menu.developer.diagnosis", "menu.developer.localCapture", "menu.developer.section",
        "menu.open", "menu.pause", "menu.quit", "menu.resume", "menu.settings", "menu.start", "menu.status",
        "menu.startupFailure",
        "pause.circle", "record.circle", "preferences.json", "results.journal", "preview.locale",
        "preview.locked.toggle", "settings.form", "settings.exclusions.empty", "settings.exclusions.foreground",
    ]
    /// Values allowed to read identically in EN and zh-Hans: the brand name, the two
    /// locale self-names, and macOS keyboard modifier names Apple leaves in English.
    static let identicalAllowlist: Set<String> = [
        "app.name", "locale.en", "locale.zh-Hans",
        "modifier.option", "modifier.control", "modifier.shift", "modifier.fn",
    ]

    static func parseCatalog(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = /"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";/
        for match in text.matches(of: pattern) { result[String(match.output.1)] = String(match.output.2) }
        return result
    }

    /// Scan independently of either catalog so keys missing from BOTH remain visible.
    static func literalKeys(in source: String) -> Set<String> {
        var keys = Set<String>()
        for match in source.matches(of: /"([a-z][a-z0-9]*(?:\.[A-Za-z0-9-]+)+)"/) {
            keys.insert(String(match.output.1))
        }
        return keys
    }

    static func referencedKeys(in source: String) -> Set<String> {
        var keys = literalKeys(in: source).subtracting(nonLocalizationLiterals)
        for match in source.matches(of: /(?:text|self)\("([^"\\]+)"/) {
            keys.insert(String(match.output.1))
        }
        return keys
    }

    /// Keys never spelled out as literals: interpolated status/action words and the dialog
    /// proposal keys produced by Core structs.
    static func dynamicKeys() -> Set<String> {
        var keys = Set<String>()
        for state in PrimitiveState.allCases {
            keys.insert(state.statusKey)
            keys.insert(state.actionKey)
        }
        let reset = ResetProposal.standard()
        keys.formUnion([reset.titleKey, reset.messageKey, reset.confirmKey, reset.cancelKey])
        let delete = DeleteProposal.deleteStandard()
        keys.formUnion([delete.titleKey, delete.messageKey, delete.confirmKey, delete.cancelKey])
        return keys
    }

    /// Bidirectional scan: referenced-but-missing (runtime raw-key leaks) and
    /// present-but-orphaned (dead translations) are both violations.
    static func audit(catalog: [String: String], referenced: Set<String>) -> [String] {
        var violations: [String] = []
        for key in referenced.subtracting(catalog.keys).sorted() {
            violations.append("missing catalog entry for referenced key: \(key)")
        }
        for key in Set(catalog.keys).subtracting(referenced).sorted() {
            violations.append("orphaned catalog entry never referenced: \(key)")
        }
        for key in referenced.sorted() {
            if let value = catalog[key], value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                violations.append("empty value: \(key)")
            }
        }
        return violations
    }

    /// Cross-locale scan: identical key sets, no empty values, and every value differs
    /// between locales unless the key is an allowlisted brand/system word.
    static func auditPair(en: [String: String], zh: [String: String]) -> [String] {
        var violations: [String] = []
        for key in Set(en.keys).symmetricDifference(zh.keys).sorted() {
            violations.append("locale parity gap: \(key)")
        }
        for key in en.keys.sorted() {
            guard let enValue = en[key], let zhValue = zh[key] else { continue }
            if enValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                zhValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { violations.append("empty value: \(key)") }
            if enValue == zhValue, !identicalAllowlist.contains(key) {
                violations.append("untranslated value identical across locales: \(key)")
            }
        }
        return violations
    }

    static func catalogURL(_ lproj: String) -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent("App/KeyRecordApp/\(lproj).lproj/Localizable.strings")
    }

    static func appSources() throws -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("App/KeyRecordApp")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }
}

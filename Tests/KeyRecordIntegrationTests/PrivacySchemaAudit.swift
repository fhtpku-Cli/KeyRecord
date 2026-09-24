import Foundation
import KeyRecordTestSupport

enum PrivacySchemaAudit {
    static let bareKeys: Set<String> = ["schemaVersion", "cycleID", "rawValue", "day", "label",
        "keyCode", "sourceCounts", "ordinary", "suspectedInjection"]
    static let shortcutKeys = bareKeys.union(["identity", "chord", "modifiers", "command", "option",
        "control", "shift", "fn", "appBucket", "unknown", "classification", "kind", "scope"])

    enum Violation: Error { case unapprovedField(String) }

    static func checkJSON(_ bytes: Data, allowed: Set<String>) throws {
        func visit(_ value: Any) throws {
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    guard allowed.contains(key) else { throw Violation.unapprovedField(key) }
                    try visit(child)
                }
            } else if let array = value as? [Any] {
                for child in array { try visit(child) }
            }
        }
        try visit(JSONSerialization.jsonObject(with: bytes))
    }

    // File-qualified registration also covers private Wire DTOs and extensions adding conformance.
    static let serializableTypes: [String: Set<String>] = [
        "CaptureDiagnostics.swift": ["CaptureRunSummary"],
        "Counts.swift": ["Count", "SourceCounts", "ActiveDayOrdinal"],
        "CycleRecords.swift": ["CycleRecord", "CycleSummary"],
        "IdentityProviders.swift": ["CycleID", "KeyVersion", "LocalDay"],
        "Schema.swift": ["SchemaVersion"],
        "Preferences.swift": ["LayoutPreset", "ProductLocale", "LayoutPreference", "Preferences"],
        "KeyCode.swift": ["KeyCode"],
        "Chord.swift": ["ModifierSideState", "FnState", "ModifierSet", "Chord", "AppBucket", "ChordBucket"],
        "DailyAggregates.swift": ["ShortcutKind", "ScopeClass", "ShortcutClassification",
            "DailyShortcutAggregate", "DailyBareKeyAggregate"],
        "CycleResetJournalPayload.swift": ["ResetJournalPhase", "RetainedObjectHash", "ResetJournalPayload"],
        "EncryptedManifest.swift": ["Wire", "Entry"],
        "KeyringMetadata.swift": ["Wire"],
        "ProtectedReferences.swift": ["KeyRotation"]
    ]

    static func registeredTypes(in source: String) throws -> Set<String> {
        let code = SourceInspection.codeOnly(source)
        let pattern = #"\b(?:struct|enum|class|extension|protocol)\s+(\w+)\s*:[^{]*\b(?:Codable|Encodable|Decodable)\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        return Set(regex.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap {
            Range($0.range(at: 1), in: code).map { String(code[$0]) }
        })
    }

    static let recordFields: [String: [String: Set<String>]] = [
        "CaptureDiagnostics.swift": ["CaptureRunSummary": [
            "tapCallbackKeyDown", "tapCallbackKeyUp", "tapCallbackFlagsChanged", "tapDisabledEvents",
            "handoffAccepted", "handoffClosed", "handoffOverflow", "normalizationOutput", "aggregateDelta",
            "flushIssued", "flushDurable", "flushFailed", "flushTimedOut",
            "flushWriteReturned", "flushWriteSucceeded", "flushInvalidated", "sessionCount",
            "snapshotPublicationCount", "snapshotReadFailureCount", "lastPublishedShortcutTotal",
            "lastPublishedBareKeyTotal", "countersInstrumented", "captureSessionLive", "sensitiveContentVisible"]],
        "Counts.swift": ["Count": ["value"], "SourceCounts": ["ordinary", "suspectedInjection", "total"],
            "ActiveDayOrdinal": ["value"]],
        "IdentityProviders.swift": ["CycleID": ["rawValue"], "KeyVersion": ["rawValue"], "LocalDay": ["label"]],
        "KeyCode.swift": ["KeyCode": ["value"]],
        "Chord.swift": ["ModifierSet": ["command", "option", "control", "shift", "fn"],
            "Chord": ["keyCode", "modifiers"], "ChordBucket": ["chord", "appBucket"]],
        "ProtectedReferences.swift": ["KeyRotation": ["from", "to"]],
        "DailyAggregates.swift": [
            "ShortcutClassification": ["kind", "scope"],
            "DailyShortcutAggregate": ["currentSchemaVersion", "schemaVersion", "cycleID", "day", "identity", "classification", "sourceCounts"],
            "DailyBareKeyAggregate": ["currentSchemaVersion", "schemaVersion", "cycleID", "day", "keyCode", "sourceCounts"]],
        "CycleRecords.swift": [
            "CycleRecord": ["currentSchemaVersion", "schemaVersion", "cycleID", "index", "createdDay", "closedDay", "isCurrent"],
            "CycleSummary": ["currentSchemaVersion", "schemaVersion", "cycleID", "perChordTotals", "perBareKeyTotals", "distinctActiveDays"]],
        "Preferences.swift": ["LayoutPreference": ["preset", "hasAsked"],
            "Preferences": ["currentSchemaVersion", "schemaVersion", "expectedCollecting",
            "currentCycleID", "excludedBundleIDs", "ignoredRecommendationKeys", "layout", "loginItemEnabled", "locale", "keyboardPoolConfirmed"]],
        "EncryptedManifest.swift": ["Wire": ["schema", "current", "entries"],
            "Entry": ["objectType", "schemaVersion", "logicalID", "locator", "keyVersion"]],
        "KeyringMetadata.swift": ["Wire": ["schema", "current", "versions", "retirementPending", "rotationFrom", "rotationTo"]],
        "CycleResetJournalPayload.swift": [
            "RetainedObjectHash": ["identity", "sha256"],
            "ResetJournalPayload": ["schemaVersion", "operationID", "oldCycleID", "newCycleID", "newCycleIndex",
                "expectedCollecting", "summary", "retainedHashes", "phase"]]
    ]
}
